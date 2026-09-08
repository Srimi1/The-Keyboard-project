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
    /// narrow target lands both fingers on one key. That produces an outcome a single touch
    /// physically cannot, so it is the deterministic UI-level rollover check. Distinct-key
    /// ordering is covered directly by the model tests; placement on two chosen keys and the
    /// real extension touch stack remain part of the physical-device gate.
    ///
    /// Finger placement is undocumented. If this test starts failing, re-characterise with
    /// `MultiTouchProbe` before assuming the keyboard broke.
    ///
    /// Do not read a pass here as proof that physical-device rollover is complete. XCUITest's
    /// finger placement is undocumented, and only real fingers in the extension answer that.
    func testD2_multiTouchRollover() {
        launchPreview()
        tapKey("x")            // burn the auto-capitalized slot

        // (a) Both fingers on one key: the key must fire twice. The first press can only be
        //     committed by the second finger landing — that is `commitPendingPresses`, the
        //     rollover path itself.
        // Aim at the key's custom accessibility element, whose frame is the complete
        // tappable key. The drawn glyph is only ~12 points wide on current simulators and
        // XCUITest cannot place a two-finger gesture inside that tiny frame reliably.
        let target = app.descendants(matching: .any)["keyboard.key-g"].firstMatch
        XCTAssertTrue(target.exists, "No accessible 'g' key to aim a two-finger tap at")

        let beforeSameKey = reportedCharacterCount
        target.twoFingerTap()
        let addedSameKey = reportedCharacterCount - beforeSameKey
        print("=== D2 two-finger tap on one key: '\(typedText)'  added \(addedSameKey)")
        XCTAssertEqual(addedSameKey, 2, "Two simultaneous touches on one key produced \(addedSameKey) characters, not 2")

        // (b) Sequential speed check. Not rollover, but it catches dropped keystrokes.
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

}
