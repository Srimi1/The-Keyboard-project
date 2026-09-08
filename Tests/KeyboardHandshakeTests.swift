import XCTest
@testable import KeyboardProject

/// Tests for the record the extension leaves in the App Group.
///
/// The throttle is the whole point of the type: it is what makes the write cheap enough to
/// sit on `viewWillAppear`, which runs every time the keyboard appears in any app. A throttle
/// that is wrong in the *suppressing* direction is invisible — the host app just quietly shows
/// stale setup status forever — so it is worth pinning down here rather than on a device.
@MainActor
final class KeyboardHandshakeTests: XCTestCase {

    private let staleAfter: TimeInterval = 6 * 60 * 60
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(
        at offset: TimeInterval = 0,
        fullAccess: Bool = true,
        version: String = "0.1.0"
    ) -> KeyboardHandshake {
        KeyboardHandshake(
            lastSeenAt: now.addingTimeInterval(offset),
            hasFullAccess: fullAccess,
            appVersion: version
        )
    }

    func testNoStoredRecordIsNeverRedundant() {
        XCTAssertFalse(record().isRedundant(against: nil, staleAfter: staleAfter, now: now))
    }

    func testFreshIdenticalRecordIsRedundant() {
        let stored = record(at: -60)   // written a minute ago
        XCTAssertTrue(record().isRedundant(against: stored, staleAfter: staleAfter, now: now))
    }

    func testStaleIdenticalRecordIsWrittenAgain() {
        let stored = record(at: -(staleAfter + 1))
        XCTAssertFalse(
            record().isRedundant(against: stored, staleAfter: staleAfter, now: now),
            "Past the stale window the record must refresh, or 'the keyboard has run recently' means nothing"
        )
    }

    /// The signal that actually matters. Full Access has no notification path (C-41), so a
    /// changed value must always get through regardless of how recently we wrote.
    func testFullAccessChangeIsNeverSuppressed() {
        let stored = record(at: -1, fullAccess: false)
        XCTAssertFalse(record(fullAccess: true).isRedundant(against: stored, staleAfter: staleAfter, now: now))
    }

    func testAppVersionChangeIsNeverSuppressed() {
        let stored = record(at: -1, version: "0.1.0")
        XCTAssertFalse(record(version: "0.2.0").isRedundant(against: stored, staleAfter: staleAfter, now: now))
    }

    /// Regression: a record dated in the future — clock moved backwards, or the container came
    /// from a restored backup — used to read as "fresh" and suppress *every* later write, so
    /// the host app's setup status would freeze until the stored date fell six hours behind.
    func testFutureDatedRecordIsTreatedAsStale() {
        let stored = record(at: +(60 * 60 * 24 * 365))   // a year ahead
        XCTAssertFalse(
            record().isRedundant(against: stored, staleAfter: staleAfter, now: now),
            "A future-dated record must not suppress writes"
        )
    }

    func testBoundaryExactlyAtTheStaleWindowRefreshes() {
        let stored = record(at: -staleAfter)
        XCTAssertFalse(record().isRedundant(against: stored, staleAfter: staleAfter, now: now))
    }

    func testRoundTripsThroughJSON() throws {
        let original = record(fullAccess: false, version: "1.2.3")
        let decoded = try JSONDecoder().decode(
            KeyboardHandshake.self,
            from: try JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
    }
}
