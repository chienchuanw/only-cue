import XCTest

/// The editor-mode switcher is present in the main window and selecting Lyric
/// mode sticks. Uses the existing three-cue seed (it carries a media item).
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
    /// Then Lyric mode is selected.
    func test_modeSwitcher_selectsLyricMode() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        let lyricSegment = app.buttons["Lyric"]
        XCTAssertTrue(lyricSegment.waitForExistence(timeout: 15))
        lyricSegment.click()
        XCTAssertTrue(lyricSegment.isSelected, "the Lyric segment should be selected after clicking it")
    }
}
