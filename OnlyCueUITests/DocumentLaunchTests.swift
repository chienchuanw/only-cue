import XCTest

final class DocumentLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: New document opens
    /// Given the app is launched fresh
    /// When the user creates a new document (⌘N)
    /// Then a window appears (transport bar is visible)
    /// And — with no media imported — the empty-state Import button is offered.
    func test_newDocument_showsEmptyStateOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(
            app.buttons["playPauseButton"].waitForExistence(timeout: 10),
            "document window should open within 10s of ⌘N"
        )
        XCTAssertTrue(
            app.buttons["importMediaButton"].waitForExistence(timeout: 10),
            "Import Media button should appear in the no-media empty state"
        )
    }
}
