import Combine
import Foundation
import UniformTypeIdentifiers

nonisolated private struct ClipboardTextPayload: Sendable {
    let text: String
    let wasTruncated: Bool
}

nonisolated enum ClipboardContext: Equatable, Sendable {
    case hostApp
    case keyboard(hasFullAccess: Bool)

    var canUseSharedStorage: Bool {
        switch self {
        case .hostApp: return true
        case .keyboard(let hasFullAccess): return hasFullAccess
        }
    }
}

/// Main-actor presentation controller for manual clipboard saving and history mutations.
/// All disk work is delegated to `ClipboardRepository`; no lifecycle method reads a pasteboard.
@MainActor
final class ClipboardController: ObservableObject {
    @Published private(set) var history = ClipboardHistory()
    @Published private(set) var freshItem: ClipboardItem?
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    @Published private(set) var notice: String?
    @Published private(set) var hasLoadedHistory = false
    @Published private(set) var canResetStorage = false

    let settings: KeyboardSettingsStore

    private let repository: any ClipboardRepositoryProtocol
    private let now: @Sendable () -> Date
    private var context = ClipboardContext.keyboard(hasFullAccess: false)
    private var activationGeneration: UInt64 = 0
    private var displayedRevision: UInt64 = 0
    private var displayedStoreGeneration: UUID?
    private var hasDisplayedStoreState = false
    private var repositoryRequestSequence: UInt64 = 0
    private var lastAppliedRequestSequence: UInt64 = 0
    private var lastPresentedRequestSequence: UInt64 = 0
    private var isActive = false
    private var pasteProgress: Progress?
    private var refreshTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var insertionTask: Task<Void, Never>?
    private var insertionEpoch: UInt64 = 0
    private var captureTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?
    /// Invalidates provider callbacks and item-resolution work without deactivating the
    /// whole controller (for example when Clear is tapped or the panel is dismissed).
    private var operationEpoch: UInt64 = 0

    init(
        repository: any ClipboardRepositoryProtocol = ClipboardRepository(),
        settings: KeyboardSettingsStore = KeyboardSettingsStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.settings = settings
        self.now = now
    }

    var needsFullAccess: Bool {
        if case .keyboard(let hasFullAccess) = context { return !hasFullAccess }
        return false
    }

    var canSave: Bool {
        context.canUseSharedStorage
            && settings.values.hasAcceptedClipboardNotice
            && settings.values.effectiveClipboardCaptureMode != .off
            && !isBusy
    }

    var canClearStorage: Bool {
        context.canUseSharedStorage && (!history.items.isEmpty || canResetStorage)
    }

    func activate(_ context: ClipboardContext) {
        // A PasteButton permission sheet can move the host app through inactive -> active
        // without ending its UI lifetime. Treating that as a fresh activation cancelled the
        // provider callback and left an explicit Save looking like it did nothing.
        if isActive, self.context == context {
            settings.refresh(canUseShared: context.canUseSharedStorage)
            if context.canUseSharedStorage, !isBusy { refreshHistory() }
            return
        }

        // A new activation is a new UI lifetime. Cancel every operation from the previous
        // lifetime before advancing the generation so a guarded stale completion cannot
        // leave `isBusy` stranded forever.
        cancelAllWork()
        activationGeneration &+= 1
        self.context = context
        isActive = true
        settings.refresh(canUseShared: context.canUseSharedStorage)
        freshItem = nil
        notice = nil
        lastError = nil
        canResetStorage = false

        guard context.canUseSharedStorage else {
            // Shared history may be cleared by the host while access is revoked. Do not retain
            // or paste an unverifiable cached copy in the surviving extension process.
            history = ClipboardHistory()
            hasLoadedHistory = false
            return
        }
        if mutationTask == nil { refreshHistory() }
    }

    func deactivate() {
        activationGeneration &+= 1
        isActive = false
        freshItem = nil
        cancelAllWork()
    }

    func refreshHistory() {
        guard context.canUseSharedStorage, !isBusy else { return }
        refreshTask?.cancel()
        let generation = activationGeneration
        let requestSequence = nextRequestSequence()
        let refreshDate = now()
        let repository = self.repository
        refreshTask = Task { [weak self] in
            do {
                // Refresh is also the durable retention sweep. A read-only in-memory
                // filter would leave expired clipboard text in both on-disk copies.
                let receipt = try await repository.sweep(at: refreshDate)
                guard !Task.isCancelled, let self,
                      self.activationGeneration == generation else { return }
                _ = self.apply(receipt, requestSequence: requestSequence)
            } catch {
                guard !Task.isCancelled, let self,
                      self.activationGeneration == generation,
                      requestSequence >= self.lastAppliedRequestSequence else { return }
                self.presentStorageError(error, requestSequence: requestSequence)
            }
        }
    }

    /// Receives providers only after the system `PasteButton` is tapped. Opening or foregrounding
    /// the app/keyboard never reaches this method, so manual mode performs no implicit read.
    func save(itemProviders: [NSItemProvider]) {
        guard canSave else {
            if needsFullAccess { notice = "Allow Full Access before saving clipboard history." }
            return
        }
        guard let provider = itemProviders.first(where: {
            $0.canLoadObject(ofClass: NSString.self) || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            notice = "The clipboard does not contain text."
            return
        }
        guard !SensitivePasteboardPolicy.looksConcealed(typeIdentifiers: provider.registeredTypeIdentifiers) else {
            notice = "Sensitive clipboard content was not saved."
            return
        }

        isBusy = true
        lastError = nil
        canResetStorage = false
        notice = nil
        let generation = activationGeneration
        let epoch = operationEpoch
        let requestSequence = nextRequestSequence()
        let capturedAt = now()
        let typeIdentifier = Self.preferredTextTypeIdentifier(
            in: provider.registeredTypeIdentifiers
        )
        pasteProgress = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
            let result: Result<ClipboardTextPayload, Error>
            if let url {
                result = Result {
                    try Self.readBoundedText(from: url, declaredTypeIdentifier: typeIdentifier)
                }
            } else {
                result = .failure(error ?? ClipboardStoreError.readFailed("provider returned no text file"))
            }
            Task { @MainActor [weak self] in
                guard let self,
                      self.activationGeneration == generation,
                      self.operationEpoch == epoch,
                      self.isActive else { return }
                self.pasteProgress = nil
                switch result {
                case .success(let payload):
                    self.persistProvidedText(
                        payload.text,
                        generation: generation,
                        epoch: epoch,
                        requestSequence: requestSequence,
                        capturedAt: capturedAt,
                        sourceWasTruncated: payload.wasTruncated
                    )
                case .failure:
                    self.isBusy = false
                    if requestSequence >= self.lastPresentedRequestSequence {
                        self.lastPresentedRequestSequence = requestSequence
                        self.notice = "The clipboard text could not be read."
                    }
                }
            }
        }
    }

    /// Internal seam used after a user-initiated PasteButton transfer and by deterministic tests.
    func saveProvidedText(_ text: String, capturedAt: Date = Date()) {
        guard canSave else { return }
        isBusy = true
        let requestSequence = nextRequestSequence()
        persistProvidedText(
            text,
            generation: activationGeneration,
            epoch: operationEpoch,
            requestSequence: requestSequence,
            capturedAt: capturedAt,
            sourceWasTruncated: false
        )
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        guard context.canUseSharedStorage, !isBusy else {
            if isBusy { notice = "Finish the current clipboard action first." }
            return
        }
        let mutationDate = now()
        performMutation { repository in
            try await repository.setPinned(pinned, id: id, at: mutationDate)
        }
    }

    func delete(id: UUID) {
        guard context.canUseSharedStorage, !isBusy else {
            if isBusy { notice = "Finish the current clipboard action first." }
            return
        }
        let mutationDate = now()
        performMutation { repository in
            try await repository.delete(id: id, at: mutationDate)
        }
    }

    func clear() {
        guard context.canUseSharedStorage, mutationTask == nil else {
            if mutationTask != nil { notice = "Finish the current clipboard action first." }
            return
        }
        freshItem = nil
        cancelPendingInteractions()
        refreshTask?.cancel()
        refreshTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        let mutationDate = now()
        performMutation(preserveResetEligibilityOnFailure: canResetStorage) { repository in
            try await repository.clear(at: mutationDate)
        }
    }

    /// Resolves an item against the latest coordinated store immediately before insertion.
    /// This prevents an expired item, or one deleted/cleared by the host app, from being
    /// inserted from a stale keyboard panel snapshot.
    func resolveTextForInsertion(id: UUID, completion: @escaping @MainActor (String) -> Void) {
        guard isActive else {
            notice = "That clipboard item is no longer available."
            return
        }
        guard !isBusy else {
            notice = "Finish the current clipboard action first."
            return
        }

        // Every insertion is revalidated against coordinated storage. With Full Access revoked
        // that check is impossible, so cached text is deliberately unavailable.
        guard context.canUseSharedStorage else {
            notice = "Allow Full Access to use clipboard history."
            return
        }
        isBusy = true
        lastError = nil
        canResetStorage = false
        notice = nil
        let generation = activationGeneration
        let epoch = operationEpoch
        let insertionEpoch = self.insertionEpoch
        let resolutionDate = now()
        let requestSequence = nextRequestSequence()
        let repository = self.repository
        insertionTask = Task { [weak self] in
            do {
                let receipt = try await repository.sweep(at: resolutionDate)
                guard !Task.isCancelled, let self,
                      self.activationGeneration == generation,
                      self.operationEpoch == epoch,
                      self.insertionEpoch == insertionEpoch,
                      self.isActive else { return }
                self.insertionTask = nil
                self.isBusy = false
                guard self.apply(receipt, requestSequence: requestSequence) else { return }
                guard let item = receipt.history.items.first(where: { $0.id == id }),
                      !item.hasExpired(at: self.now()) else {
                    self.notice = "That clipboard item is no longer available."
                    self.refreshHistory()
                    return
                }
                completion(item.text)
            } catch {
                guard !Task.isCancelled, let self,
                      self.activationGeneration == generation,
                      self.operationEpoch == epoch,
                      self.insertionEpoch == insertionEpoch,
                      self.isActive else { return }
                self.insertionTask = nil
                self.isBusy = false
                self.presentStorageError(error, requestSequence: requestSequence)
            }
        }
    }

    /// Called when leaving a panel or beginning Clear. Storage work already holding the
    /// coordinator may finish, but its timestamp fence/result cannot affect the new UI epoch.
    func cancelPendingInteractions() {
        operationEpoch &+= 1
        insertionEpoch &+= 1
        pasteProgress?.cancel()
        pasteProgress = nil
        captureTask?.cancel()
        captureTask = nil
        insertionTask?.cancel()
        insertionTask = nil
        // A user-requested pin/delete/clear is durable work. Leaving its panel must not
        // abandon it; keep the busy state until that mutation publishes its receipt.
        isBusy = mutationTask != nil
    }

    func userDidType() {
        freshItem = nil
        cancelPendingInsertion()
    }

    /// Invalidates only an unresolved paste request. Durable history mutations and an explicit
    /// Save transfer continue; this is safe to call for every later keyboard/host action.
    func cancelPendingInsertion() {
        // A paste tap resolves asynchronously. Once a later key has been typed, inserting that
        // earlier clipboard request would reverse the user's action order.
        insertionEpoch &+= 1
        insertionTask?.cancel()
        insertionTask = nil
        isBusy = mutationTask != nil || captureTask != nil || pasteProgress != nil
    }

    private func persistProvidedText(
        _ text: String,
        generation: UInt64,
        epoch: UInt64,
        requestSequence: UInt64,
        capturedAt: Date,
        sourceWasTruncated: Bool
    ) {
        let repository = self.repository
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let receipt = try await repository.capture(
                    text: text,
                    at: capturedAt,
                    sourceWasTruncated: sourceWasTruncated
                )
                guard let self,
                      !Task.isCancelled,
                      self.activationGeneration == generation,
                      self.operationEpoch == epoch,
                      self.isActive else { return }
                self.captureTask = nil
                self.isBusy = false
                guard self.apply(receipt, requestSequence: requestSequence) else { return }
                switch receipt.outcome {
                case .stored(let item), .refreshed(let item):
                    self.freshItem = item
                    self.notice = item.wasTruncated ? "Saved a shortened copy." : "Saved."
                case .rejectedEmpty:
                    self.notice = "Whitespace-only text was not saved."
                case .staleCaptureRejected:
                    self.notice = "The save was cancelled because history was cleared."
                default:
                    break
                }
            } catch {
                guard !(error is CancellationError), let self,
                      !Task.isCancelled,
                      self.activationGeneration == generation,
                      self.operationEpoch == epoch,
                      self.isActive else { return }
                self.captureTask = nil
                self.isBusy = false
                self.presentStorageError(error, requestSequence: requestSequence)
            }
        }
    }

    private func performMutation(
        preserveResetEligibilityOnFailure: Bool = false,
        _ operation: @escaping @Sendable (any ClipboardRepositoryProtocol) async throws -> ClipboardMutationReceipt
    ) {
        guard mutationTask == nil else {
            notice = "Finish the current clipboard action first."
            return
        }
        isBusy = true
        lastError = nil
        canResetStorage = false
        notice = nil
        let repository = self.repository
        let requestSequence = nextRequestSequence()
        let generation = activationGeneration
        mutationTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let receipt = try await operation(repository)
                guard let self, !Task.isCancelled else { return }
                self.mutationTask = nil
                self.isBusy = false
                guard self.isActive,
                      self.activationGeneration == generation,
                      self.context.canUseSharedStorage else {
                    if !self.context.canUseSharedStorage {
                        self.history = ClipboardHistory()
                        self.freshItem = nil
                        self.hasLoadedHistory = false
                    } else if self.isActive {
                        self.refreshHistory()
                    }
                    return
                }
                guard self.apply(receipt, requestSequence: requestSequence) else { return }
                switch receipt.outcome {
                case .pinnedSectionFull:
                    self.notice = "Pinned clipboard is full (25 items)."
                case .notFound:
                    self.notice = "That clipboard item is no longer available."
                default:
                    break
                }
            } catch {
                guard !(error is CancellationError), let self, !Task.isCancelled else { return }
                self.mutationTask = nil
                self.isBusy = false
                guard self.isActive,
                      self.activationGeneration == generation,
                      self.context.canUseSharedStorage else {
                    if self.isActive, self.context.canUseSharedStorage {
                        self.refreshHistory()
                    }
                    return
                }
                self.presentStorageError(
                    error,
                    requestSequence: requestSequence,
                    preserveResetEligibility: preserveResetEligibilityOnFailure
                )
            }
        }
    }

    @discardableResult
    private func apply(_ snapshot: ClipboardSnapshot, requestSequence: UInt64) -> Bool {
        guard shouldApply(
            revision: snapshot.revision,
            generation: snapshot.generation,
            requestSequence: requestSequence
        ) else { return false }
        displayedRevision = snapshot.revision
        displayedStoreGeneration = snapshot.generation
        hasDisplayedStoreState = true
        lastAppliedRequestSequence = max(lastAppliedRequestSequence, requestSequence)
        history = snapshot.history
        retainFreshItemIfStillVisible()
        hasLoadedHistory = true
        if requestSequence >= lastPresentedRequestSequence {
            lastPresentedRequestSequence = requestSequence
            lastError = nil
            canResetStorage = false
            if snapshot.recovery == .usedBackup {
                notice = "History was recovered from its last good backup."
            } else if snapshot.recovery == .repairPending {
                notice = "Saved. The local recovery copy will be checked again."
            }
        }
        scheduleExpiration()
        return true
    }

    @discardableResult
    private func apply(_ receipt: ClipboardMutationReceipt, requestSequence: UInt64) -> Bool {
        // A reset changes the store generation; request ordering prevents an older completion
        // from switching the UI back, while revision ordering handles one generation.
        guard shouldApply(
            revision: receipt.revision,
            generation: receipt.generation,
            requestSequence: requestSequence
        ) else { return false }
        if case .cleared = receipt.outcome { freshItem = nil }
        displayedRevision = receipt.revision
        displayedStoreGeneration = receipt.generation
        hasDisplayedStoreState = true
        lastAppliedRequestSequence = max(lastAppliedRequestSequence, requestSequence)
        history = receipt.history
        retainFreshItemIfStillVisible()
        hasLoadedHistory = true
        if requestSequence >= lastPresentedRequestSequence {
            lastPresentedRequestSequence = requestSequence
            lastError = nil
            canResetStorage = false
            if receipt.recovery == .repairPending {
                notice = "Saved. The local recovery copy will be checked again."
            }
        }
        scheduleExpiration()
        return true
    }

    private func shouldApply(
        revision: UInt64,
        generation: UUID?,
        requestSequence: UInt64
    ) -> Bool {
        guard hasDisplayedStoreState else { return true }
        if generation != displayedStoreGeneration {
            return requestSequence >= lastAppliedRequestSequence
        }
        return revision >= displayedRevision
    }

    private func nextRequestSequence() -> UInt64 {
        repositoryRequestSequence &+= 1
        return repositoryRequestSequence
    }

    private func scheduleExpiration() {
        expiryTask?.cancel()
        guard isActive, let expiry = history.nextExpirationDate else { return }
        let delay = max(0, expiry.timeIntervalSince(now()))
        expiryTask = Task { [weak self] in
            let nanoseconds = UInt64(min(delay, 24 * 60 * 60) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.refreshHistory()
        }
    }

    private func retainFreshItemIfStillVisible() {
        guard let current = freshItem else { return }
        freshItem = history.items.first(where: {
            $0.id == current.id && !$0.hasExpired(at: now())
        })
    }

    private func cancelAllWork() {
        cancelPendingInteractions()
        refreshTask?.cancel()
        refreshTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        // Pin/delete/clear are confirmed durable actions. Let them finish even when the
        // keyboard is dismissed; only transient provider/capture/insert work is cancelled.
        isBusy = mutationTask != nil
    }

    private static func safeMessage(for error: Error) -> String {
        (error as? ClipboardStoreError)?.errorDescription ?? "Clipboard history is unavailable."
    }

    private func presentStorageError(
        _ error: Error,
        requestSequence: UInt64,
        preserveResetEligibility: Bool = false
    ) {
        guard requestSequence >= lastPresentedRequestSequence else { return }
        lastPresentedRequestSequence = requestSequence
        lastError = Self.safeMessage(for: error)
        canResetStorage = preserveResetEligibility
            || ((error as? ClipboardStoreError)?.canBeExplicitlyReset ?? false)
    }

    /// Reads only a small window from the provider-owned temporary file. This keeps a
    /// multi-megabyte clipboard from being materialized inside the keyboard extension.
    nonisolated private static func preferredTextTypeIdentifier(in identifiers: [String]) -> String {
        let preferred = [
            UTType.utf8PlainText.identifier,
            UTType.utf16PlainText.identifier,
            UTType.utf16ExternalPlainText.identifier,
        ]
        if let exact = preferred.first(where: identifiers.contains) { return exact }
        return identifiers.first(where: {
            UTType($0)?.conforms(to: .plainText) == true
        }) ?? UTType.plainText.identifier
    }

    nonisolated private static func readBoundedText(
        from url: URL,
        declaredTypeIdentifier: String
    ) throws -> ClipboardTextPayload {
        let lookaheadBytes = 4 * 1_024
        let isExplicitUTF8 = declaredTypeIdentifier == UTType.utf8PlainText.identifier
        let contentLimit = !isExplicitUTF8
            ? (ClipboardLimits.maxTextBytes + lookaheadBytes) * 2 + 2
            : ClipboardLimits.maxTextBytes + lookaheadBytes
        let readLimit = contentLimit + 1
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: readLimit) ?? Data()
        let sourceWasTruncated = data.count > contentLimit
        var boundedData = Data(data.prefix(contentLimit))

        let hasUTF16BOM = boundedData.starts(with: [0xFF, 0xFE])
            || boundedData.starts(with: [0xFE, 0xFF])
        let encodings: [String.Encoding]
        switch declaredTypeIdentifier {
        case UTType.utf16PlainText.identifier:
            // Native byte order on every supported iPhone is little-endian. Foundation's
            // `.utf16` assumes big-endian without a BOM, and can silently produce gibberish.
            encodings = hasUTF16BOM ? [.utf16] : [.utf16LittleEndian]
        case UTType.utf16ExternalPlainText.identifier:
            encodings = hasUTF16BOM ? [.utf16] : [.utf16BigEndian]
        case UTType.utf8PlainText.identifier:
            encodings = [.utf8]
        default:
            // `public.plain-text` has no declared encoding. A BOM is authoritative; otherwise
            // sniff the alternating NUL pattern before trying UTF-8. BOM-less UTF-16 ASCII is
            // technically valid UTF-8 containing NULs, so blindly trying UTF-8 first corrupts it.
            if hasUTF16BOM {
                encodings = [.utf16]
            } else if looksLikeUTF16(boundedData, zeroByteOffset: 1) {
                encodings = [.utf16LittleEndian]
            } else if looksLikeUTF16(boundedData, zeroByteOffset: 0) {
                encodings = [.utf16BigEndian]
            } else {
                encodings = [.utf8]
            }
        }

        // A bounded read can end inside a UTF-8 scalar or halfway through a UTF-16 code
        // unit/surrogate. Remove only a tiny tail; invalid data elsewhere is rejected.
        for _ in 0...4 {
            for encoding in encodings {
                if let text = String(data: boundedData, encoding: encoding) {
                    let truncated = ClipboardLimits.truncate(text)
                    return ClipboardTextPayload(
                        text: truncated.text,
                        wasTruncated: sourceWasTruncated || truncated.wasTruncated
                    )
                }
            }
            guard !boundedData.isEmpty else { break }
            boundedData.removeLast()
        }
        throw ClipboardStoreError.readFailed("text provider used an unsupported encoding")
    }

    nonisolated private static func looksLikeUTF16(_ data: Data, zeroByteOffset: Int) -> Bool {
        let sample = Array(data.prefix(256))
        let pairCount = sample.count / 2
        guard pairCount >= 2 else { return false }
        var zeroCount = 0
        for pair in 0..<pairCount where sample[pair * 2 + zeroByteOffset] == 0 {
            zeroCount += 1
        }
        return zeroCount * 2 >= pairCount
    }
}

/// Best-effort deny list for password-manager and transient clipboard providers. The absence
/// of one of these de-facto markers is never presented as proof that content is safe.
nonisolated enum SensitivePasteboardPolicy {
    static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
    ]

    static func looksConcealed(typeIdentifiers: [String]) -> Bool {
        !Set(typeIdentifiers).isDisjoint(with: concealedTypes)
    }
}
