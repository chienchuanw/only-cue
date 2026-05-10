import XCTest

/// Pioneers the XCUITest screenshot-validation pattern for OnlyCue.
/// Captures the full screen via `XCUIScreen.main.screenshot()` and attaches
/// it to the test result with `lifetime = .keepAlways` so a human can review
/// the actual rendered transport bar in the Xcode result bundle.
final class TransportBarScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Transport bar renders on a fresh document
    /// Given the app is launched and an untitled document is opened
    /// Then the play/pause button is visible
    /// And a screenshot of the document window is attached for review.
    func test_transportBar_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let playPauseButton = app.buttons["playPauseButton"]
        XCTAssertTrue(
            playPauseButton.waitForExistence(timeout: 5),
            "playPauseButton should appear within 5 seconds of opening a document"
        )

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "transport-bar-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Explicit terminate avoids the "Failed to terminate" tear-down error
        // observed when leaving the launched app + attachment processing for
        // the harness to clean up. Pinning the lifecycle inside the test keeps
        // the run deterministic.
        app.terminate()
    }
}
