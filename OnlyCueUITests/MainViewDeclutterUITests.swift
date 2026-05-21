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

        // The empty-state onboarding affordance: the Import button. Its
        // appearance also confirms the document window opened. The transport is
        // intentionally absent until media exists (Quiet Pro redesign).
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
