import Foundation
import XCTest
@testable import KeyboardProject

final class ClipboardRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testMissingFileLoadsEmpty() async throws {
        try await withTemporaryStore { repository, _ in
            let snapshot = try await repository.load(at: now)
            XCTAssertEqual(snapshot.revision, 0)
            XCTAssertTrue(snapshot.history.items.isEmpty)
        }
    }

    func testCaptureRoundTripsAcrossFreshRepository() async throws {
        try await withTemporaryStore { repository, fileURL in
            let receipt = try await repository.capture(text: "hello", at: now)
            XCTAssertEqual(receipt.history.items.map(\.text), ["hello"])
            XCTAssertEqual(receipt.revision, 1)

            let reopened = ClipboardRepository(fileURL: fileURL)
            let snapshot = try await reopened.load(at: now)
            XCTAssertEqual(snapshot.history.items.map(\.text), ["hello"])
            XCTAssertEqual(snapshot.revision, 1)
        }
    }

    func testLegacyHistoryMigratesOnNextMutation() async throws {
        try await withTemporaryStore { repository, fileURL in
            var legacy = ClipboardHistory()
            legacy.insert("legacy", at: now)
            try JSONEncoder().encode(legacy).write(to: fileURL)

            let loaded = try await repository.load(at: now)
            XCTAssertEqual(loaded.recovery, .migratedLegacy)
            _ = try await repository.capture(text: "new", at: now.addingTimeInterval(1))

            let document = try JSONDecoder().decode(ClipboardDocument.self, from: Data(contentsOf: fileURL))
            XCTAssertEqual(document.schemaVersion, ClipboardDocument.currentSchemaVersion)
            XCTAssertEqual(Set(document.items.map(\.text)), ["legacy", "new"])
        }
    }

    func testCaptureSweepsExpiredAndInsertsAtomically() async throws {
        try await withTemporaryStore { repository, _ in
            _ = try await repository.capture(text: "expired", at: now.addingTimeInterval(-3_601))
            let receipt = try await repository.capture(text: "current", at: now)
            XCTAssertEqual(receipt.history.items.map(\.text), ["current"])
        }
    }

    func testPinDeleteAndClearPersist() async throws {
        try await withTemporaryStore { repository, fileURL in
            let captured = try await repository.capture(text: "one", at: now)
            let id = captured.history.items[0].id
            _ = try await repository.setPinned(true, id: id, at: now)
            _ = try await repository.delete(id: id, at: now)
            _ = try await repository.capture(text: "two", at: now.addingTimeInterval(1))
            _ = try await repository.clear(at: now.addingTimeInterval(2))

            let reopened = ClipboardRepository(fileURL: fileURL)
            let snapshot = try await reopened.load(at: now.addingTimeInterval(3))
            XCTAssertTrue(snapshot.history.items.isEmpty)
        }
    }

    func testClearFenceRejectsAnOlderDelayedCapture() async throws {
        try await withTemporaryStore { repository, _ in
            _ = try await repository.clear(at: now)
            let receipt = try await repository.capture(text: "stale", at: now.addingTimeInterval(-1))
            XCTAssertEqual(receipt.outcome, .staleCaptureRejected)
            XCTAssertTrue(receipt.history.items.isEmpty)
        }
    }

    func testConcurrentClearCannotBeUndoneByOlderCapture() async throws {
        try await withTemporaryStore { repository, fileURL in
            let secondProcess = ClipboardRepository(fileURL: fileURL)
            let captureTime = self.now
            let clearTime = captureTime.addingTimeInterval(1)
            async let capture = repository.capture(text: "must not return", at: captureTime)
            async let clear = secondProcess.clear(at: clearTime)
            _ = try await (capture, clear)

            let final = try await ClipboardRepository(fileURL: fileURL)
                .load(at: clearTime.addingTimeInterval(1))
            XCTAssertTrue(final.history.items.isEmpty)
        }
    }

    func testClearAlsoScrubsRecoveryCopy() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "secret", at: now)
            _ = try await repository.clear(at: now.addingTimeInterval(1))
            try Data("damaged-primary".utf8).write(to: fileURL)

            let recovered = try await ClipboardRepository(fileURL: fileURL)
                .load(at: now.addingTimeInterval(2))
            XCTAssertEqual(recovered.recovery, .usedBackup)
            XCTAssertTrue(recovered.history.items.isEmpty)
        }
    }

    func testDeleteAlsoScrubsRecoveryCopy() async throws {
        try await withTemporaryStore { repository, fileURL in
            let capture = try await repository.capture(text: "delete me", at: now)
            _ = try await repository.delete(id: capture.history.items[0].id, at: now.addingTimeInterval(1))
            try Data("damaged-primary".utf8).write(to: fileURL)

            let recovered = try await ClipboardRepository(fileURL: fileURL)
                .load(at: now.addingTimeInterval(2))
            XCTAssertTrue(recovered.history.items.isEmpty)
        }
    }

    func testSweepRemovesExpiredTextFromRecoveryCopy() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "expired", at: now.addingTimeInterval(-3_601))
            _ = try await repository.sweep(at: now)
            try Data("damaged-primary".utf8).write(to: fileURL)

            let recovered = try await ClipboardRepository(fileURL: fileURL).load(at: now)
            XCTAssertTrue(recovered.history.items.isEmpty)
        }
    }

    func testCorruptJSONIsPreservedAndNotSilentlyOverwritten() async throws {
        try await withTemporaryStore { repository, fileURL in
            let corrupt = Data("not-json".utf8)
            try corrupt.write(to: fileURL)

            do {
                _ = try await repository.capture(text: "new", at: now)
                XCTFail("corrupt storage unexpectedly accepted a write")
            } catch {
                XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
            }
        }
    }

    func testExplicitClearResetsUnrecoverableCorruptStorage() async throws {
        try await withTemporaryStore { repository, fileURL in
            try Data("not-json".utf8).write(to: fileURL)

            let receipt = try await repository.clear(at: now)
            XCTAssertEqual(receipt.outcome, .cleared)
            XCTAssertTrue(receipt.history.items.isEmpty)

            let document = try JSONDecoder().decode(
                ClipboardDocument.self,
                from: Data(contentsOf: fileURL)
            )
            XCTAssertEqual(document.schemaVersion, ClipboardDocument.currentSchemaVersion)
            XCTAssertEqual(document.clearedAt, now)
            XCTAssertTrue(document.items.isEmpty)
        }
    }

    func testFutureSchemaIsPreserved() async throws {
        try await withTemporaryStore { repository, fileURL in
            let future = ClipboardDocument(schemaVersion: 999)
            let data = try JSONEncoder().encode(future)
            try data.write(to: fileURL)

            do {
                _ = try await repository.capture(text: "new", at: now)
                XCTFail("future schema unexpectedly accepted a write")
            } catch let error as ClipboardStoreError {
                XCTAssertEqual(error, .unsupportedSchema(999))
                XCTAssertEqual(try Data(contentsOf: fileURL), data)
            }
        }
    }

    func testExplicitClearResetsFutureSchemaStorage() async throws {
        try await withTemporaryStore { repository, fileURL in
            try JSONEncoder().encode(ClipboardDocument(schemaVersion: 999)).write(to: fileURL)

            _ = try await repository.clear(at: now)

            let document = try JSONDecoder().decode(
                ClipboardDocument.self,
                from: Data(contentsOf: fileURL)
            )
            XCTAssertEqual(document.schemaVersion, ClipboardDocument.currentSchemaVersion)
            XCTAssertEqual(document.clearedAt, now)
            XCTAssertTrue(document.items.isEmpty)
        }
    }

    func testExplicitClearResetsOversizedStorageWithoutReadingItUnbounded() async throws {
        try await withTemporaryStore { repository, fileURL in
            let oversized = Data(
                repeating: 0x41,
                count: ClipboardLimits.maxEncodedFileBytes + 1
            )
            try oversized.write(to: fileURL)

            do {
                _ = try await repository.capture(text: "must not overwrite", at: now)
                XCTFail("oversized storage unexpectedly accepted a normal mutation")
            } catch {
                XCTAssertEqual(try Data(contentsOf: fileURL).count, oversized.count)
            }

            _ = try await repository.clear(at: now)
            XCTAssertLessThanOrEqual(
                try Data(contentsOf: fileURL).count,
                ClipboardLimits.maxEncodedFileBytes
            )
            let reloaded = try await repository.load(at: now)
            XCTAssertTrue(reloaded.history.items.isEmpty)
        }
    }

    func testClearRemovesQuarantinedClipboardCopies() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "recoverable", at: now)
            try Data("damaged-primary".utf8).write(to: fileURL)
            _ = try await repository.sweep(at: now.addingTimeInterval(1))

            let directory = fileURL.deletingLastPathComponent()
            let strandedTemporary = directory.appendingPathComponent(".clipboard-write-stranded.tmp")
            try Data("clipboard residue".utf8).write(to: strandedTemporary)
            let before = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            XCTAssertTrue(before.contains(where: {
                $0.lastPathComponent.hasPrefix("clipboard.corrupt-")
            }))

            _ = try await repository.clear(at: now.addingTimeInterval(2))

            let after = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            XCTAssertFalse(after.contains(where: {
                $0.lastPathComponent.hasPrefix("clipboard.corrupt-")
            }))
            XCTAssertFalse(FileManager.default.fileExists(atPath: strandedTemporary.path))
        }
    }

    func testSweepScrubsOnlyOwnedStrandedTemporaryFiles() async throws {
        try await withTemporaryStore { repository, fileURL in
            let directory = fileURL.deletingLastPathComponent()
            let stranded = directory.appendingPathComponent(".clipboard-write-stranded.tmp")
            let unrelated = directory.appendingPathComponent(".other-component.tmp")
            try Data("clipboard residue".utf8).write(to: stranded)
            try Data("keep".utf8).write(to: unrelated)

            _ = try await repository.sweep(at: now)

            XCTAssertFalse(FileManager.default.fileExists(atPath: stranded.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        }
    }

    func testSweepRepairsStaleCommitFenceBeforeRecoveryIsNeeded() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "recoverable", at: now)
            let commitURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("clipboard.commit.json")
            let staleMarker = Data(#"{"generation":null,"revision":0}"#.utf8)
            try staleMarker.write(to: commitURL)

            let repair = try await repository.sweep(at: now.addingTimeInterval(1))
            XCTAssertGreaterThan(repair.revision, 1)
            try Data("damaged-primary".utf8).write(to: fileURL)

            let recovered = try await repository.load(at: now.addingTimeInterval(2))
            XCTAssertEqual(recovered.recovery, .usedBackup)
            XCTAssertEqual(recovered.history.items.map(\.text), ["recoverable"])
        }
    }

    func testUncommittedSpeculativeBackupIsNeverRecovered() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "committed", at: now)
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("clipboard.backup.json")
            var speculative = try JSONDecoder().decode(
                ClipboardDocument.self,
                from: Data(contentsOf: fileURL)
            )
            speculative.revision += 1
            speculative.items.append(ClipboardItem(text: "speculative", createdAt: now))
            try JSONEncoder().encode(speculative).write(to: backupURL)
            try Data("damaged-primary".utf8).write(to: fileURL)

            do {
                _ = try await repository.load(at: now)
                XCTFail("an uncommitted recovery copy unexpectedly loaded")
            } catch let error as ClipboardStoreError {
                guard case .corruptUnrecoverable = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testCurrentFormatBackupWithoutCommitMarkerIsNeverRecovered() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "current", at: now)
            let commitURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("clipboard.commit.json")
            try FileManager.default.removeItem(at: commitURL)
            try Data("damaged-primary".utf8).write(to: fileURL)

            do {
                _ = try await repository.load(at: now)
                XCTFail("a current-format backup without its fence unexpectedly loaded")
            } catch let error as ClipboardStoreError {
                guard case .corruptUnrecoverable = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testDivergentBackupWithMatchingGenerationAndRevisionIsNeverRecovered() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "committed", at: now)
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("clipboard.backup.json")
            var divergent = try JSONDecoder().decode(
                ClipboardDocument.self,
                from: Data(contentsOf: backupURL)
            )
            divergent.items = [ClipboardItem(text: "divergent", createdAt: now)]
            try JSONEncoder().encode(divergent).write(to: backupURL)
            try Data("damaged-primary".utf8).write(to: fileURL)

            do {
                _ = try await repository.load(at: now)
                XCTFail("same-revision divergent recovery content unexpectedly loaded")
            } catch let error as ClipboardStoreError {
                guard case .corruptUnrecoverable = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testFutureSchemaMissingCurrentFieldsIsNeverDecodedAsLegacy() async throws {
        try await withTemporaryStore { repository, fileURL in
            let future = Data(#"{"schemaVersion":999,"items":[]}"#.utf8)
            try future.write(to: fileURL)

            do {
                _ = try await repository.capture(text: "new", at: now)
                XCTFail("future schema unexpectedly accepted a write")
            } catch let error as ClipboardStoreError {
                XCTAssertEqual(error, .unsupportedSchema(999))
                XCTAssertEqual(try Data(contentsOf: fileURL), future)
            }
        }
    }

    func testTransientReadFailureDoesNotFallBackOrReplacePrimary() async throws {
        try await withTemporaryStore { _, fileURL in
            // A directory at the primary path produces an I/O failure rather than a
            // structural JSON failure. A valid backup must not mask that condition.
            try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("clipboard.backup.json")
            let backup = try JSONEncoder().encode(ClipboardDocument(items: [
                ClipboardItem(text: "older backup", createdAt: now),
            ]))
            try backup.write(to: backupURL)

            do {
                _ = try await ClipboardRepository(fileURL: fileURL).load(at: now)
                XCTFail("transient read failure unexpectedly used the backup")
            } catch let error as ClipboardStoreError {
                guard case .readFailed = error else {
                    return XCTFail("unexpected error: \(error)")
                }
                var isDirectory: ObjCBool = false
                XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
                XCTAssertTrue(isDirectory.boolValue)
            }
        }
    }

    func testStoredFilesAreExcludedFromBackup() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "local only", at: now)
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("clipboard.backup.json")
            XCTAssertEqual(
                try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
                true
            )
            XCTAssertEqual(
                try backupURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
                true
            )
            let commitURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("clipboard.commit.json")
            XCTAssertEqual(
                try commitURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
                true
            )
        }
    }

    func testStoredFilesUseCompleteDataProtectionOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The simulator does not expose NSFileProtectionKey; verify on device.")
        #else
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "protected", at: now)
            let directory = fileURL.deletingLastPathComponent()
            for url in [
                fileURL,
                directory.appendingPathComponent("clipboard.backup.json"),
                directory.appendingPathComponent("clipboard.commit.json"),
            ] {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                XCTAssertEqual(
                    attributes[.protectionKey] as? FileProtectionType,
                    .complete,
                    "\(url.lastPathComponent) must be protected"
                )
            }
        }
        #endif
    }

    func testQuarantinedCorruptPrimaryIsProtectedAndExcludedBeforeRetention() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "first", at: now)
            try Data("corrupt".utf8).write(to: fileURL)

            _ = try await repository.capture(text: "second", at: now.addingTimeInterval(1))

            let quarantines = try FileManager.default.contentsOfDirectory(
                at: fileURL.deletingLastPathComponent(),
                includingPropertiesForKeys: [.isExcludedFromBackupKey]
            ).filter { $0.lastPathComponent.hasPrefix("clipboard.corrupt-") }
            let quarantine = try XCTUnwrap(quarantines.first)
            XCTAssertEqual(
                try quarantine.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
                true
            )
            #if !targetEnvironment(simulator)
            let attributes = try FileManager.default.attributesOfItem(atPath: quarantine.path)
            XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
            #endif
        }
    }

    func testLoadMigratesBackupExclusionForExistingArtifactsAndQuarantines() async throws {
        try await withTemporaryStore { repository, fileURL in
            _ = try await repository.capture(text: "existing", at: now)
            let directory = fileURL.deletingLastPathComponent()
            let urls = [
                fileURL,
                directory.appendingPathComponent("clipboard.backup.json"),
                directory.appendingPathComponent("clipboard.commit.json"),
            ]
            let quarantine = directory.appendingPathComponent("clipboard.corrupt-existing.json")
            try Data("old corrupt copy".utf8).write(to: quarantine)

            for var url in urls + [quarantine] {
                var values = URLResourceValues()
                values.isExcludedFromBackup = false
                try url.setResourceValues(values)
            }

            _ = try await repository.load(at: now)

            for url in urls + [quarantine] {
                XCTAssertEqual(
                    try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
                    true,
                    "\(url.lastPathComponent) was not migrated"
                )
            }
        }
    }

    func testRepositoryResolvesContainerAgainAfterItBecomesAvailable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardProjectTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = RepositoryURLGate()
        let repository = ClipboardRepository(fileURLProvider: { gate.value })

        do {
            _ = try await repository.load(at: now)
            XCTFail("an unavailable container unexpectedly loaded")
        } catch let error as ClipboardStoreError {
            XCTAssertEqual(error, .unavailable)
        }

        gate.value = directory.appendingPathComponent(ClipboardRepository.fileName)
        _ = try await repository.capture(text: "available now", at: now)
        let loaded = try await repository.load(at: now)
        XCTAssertEqual(loaded.history.items.map(\.text), ["available now"])
    }

    func testConcurrentRepositoriesDoNotLoseCaptures() async throws {
        try await withTemporaryStore { first, fileURL in
            let second = ClipboardRepository(fileURL: fileURL)
            let firstTimestamp = self.now
            let secondTimestamp = firstTimestamp.addingTimeInterval(1)
            async let one = first.capture(text: "one", at: firstTimestamp)
            async let two = second.capture(text: "two", at: secondTimestamp)
            _ = try await (one, two)

            let result = try await ClipboardRepository(fileURL: fileURL)
                .load(at: firstTimestamp.addingTimeInterval(2))
            XCTAssertEqual(Set(result.history.items.map(\.text)), ["one", "two"])
        }
    }

    func testUnavailableDirectoryThrowsInsteadOfReturningOptimisticState() async {
        let repository = ClipboardRepository(fileURL: URL(fileURLWithPath: "/dev/null/clipboard.json"))
        do {
            _ = try await repository.capture(text: "not saved", at: now)
            XCTFail("write unexpectedly succeeded")
        } catch {
            XCTAssertTrue(true)
        }
    }

    private func withTemporaryStore(
        _ operation: (ClipboardRepository, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardProjectTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(ClipboardRepository.fileName)
        try await operation(ClipboardRepository(fileURL: fileURL), fileURL)
    }
}

private final class RepositoryURLGate: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: URL?

    var value: URL? {
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
