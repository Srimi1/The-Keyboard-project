import XCTest

/// Exploratory probe for trial D2. Prints, does not assert.
///
/// Characterises what XCUITest's element-relative multi-finger gestures actually deliver to
/// `MultiTouchView`, since none of them let the caller choose where the fingers land. The
/// question is where a two-finger tap puts its fingers relative to the target element, and
/// whether both reach the keyboard.
final class MultiTouchProbe: KeyboardUITestCase {

    func testCharacteriseTwoFingerTap() {
        launchPreview()

        // 1. On the full-width touch overlay.
        type("abcde")
        print("=== MT overlay before: '\(typedText)' shift '\(shiftState)'")
        touchOverlay().twoFingerTap()
        print("=== MT overlay after:  '\(typedText)' shift '\(shiftState)'")
        saveScreenshot(to: "/tmp/kbtrial-d2-overlay.png")
    }

    /// Same gesture aimed at progressively narrower elements. If finger separation scales
    /// with the target's width, a narrow target should land both fingers on nearby keys.
    func testTwoFingerTapOnNarrowTargets() {
        launchPreview()
        tapKey("x")

        for name in ["g", "English (US)"] {
            let element = labelElement(name)
            guard element.exists else { print("=== MT no element '\(name)'"); continue }
            let before = typedText
            let beforeShift = shiftState
            element.twoFingerTap()
            print("=== MT twoFingerTap on '\(name)' \(element.frame): '\(before)'/\(beforeShift) -> '\(typedText)'/\(shiftState)")
        }
        saveScreenshot(to: "/tmp/kbtrial-d2-narrow.png")
    }

    private func touchOverlay() -> XCUIElement {
        let candidates = app.otherElements.allElementsBoundByIndex.filter {
            let frame = $0.frame
            return abs(frame.minY - keyAreaFrame.minY) < 3
                && abs(frame.height - keyAreaFrame.height) < 3
                && abs(frame.width - keyAreaFrame.width) < 3
        }
        return candidates.last ?? app.otherElements.firstMatch
    }
}
