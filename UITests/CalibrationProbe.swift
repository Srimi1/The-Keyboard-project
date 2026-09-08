import XCTest

/// Not a behaviour test — the calibration rig.
///
/// Coordinates are the whole risk in this harness: a press two points off types the wrong
/// letter and every trial downstream is measuring the wrong thing. These two tests exist so
/// the coordinates are *checked* rather than trusted — once against the drawn key rects, and
/// once against what the keyboard actually types.
///
/// Re-run these first if the layout changes or the tests move to another device size.
final class CalibrationProbe: KeyboardUITestCase {

    /// Every computed visual centre must land inside the key's published hit frame.
    func testComputedCentresMatchDrawnKeys() {
        launchPreview()

        print("=== WINDOW: \(app.windows.element(boundBy: 0).frame)")
        print("=== KEY AREA: \(keyAreaFrame)  rowHeight=\(rowHeight)")

        // label on screen -> the name keyCenter(_:) knows it by
        let checks: [(onScreen: String, key: String)] = [
            ("q", "q"), ("p", "p"), ("a", "a"), ("l", "l"), ("z", "z"), ("m", "m"),
            ("⇧", "shift"), ("⌫", "backspace"),
            ("?123", "layer"), (",", ","), ("English (US)", "space"), (".", "."), ("return", "return"),
        ]

        for check in checks {
            let element = labelElement(check.onScreen)
            XCTAssertTrue(element.exists, "No accessible key '\(check.onScreen)' on screen")
            let hitFrame = element.frame
            let computed = keyCenter(check.key)
            print("=== \(check.key): hit frame \(hitFrame)  computed (\(computed.x), \(computed.y))")
            XCTAssertTrue(hitFrame.contains(computed), "\(check.key): computed centre is outside its hit frame")
        }

        attachScreenshot("preview")
        saveScreenshot(to: "/tmp/kbtrial-calibration.png")
    }

    /// The empirical check the geometry cannot give: each probe key must type *itself*.
    func testEveryProbeKeyTypesItself() {
        launchPreview()

        // The field is `.sentences`, so the first character of an empty buffer comes out
        // capitalized. Burn that slot with a known letter instead of fighting it.
        let probes = ["q", "p", "a", "l", "z", "m"]
        tapKey("x")
        for probe in probes { tapKey(probe) }

        let expected = "X" + probes.joined()
        print("=== PROBE letters: '\(typedText)' (expected '\(expected)')")
        XCTAssertEqual(typedText, expected, "Letter key coordinates are miscalibrated")

        tapKey("space")
        print("=== PROBE space: '\(typedText)'")
        XCTAssertEqual(typedText, expected + " ", "space key miscalibrated")

        tapKey("backspace")
        print("=== PROBE backspace: '\(typedText)'")
        XCTAssertEqual(typedText, expected, "backspace key miscalibrated")

        saveScreenshot(to: "/tmp/kbtrial-probe.png")
    }
}
