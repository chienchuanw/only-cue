import XCTest

final class MainViewDeclutterUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_noMediaState_showsOnboarding_andHidesLoadedChrome() throws {
        let app = XCUIApplication()
        // Don't inherit a previously-restored document window — we need a fresh
        // untitled doc so the no-media empty state is what's on screen.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        // Sanity: the document window opened (TransportBar renders in both states).
        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 10),
            "document window should open within 10s of ⌘N"
        )

        // The empty-state onboarding affordance: the Import button.
        XCTAssertTrue(
            app.buttons["importMediaButton"].waitForExistence(timeout: 10),
            "Import Media button should appear in the no-media empty state"
        )

        // The removed loaded-state chrome must not be present.
        XCTAssertFalse(app.staticTexts["documentTitle"].exists)
        XCTAssertFalse(app.staticTexts["mediaSummary"].exists)
        XCTAssertFalse(app.staticTexts["cueCount"].exists)
    }
}
