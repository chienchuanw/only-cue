import XCTest

/// Visual baseline for the Tempo Map sheet (epic #199 leaf 6).
///
/// Like every XCUITest in this repo, this does not pass headless in CI (the app
/// never finishes launching there) — it's committed so a developer can run it
/// from Xcode. To populate the section table you also need an imported media
/// item; with a fresh document the sheet shows its "select a media item" state.
final class TempoMapSheetScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_tempoMapSheet_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)            // new document

        XCTAssertTrue(
            app.buttons["playPauseButton"].waitForExistence(timeout: 5),
            "a document window should open"
        )

        // Tools → Tempo Map…
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Tempo Map…"].click()

        XCTAssertTrue(
            app.otherElements["tempoMapSheet"].waitForExistence(timeout: 3)
                || app.dialogs.firstMatch.waitForExistence(timeout: 3),
            "the Tempo Map sheet should appear"
        )

        app.activate()
        let screenshot = app.windows.firstMatch.waitForExistence(timeout: 2)
            ? app.windows.firstMatch.screenshot()
            : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "tempo-map-sheet-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }
}
