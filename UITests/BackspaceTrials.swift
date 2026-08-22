import XCTest

/// Trial B — backspace, the one key that acts on press and repeats while held.
final class BackspaceTrials: KeyboardUITestCase {

    // MARK: - B1

    func testB1_singleTapRemovesExactlyOneCharacter() {
        launchPreview()

        type("abcd")
        XCTAssertEqual(typedText, "Abcd")
        let before = reportedCharacterCount

        tapKey("backspace")

        let after = reportedCharacterCount
        print("=== B1 typed: '\(typedText)'  count \(before) -> \(after)")
        XCTAssertEqual(before - after, 1, "One tap must remove exactly one character")
        XCTAssertEqual(typedText, "Abc")

        // And again, to rule out a first-tap special case.
        tapKey("backspace")
        print("=== B1 second tap: '\(typedText)'")
        XCTAssertEqual(typedText, "Ab")
    }

    func testB1_backspaceOnEmptyBufferIsHarmless() {
        launchPreview()

        tapKey("backspace")
        print("=== B1 empty-buffer backspace: '\(typedText)' count \(reportedCharacterCount)")
        XCTAssertEqual(reportedCharacterCount, 0)
    }

    // MARK: - B2

    /// Hold-repeat, and the acceleration ROADMAP claims: after 20 repeat ticks each tick
    /// removes two characters instead of one (`KeyboardTimings.deletesBeforeAcceleration`,
    /// `acceleratedDeleteCount`).
    ///
    /// Acceleration is measured as a *rate change*, not an absolute count, because the
    /// absolute count depends on how fast the host services the 50 ms tick. Two holds of
    /// different lengths on identical buffers give the deletion rate early in the hold and
    /// the rate later in the hold; if acceleration works the later rate must be materially
    /// higher. Both windows exclude the 400 ms start delay from the comparison.
    func testB2_holdRepeatsAndAccelerates() {
        launchPreview()

        let fill = 80
        let shortHold: TimeInterval = 0.9
        let longHold: TimeInterval = 2.5

        fillBuffer(to: fill)
        let shortDeleted = deleteByHolding(seconds: shortHold)
        print("=== B2 hold \(shortHold)s deleted \(shortDeleted)")

        fillBuffer(to: fill)
        let longDeleted = deleteByHolding(seconds: longHold)
        print("=== B2 hold \(longHold)s deleted \(longDeleted)")

        // 1. It repeats at all.
        XCTAssertGreaterThan(shortDeleted, 1, "A held backspace must delete more than one character")
        XCTAssertLessThan(shortDeleted, fill, "The buffer bottomed out — the measurement is saturated")
        XCTAssertLessThan(longDeleted, fill, "The buffer bottomed out — the measurement is saturated")

        // 2. It accelerates. `keyRepeatStartTimeout` is 400 ms, so the repeat phase of the
        //    short hold is (0.9 - 0.4) s and the extra repeat phase of the long hold is
        //    (2.5 - 0.9) s. Without acceleration both run at 1 / keyRepeatInterval.
        let startDelay = 0.4
        let earlyRate = Double(shortDeleted - 1) / (shortHold - startDelay)
        let lateRate = Double(longDeleted - shortDeleted) / (longHold - shortHold)
        print("=== B2 early repeat rate \(earlyRate)/s   late repeat rate \(lateRate)/s   ratio \(lateRate / earlyRate)")

        XCTAssertGreaterThan(
            lateRate, earlyRate * 1.2,
            "Later in the hold, deletion is not measurably faster — acceleration to two characters per tick is not happening"
        )
    }

    // MARK: - Helpers

    /// Types "x" until the caption reports `count` characters.
    private func fillBuffer(to count: Int) {
        var current = reportedCharacterCount
        var passes = 0
        while current < count && passes < 5 {
            for _ in 0..<(count - current) { tapKey("x") }
            current = reportedCharacterCount
            passes += 1
        }
        XCTAssertEqual(current, count, "Could not fill the buffer to \(count) characters")
    }

    private func deleteByHolding(seconds: TimeInterval) -> Int {
        let before = reportedCharacterCount
        holdKey("backspace", seconds: seconds)
        return before - reportedCharacterCount
    }
}
