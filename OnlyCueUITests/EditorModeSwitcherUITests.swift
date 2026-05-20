import XCTest

/// The editor-mode switcher is present in the main window and its segments are
/// clickable. Uses the existing three-cue seed (it carries a media item).
final class EditorModeSwitcherUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.threeCuesAt1And3And6.launchArgument]
        app.launch()
        return app
    }

    /// Scenario: the mode switcher appears in the document window
    /// Given a seeded document is open
    /// Then the editor-mode switcher is visible.
    func test_modeSwitcher_isPresent() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        let switcher = app.descendants(matching: .any).matching(identifier: "editorModeSwitcher").firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 15), "the editor-mode switcher should be visible")
    }

    /// Scenario: switching to Lyric mode
    /// Given the document window is open
    /// When the user clicks the Lyric segment
    /// Then the Lyric segment reports the selected trait.
    func test_modeSwitcher_selectsLyricMode() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        let lyricSegment = app.buttons["editorModeSegment-lyric"]
        XCTAssertTrue(lyricSegment.waitForExistence(timeout: 15))
        lyricSegment.click()
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: lyricSegment)
        wait(for: [selected], timeout: 5)
    }
}
