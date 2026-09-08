import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import KeyboardProject

@MainActor
final class ClipboardControllerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testNoFullAccessCannotSaveOrTouchRepository() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })

        controller.activate(.keyboard(hasFullAccess: false))
        controller.saveProvidedText("must not persist", capturedAt: now)
        try await Task.sleep(nanoseconds: 20_000_000)

        let captureWasCalled = await repository.captureWasCalled()
        XCTAssertFalse(captureWasCalled)
        XCTAssertTrue(controller.history.items.isEmpty)
        XCTAssertFalse(controller.isBusy)
    }

    func testSuccessfulSavePublishesOnlyPersistedReceipt() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)

        controller.saveProvidedText("persisted", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }

        XCTAssertEqual(controller.history.items.map(\.text), ["persisted"])
        XCTAssertEqual(controller.freshItem?.text, "persisted")
    }

    func testPersistenceFailureDoesNotPublishOptimisticItem() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(failCaptures: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)

        controller.saveProvidedText("not persisted", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.lastError != nil }

        XCTAssertTrue(controller.history.items.isEmpty)
        XCTAssertNil(controller.freshItem)
    }

    func testOlderRefreshCannotEraseNewerSaveFailure() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(failCaptures: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        try await waitUntil { controller.hasLoadedHistory }
        await repository.suspendNextSweep()
        controller.refreshHistory()
        try await waitUntil { await repository.sweepIsSuspended() }

        controller.saveProvidedText("fails", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.lastError != nil }
        let failure = controller.lastError
        await repository.resumeSweep()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(controller.lastError, failure)
        XCTAssertTrue(controller.history.items.isEmpty)
    }

    func testDeactivationCancelsSuspendedCaptureAndClearsBusyState() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(suspendCaptures: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)

        controller.saveProvidedText("late", capturedAt: now)
        try await waitUntil { await repository.captureIsSuspended() }
        XCTAssertTrue(controller.isBusy)

        controller.deactivate()
        await repository.resumeCapture()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertFalse(controller.isBusy)
        XCTAssertNil(controller.freshItem)
        XCTAssertTrue(controller.history.items.isEmpty)
        let stored = try await repository.load(at: now)
        XCTAssertTrue(stored.history.items.isEmpty)
    }

    func testScreenDismissalCancelsTransientSave() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(suspendCaptures: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("dismissed", capturedAt: now)
        try await waitUntil { await repository.captureIsSuspended() }

        controller.cancelPendingInteractions()
        await repository.resumeCapture()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(controller.history.items.isEmpty)
        let stored = try await repository.load(at: now)
        XCTAssertTrue(stored.history.items.isEmpty)
    }

    func testSuspendedStorageNeverBlocksMainActorSettings() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(suspendCaptures: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("waiting", capturedAt: now)
        try await waitUntil { await repository.captureIsSuspended() }

        settings.setSoundEnabled(true, at: now)
        XCTAssertTrue(settings.values.soundEnabled)

        controller.deactivate()
        await repository.resumeCapture()
    }

    func testSameContextReactivationDoesNotCancelExplicitSave() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(suspendCaptures: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("permission round trip", capturedAt: now)
        try await waitUntil { await repository.captureIsSuspended() }

        // Mirrors inactive -> active after the system Paste permission sheet.
        controller.activate(.hostApp)
        XCTAssertTrue(controller.isBusy)
        await repository.resumeCapture()
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }

        XCTAssertEqual(controller.history.items.first?.text, "permission round trip")
    }

    func testUTF16ProviderIsDecodedAndPersisted() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardProject-provider-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let providerData = try XCTUnwrap("Hello 👋".data(using: .utf16LittleEndian))
        try providerData.write(to: fileURL)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.utf16PlainText.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(fileURL, false, nil)
            return nil
        }

        controller.save(itemProviders: [provider])
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }

        XCTAssertEqual(controller.history.items.first?.text, "Hello 👋")
    }

    func testBroadPlainTextProviderSniffsBOMlessUTF16() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardProject-broad-provider-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let providerData = try XCTUnwrap("Broad text".data(using: .utf16LittleEndian))
        try providerData.write(to: fileURL)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(fileURL, false, nil)
            return nil
        }

        controller.save(itemProviders: [provider])
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }

        XCTAssertEqual(controller.history.items.first?.text, "Broad text")
    }

    func testPanelDismissalAndRapidSecondMutationDoNotAbandonClear() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(suspendClears: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("erase me", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }
        let id = try XCTUnwrap(controller.history.items.first?.id)

        controller.clear()
        try await waitUntil { await repository.clearIsSuspended() }
        controller.cancelPendingInteractions()
        controller.delete(id: id)
        XCTAssertTrue(controller.isBusy, "dismissal must keep the durable clear alive")

        await repository.resumeClear()
        try await waitUntil { !controller.isBusy && controller.history.items.isEmpty }
        let persisted = try await repository.load(at: now)
        XCTAssertTrue(persisted.history.items.isEmpty)
    }

    func testDeactivationDoesNotAbandonConfirmedClear() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(suspendClears: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("erase after dismissal", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }

        controller.clear()
        try await waitUntil { await repository.clearIsSuspended() }
        controller.deactivate()
        await repository.resumeClear()
        try await waitUntil { !controller.isBusy }

        let persisted = try await repository.load(at: now)
        XCTAssertTrue(persisted.history.items.isEmpty)
        XCTAssertNil(controller.freshItem)
    }

    func testFullAccessRevocationCannotBeUndoneByDelayedMutationReceipt() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(suspendClears: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.keyboard(hasFullAccess: true))
        controller.saveProvidedText("private", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }

        controller.clear()
        try await waitUntil { await repository.clearIsSuspended() }
        controller.activate(.keyboard(hasFullAccess: false))
        XCTAssertTrue(controller.history.items.isEmpty)
        await repository.resumeClear()
        try await waitUntil { !controller.isBusy }

        XCTAssertTrue(controller.history.items.isEmpty)
        XCTAssertNil(controller.freshItem)
        XCTAssertFalse(controller.hasLoadedHistory)
    }

    func testDeletingFreshItemRemovesPasteChip() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("temporary", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.freshItem != nil }
        let id = try XCTUnwrap(controller.freshItem?.id)

        controller.delete(id: id)
        try await waitUntil { !controller.isBusy && controller.history.items.isEmpty }

        XCTAssertNil(controller.freshItem)
    }

    func testExpiryRefreshRemovesPasteChip() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let clock = ControllerTestClock(now)
        let controller = ClipboardController(repository: repository, settings: settings, now: { clock.value })
        controller.activate(.hostApp)
        controller.saveProvidedText("temporary", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.freshItem != nil }

        clock.value = now.addingTimeInterval(ClipboardLimits.retention + 1)
        controller.refreshHistory()
        try await waitUntil { controller.history.items.isEmpty }

        XCTAssertNil(controller.freshItem)
    }

    func testDelayedInsertionRechecksExpiryAtCompletion() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let clock = ControllerTestClock(now)
        let controller = ClipboardController(repository: repository, settings: settings, now: { clock.value })
        controller.activate(.hostApp)
        controller.saveProvidedText("expires while waiting", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }
        let id = try XCTUnwrap(controller.history.items.first?.id)
        await repository.suspendNextSweep()
        var inserted: String?

        controller.resolveTextForInsertion(id: id) { inserted = $0 }
        try await waitUntil { await repository.sweepIsSuspended() }
        clock.value = now.addingTimeInterval(ClipboardLimits.retention + 1)
        await repository.resumeSweep()
        try await waitUntil { !controller.isBusy && controller.history.items.isEmpty }

        XCTAssertNil(inserted)
        XCTAssertNil(controller.freshItem)
    }

    func testTypingCancelsEarlierSuspendedInsertion() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("earlier paste", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }
        let id = try XCTUnwrap(controller.history.items.first?.id)
        await repository.suspendNextSweep()
        var inserted: String?

        controller.resolveTextForInsertion(id: id) { inserted = $0 }
        try await waitUntil { await repository.sweepIsSuspended() }
        controller.userDidType()
        await repository.resumeSweep()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertNil(inserted, "an older delayed paste must not appear after a later keystroke")
        XCTAssertFalse(controller.isBusy)
    }

    func testFullAccessRevocationBlocksWritesAndDropsUnverifiableCachedPaste() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository()
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.keyboard(hasFullAccess: true))
        controller.saveProvidedText("cached", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }
        let id = try XCTUnwrap(controller.history.items.first?.id)

        controller.activate(.keyboard(hasFullAccess: false))
        controller.saveProvidedText("blocked", capturedAt: now.addingTimeInterval(1))
        controller.delete(id: id)
        var inserted: String?
        controller.resolveTextForInsertion(id: id) { inserted = $0 }

        XCTAssertTrue(controller.needsFullAccess)
        XCTAssertFalse(controller.canSave)
        XCTAssertNil(inserted)
        XCTAssertTrue(controller.history.items.isEmpty)
        XCTAssertEqual(controller.notice, "Allow Full Access to use clipboard history.")
        let captureCount = await repository.captureCallCount()
        let persisted = try await repository.load(at: now)
        XCTAssertEqual(captureCount, 1)
        XCTAssertEqual(persisted.history.items.map(\.text), ["cached"])
    }

    func testExternalDestructiveResetReplacesHigherRevisionCache() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(initialRevision: 20)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })
        controller.activate(.hostApp)
        controller.saveProvidedText("must disappear", capturedAt: now)
        try await waitUntil { !controller.isBusy && controller.history.items.count == 1 }

        await repository.simulateExternalDestructiveReset()
        controller.refreshHistory()
        try await waitUntil { controller.history.items.isEmpty }

        XCTAssertNil(controller.freshItem)
    }

    func testDamagedStorageExposesAndCompletesConfirmedReset() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardProjectControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(ClipboardRepository.fileName)
        try Data("damaged".utf8).write(to: fileURL)
        let fixedNow = now
        let controller = ClipboardController(
            repository: ClipboardRepository(fileURL: fileURL),
            settings: settings,
            now: { fixedNow }
        )

        controller.activate(.hostApp)
        try await waitUntil { controller.lastError != nil }
        XCTAssertTrue(controller.canResetStorage)
        XCTAssertTrue(controller.canClearStorage)

        controller.clear()
        try await waitUntil { !controller.isBusy && controller.lastError == nil }
        XCTAssertTrue(controller.history.items.isEmpty)
        XCTAssertFalse(controller.canResetStorage)
    }

    func testFailedDamagedStorageResetRemainsRetryable() async throws {
        let (settings, domain) = acceptedSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let repository = ClipboardTestRepository(failSweepsAsCorrupt: true, failClears: true)
        let fixedNow = now
        let controller = ClipboardController(repository: repository, settings: settings, now: { fixedNow })

        controller.activate(.hostApp)
        try await waitUntil { controller.canResetStorage }
        controller.clear()
        try await waitUntil { !controller.isBusy && controller.lastError != nil }

        XCTAssertTrue(controller.canResetStorage)
        XCTAssertTrue(controller.canClearStorage)
    }

    private func acceptedSettings() -> (KeyboardSettingsStore, String) {
        let domain = "KeyboardProjectTests.controller.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain) ?? .standard
        let settings = KeyboardSettingsStore(localDefaults: defaults, sharedDefaults: defaults)
        settings.refresh(canUseShared: true)
        settings.acceptClipboardNotice(at: now)
        return (settings, domain)
    }

    private func waitUntil(
        attempts: Int = 200,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition did not become true")
    }
}

private final class ControllerTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) { storedValue = value }

    var value: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

actor ClipboardTestRepository: ClipboardRepositoryProtocol {
    private var history = ClipboardHistory()
    private var revision: UInt64 = 0
    private var generation: UUID? = UUID()
    private var clearedAt: Date?
    private let failCaptures: Bool
    private let suspendCaptures: Bool
    private let suspendClears: Bool
    private let failSweepsAsCorrupt: Bool
    private let failClears: Bool
    private var captureCalled = false
    private var captureCount = 0
    private var captureContinuation: CheckedContinuation<Void, Never>?
    private var clearContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendNextSweep = false
    private var sweepContinuation: CheckedContinuation<Void, Never>?

    init(
        failCaptures: Bool = false,
        suspendCaptures: Bool = false,
        suspendClears: Bool = false,
        failSweepsAsCorrupt: Bool = false,
        failClears: Bool = false,
        initialRevision: UInt64 = 0
    ) {
        self.failCaptures = failCaptures
        self.suspendCaptures = suspendCaptures
        self.suspendClears = suspendClears
        self.failSweepsAsCorrupt = failSweepsAsCorrupt
        self.failClears = failClears
        revision = initialRevision
    }

    func captureWasCalled() -> Bool { captureCalled }
    func captureCallCount() -> Int { captureCount }
    func captureIsSuspended() -> Bool { captureContinuation != nil }
    func clearIsSuspended() -> Bool { clearContinuation != nil }
    func sweepIsSuspended() -> Bool { sweepContinuation != nil }

    func suspendNextSweep() { shouldSuspendNextSweep = true }

    func simulateExternalDestructiveReset() {
        history.removeAll()
        revision = 1
        generation = UUID()
    }

    func resumeCapture() {
        let continuation = captureContinuation
        captureContinuation = nil
        continuation?.resume()
    }

    func resumeClear() {
        let continuation = clearContinuation
        clearContinuation = nil
        continuation?.resume()
    }

    func resumeSweep() {
        let continuation = sweepContinuation
        sweepContinuation = nil
        continuation?.resume()
    }

    func load(at now: Date) async throws -> ClipboardSnapshot {
        var visible = history
        visible.sweep(at: now)
        return ClipboardSnapshot(
            revision: revision,
            generation: generation,
            history: visible,
            recovery: .none
        )
    }

    func capture(
        text: String,
        at capturedAt: Date,
        sourceWasTruncated: Bool
    ) async throws -> ClipboardMutationReceipt {
        captureCalled = true
        captureCount += 1
        if suspendCaptures {
            await withCheckedContinuation { continuation in
                captureContinuation = continuation
            }
        }
        try Task.checkCancellation()
        if failCaptures { throw ClipboardStoreError.writeFailed("injected") }
        if let clearedAt, capturedAt <= clearedAt {
            return receipt(.staleCaptureRejected)
        }
        let inserted = history.insert(
            text,
            at: capturedAt,
            sourceWasTruncated: sourceWasTruncated
        )
        revision += 1
        switch inserted {
        case .stored(let item): return receipt(.stored(item))
        case .refreshed(let item): return receipt(.refreshed(item))
        case .rejectedEmpty: return receipt(.rejectedEmpty)
        }
    }

    func sweep(at now: Date) async throws -> ClipboardMutationReceipt {
        if failSweepsAsCorrupt {
            throw ClipboardStoreError.corruptUnrecoverable("injected")
        }
        if shouldSuspendNextSweep {
            shouldSuspendNextSweep = false
            let count = history.sweep(at: now)
            if count > 0 { revision += 1 }
            let delayedReceipt = receipt(.swept(count))
            await withCheckedContinuation { continuation in
                sweepContinuation = continuation
            }
            try Task.checkCancellation()
            return delayedReceipt
        }
        try Task.checkCancellation()
        let count = history.sweep(at: now)
        if count > 0 { revision += 1 }
        return receipt(.swept(count))
    }

    func setPinned(_ pinned: Bool, id: UUID, at now: Date) async throws -> ClipboardMutationReceipt {
        switch history.setPinned(pinned, id: id) {
        case .changed:
            revision += 1
            return receipt(.pinChanged)
        case .unchanged: return receipt(.pinUnchanged)
        case .notFound: return receipt(.notFound)
        case .pinnedSectionFull: return receipt(.pinnedSectionFull)
        }
    }

    func delete(id: UUID, at now: Date) async throws -> ClipboardMutationReceipt {
        guard history.delete(id: id) else { return receipt(.notFound) }
        revision += 1
        return receipt(.deleted)
    }

    func clear(at now: Date) async throws -> ClipboardMutationReceipt {
        if failClears { throw ClipboardStoreError.writeFailed("injected") }
        if suspendClears {
            await withCheckedContinuation { continuation in
                clearContinuation = continuation
            }
        }
        try Task.checkCancellation()
        history.removeAll()
        clearedAt = max(clearedAt ?? .distantPast, now)
        revision += 1
        return receipt(.cleared)
    }

    private func receipt(_ outcome: ClipboardMutationOutcome) -> ClipboardMutationReceipt {
        ClipboardMutationReceipt(
            revision: revision,
            generation: generation,
            history: history,
            outcome: outcome,
            recovery: .none
        )
    }
}
