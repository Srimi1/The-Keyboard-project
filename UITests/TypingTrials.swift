import XCTest

/// Trials A and D — letters, shift, auto-capitalization, the spacebar, and rollover.
///
/// Each test relaunches the app so it starts from a known state: the buffer is empty, and
/// because the preview field is `.sentences`, `KeyboardViewModel.syncWithTextField()` raises
/// shift on appear. The first character of a fresh buffer is therefore expected to be
/// uppercase — that is auto-capitalization working, not a shift bug.
final class TypingTrials: KeyboardUITestCase {

    // MARK: - A1

    func testA1_basicLetterTyping() {
        launchPreview()

        type("hello")

        print("=== A1 typed: '\(typedText)'  caption: '\(caption)'")
        XCTAssertEqual(typedText, "Hello")
        XCTAssertEqual(reportedCharacterCount, 5)
    }

    /// Keys from all three letter rows and both ends of each row, so a hit-test that is
    /// subtly wrong at the edges cannot hide behind a middle-of-the-keyboard sample.
    func testA1_lettersAcrossEveryRow() {
        launchPreview()

        type("qwertyuiop")
        tapKey("space")
        type("asdfghjkl")
        tapKey("space")
        type("zxcvbnm")

        print("=== A1 rows typed: '\(typedText)'")
        XCTAssertEqual(typedText, "Qwertyuiop asdfghjkl zxcvbnm")
    }

    // MARK: - A2

    func testA2_autoCapitalization() {
        launchPreview()

        // Empty buffer -> sentence start -> shift raised before the first key.
        XCTAssertEqual(shiftState, "shifted", "Shift should be raised on an empty .sentences field")

        type("hello")
        XCTAssertEqual(typedText, "Hello", "First character capitalized, the rest not")
        XCTAssertEqual(shiftState, "off", "Shift must fall back after the first character")

        // ". " then a letter starts a new sentence.
        tapKey(".")
        XCTAssertEqual(shiftState, "off", "A period alone is not yet a sentence start")
        tapKey("space")
        print("=== A2 after '. ': caption '\(caption)'")
        XCTAssertEqual(shiftState, "shifted", "'. ' must re-raise shift")

        type("world")
        print("=== A2 typed: '\(typedText)'")
        XCTAssertEqual(typedText, "Hello. World")
    }

    // MARK: - A3

    func testA3_shiftStateMachine() {
        launchPreview()

        // Burn the auto-capitalized first slot so the shift tap is measured on its own.
        tapKey("x")
        tapKey("y")
        XCTAssertEqual(typedText, "Xy")
        XCTAssertEqual(shiftState, "off")

        tapKey("shift")
        print("=== A3 after shift tap: caption '\(caption)'")
        XCTAssertEqual(shiftState, "shifted", "One shift tap must report 'shifted'")

        tapKey("z")
        print("=== A3 after shifted letter: '\(typedText)'  caption '\(caption)'")
        XCTAssertEqual(shiftState, "off", "Shift must fall back to 'off' after one character")

        tapKey("w")
        print("=== A3 typed: '\(typedText)'")
        XCTAssertEqual(typedText, "XyZw", "Exactly one character uppercase after a single shift tap")
    }

    // MARK: - A4

    func testA4_capsLock() {
        launchPreview()

        tapKey("x")
        XCTAssertEqual(shiftState, "off")

        doubleTapKey("shift")
        print("=== A4 after double tap: caption '\(caption)'")
        XCTAssertEqual(shiftState, "caps lock", "Double-tapping shift must latch caps lock")

        type("abc")
        print("=== A4 in caps lock: '\(typedText)'  caption '\(caption)'")
        XCTAssertEqual(typedText, "XABC", "Caps lock must hold across several characters")
        XCTAssertEqual(shiftState, "caps lock", "Caps lock must not fall back after a character")

        tapKey("shift")
        print("=== A4 after exit tap: caption '\(caption)'")
        XCTAssertEqual(shiftState, "off", "A third shift tap must leave caps lock")

        tapKey("d")
        print("=== A4 typed: '\(typedText)'")
        XCTAssertEqual(typedText, "XABCd", "Lowercase must resume after leaving caps lock")
    }

    // MARK: - D1

    func testD1_spaceKey() {
        launchPreview()

        type("ab")
        tapKey("space")
        type("cd")

        print("=== D1 typed: '\(typedText)'  count \(reportedCharacterCount)")
        XCTAssertEqual(typedText, "Ab cd")
        XCTAssertEqual(reportedCharacterCount, 5, "The space must be a real character in the buffer")
    }

    // MARK: - D2

    /// Two fingers down at once, both registering — the guarantee `MultiTouchView` exists for.
    ///
    /// XCUITest cannot place two simultaneous touches at two *chosen* coordinates:
    /// `XCUICoordinate` offers only `tap`, `doubleTap` and `press(forDuration:)`, all
    /// single-touch, and the multi-finger gestures are element-relative with placement the
    /// caller does not control. What it can do is aim `twoFingerTap()` at an element, and
    /// XCUITest separates the two fingers in proportion to that element's width — so a
    /// narrow target lands both fingers on one key and a full-width target lands them on
    /// keys at opposite ends of a row. Both cases are used here, because both produce an
    /// outcome a single touch physically cannot.
    ///
    /// Finger placement is undocumented. If this test starts failing, re-characterise with
    /// `MultiTouchProbe` before assuming the keyboard broke.
    ///
    /// ⚠️ Whether two touches actually get delivered to the full-width overlay is decided
    /// **per app session** (measured 2026-08-22 — see Q-13), which is why part (b) relaunches
    /// rather than retrying in place. That workaround keeps the harness honest; it does not
    /// settle whether the touch layer itself ever drops a touch. Do not read a pass here as
    /// proof that rollover is sound — Q-13 is still open, and only real fingers on a real
    /// device answer it.
    func testD2_multiTouchRollover() {
        launchPreview()
        tapKey("x")            // burn the auto-capitalized slot

        // (a) Both fingers on one key: the key must fire twice. The first press can only be
        //     committed by the second finger landing — that is `commitPendingPresses`, the
        //     rollover path itself.
        let target = labelElement("g")
        XCTAssertTrue(target.exists, "No 'g' key label to aim a two-finger tap at")

        let beforeSameKey = reportedCharacterCount
        target.twoFingerTap()
        let addedSameKey = reportedCharacterCount - beforeSameKey
        print("=== D2 two-finger tap on one key: '\(typedText)'  added \(addedSameKey)")
        XCTAssertEqual(addedSameKey, 2, "Two simultaneous touches on one key produced \(addedSameKey) characters, not 2")

        // (b) Fingers far apart, on two different keys. On the full-width overlay they land
        //     on shift and backspace — opposite ends of row 2. One touch cannot do both.
        //
        // Whether XCUITest delivers one touch or two to this overlay is decided **per app
        // session** (Q-13, measured 2026-08-22): three consecutive attempts inside one launch
        // reproduced a single-touch result identically, while separate launches delivered
        // both. Two consequences, both load-bearing:
        //
        //   1. Every attempt needs its own launch — retrying in place is worthless.
        //   2. The first attempt starts from a **fresh** session rather than reusing the one
        //      part (a) just tapped in — that turns out to matter more than the retry does.
        //      Measured 2026-08-22: an attempt reusing part (a)'s session succeeded 1 time in
        //      5; a freshly launched one 5 times in 6 (6 runs, one needing a second attempt).
        //
        // Five fresh attempts therefore puts a false failure far below 1%, while a genuine
        // rollover break still fails every attempt and reports below.
        var deleted = 0
        var shiftAfter = "off"
        let attempts = 5

        for attempt in 1...attempts {
            launchPreview()
            let overlay = touchOverlay()
            XCTAssertTrue(overlay.exists, "Could not find the touch overlay on attempt \(attempt)")

            // Guarantees both preconditions: a character available to delete, and shift down
            // (typing the first character after a raised shift consumes it).
            type("g")
            XCTAssertEqual(shiftState, "off", "Precondition: shift should be down before the two-finger tap")

            let before = reportedCharacterCount
            overlay.twoFingerTap()
            deleted = before - reportedCharacterCount
            shiftAfter = shiftState
            print("=== D2 two-finger across a row, attempt \(attempt)/\(attempts): deleted \(deleted)  shift '\(shiftAfter)'  text '\(typedText)'")

            if deleted == 1 && shiftAfter == "shifted" { break }
        }

        saveScreenshot(to: "/tmp/kbtrial-d2-twofinger.png")
        XCTAssertEqual(deleted, 1, "Backspace did not fire from the two-finger tap")
        XCTAssertEqual(shiftAfter, "shifted", "Shift never fired alongside backspace — only one of the two touches registered, across \(attempts) separate launches")

        // (c) Sequential speed check. Not rollover, but it would catch dropped keystrokes.
        //     Measured as a delta, so it does not care which session (b) left us in.
        let sequentialStart = reportedCharacterCount
        for _ in 0..<10 { tapKey("a") }
        print("=== D2 sequential 10 taps: '\(typedText)'  count \(sequentialStart) -> \(reportedCharacterCount)")
        XCTAssertEqual(reportedCharacterCount - sequentialStart, 10, "Sequential taps dropped a keystroke")
    }

    // MARK: - Helpers

    private func doubleTapKey(_ label: String, layer: Layer = .base) {
        let point = keyCenter(label, layer: layer)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .doubleTap()
    }

    /// The `MultiTouchView` that `TouchTracker` installs: the element whose frame is exactly
    /// the key area.
    private func touchOverlay() -> XCUIElement {
        let candidates = app.otherElements.allElementsBoundByIndex.filter {
            let frame = $0.frame
            return abs(frame.minY - keyAreaFrame.minY) < 3
                && abs(frame.height - keyAreaFrame.height) < 3
                && abs(frame.width - keyAreaFrame.width) < 3
        }
        print("=== D2 overlay candidates: \(candidates.map { $0.frame })")
        return candidates.last ?? app.otherElements.firstMatch
    }
}
