import XCTest

/// Exploratory measurement for trial B2. Prints, does not assert.
///
/// Hold-repeat is timing-driven (`KeyboardTimings.keyRepeatStartTimeout` 400 ms, then a
/// 50 ms tick, accelerating to two characters per tick after 20 ticks). How many of those
/// ticks actually land depends on how fast the host can service them, so the real rate has
/// to be measured before a threshold can be asserted honestly.
final class BackspaceRepeatProbe: KeyboardUITestCase {

    func testMeasureRepeatRate() {
        launchPreview()

        for duration in [0.9, 1.6, 2.5, 3.5] as [TimeInterval] {
            fillBuffer(to: 120)
            let before = reportedCharacterCount
            holdKey("backspace", seconds: duration)
            let after = reportedCharacterCount
            print("=== HOLD \(duration)s: \(before) -> \(after), deleted \(before - after)")
        }
    }

    /// Types "x" until the caption reports `count` characters.
    private func fillBuffer(to count: Int) {
        var current = reportedCharacterCount
        var guardCount = 0
        while current < count && guardCount < 400 {
            for _ in 0..<(count - current) { tapKey("x") }
            current = reportedCharacterCount
            guardCount += 1
        }
    }
}
