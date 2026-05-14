import XCTest

/// Visual baseline for the tempo-grid overlay toggle (epic #199 leaf 5).
///
/// Like every XCUITest in this repo, this does not pass in a headless CI run
/// (the app never finishes launching there) — it's committed so a developer can
/// run it from Xcode against a real session. To see the grid itself you also
/// need a media item with a tempo map (Tools → Tempo Map…, leaf #205); this test
/// just exercises the View → Show Tempo Grid toggle and captures a screenshot.
final class TempoGridOverlayScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_showTempoGrid_toggle_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)            // new document

        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 5),
            "a document window should open"
        )

        // View → Show Tempo Grid (⇧⌘G in the default keymap).
        app.typeKey("g", modifierFlags: [.command, .shift])

        app.activate()
        let screenshot = app.windows.firstMatch.waitForExistence(timeout: 2)
            ? app.windows.firstMatch.screenshot()
            : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "tempo-grid-toggle-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }
}
