import XCTest

/// Deterministic host-app trials for the explicit clipboard-save flow.
///
/// The Debug-only fixture uses an isolated repository, settings suite and clock per test.
/// It never reads the simulator pasteboard, so onboarding behavior is tested separately
/// from persistence and no system permission state can make this suite flaky.
final class ClipboardTrials: KeyboardUITestCase {
    private let fixtureNow = 2_000_000_000.0

    private func launchClipboard(fixtureText: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment["KB_UI_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["KB_UI_NOW"] = String(fixtureNow)
        if let fixtureText {
            app.launchEnvironment["KB_UI_CLIPBOARD_TEXT"] = fixtureText
        }
        app.launch()

        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Clipboard history"))
            .firstMatch
        XCTAssertTrue(app.navigationBars["Keyboard Project"].waitForExistence(timeout: 20))
        scrollUntilHittable(row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Clipboard"].waitForExistence(timeout: 10))
    }

    private func acceptNoticeIfNeeded() {
        let enable = app.buttons["Enable tap-to-save"]
        if enable.waitForExistence(timeout: 2) { enable.tap() }
        let turnOn = app.buttons["Turn on tap-to-save"]
        if turnOn.waitForExistence(timeout: 1) { turnOn.tap() }
    }

    func testClipboardNoticePrecedesSaveControl() {
        launchClipboard(fixtureText: "must remain unavailable")

        XCTAssertTrue(app.staticTexts["Save clipboard history on this iPhone?"].exists)
        XCTAssertFalse(app.buttons["host.clipboard.save"].exists)
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].exists)
    }

    /// A-10 — opening/foregrounding does not capture; only the explicit Save action does.
    func testA10_explicitSaveStoresText() {
        let copied = "Clipboard trial \(UUID().uuidString)"
        launchClipboard(fixtureText: copied)

        XCTAssertFalse(app.staticTexts[copied].exists, "Text was captured before explicit consent/save")
        acceptNoticeIfNeeded()
        let save = app.buttons["host.clipboard.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        XCTAssertTrue(
            app.staticTexts[copied].waitForExistence(timeout: 10),
            "Explicitly saved text never reached persisted history"
        )
    }

    /// A-06 — saving the same supplied text twice refreshes one entry rather than duplicating it.
    func testA06_identicalExplicitSaveIsNotDuplicated() {
        let copied = "Duplicate trial \(UUID().uuidString)"
        launchClipboard(fixtureText: copied)
        acceptNoticeIfNeeded()

        let save = app.buttons["host.clipboard.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts[copied].waitForExistence(timeout: 10))
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let entries = app.staticTexts.matching(identifier: copied)
        XCTAssertEqual(entries.count, 1, "Repeated explicit saves must leave one entry")
    }

    func testKeyboardClipboardPastesAndClearsInsideKeyboardAndRemembersConsent() {
        let copied = "Keyboard clipboard fixture"
        launchClipboard(fixtureText: copied)
        acceptNoticeIfNeeded()
        app.buttons["host.clipboard.save"].tap()
        XCTAssertTrue(app.staticTexts[copied].waitForExistence(timeout: 10))
        app.navigationBars["Clipboard"].buttons.element(boundBy: 0).tap()
        let preview = app.buttons["Keyboard preview"].firstMatch
        scrollUntilHittable(preview)
        preview.tap()
        let clipboard = app.buttons["keyboard.toolbar.clipboard"]
        XCTAssertTrue(clipboard.waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["stethoscope"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "globe ")).firstMatch.exists)
        clipboard.tap()
        XCTAssertFalse(app.buttons["keyboard.clipboard.enable"].exists)
        let clip = app.buttons[copied]
        XCTAssertTrue(clip.waitForExistence(timeout: 10))
        clip.tap()
        let inserted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", copied),
            object: app.staticTexts["keyboard.preview.text"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 5), .completed)
        app.buttons["keyboard.clipboard.clear"].tap()
        app.buttons["Delete everything"].tap()
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].waitForExistence(timeout: 10))
        app.buttons["keyboard.clipboard.back"].tap()
        clipboard.tap()
        XCTAssertFalse(app.buttons["keyboard.clipboard.enable"].exists)
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].exists)
    }

    func testKeyboardClipboardPinDeleteAndRepeatedPanelSwitches() {
        let copied = "Repeat validation clip"
        launchClipboard(fixtureText: copied)
        acceptNoticeIfNeeded()
        app.buttons["host.clipboard.save"].tap()
        XCTAssertTrue(app.staticTexts[copied].waitForExistence(timeout: 10))
        app.navigationBars["Clipboard"].buttons.element(boundBy: 0).tap()
        let preview = app.buttons["Keyboard preview"].firstMatch
        scrollUntilHittable(preview)
        preview.tap()
        let clipboard = app.buttons["keyboard.toolbar.clipboard"]
        XCTAssertTrue(clipboard.waitForExistence(timeout: 10))
        clipboard.tap()
        let clip = app.buttons[copied]
        XCTAssertTrue(clip.waitForExistence(timeout: 10))

        clip.press(forDuration: 1)
        app.buttons["Pin"].tap()
        XCTAssertTrue(app.staticTexts["PINNED"].waitForExistence(timeout: 5))
        app.buttons["keyboard.clipboard.clear"].tap()
        XCTAssertTrue(app.buttons["Delete everything"].waitForExistence(timeout: 5))
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "Clear-all confirmation"
        confirmation.lifetime = .keepAlways
        add(confirmation)
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // iOS can present a popover with outside-tap dismissal instead of a
            // Cancel row. The preview text is outside the keyboard and has no action.
            let outside = app.staticTexts["keyboard.preview.text"].frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: outside.midX, dy: outside.midY)).tap()
        }
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.buttons["Delete everything"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(clip.exists, "Cancelling clear-all must preserve pinned clips")

        for _ in 0..<5 {
            app.buttons["keyboard.clipboard.back"].tap()
            app.buttons["keyboard.toolbar.settings"].tap()
            XCTAssertTrue(app.switches["Adaptive haptics"].waitForExistence(timeout: 5))
            clipboard.tap()
            XCTAssertTrue(clip.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["keyboard.clipboard.enable"].exists)
        }

        clip.press(forDuration: 1)
        app.buttons["Unpin"].tap()
        XCTAssertTrue(app.staticTexts["RECENT · EXPIRES AFTER 1 HOUR"].waitForExistence(timeout: 5))
        clip.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(clip.exists)
        app.buttons["keyboard.clipboard.back"].tap()
        clipboard.tap()
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].exists)
        app.buttons["keyboard.clipboard.back"].tap()
        let key = app.descendants(matching: .any)["keyboard.key-a"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.tap()
        XCTAssertEqual(app.staticTexts["keyboard.preview.text"].label, "A",
                       "Typing must still work after repeated panel changes; menu actions must not paste a clip")
        let keyboard = XCTAttachment(screenshot: app.screenshot())
        keyboard.name = "Typing after repeated panel switches"
        keyboard.lifetime = .keepAlways
        add(keyboard)
    }
}
