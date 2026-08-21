import XCTest
import UIKit
@testable import KeyboardProject

/// Tests for the rules that decide what a keypress does.
///
/// These exist because the alternative is checking shift and auto-capitalization by hand on a
/// device after every change, and the failure mode — a keyboard that capitalizes in the wrong
/// place — is exactly the kind of small wrongness that makes a keyboard feel third-party.
final class AutoCapitalizationTests: XCTestCase {

    private func shouldCapitalize(_ context: String?, _ type: UITextAutocapitalizationType = .sentences) -> Bool {
        AutoCapitalization.shouldCapitalize(before: context, type: type)
    }

    func testEmptyFieldCapitalizes() {
        XCTAssertTrue(shouldCapitalize(nil))
        XCTAssertTrue(shouldCapitalize(""))
    }

    func testMidWordDoesNotCapitalize() {
        XCTAssertFalse(shouldCapitalize("hel"))
        XCTAssertFalse(shouldCapitalize("Hello worl"))
    }

    func testAfterSpaceMidSentenceDoesNotCapitalize() {
        XCTAssertFalse(shouldCapitalize("Hello "))
    }

    func testAfterSentenceTerminatorAndSpaceCapitalizes() {
        XCTAssertTrue(shouldCapitalize("Hello. "))
        XCTAssertTrue(shouldCapitalize("Really? "))
        XCTAssertTrue(shouldCapitalize("Wow! "))
    }

    /// The space is what marks the sentence as finished — "Hello." with the cursor right
    /// after the period is still inside the sentence.
    func testTerminatorWithoutTrailingSpaceDoesNotCapitalize() {
        XCTAssertFalse(shouldCapitalize("Hello."))
    }

    func testAfterNewlineCapitalizes() {
        XCTAssertTrue(shouldCapitalize("Hello\n"))
    }

    func testOnlyWhitespaceCapitalizes() {
        XCTAssertTrue(shouldCapitalize("   "))
    }

    // A username or URL field asks for .none; overriding it is a real annoyance.
    func testNoneNeverCapitalizes() {
        XCTAssertFalse(shouldCapitalize("", .none))
        XCTAssertFalse(shouldCapitalize("Hello. ", .none))
    }

    func testAllCharactersAlwaysCapitalizes() {
        XCTAssertTrue(shouldCapitalize("hel", .allCharacters))
    }

    func testWordsCapitalizesAfterAnySpace() {
        XCTAssertTrue(shouldCapitalize("hello ", .words))
        XCTAssertFalse(shouldCapitalize("hel", .words))
        XCTAssertTrue(shouldCapitalize("", .words))
    }
}

final class ShiftControllerTests: XCTestCase {

    func testTapShiftsThenFallsBackAfterOneCharacter() {
        var shift = ShiftController()
        XCTAssertEqual(shift.state, .off)

        shift.handleTap()
        XCTAssertEqual(shift.state, .shifted)

        shift.didInsertCharacter()
        XCTAssertEqual(shift.state, .off, "shift applies to one character only")
    }

    func testDoubleTapLatchesCapsLock() {
        var shift = ShiftController()
        let start = Date()

        shift.handleTap(now: start)
        shift.handleTap(now: start.addingTimeInterval(0.1))
        XCTAssertEqual(shift.state, .capsLock)
    }

    func testCapsLockSurvivesTypedCharacters() {
        var shift = ShiftController()
        let start = Date()
        shift.handleTap(now: start)
        shift.handleTap(now: start.addingTimeInterval(0.1))

        shift.didInsertCharacter()
        XCTAssertEqual(shift.state, .capsLock)
    }

    func testTapAfterCapsLockTurnsItOff() {
        var shift = ShiftController()
        let start = Date()
        shift.handleTap(now: start)
        shift.handleTap(now: start.addingTimeInterval(0.1))

        shift.handleTap(now: start.addingTimeInterval(2))
        XCTAssertEqual(shift.state, .off)
    }

    func testSlowSecondTapTogglesRatherThanLatching() {
        var shift = ShiftController()
        let start = Date()

        shift.handleTap(now: start)
        shift.handleTap(now: start.addingTimeInterval(5))
        XCTAssertEqual(shift.state, .off, "outside the double-tap window this is just a toggle")
    }

    /// Regression guard: if auto-capitalization counted as a tap, typing a sentence would
    /// latch caps lock by accident.
    func testAutoCapitalizationDoesNotLatchCapsLock() {
        var shift = ShiftController()

        shift.applyAutoCapitalization(true)
        shift.applyAutoCapitalization(true)
        XCTAssertEqual(shift.state, .shifted)
    }

    func testAutoCapitalizationNeverOverridesCapsLock() {
        var shift = ShiftController()
        let start = Date()
        shift.handleTap(now: start)
        shift.handleTap(now: start.addingTimeInterval(0.1))

        shift.applyAutoCapitalization(false)
        XCTAssertEqual(shift.state, .capsLock)
    }
}

final class ReturnKeyLabelTests: XCTestCase {

    func testLabelsMatchApplesKeyboard() {
        XCTAssertEqual(ReturnKeyLabel.label(for: .default), "return")
        XCTAssertEqual(ReturnKeyLabel.label(for: .go), "go")
        XCTAssertEqual(ReturnKeyLabel.label(for: .search), "search")
        XCTAssertEqual(ReturnKeyLabel.label(for: .send), "send")
        XCTAssertEqual(ReturnKeyLabel.label(for: .done), "done")
        XCTAssertEqual(ReturnKeyLabel.label(for: .next), "next")
        XCTAssertEqual(ReturnKeyLabel.label(for: .join), "join")
        XCTAssertEqual(ReturnKeyLabel.label(for: .google), "search")
    }
}

final class KeyboardLayoutTests: XCTestCase {

    func testBaseLayerHasFourRows() {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: false)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].keys.count, 10)
        XCTAssertEqual(rows[1].keys.count, 9)
        XCTAssertEqual(rows[2].keys.count, 9, "shift + 7 letters + backspace")
    }

    /// AOSP LatinIME geometry (UI-SPEC §1): the home row is centered by a half-key inset.
    func testHomeRowIsCentered() {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: false)
        XCTAssertEqual(rows[1].leadingInset, 0.05, accuracy: 0.0001)
    }

    func testShiftAndBackspaceAreWiderThanLetters() {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: false)
        let row = rows[2]
        XCTAssertEqual(row.keys.first?.widthFraction ?? 0, 0.15, accuracy: 0.0001)
        XCTAssertEqual(row.keys.last?.widthFraction ?? 0, 0.15, accuracy: 0.0001)
        XCTAssertEqual(row.keys[1].widthFraction, 0.10, accuracy: 0.0001)
    }

    /// The row iPhone users notice is wrong: [?123][,][space][.][return].
    func testBottomRowOrderAndWidths() {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: false)
        let bottom = rows[3]
        XCTAssertEqual(bottom.keys.map(\.id), [
            "key-layer", "key-comma", "key-space", "key-period", "key-return",
        ])
        XCTAssertEqual(bottom.keys.map(\.widthFraction), [0.15, 0.10, 0.50, 0.10, 0.15])
    }

    func testGlobeReplacesCommaWhenTheSystemRequiresIt() {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: true)
        let ids = rows[3].keys.map(\.id)
        XCTAssertTrue(ids.contains("key-globe"))
        XCTAssertFalse(ids.contains("key-comma"), "the globe takes the comma's slot (UI-SPEC §1)")
    }

    func testShiftUppercasesLetters() {
        let lower = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: false)
        let upper = KeyboardLayout.rows(layer: .base, shift: .shifted, needsGlobe: false)
        XCTAssertEqual(lower[0].keys.first?.label, "q")
        XCTAssertEqual(upper[0].keys.first?.label, "Q")
    }

    func testReturnKeyUsesTheFieldsLabel() {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: false, returnLabel: "send")
        XCTAssertEqual(rows[3].keys.last?.label, "send")
    }

    func testTopRowCarriesDigitHints() {
        XCTAssertEqual(KeyboardLayout.digitHints["q"], "1")
        XCTAssertEqual(KeyboardLayout.digitHints["p"], "0")
    }
}

final class KeyboardMetricsTests: XCTestCase {

    private let size = CGSize(width: 390, height: 216)

    private func keys(needsGlobe: Bool = false) -> [PositionedKey] {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: needsGlobe)
        return KeyboardMetrics.positionedKeys(rows: rows, in: size)
    }

    func testEveryKeyGetsAFrame() {
        XCTAssertEqual(keys().count, 10 + 9 + 9 + 5)
    }

    func testKeysStayWithinBounds() {
        for positioned in keys() {
            XCTAssertGreaterThanOrEqual(positioned.rect.minX, -0.01, "\(positioned.id) starts off-screen")
            XCTAssertLessThanOrEqual(positioned.rect.maxX, size.width + 0.01, "\(positioned.id) overflows")
            XCTAssertGreaterThan(positioned.rect.width, 0)
            XCTAssertGreaterThan(positioned.rect.height, 0)
        }
    }

    func testKeysInARowDoNotOverlap() {
        let all = keys()
        let rows = Dictionary(grouping: all) { $0.rect.minY.rounded() }
        for (_, row) in rows {
            let sorted = row.sorted { $0.rect.minX < $1.rect.minX }
            for (left, right) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(left.rect.maxX, right.rect.minX + 0.01,
                                         "\(left.id) overlaps \(right.id)")
            }
        }
    }

    /// A tap in the middle of a key must resolve to that key — the guard against the
    /// classic "pressed A, got S" class of bug.
    func testHitTestingFindsTheKeyUnderTheTouch() {
        for positioned in keys() {
            let centre = CGPoint(x: positioned.rect.midX, y: positioned.rect.midY)
            let hit = KeyboardMetrics.key(at: centre, in: keys())
            XCTAssertEqual(hit?.id, positioned.id, "centre of \(positioned.id) resolved elsewhere")
        }
    }

    func testTouchOutsideAnyKeyResolvesToNothing() {
        let outside = CGPoint(x: size.width + 50, y: size.height / 2)
        XCTAssertNil(KeyboardMetrics.key(at: outside, in: keys()))
    }

    /// Hysteresis keeps a drifting finger on its key; without it fast typing drops
    /// characters at key edges.
    func testHysteresisKeepsAJustOffKeyTouch() {
        let all = keys()
        guard let key = all.first(where: { $0.id == "key-g" }) else {
            return XCTFail("expected a G key")
        }
        let justPastEdge = CGPoint(x: key.rect.maxX + 3, y: key.rect.midY)

        let withoutSlack = KeyboardMetrics.key(at: justPastEdge, in: [key], hysteresis: 0)
        let withSlack = KeyboardMetrics.key(at: justPastEdge, in: [key], hysteresis: 8)
        XCTAssertNil(withoutSlack)
        XCTAssertEqual(withSlack?.id, key.id)
    }

    func testRowsFillTheAvailableWidth() {
        let all = keys()
        let rows = Dictionary(grouping: all) { $0.rect.minY.rounded() }
        for (_, row) in rows {
            let minX = row.map(\.rect.minX).min() ?? 0
            let maxX = row.map(\.rect.maxX).max() ?? 0
            // The home row is inset by a half key on each side by design.
            let expectedInset = row.count == 9 && row.contains(where: { $0.id == "key-a" }) ? size.width * 0.05 : 0
            XCTAssertEqual(minX, expectedInset, accuracy: 0.5)
            XCTAssertEqual(maxX, size.width - expectedInset, accuracy: 0.5)
        }
    }
}
