import XCTest

/// Verifies the `File → New from Template…` menu command is present. The full
/// flow (open panel → pick a `.cuelist-template` → new document pre-loaded with
/// its types) is exercised by `NewFromTemplateTests` at the unit level — the
/// `CueListDocument.init()` pickup path is the substantive part; `NSOpenPanel`
/// automation is too brittle to drive here.
final class NewFromTemplateMenuTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_fileMenu_offersNewFromTemplate() {
        let app = XCUIApplication()
        app.launch()
        app.activate()

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
        fileMenu.click()

        let item = app.menuItems["New from Template…"]
        XCTAssertTrue(
            item.waitForExistence(timeout: 2),
            "the File menu should offer New from Template…"
        )

        // Dismiss the menu without invoking it (would open an NSOpenPanel).
        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }
}
