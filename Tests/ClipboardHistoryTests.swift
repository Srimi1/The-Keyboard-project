import XCTest
@testable import KeyboardProject

final class ClipboardHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testWhitespaceInsertIsRejectedWithoutMutation() {
        var history = ClipboardHistory()
        XCTAssertEqual(history.insert(" \n\t ", at: now), .rejectedEmpty)
        XCTAssertTrue(history.items.isEmpty)
    }

    func testLargeUnicodeTextIsTruncatedAtGraphemeBoundaryBeforeHashing() {
        let cluster = "👨‍👩‍👧‍👦"
        let source = String(repeating: cluster, count: 2_000)
        let item = ClipboardItem(text: source, createdAt: now)

        XCTAssertLessThanOrEqual(item.text.utf8.count, ClipboardLimits.maxTextBytes)
        XCTAssertTrue(item.wasTruncated)
        XCTAssertEqual(item.contentHash, ClipboardLimits.hash(item.text))
        XCTAssertTrue(item.text.allSatisfy { String($0) == cluster })
    }

    func testBoundedProviderTruncationMarkerIsPersisted() {
        var history = ClipboardHistory()
        guard case .stored(let item) = history.insert(
            "bounded text",
            at: now,
            sourceWasTruncated: true
        ) else {
            return XCTFail("bounded provider text was not stored")
        }
        XCTAssertTrue(item.wasTruncated)
    }

    func testDuplicateRefreshKeepsIdentityPinAndSingleEntry() {
        var history = ClipboardHistory()
        guard case .stored(let first) = history.insert("same", at: now) else {
            return XCTFail("first insert was not stored")
        }
        XCTAssertEqual(history.setPinned(true, id: first.id), .changed)

        let later = now.addingTimeInterval(30)
        guard case .refreshed(let refreshed) = history.insert("same", at: later) else {
            return XCTFail("duplicate was not refreshed")
        }
        XCTAssertEqual(refreshed.id, first.id)
        XCTAssertTrue(refreshed.pinned)
        XCTAssertEqual(refreshed.createdAt, later)
        XCTAssertEqual(history.items.count, 1)
    }

    func testExactOneHourExpiresRecentButNotPinned() {
        let recent = ClipboardItem(text: "recent", createdAt: now)
        let pinned = ClipboardItem(text: "pinned", createdAt: now, pinned: true)
        let history = ClipboardHistory(items: [recent, pinned])
        let visible = history.visible(at: now.addingTimeInterval(ClipboardLimits.retention))

        XCTAssertTrue(visible.recent.isEmpty)
        XCTAssertEqual(visible.pinned.map(\.text), ["pinned"])
    }

    func testSweepRemovesOnlyExpiredRecentItems() {
        var history = ClipboardHistory(items: [
            ClipboardItem(text: "old", createdAt: now.addingTimeInterval(-3_601)),
            ClipboardItem(text: "kept", createdAt: now.addingTimeInterval(-3_601), pinned: true),
            ClipboardItem(text: "new", createdAt: now),
        ])
        XCTAssertEqual(history.sweep(at: now), 1)
        XCTAssertEqual(Set(history.items.map(\.text)), ["kept", "new"])
    }

    func testRecentCapEvictsOldest() {
        var history = ClipboardHistory()
        for index in 0...ClipboardLimits.maxUnpinned {
            history.insert("item-\(index)", at: now.addingTimeInterval(TimeInterval(index)))
        }
        XCTAssertEqual(history.items.filter { !$0.pinned }.count, ClipboardLimits.maxUnpinned)
        XCTAssertFalse(history.items.contains { $0.text == "item-0" })
    }

    func testTwentySixthPinIsRefusedWithoutEviction() {
        var history = ClipboardHistory()
        var ids: [UUID] = []
        for index in 0...ClipboardLimits.maxPinned {
            guard case .stored(let item) = history.insert("item-\(index)", at: now) else {
                return XCTFail("insert failed")
            }
            ids.append(item.id)
        }
        for id in ids.prefix(ClipboardLimits.maxPinned) {
            XCTAssertEqual(history.setPinned(true, id: id), .changed)
        }
        XCTAssertEqual(history.setPinned(true, id: ids.last!), .pinnedSectionFull)
        XCTAssertEqual(history.items.filter(\.pinned).count, ClipboardLimits.maxPinned)
    }

    func testVisibleSectionsAreNewestFirst() {
        let history = ClipboardHistory(items: [
            ClipboardItem(text: "old recent", createdAt: now),
            ClipboardItem(text: "new recent", createdAt: now.addingTimeInterval(2)),
            ClipboardItem(text: "old pinned", createdAt: now, pinned: true),
            ClipboardItem(text: "new pinned", createdAt: now.addingTimeInterval(2), pinned: true),
        ])
        let visible = history.visible(at: now.addingTimeInterval(3))
        XCTAssertEqual(visible.recent.map(\.text), ["new recent", "old recent"])
        XCTAssertEqual(visible.pinned.map(\.text), ["new pinned", "old pinned"])
    }
}
