import XCTest

/// The right inspector swaps content with the editor mode.
final class ModeAwareInspectorUITests: OnlyCueUITestCase {

    private func launchSeeded() -> XCUIApplication {
        launchApp(seed: .lyricsWithPlacedLines)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Switches editor mode via the View ▸ Mode menu — reliable in XCUITest,
    /// and the same `.editorModeChangeRequested` path the `⌘1/2/3` keys use.
    private func selectMode(_ app: XCUIApplication, _ menuTitle: String) {
        app.menuBars.menuBarItems["View"].click()
        app.menuItems[menuTitle].click()
    }

    /// Scenario: Cue mode shows the cue list inspector
    /// Given a seeded document in Cue mode
    /// Then the cue list inspector is present.
    func test_cueMode_showsCueListInspector() throws {
        let app = launchSeeded()
        XCTAssertTrue(element(app, "cueListPane").waitForExistence(timeout: 15))
    }

    /// Scenario: Lyric mode shows the lyrics inspector
    /// Given a seeded document
    /// When the user switches to Lyric mode
    /// Then the lyrics inspector pane is present.
    func test_lyricMode_showsLyricsInspector() throws {
        let app = launchSeeded()
        XCTAssertTrue(element(app, "cueListPane").waitForExistence(timeout: 15))
        selectMode(app, "Lyric Mode")
        XCTAssertTrue(
            element(app, "lyricsInspectorPane").waitForExistence(timeout: 5),
            "Lyric mode should show the lyrics inspector"
        )
    }
}
