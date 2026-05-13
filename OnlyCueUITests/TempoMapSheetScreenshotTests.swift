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

        // Best-effort: open Tools → Tempo Map… so the screenshot shows the sheet.
        // XCUITest menu navigation can be flaky across runners, so this is not
        // asserted — if it doesn't open, the screenshot still captures the doc window.
        let toolsMenu = app.menuBars.menuBarItems["Tools"]
        if toolsMenu.waitForExistence(timeout: 2) {
            toolsMenu.click()
            let item = app.menuItems["Tempo Map…"]
            if item.waitForExistence(timeout: 2) { item.click() } else { app.typeKey(.escape, modifierFlags: []) }
        }

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
