import XCTest
import UIKit
@testable import KeyboardProject

/// Tests for the rules that decide what a keypress does.
///
/// These exist because the alternative is checking shift and auto-capitalization by hand on a
/// device after every change, and the failure mode — a keyboard that capitalizes in the wrong
/// place — is exactly the kind of small wrongness that makes a keyboard feel third-party.
@MainActor
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

    // MARK: - AOSP getCapsMode rules

    /// "e.g. " and "U.S. " end in a period but not a sentence.
    func testAbbreviationsDoNotCapitalize() {
        XCTAssertFalse(shouldCapitalize("For example, e.g. "))
        XCTAssertFalse(shouldCapitalize("I live in the U.S. "))
    }

    /// "Dr." is indistinguishable from a sentence end, and AOSP capitalizes — the tell for an
    /// abbreviation is a single letter between two periods.
    func testTitlesStillCapitalize() {
        XCTAssertTrue(shouldCapitalize("Hello Dr. "))
    }

    /// Opening punctuation the user just typed is not a reason to stop capitalizing.
    func testOpeningPunctuationIsSkipped() {
        XCTAssertTrue(shouldCapitalize("Hello. \""))
        XCTAssertTrue(shouldCapitalize("Hello. ("))
    }

    /// American typography puts the terminator inside the closing quote.
    func testClosingQuoteAfterTerminatorCapitalizes() {
        XCTAssertTrue(shouldCapitalize("He said \"hi.\" "))
    }

    func testTabCountsAsWhitespace() {
        XCTAssertTrue(shouldCapitalize("Hello.\t"))
    }

    func testWordsCapitalizesAfterAnySpace() {
        XCTAssertTrue(shouldCapitalize("hello ", .words))
        XCTAssertFalse(shouldCapitalize("hel", .words))
        XCTAssertTrue(shouldCapitalize("", .words))
    }
}

@MainActor
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

    func testInterveningCharacterBreaksShiftDoubleTapSequence() {
        var shift = ShiftController()
        let start = Date()

        shift.handleTap(now: start)
        shift.didInsertCharacter()
        shift.handleTap(now: start.addingTimeInterval(0.1))

        XCTAssertEqual(shift.state, .shifted, "non-consecutive shift taps must not latch caps lock")
    }
}

@MainActor
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

@MainActor
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
        XCTAssertEqual(lower[0].keys.map(\.id), upper[0].keys.map(\.id), "shift must not change physical key identity")
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

@MainActor
final class MoreKeysTests: XCTestCase {

    private func key(_ character: String) -> Key { .letter(character) }

    /// The corner hint glyph advertises the digit, so it has to be the first thing under the
    /// finger. AOSP prepends it via additionalMoreKeys.
    func testTopRowLeadsWithItsDigit() {
        XCTAssertEqual(MoreKeys.options(for: key("q"), shift: .off)?.first, "1")
        XCTAssertEqual(MoreKeys.options(for: key("p"), shift: .off)?.first, "0")
        XCTAssertEqual(MoreKeys.options(for: key("e"), shift: .off)?.first, "3")
    }

    /// Order is ground truth: it decides which accent the finger lands on.
    func testAccentSetsMatchAOSPExactly() {
        XCTAssertEqual(MoreKeys.options(for: key("e"), shift: .off), ["3", "é", "è", "ê", "ë", "ē"])
        XCTAssertEqual(MoreKeys.options(for: key("u"), shift: .off), ["7", "ú", "û", "ü", "ù", "ū"])
        XCTAssertEqual(MoreKeys.options(for: key("i"), shift: .off), ["8", "í", "î", "ï", "ī", "ì"])
        XCTAssertEqual(MoreKeys.options(for: key("o"), shift: .off), ["9", "ó", "ô", "ö", "ò", "œ", "ø", "ō", "õ"])
        XCTAssertEqual(MoreKeys.options(for: key("a"), shift: .off), ["à", "á", "â", "ä", "æ", "ã", "å", "ā"])
        XCTAssertEqual(MoreKeys.options(for: key("s"), shift: .off), ["ß"])
        XCTAssertEqual(MoreKeys.options(for: key("c"), shift: .off), ["ç"])
        XCTAssertEqual(MoreKeys.options(for: key("n"), shift: .off), ["ñ"])
    }

    /// English overrides exactly eight letters. A plausible-looking guess gives y, d, g, l and
    /// z accents they do not have in AOSP — this guards against drifting back to that.
    func testLettersAOSPGivesNoAccentsHaveNone() {
        for letter in ["d", "f", "g", "h", "j", "k", "l", "z", "x", "v", "b", "m"] {
            XCTAssertNil(MoreKeys.options(for: key(letter), shift: .off), "\(letter) should have no more-keys in en_US")
        }
        // y is on the top row, so it has its digit and nothing else.
        XCTAssertEqual(MoreKeys.options(for: key("y"), shift: .off), ["6"])
    }

    func testShiftUppercasesAccents() {
        let options = MoreKeys.options(for: key("A"), shift: .shifted) ?? []
        XCTAssertTrue(options.contains("À"))
        XCTAssertFalse(options.contains("à"))
    }

    /// ß upper-cases to the two-character "SS", which AOSP models as an output-text key.
    func testShiftedEszettBecomesTwoCharacters() {
        XCTAssertEqual(MoreKeys.options(for: key("S"), shift: .shifted), ["SS"])
    }

    /// morekeys_punctuation, in resource order. It leads with the comma, which none of the
    /// press coverage mentions.
    func testPeriodGridMatchesAOSPOrder() {
        XCTAssertEqual(
            MoreKeys.options(for: key("."), shift: .off),
            [",", "?", "!", "#", ")", "(", "/", ";", "'", "@", ":", "-", "\"", "+", "%", "&"]
        )
    }

    /// !autoColumnOrder!8 — 16 entries wrap to 8 columns across two rows.
    func testPeriodGridWrapsToEightColumns() {
        let options = MoreKeys.options(for: key("."), shift: .off) ?? []
        XCTAssertEqual(MoreKeys.columns(for: key("."), options: options), 8)
    }

    /// The 8-column rule belongs to the punctuation set alone. Applying it generally wrapped
    /// o's nine options across two rows for no reason.
    func testLetterCalloutsStayOneRow() {
        let options = MoreKeys.options(for: key("o"), shift: .off) ?? []
        XCTAssertEqual(options.count, 9)
        XCTAssertEqual(MoreKeys.columns(for: key("o"), options: options), 9)
    }

    func testFunctionKeysHaveNoOptions() {
        let shift = Key(id: "key-shift", label: "⇧", action: .shift, widthFraction: 0.15, style: .function)
        XCTAssertNil(MoreKeys.options(for: shift, shift: .off))
    }
}

@MainActor
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
    /// characters at key edges. Measured from the visual rect, not the hit rect.
    func testHysteresisKeepsAJustOffKeyTouch() {
        let all = keys()
        guard let key = all.first(where: { $0.id == "key-g" }) else {
            return XCTFail("expected a G key")
        }
        let justPastEdge = CGPoint(x: key.rect.maxX + 3, y: key.rect.midY)

        XCTAssertFalse(KeyboardMetrics.isStillOnKey(justPastEdge, key: key, hysteresis: 0))
        XCTAssertTrue(KeyboardMetrics.isStillOnKey(justPastEdge, key: key, hysteresis: 8))
    }

    /// Regression guard for a real bug: hit-testing against the *visual* rects left the gaps
    /// between keys, the home row's half-key inset, and the edge margins as dead zones that
    /// silently swallowed keystrokes. Hit rects must tile the whole area.
    func testEveryPointInTheKeyboardResolvesToAKey() {
        let all = keys()
        var misses: [CGPoint] = []

        for x in stride(from: CGFloat(1), to: size.width, by: 3) {
            for y in stride(from: CGFloat(1), to: size.height, by: 3) {
                let point = CGPoint(x: x, y: y)
                if KeyboardMetrics.key(at: point, in: all) == nil {
                    misses.append(point)
                }
            }
        }

        XCTAssertTrue(misses.isEmpty, "\(misses.count) dead points, first at \(misses.first.map(String.init(describing:)) ?? "-")")
    }

    func testHitRectsDoNotOverlap() {
        let all = keys()
        for (index, key) in all.enumerated() {
            for other in all[(index + 1)...] where key.hitRect.intersects(other.hitRect) {
                let overlap = key.hitRect.intersection(other.hitRect)
                XCTAssertTrue(
                    overlap.width < 0.01 || overlap.height < 0.01,
                    "\(key.id) and \(other.id) hit boxes overlap by \(overlap)"
                )
            }
        }
    }

    /// The gap between two keys must belong to one of them, not to nothing.
    func testGapBetweenKeysIsClaimed() {
        let all = keys()
        guard let f = all.first(where: { $0.id == "key-f" }),
              let g = all.first(where: { $0.id == "key-g" }) else {
            return XCTFail("expected F and G keys")
        }
        let midGap = CGPoint(x: (f.rect.maxX + g.rect.minX) / 2, y: f.rect.midY)
        let hit = KeyboardMetrics.key(at: midGap, in: all)
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit?.id == f.id || hit?.id == g.id)
    }

    /// The home row is inset by a half key; that inset must still be touchable, or the A and
    /// L keys are unreachable from the screen edge.
    func testHomeRowInsetIsTouchable() {
        let all = keys()
        guard let a = all.first(where: { $0.id == "key-a" }) else {
            return XCTFail("expected an A key")
        }
        let insetPoint = CGPoint(x: 2, y: a.rect.midY)
        XCTAssertEqual(KeyboardMetrics.key(at: insetPoint, in: all)?.id, a.id)
    }

    /// Solving against the garbage sizes iOS hands an extension while it settles produces
    /// briefly-wrong hit rects.
    func testImplausibleSizesProduceNoKeys() {
        let rows = KeyboardLayout.rows(layer: .base, shift: .off, needsGlobe: false)
        XCTAssertFalse(KeyboardMetrics.isPlausible(.zero))
        XCTAssertTrue(KeyboardMetrics.positionedKeys(rows: rows, in: .zero).isEmpty)
        XCTAssertTrue(KeyboardMetrics.positionedKeys(rows: rows, in: CGSize(width: 390, height: 4)).isEmpty)
        XCTAssertTrue(KeyboardMetrics.isPlausible(size))
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
