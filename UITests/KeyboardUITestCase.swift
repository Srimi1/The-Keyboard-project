import XCTest

/// Base class for the touch-level keyboard tests.
///
/// The keys are drawn rects under a raw UIKit `MultiTouchView` (TouchTracker.swift).
/// Actionable accessibility elements exist for VoiceOver, while touch-behavior trials use
/// coordinates computed from the same percentage layout as production hit-testing.
///
/// The tests drive the **host app**, which compiles `Sources/Keyboard` in and renders the
/// real `KeyboardRootView` via `KeyboardPreviewView`. That is the real keyboard code;
/// what it is *not* is the extension process — no `UITextDocumentProxy`, no real
/// `hasFullAccess`, no haptics, no globe key, no jetsam limit.
@MainActor
class KeyboardUITestCase: XCTestCase {

    var app: XCUIApplication!

    /// The key area's frame in screen coordinates, resolved once per launch.
    private(set) var keyAreaFrame: CGRect = .zero
    /// Height of one key row inside `keyAreaFrame`.
    private(set) var rowHeight: CGFloat = 0

    // Mirrors of the production constants. Deliberately duplicated rather than imported:
    // a UI test target cannot `@testable import` an app target's internal types without
    // the app being built for testing in a way that changes it, and hard-coding the
    // numbers means a silent change to the real layout shows up as a failing tap rather
    // than as a test that quietly follows along.
    static let keySpacing: CGFloat = 3
    static let rowSpacing: CGFloat = 6
    static let keyboardVerticalPadding: CGFloat = 6
    /// Mirror of `KeyboardTheme.stripHeight`. Currently unused — `calibrateGeometry()` reads
    /// the key area off the drawn labels instead — but kept in step so the documented
    /// fallback path stays correct if it is ever needed.
    static let stripHeight: CGFloat = 44

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launching

    /// Launches the app and pushes the "Keyboard preview" screen, then calibrates the
    /// key-area geometry from what is actually on screen.
    @discardableResult
    func launchPreview() -> XCUIApplication {
        app = XCUIApplication()
        app.launch()

        let row = app.buttons["Keyboard preview"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The 'Keyboard preview' row never appeared")
        scrollUntilHittable(row)
        row.tap()

        XCTAssertTrue(
            app.staticTexts["Type on the keyboard below."].waitForExistence(timeout: 10),
            "The typed-text pane never appeared — did the preview screen push?"
        )

        calibrateGeometry()
        return app
    }

    /// Swipes the list until `element` can actually be tapped.
    ///
    /// `waitForExistence` is satisfied by a row that exists but is scrolled off screen, and
    /// tapping one of those fails. The setup checklist ahead of the preview row grows as the
    /// onboarding copy changes, so pinning these tests to a fixed scroll position would make
    /// unrelated UI edits look like touch-layer failures.
    func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "'\(element)' never became hittable after \(swipes) swipes")
    }

    /// Works out where the key grid actually is.
    ///
    /// TouchTracker publishes each key's complete hit frame as an accessibility element, so
    /// the row geometry can be read off the screen rather than guessed. Labels are matched
    /// case-insensitively because the
    /// keyboard opens with shift raised (auto-capitalization on an empty field), so the caps
    /// on screen read "Q", not "q".
    ///
    /// `q` (row 0) and `m` (row 2) are two row-pitches apart, which fixes both the row height
    /// and the grid's top edge. Horizontal geometry is not measured — `keyCenter` reproduces
    /// `KeyboardMetrics`' own arithmetic across the full window width, and
    /// `CalibrationProbe.testComputedCentresMatchDrawnKeys` checks that against the drawn
    /// labels.
    ///
    /// Fallback (if a future change hides those labels): derive the grid from the window,
    /// using `KeyboardMetrics.preferredRowHeight`'s formula and the bottom safe area.
    private func calibrateGeometry() {
        let window = app.windows.element(boundBy: 0).frame

        let q = labelElement("q")
        let m = labelElement("m")

        if q.exists, m.exists, q.frame.width > 0, m.frame.midY > q.frame.midY {
            let pitch = (m.frame.midY - q.frame.midY) / 2
            rowHeight = pitch - Self.rowSpacing
            let gridTop = q.frame.midY - rowHeight / 2 - Self.keyboardVerticalPadding
            let gridHeight = rowHeight * 4 + Self.rowSpacing * 3 + Self.keyboardVerticalPadding * 2
            keyAreaFrame = CGRect(x: window.minX, y: gridTop, width: window.width, height: gridHeight)
        } else {
            // preferredRowHeight = clamp(width * 0.10 * 1.35, 44...62).
            let derived = min(max(window.width * 0.10 * 1.35, 44), 62)
            rowHeight = derived
            let gridHeight = derived * 4 + Self.rowSpacing * 3 + Self.keyboardVerticalPadding * 2
            // The preview VStack respects the bottom safe area, so the grid sits above it.
            let bottomInset: CGFloat = 34
            keyAreaFrame = CGRect(
                x: window.minX,
                y: window.maxY - bottomInset - gridHeight,
                width: window.width,
                height: gridHeight
            )
        }
    }

    /// A drawn key label, matched case-insensitively and scoped away from the typed-text pane
    /// (which would otherwise match once the same character has been typed).
    func labelElement(_ label: String) -> XCUIElement {
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@ AND label ==[c] %@",
            "keyboard.key-",
            label
        )
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    // MARK: - Reading the screen

    /// Everything typed so far, or "" when the pane still shows its placeholder.
    var typedText: String {
        if app.staticTexts["Type on the keyboard below."].exists { return "" }
        // The pane is the first static text inside the scroll view; the caption and the
        // key labels are the other candidates, so match the caption's format to exclude it.
        let texts = app.scrollViews.firstMatch.staticTexts.allElementsBoundByIndex
        for element in texts {
            let value = element.label
            if value.hasPrefix("Shift: ") { continue }
            if value == "Clear" { continue }
            return value
        }
        return ""
    }

    /// The caption line: `Shift: <off|shifted|caps lock>   •   <N> characters`.
    var caption: String {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "Shift: ")
        let element = app.staticTexts.matching(predicate).firstMatch
        return element.exists ? element.label : ""
    }

    /// The word after "Shift: " in the caption.
    var shiftState: String {
        let caption = self.caption
        guard let range = caption.range(of: "Shift: "),
              let end = caption.range(of: "   •   ") else { return "" }
        return String(caption[range.upperBound..<end.lowerBound])
    }

    /// The character count the caption reports, which is the model's own count rather than
    /// something the test derived — useful when the typed text contains newlines.
    var reportedCharacterCount: Int {
        let caption = self.caption
        guard let end = caption.range(of: "   •   ") else { return -1 }
        let tail = caption[end.upperBound...].replacingOccurrences(of: " characters", with: "")
        return Int(tail) ?? -1
    }

    func clearTypedText() {
        let clear = app.buttons["Clear"].firstMatch
        if clear.exists { clear.tap() }
    }

    // MARK: - Key geometry

    /// The rows as `KeyboardLayout` builds them, per layer, as (label, widthFraction).
    ///
    /// ⚠️ These rows are the **preview's** bottom row, not the shipping one. `KeyboardPreviewView`
    /// never sets `needsGlobe`, so it defaults to false and the comma keeps its slot — nothing
    /// to do with Face ID, which is what an earlier version of this comment claimed. On a real
    /// iPhone `needsInputModeSwitchKey` is **true** (Q-10, measured 2026-08-22), so the globe
    /// takes that slot and the comma moves to the period's long-press set, where AOSP puts it
    /// first. Both keys are 0.10 wide, so every coordinate below is correct either way — what
    /// these tests never exercise is the globe key itself.
    enum Layer { case base, symbols, extendedSymbols }

    private static let bottomRow: [(String, Double)] =
        [("layer", 0.15), (",", 0.10), ("space", 0.50), (".", 0.10), ("return", 0.15)]

    static func rows(for layer: Layer) -> [(inset: Double, keys: [(String, Double)])] {
        switch layer {
        case .base:
            return [
                (0.00, "qwertyuiop".map { (String($0), 0.10) }),
                (0.05, "asdfghjkl".map { (String($0), 0.10) }),
                (0.00, [("shift", 0.15)] + "zxcvbnm".map { (String($0), 0.10) } + [("backspace", 0.15)]),
                (0.00, bottomRow),
            ]
        case .symbols:
            return [
                (0.00, "1234567890".map { (String($0), 0.10) }),
                (0.00, ["@", "#", "$", "_", "&", "-", "+", "(", ")", "/"].map { ($0, 0.10) }),
                (0.00, [("extended", 0.15)] + ["*", "\"", "'", ":", ";", "!", "?"].map { ($0, 0.10) } + [("backspace", 0.15)]),
                (0.00, bottomRow),
            ]
        case .extendedSymbols:
            return [
                (0.00, ["~", "`", "|", "•", "√", "π", "÷", "×", "¶", "∆"].map { ($0, 0.10) }),
                (0.00, ["£", "¢", "€", "¥", "^", "°", "=", "{", "}", "\\"].map { ($0, 0.10) }),
                (0.00, [("symbols", 0.15)] + ["%", "©", "®", "™", "✓", "[", "]"].map { ($0, 0.10) } + [("backspace", 0.15)]),
                (0.00, bottomRow),
            ]
        }
    }

    /// Centre of a key's **visual** rect, in screen coordinates.
    ///
    /// This is the same arithmetic `KeyboardMetrics.positionedKeys` does: usable width is the
    /// row minus the inter-key gaps and the row inset, then each key takes its share of the
    /// remaining width by fraction.
    func keyCenter(row rowIndex: Int, index keyIndex: Int, layer: Layer = .base) -> CGPoint {
        let rows = Self.rows(for: layer)
        precondition(rowIndex < rows.count, "row \(rowIndex) out of range")
        let row = rows[rowIndex]
        precondition(keyIndex < row.keys.count, "key \(keyIndex) out of range in row \(rowIndex)")

        let width = keyAreaFrame.width
        let inset = width * row.inset
        let gapTotal = CGFloat(row.keys.count - 1) * Self.keySpacing
        let usable = width - gapTotal - inset * 2
        let fractionSum = row.keys.reduce(0.0) { $0 + $1.1 }

        var x = inset
        for i in 0..<keyIndex {
            x += usable * CGFloat(row.keys[i].1 / fractionSum) + Self.keySpacing
        }
        let keyWidth = usable * CGFloat(row.keys[keyIndex].1 / fractionSum)

        let y = keyAreaFrame.minY
            + Self.keyboardVerticalPadding
            + CGFloat(rowIndex) * (rowHeight + Self.rowSpacing)
            + rowHeight / 2

        return CGPoint(x: keyAreaFrame.minX + x + keyWidth / 2, y: y)
    }

    /// Finds a key by its label in the given layer. Function keys use the names in
    /// `rows(for:)`: "shift", "backspace", "space", "return", "layer", "extended", "symbols".
    func keyCenter(_ label: String, layer: Layer = .base) -> CGPoint {
        let rows = Self.rows(for: layer)
        for (rowIndex, row) in rows.enumerated() {
            if let keyIndex = row.keys.firstIndex(where: { $0.0 == label }) {
                return keyCenter(row: rowIndex, index: keyIndex, layer: layer)
            }
        }
        XCTFail("No key labelled '\(label)' in layer \(layer)")
        return .zero
    }

    // MARK: - Tapping

    private func coordinate(at point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x, dy: point.y))
    }

    /// One press-and-release on a key.
    ///
    /// `tap()` is short enough not to trip the 300 ms long-press callout
    /// (`KeyboardTimings.longPressTimeout`), which every top-row letter and the period have.
    func tapKey(_ label: String, layer: Layer = .base) {
        coordinate(at: keyCenter(label, layer: layer)).tap()
    }

    func tapKey(row: Int, index: Int, layer: Layer = .base) {
        coordinate(at: keyCenter(row: row, index: index, layer: layer)).tap()
    }

    /// Types a run of letters from the base layer.
    func type(_ characters: String) {
        for character in characters {
            tapKey(String(character))
        }
    }

    /// Press and hold, for backspace repeat.
    func holdKey(_ label: String, seconds: TimeInterval, layer: Layer = .base) {
        coordinate(at: keyCenter(label, layer: layer)).press(forDuration: seconds)
    }

    // MARK: - Evidence

    func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Saves a screenshot outside the result bundle too, so failures can be eyeballed
    /// without opening the .xcresult.
    func saveScreenshot(to path: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
