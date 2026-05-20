import XCTest

/// Smoke + visual baseline for the Lyrics Editor sheet (#311). Opens a seeded
/// document, invokes Tools -> Lyrics Editor..., and captures a window-scoped
/// screenshot.
///
/// SwiftUI sheets expose a limited accessibility tree on the headless CI runner,
/// so — following `TimecodeSettingsSheetScreenshotTests` / `OSCMonitorScreenshotTests`
/// — this verifies the menu path and screenshots the window rather than asserting
/// on sheet-internal elements. The load-bearing coverage of the editor's
/// behaviour is the unit suite (`LyricsTimeFormatTests`, `CueCommandsLyricsTests`,
/// `LyricsTests`).
final class LyricsEditorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// One-call-per-line element lookup by identifier.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    /// Scenario: the Lyrics Editor opens from the Tools menu
    /// Given a seeded document is open
    /// When the user invokes Tools -> Lyrics Editor...
    /// Then the Lyrics Editor sheet is presented (captured as a screenshot).
    func test_lyricsEditor_opensFromToolsMenu_visualBaseline() throws {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.threeCuesAt1And3And6.launchArgument]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(
            element("cueMarkersOverlay", in: app).waitForExistence(timeout: 15),
            "seed document should open"
        )
        app.activate()

        let toolsMenu = app.menuBars.menuBarItems["Tools"]
        XCTAssertTrue(toolsMenu.waitForExistence(timeout: 3))
        toolsMenu.click()

        let item = app.menuItems["Lyrics Editor…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Tools menu should offer Lyrics Editor…")
        item.click()

        // Let the sheet animate in before the screenshot.
        Thread.sleep(forTimeInterval: 1.5)

        let window = app.windows.firstMatch
        let screenshot = window.waitForExistence(timeout: 2)
            ? window.screenshot()
            : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "lyrics-editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
