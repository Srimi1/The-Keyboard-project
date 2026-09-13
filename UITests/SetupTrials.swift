import XCTest

final class SetupTrials: KeyboardUITestCase {
    func testSetupIsRememberedAndCanBeReviewedWithoutGrantingClipboardConsent() {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment["KB_UI_STORE_ID"] = UUID().uuidString
        app.launch()
        let finish = app.buttons["host.setup.continue"]
        XCTAssertTrue(finish.waitForExistence(timeout: 20))
        scrollUntilHittable(finish)
        finish.tap()
        XCTAssertTrue(app.buttons["host.setup.review"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        let review = app.buttons["host.setup.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["host.setup.continue"].exists)
        review.tap()
        XCTAssertTrue(app.buttons["host.setup.clipboard"].exists,
                      "Skipping setup must never imply clipboard consent")
    }
}
