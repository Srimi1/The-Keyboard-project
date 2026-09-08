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
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Clipboard history row did not appear")
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
}
