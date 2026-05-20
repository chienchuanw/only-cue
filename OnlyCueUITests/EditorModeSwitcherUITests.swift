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
    /// Then the click path runs and the window is captured.
    ///
    /// Screenshot-smoke: SwiftUI's `.accessibilityAddTraits(.isSelected)` does
    /// not reliably surface as `XCUIElement.isSelected` on the macOS CI runner,
    /// and this leaf produces no other mode-dependent UI change (gating arrives
    /// in the next leaf). `EditorModeTests` covers the enum; the mode-gating
    /// leaf adds a real behavioral UI assertion.
    func test_modeSwitcher_selectsLyricMode_smoke() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        let lyricSegment = app.descendants(matching: .any).matching(identifier: "editorModeSegment-lyric").firstMatch
        XCTAssertTrue(lyricSegment.waitForExistence(timeout: 15))
        lyricSegment.click()
        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "lyric-mode-selected"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
