import XCTest

/// The right inspector swaps content with the editor mode.
final class ModeAwareInspectorUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.lyricsWithPlacedLines.launchArgument]
        app.launch()
        return app
    }

    /// Scenario: Cue mode shows the cue list inspector
    /// Given a seeded document in Cue mode
    /// Then the cue list inspector is present.
    func test_cueMode_showsCueListInspector() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        let pane = app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15))
    }

    /// Scenario: Lyric mode shows the lyrics inspector
    /// Given a seeded document
    /// When the user switches to Lyric mode
    /// Then the lyrics inspector pane is present.
    func test_lyricMode_showsLyricsInspector() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        let lyricSegment = app.descendants(matching: .any).matching(identifier: "editorModeSegment-lyric").firstMatch
        XCTAssertTrue(lyricSegment.waitForExistence(timeout: 15))
        lyricSegment.click()
        let pane = app.descendants(matching: .any).matching(identifier: "lyricsInspectorPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 5), "Lyric mode should show the lyrics inspector")
    }
}
