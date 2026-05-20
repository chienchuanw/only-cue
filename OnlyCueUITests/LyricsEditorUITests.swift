import XCTest

/// Tools -> Lyrics Editor... opens a self-contained sheet for authoring
/// per-`MediaItem` lyrics. Uses the existing three-cue seed (it carries a media
/// item, which the sheet attaches lyrics to).
final class LyricsEditorUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.threeCuesAt1And3And6.launchArgument]
        app.launch()
        return app
    }

    private func openEditor(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "cueMarkersOverlay").firstMatch
                .waitForExistence(timeout: 15),
            "seed document should open"
        )
        app.activate()
        let toolsMenu = app.menuBars.menuBarItems["Tools"]
        XCTAssertTrue(toolsMenu.waitForExistence(timeout: 3))
        toolsMenu.click()
        let item = app.menuItems["Lyrics Editor…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
    }

    /// Scenario: the Lyrics Editor opens from the Tools menu
    /// Given a seeded document is open
    /// When the user invokes Tools -> Lyrics Editor...
    /// Then the Lyrics Editor sheet is presented.
    func test_lyricsEditor_opensFromToolsMenu() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        openEditor(app)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "lyricsEditorSheet").firstMatch
                .waitForExistence(timeout: 5),
            "the Lyrics Editor sheet should appear"
        )
    }

    /// Scenario: a new row can be added to the table
    /// Given the Lyrics Editor is open with no lyrics
    /// When the user clicks Add Line
    /// Then a lyric row appears in the table.
    func test_lyricsEditor_addLine_insertsRow() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        openEditor(app)
        let addButton = app.buttons["lyricsEditorAddLine"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'lyricsEditorRow-'")
            ).firstMatch.waitForExistence(timeout: 3),
            "Add Line should insert a table row"
        )
    }
}
