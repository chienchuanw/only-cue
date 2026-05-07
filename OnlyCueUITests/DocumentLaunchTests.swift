import XCTest

final class DocumentLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: New document opens
    /// Given the app is launched fresh
    /// When the user creates a new document
    /// Then a window appears
    /// And the placeholder content (cue count + hint text) is visible.
    func test_appLaunches_andShowsPlaceholderContent() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["OnlyCue"].waitForExistence(timeout: 5),
            "Title 'OnlyCue' should appear within 5 seconds of launch"
        )

        XCTAssertTrue(
            app.staticTexts["0 cues"].exists,
            "Empty document must show '0 cues' label"
        )

        XCTAssertGreaterThan(
            app.windows.count,
            0,
            "DocumentGroup should open at least one window on launch"
        )
    }
}
