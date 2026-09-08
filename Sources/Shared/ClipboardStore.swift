import CryptoKit
import Foundation

nonisolated enum ClipboardStoreError: Error, Equatable, LocalizedError, Sendable {
    case unavailable
    case fileTooLarge(Int)
    case unsupportedSchema(Int)
    case invalidData(String)
    case readFailed(String)
    case writeFailed(String)
    case corruptUnrecoverable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Clipboard storage is unavailable."
        case .fileTooLarge:
            return "Clipboard storage exceeded its safety limit."
        case .unsupportedSchema:
            return "Clipboard storage was created by a newer version."
        case .invalidData, .corruptUnrecoverable:
            return "Clipboard storage is damaged and was preserved for recovery."
        case .readFailed:
            return "Clipboard history could not be read."
        case .writeFailed:
            return "The clipboard change could not be saved."
        }
    }
}

nonisolated enum ClipboardRecovery: Equatable, Sendable {
    case none
    case migratedLegacy
    case usedBackup
    /// Primary and backup committed, but the small recovery fence needs another sweep.
    case repairPending
}

nonisolated enum ClipboardMutationOutcome: Equatable, Sendable {
    case stored(ClipboardItem)
    case refreshed(ClipboardItem)
    case rejectedEmpty
    case staleCaptureRejected
    case pinChanged
    case pinUnchanged
    case pinnedSectionFull
    case notFound
    case deleted
    case cleared
    case swept(Int)
}

nonisolated struct ClipboardSnapshot: Equatable, Sendable {
    let revision: UInt64
    let generation: UUID?
    let history: ClipboardHistory
    let recovery: ClipboardRecovery

    init(
        revision: UInt64,
        generation: UUID? = nil,
        history: ClipboardHistory,
        recovery: ClipboardRecovery
    ) {
        self.revision = revision
        self.generation = generation
        self.history = history
        self.recovery = recovery
    }
}

nonisolated struct ClipboardMutationReceipt: Equatable, Sendable {
    let revision: UInt64
    let generation: UUID?
    let history: ClipboardHistory
    let outcome: ClipboardMutationOutcome
    let recovery: ClipboardRecovery

    init(
        revision: UInt64,
        generation: UUID? = nil,
        history: ClipboardHistory,
        outcome: ClipboardMutationOutcome,
        recovery: ClipboardRecovery
    ) {
        self.revision = revision
        self.generation = generation
        self.history = history
        self.outcome = outcome
        self.recovery = recovery
    }
}

nonisolated protocol ClipboardRepositoryProtocol: Sendable {
    func load(at now: Date) async throws -> ClipboardSnapshot
    func capture(
        text: String,
        at capturedAt: Date,
        sourceWasTruncated: Bool
    ) async throws -> ClipboardMutationReceipt
    func sweep(at now: Date) async throws -> ClipboardMutationReceipt
    func setPinned(_ pinned: Bool, id: UUID, at now: Date) async throws -> ClipboardMutationReceipt
    func delete(id: UUID, at now: Date) async throws -> ClipboardMutationReceipt
    func clear(at now: Date) async throws -> ClipboardMutationReceipt
}

/// Versioned on-disk envelope. The prototype stored `ClipboardHistory` directly; decoding
/// still accepts that shape and the next successful mutation upgrades it atomically.
nonisolated struct ClipboardDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// Distinguishes a confirmed destructive reset from an older delayed revision.
    /// Optional so pre-launch versioned files decode and migrate without data loss.
    var generation: UUID?
    var revision: UInt64
    var clearedAt: Date?
    var items: [ClipboardItem]

    init(
        schemaVersion: Int = currentSchemaVersion,
        generation: UUID? = UUID(),
        revision: UInt64 = 0,
        clearedAt: Date? = nil,
        items: [ClipboardItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generation = generation
        self.revision = revision
        self.clearedAt = clearedAt
        self.items = items
    }

    var history: ClipboardHistory {
        get { ClipboardHistory(items: items) }
        set { items = newValue.items }
    }
}

/// Small commit fence for the two-file transaction. A backup is eligible for recovery only
/// when this marker names the same store generation and revision.
nonisolated private struct ClipboardCommitMarker: Codable, Equatable, Sendable {
    let generation: UUID?
    let revision: UInt64
    let documentHash: String?
}

/// Async, bounded JSON persistence shared by the host app and keyboard extension.
///
/// The actor orders work inside one process. `NSFileCoordinator` covers the complete
/// read-modify-write transaction across the two App Group processes. No caller performs file
/// I/O on the main actor, and UI is updated only from a persisted receipt.
actor ClipboardRepository: ClipboardRepositoryProtocol {
    nonisolated static let fileName = "clipboard.json"

    private let fileURLProvider: @Sendable () -> URL?
    private let fileManager: FileManager

    /// Production initializer. The App Group URL is resolved for every operation because
    /// enabling Full Access can make it available without terminating the keyboard process.
    init(fileManager: FileManager = .default) {
        fileURLProvider = {
            AppGroup.containerURL?.appendingPathComponent(ClipboardRepository.fileName)
        }
        self.fileManager = fileManager
    }

    /// Fixed URL seam for deterministic tests (including an intentionally unavailable nil).
    init(fileURL: URL?, fileManager: FileManager = .default) {
        fileURLProvider = { fileURL }
        self.fileManager = fileManager
    }

    /// Dynamic seam used to regression-test an App Group becoming available in-process.
    init(
        fileURLProvider: @escaping @Sendable () -> URL?,
        fileManager: FileManager = .default
    ) {
        self.fileURLProvider = fileURLProvider
        self.fileManager = fileManager
    }

    func load(at now: Date = Date()) async throws -> ClipboardSnapshot {
        let state = try loadCoordinated()
        var history = state.document.history
        history.sweep(at: now)
        return ClipboardSnapshot(
            revision: state.document.revision,
            generation: state.document.generation,
            history: history,
            recovery: state.recovery
        )
    }

    func capture(
        text: String,
        at capturedAt: Date,
        sourceWasTruncated: Bool = false
    ) async throws -> ClipboardMutationReceipt {
        try mutate(
            command: .capture(text, capturedAt, sourceWasTruncated),
            now: capturedAt
        )
    }

    func sweep(at now: Date) async throws -> ClipboardMutationReceipt {
        try mutate(command: .sweep, now: now)
    }

    func setPinned(_ pinned: Bool, id: UUID, at now: Date = Date()) async throws -> ClipboardMutationReceipt {
        try mutate(command: .setPinned(pinned, id), now: now)
    }

    func delete(id: UUID, at now: Date = Date()) async throws -> ClipboardMutationReceipt {
        try mutate(command: .delete(id), now: now)
    }

    func clear(at now: Date = Date()) async throws -> ClipboardMutationReceipt {
        try mutate(command: .clear, now: now)
    }

    private enum Command {
        case capture(String, Date, Bool)
        case sweep
        case setPinned(Bool, UUID)
        case delete(UUID)
        case clear
    }

    private struct StoredState {
        var document: ClipboardDocument
        var recovery: ClipboardRecovery
        var primaryWasValid: Bool
        var recoveryCopyNeedsRepair: Bool
    }

    private func mutate(command: Command, now: Date) throws -> ClipboardMutationReceipt {
        try Task.checkCancellation()
        guard let fileURL = fileURLProvider() else { throw ClipboardStoreError.unavailable }
        try prepareDirectory(for: fileURL)
        let backupURL = backupURL(for: fileURL)
        let isExplicitClear: Bool
        if case .clear = command { isExplicitClear = true } else { isExplicitClear = false }

        return try coordinatePair(
            primaryURL: fileURL,
            backupURL: backupURL,
            reportsWriteFailure: true
        ) { coordinatedPrimary, coordinatedBackup in
            try Task.checkCancellation()
            try removeTemporaryDocuments(in: coordinatedPrimary.deletingLastPathComponent())
            try secureExistingArtifacts(
                primaryURL: coordinatedPrimary,
                backupURL: coordinatedBackup
            )
            var state: StoredState
            do {
                state = try loadForMutation(
                    primaryURL: coordinatedPrimary,
                    backupURL: coordinatedBackup
                )
            } catch let error as ClipboardStoreError {
                // A confirmed Clear is also the recovery path for a future-schema, oversized,
                // or otherwise unreadable file. No other mutation may discard those bytes.
                guard isExplicitClear, error.canBeExplicitlyReset else { throw error }
                state = StoredState(
                    document: ClipboardDocument(clearedAt: now),
                    recovery: .none,
                    primaryWasValid: false,
                    recoveryCopyNeedsRepair: true
                )
            }
            let previousDocument = state.document
            var history = state.document.history
            let sweptCount = history.sweep(at: now)
            var changed = sweptCount > 0
            let outcome: ClipboardMutationOutcome

            switch command {
            case .capture(let text, let capturedAt, let sourceWasTruncated):
                if let clearedAt = state.document.clearedAt, capturedAt <= clearedAt {
                    outcome = .staleCaptureRejected
                } else {
                    switch history.insert(
                        text,
                        at: capturedAt,
                        sourceWasTruncated: sourceWasTruncated
                    ) {
                    case .stored(let item):
                        outcome = .stored(item)
                        changed = true
                    case .refreshed(let item):
                        outcome = .refreshed(item)
                        changed = true
                    case .rejectedEmpty:
                        outcome = .rejectedEmpty
                    }
                }

            case .sweep:
                outcome = .swept(sweptCount)

            case .setPinned(let pinned, let id):
                switch history.setPinned(pinned, id: id) {
                case .changed:
                    outcome = .pinChanged
                    changed = true
                case .unchanged:
                    outcome = .pinUnchanged
                case .notFound:
                    outcome = .notFound
                case .pinnedSectionFull:
                    outcome = .pinnedSectionFull
                }

            case .delete(let id):
                if history.delete(id: id) {
                    outcome = .deleted
                    changed = true
                } else {
                    outcome = .notFound
                }

            case .clear:
                history.removeAll()
                state.document.clearedAt = max(state.document.clearedAt ?? .distantPast, now)
                outcome = .cleared
                changed = true
            }

            let mustRepair = state.recovery != .none
                || !state.primaryWasValid
                || state.recoveryCopyNeedsRepair
            if changed || mustRepair {
                try Task.checkCancellation()
                guard state.document.revision < UInt64.max else {
                    throw ClipboardStoreError.invalidData("revision overflow")
                }
                state.document.schemaVersion = ClipboardDocument.currentSchemaVersion
                if state.document.generation == nil { state.document.generation = UUID() }
                state.document.revision += 1
                state.document.history = history
                let recoveryFenceCommitted = try save(
                    state.document,
                    to: coordinatedPrimary,
                    backupURL: coordinatedBackup,
                    previousDocument: previousDocument
                )
                if !recoveryFenceCommitted { state.recovery = .repairPending }
                if isExplicitClear {
                    try removeClipboardArtifacts(in: coordinatedPrimary.deletingLastPathComponent())
                }
            }

            return ClipboardMutationReceipt(
                revision: state.document.revision,
                generation: state.document.generation,
                history: history,
                outcome: outcome,
                recovery: state.recovery
            )
        }
    }

    private func loadCoordinated() throws -> StoredState {
        guard let fileURL = fileURLProvider() else { throw ClipboardStoreError.unavailable }
        try prepareDirectory(for: fileURL)
        let backupURL = backupURL(for: fileURL)

        // Claim both documents for the whole decision. A reader can therefore never observe
        // the recovery copy from a transaction whose primary commit has not completed yet.
        return try coordinatePair(
            primaryURL: fileURL,
            backupURL: backupURL,
            reportsWriteFailure: false
        ) { coordinatedPrimary, coordinatedBackup in
            try removeTemporaryDocuments(in: coordinatedPrimary.deletingLastPathComponent())
            try secureExistingArtifacts(
                primaryURL: coordinatedPrimary,
                backupURL: coordinatedBackup
            )
            return try loadState(
                primaryURL: coordinatedPrimary,
                backupURL: coordinatedBackup,
                quarantineDamagedPrimary: false
            )
        }
    }

    /// Called while both the primary and recovery URL are exclusively coordinated.
    private func loadForMutation(primaryURL: URL, backupURL: URL) throws -> StoredState {
        try loadState(
            primaryURL: primaryURL,
            backupURL: backupURL,
            quarantineDamagedPrimary: true
        )
    }

    private func loadState(
        primaryURL: URL,
        backupURL: URL,
        quarantineDamagedPrimary: Bool
    ) throws -> StoredState {
        guard fileManager.fileExists(atPath: primaryURL.path) else {
            if fileManager.fileExists(atPath: backupURL.path) {
                let decoded = try decodeDocument(at: backupURL)
                try requireCommittedBackup(decoded.document, primaryURL: primaryURL)
                return StoredState(
                    document: decoded.document,
                    recovery: .usedBackup,
                    primaryWasValid: false,
                    recoveryCopyNeedsRepair: true
                )
            }
                return StoredState(
                    document: ClipboardDocument(generation: nil),
                    recovery: .none,
                    primaryWasValid: false,
                    recoveryCopyNeedsRepair: false
                )
        }

        do {
            let decoded = try decodeDocument(at: primaryURL)
            let recoveryCopyNeedsRepair = !recoveryCopyIsHealthy(
                for: decoded.document,
                primaryURL: primaryURL,
                backupURL: backupURL
            )
            return StoredState(
                document: decoded.document,
                recovery: decoded.wasLegacy ? .migratedLegacy : .none,
                primaryWasValid: true,
                recoveryCopyNeedsRepair: recoveryCopyNeedsRepair
            )
        } catch let error as ClipboardStoreError {
            guard error.canRecoverFromBackup else { throw error }
            guard fileManager.fileExists(atPath: backupURL.path) else {
                throw ClipboardStoreError.corruptUnrecoverable(error.localizedDescription)
            }
            let decoded: DecodedDocument
            do {
                decoded = try decodeDocument(at: backupURL)
                try requireCommittedBackup(decoded.document, primaryURL: primaryURL)
            } catch {
                throw ClipboardStoreError.corruptUnrecoverable(error.localizedDescription)
            }
            if quarantineDamagedPrimary { try quarantine(primaryURL) }
            return StoredState(
                document: decoded.document,
                recovery: .usedBackup,
                primaryWasValid: false,
                recoveryCopyNeedsRepair: true
            )
        }
    }

    private struct DecodedDocument {
        let document: ClipboardDocument
        let wasLegacy: Bool
    }

    private func decodeDocument(at url: URL) throws -> DecodedDocument {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > ClipboardLimits.maxEncodedFileBytes {
                throw ClipboardStoreError.fileTooLarge(size)
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= ClipboardLimits.maxEncodedFileBytes else {
                throw ClipboardStoreError.fileTooLarge(data.count)
            }

            let decoder = JSONDecoder()
            let jsonObject = try? JSONSerialization.jsonObject(with: data)
            let jsonDictionary = jsonObject as? [String: Any]

            // A version marker means this is an envelope, even if a future version no
            // longer has today's required fields. Never fall through to the permissive
            // legacy decoder and overwrite a newer schema as if it were old history.
            if jsonDictionary?.keys.contains("schemaVersion") == true {
                guard let version = jsonDictionary?["schemaVersion"] as? Int else {
                    throw ClipboardStoreError.invalidData("schema version was not an integer")
                }
                guard version == ClipboardDocument.currentSchemaVersion else {
                    throw ClipboardStoreError.unsupportedSchema(version)
                }
                let document: ClipboardDocument
                do {
                    document = try decoder.decode(ClipboardDocument.self, from: data)
                } catch {
                    throw ClipboardStoreError.invalidData("versioned document was incomplete")
                }
                try document.history.validate()
                return DecodedDocument(document: document, wasLegacy: false)
            }

            if let legacy = try? decoder.decode(ClipboardHistory.self, from: data) {
                try legacy.validate()
                return DecodedDocument(
                    document: ClipboardDocument(generation: nil, items: legacy.items),
                    wasLegacy: true
                )
            }

            throw ClipboardStoreError.invalidData("JSON did not match a supported schema")
        } catch let error as ClipboardStoreError {
            throw error
        } catch {
            throw ClipboardStoreError.readFailed(error.localizedDescription)
        }
    }

    private func save(
        _ document: ClipboardDocument,
        to primaryURL: URL,
        backupURL: URL,
        previousDocument: ClipboardDocument
    ) throws -> Bool {
        try document.history.validate()
        try previousDocument.history.validate()
        let encoded = try encodeDocument(document)
        let previousBackup = try encodeDocument(previousDocument)
        guard encoded.count <= ClipboardLimits.maxEncodedFileBytes else {
            throw ClipboardStoreError.fileTooLarge(encoded.count)
        }
        guard previousBackup.count <= ClipboardLimits.maxEncodedFileBytes else {
            throw ClipboardStoreError.fileTooLarge(previousBackup.count)
        }

        do {
            // Establish a fence for the last committed state *before* replacing the backup.
            // If the primary commit subsequently fails, a speculative backup revision cannot
            // be recovered even when restoring the old backup also fails.
            try writeCommitMarker(
                commitMarker(for: previousDocument),
                primaryURL: primaryURL
            )
            // The recovery copy mirrors the exact committed revision. Keeping the old
            // primary here would retain cleared/deleted/expired clipboard text and could
            // resurrect it after later corruption.
            try writeProtected(encoded, to: backupURL)
            do {
                try writeProtected(encoded, to: primaryURL)
            } catch {
                // The primary is authoritative. If committing it fails, roll the recovery
                // copy back so a failed capture cannot surface later through recovery.
                try? writeProtected(previousBackup, to: backupURL)
                throw error
            }
            do {
                try writeCommitMarker(
                    commitMarker(for: document),
                    primaryURL: primaryURL
                )
                return true
            } catch {
                // Both protected data files already contain the persisted mutation. Report
                // that truth, mark recovery degraded, and let the next sweep repair the fence.
                return false
            }
        } catch let error as ClipboardStoreError {
            throw error
        } catch {
            throw ClipboardStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func recoveryCopyIsHealthy(
        for primaryDocument: ClipboardDocument,
        primaryURL: URL,
        backupURL: URL
    ) -> Bool {
        guard fileManager.fileExists(atPath: backupURL.path),
              fileManager.fileExists(atPath: commitURL(for: primaryURL).path),
              let backup = try? decodeDocument(at: backupURL),
              backup.document == primaryDocument else { return false }
        do {
            try requireCommittedBackup(backup.document, primaryURL: primaryURL)
            return true
        } catch {
            return false
        }
    }

    private func encodeDocument(_ document: ClipboardDocument) throws -> Data {
        do {
            return try JSONEncoder().encode(document)
        } catch {
            throw ClipboardStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func commitMarker(for document: ClipboardDocument) throws -> ClipboardCommitMarker {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw ClipboardStoreError.writeFailed("could not bind clipboard commit marker")
        }
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return ClipboardCommitMarker(
            generation: document.generation,
            revision: document.revision,
            documentHash: digest
        )
    }

    private func writeCommitMarker(_ marker: ClipboardCommitMarker, primaryURL: URL) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(marker)
        } catch {
            throw ClipboardStoreError.writeFailed("could not encode clipboard commit marker")
        }
        guard data.count <= 4 * 1_024 else {
            throw ClipboardStoreError.writeFailed("clipboard commit marker exceeded its limit")
        }
        try writeProtected(data, to: commitURL(for: primaryURL))
    }

    private func requireCommittedBackup(_ document: ClipboardDocument, primaryURL: URL) throws {
        let url = commitURL(for: primaryURL)
        // Only a genuinely pre-marker document (which has no generation) may be recovered
        // without a fence. A current-format backup with a missing marker could be a speculative
        // write whose primary commit never completed, so accepting it would resurrect data.
        guard fileManager.fileExists(atPath: url.path) else {
            guard document.generation == nil else {
                throw ClipboardStoreError.invalidData("backup commit marker was missing")
            }
            return
        }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= 4 * 1_024 else {
                throw ClipboardStoreError.invalidData("commit marker exceeded its limit")
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 4 * 1_024 else {
                throw ClipboardStoreError.invalidData("commit marker exceeded its limit")
            }
            let marker = try JSONDecoder().decode(ClipboardCommitMarker.self, from: data)
            guard marker.generation == document.generation,
                  marker.revision == document.revision else {
                throw ClipboardStoreError.invalidData("backup was not committed")
            }
            if document.generation != nil {
                let actualHash = try commitMarker(for: document).documentHash
                guard let expectedHash = marker.documentHash,
                      expectedHash == actualHash else {
                    throw ClipboardStoreError.invalidData("backup content did not match its commit marker")
                }
            }
        } catch let error as ClipboardStoreError {
            throw error
        } catch {
            throw ClipboardStoreError.invalidData("commit marker was unreadable")
        }
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".clipboard-write-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        // Create and secure the empty inode before writing clipboard bytes. This closes the
        // small window in which a backup agent could observe a populated but not-yet-excluded
        // temporary file. A crash can leave only this exact owned temp name, swept next load.
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw ClipboardStoreError.writeFailed("could not create protected temporary storage")
        }
        var protectedURL = temporaryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
        do {
            let handle = try FileHandle(forWritingTo: temporaryURL)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            throw ClipboardStoreError.writeFailed("could not write protected temporary storage")
        }

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }

    private func quarantine(_ url: URL) throws {
        let quarantineURL = url.deletingLastPathComponent()
            .appendingPathComponent("clipboard.corrupt-\(UUID().uuidString).json")
        do {
            // Secure and exclude the existing inode before renaming it. A corrupt legacy file
            // may predate these policies, and moving it first would briefly create a forgotten,
            // backup-eligible copy containing clipboard text.
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            var protectedURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedURL.setResourceValues(values)
            try fileManager.moveItem(at: url, to: quarantineURL)
        } catch {
            throw ClipboardStoreError.writeFailed("could not preserve damaged storage")
        }
    }

    private func removeTemporaryDocuments(in directory: URL) throws {
        try removeClipboardArtifacts(in: directory, includesQuarantines: false)
    }

    /// Migrates valid files and retained corrupt copies created before the protection policy.
    /// This runs under the primary/backup coordinator before any bytes are decoded or exposed.
    private func secureExistingArtifacts(primaryURL: URL, backupURL: URL) throws {
        let directory = primaryURL.deletingLastPathComponent()
        var urls = [primaryURL, backupURL, commitURL(for: primaryURL)]
        do {
            urls += try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            ).filter {
                $0.lastPathComponent.hasPrefix("clipboard.corrupt-")
                    && $0.pathExtension == "json"
            }

            for url in urls where fileManager.fileExists(atPath: url.path) {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: url.path
                )
                var protectedURL = url
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try protectedURL.setResourceValues(values)
            }
        } catch {
            throw ClipboardStoreError.writeFailed("could not secure existing clipboard storage")
        }
    }

    private func removeClipboardArtifacts(
        in directory: URL,
        includesQuarantines: Bool = true
    ) throws {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
            for url in contents {
                let name = url.lastPathComponent
                let isTemporary = name.hasPrefix(".clipboard-write-") && name.hasSuffix(".tmp")
                let isQuarantine = includesQuarantines
                    && name.hasPrefix("clipboard.corrupt-")
                    && url.pathExtension == "json"
                if isTemporary || isQuarantine { try fileManager.removeItem(at: url) }
            }
        } catch let error as ClipboardStoreError {
            throw error
        } catch {
            throw ClipboardStoreError.writeFailed("could not remove damaged clipboard copies")
        }
    }

    private func prepareDirectory(for url: URL) throws {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw ClipboardStoreError.unavailable
        }
    }

    private func backupURL(for primaryURL: URL) -> URL {
        primaryURL.deletingLastPathComponent().appendingPathComponent("clipboard.backup.json")
    }

    private func commitURL(for primaryURL: URL) -> URL {
        primaryURL.deletingLastPathComponent().appendingPathComponent("clipboard.commit.json")
    }

    /// NSFileCoordinator has no two-item read API, so both tiny files are claimed through its
    /// two-item writing form for reads and mutations alike. That intentionally serializes the
    /// host app and extension around one primary/backup transaction.
    private func coordinatePair<T>(
        primaryURL: URL,
        backupURL: URL,
        reportsWriteFailure: Bool,
        operation: (URL, URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: primaryURL,
            options: .forMerging,
            writingItemAt: backupURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedPrimary, coordinatedBackup in
            result = Result { try operation(coordinatedPrimary, coordinatedBackup) }
        }
        if let coordinationError {
            if reportsWriteFailure {
                throw ClipboardStoreError.writeFailed(coordinationError.localizedDescription)
            }
            throw ClipboardStoreError.readFailed(coordinationError.localizedDescription)
        }
        guard let result else {
            if reportsWriteFailure {
                throw ClipboardStoreError.writeFailed("coordination produced no result")
            }
            throw ClipboardStoreError.readFailed("coordination produced no result")
        }
        return try result.get()
    }
}

extension ClipboardStoreError {
    var canRecoverFromBackup: Bool {
        switch self {
        case .fileTooLarge, .invalidData:
            return true
        case .unavailable, .unsupportedSchema, .readFailed, .writeFailed, .corruptUnrecoverable:
            return false
        }
    }

    var canBeExplicitlyReset: Bool {
        switch self {
        case .fileTooLarge, .unsupportedSchema, .invalidData, .corruptUnrecoverable:
            return true
        case .unavailable, .readFailed, .writeFailed:
            return false
        }
    }
}
