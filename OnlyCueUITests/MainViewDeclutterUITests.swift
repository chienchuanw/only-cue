import XCTest

final class MainViewDeclutterUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_noMediaState_showsOnboarding_andHidesLoadedChrome() throws {
        let app = XCUIApplication()
        app.launch()

        // With no media imported the app shows the empty state: shortcut hints
        // and the Import button.
        XCTAssertTrue(app.staticTexts["documentShortcutHints"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["importMediaButton"].exists)

        // The removed loaded-state chrome must not be present.
        XCTAssertFalse(app.staticTexts["documentTitle"].exists)
        XCTAssertFalse(app.staticTexts["mediaSummary"].exists)
        XCTAssertFalse(app.staticTexts["cueCount"].exists)
    }
}
