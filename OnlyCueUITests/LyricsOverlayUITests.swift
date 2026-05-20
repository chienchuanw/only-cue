import XCTest

/// The `View -> Show Lyrics Overlay` playback HUD. Launches a seeded document
/// that already carries lyrics, toggles the overlay, and asserts the HUD shows
/// the active line. The HUD is a main-window overlay (not sheet content), so
/// its rendered text is reliably queryable on the CI runner.
final class LyricsOverlayUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// One-call-per-line element lookup by identifier.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    /// Scenario: the lyrics HUD appears when toggled on for a doc with lyrics
    /// Given a seeded document that carries lyrics is open
    /// When the user enables View -> Show Lyrics Overlay
    /// Then the HUD shows the lyric line active at the playhead.
    func test_showLyricsOverlay_displaysActiveLine() throws {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.songWithLyrics.launchArgument]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(
            element("previewPane", in: app).waitForExistence(timeout: 15),
            "seed document should open"
        )
        app.activate()

        app.menuBars.menuBarItems["View"].click()
        let toggle = app.menuItems["Show Lyrics Overlay"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "View menu should offer Show Lyrics Overlay")
        toggle.click()

        XCTAssertTrue(
            app.staticTexts["Seeded opening line"].waitForExistence(timeout: 5),
            "the lyrics HUD should show the line active at the opening playhead"
        )
    }
}
