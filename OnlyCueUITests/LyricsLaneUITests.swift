import XCTest

/// The `View -> Show Lyrics Lane` waveform strip. Launches a seeded document
/// that carries lyrics, toggles the lane, and asserts it appears. The lane is a
/// main-window overlay inside the waveform pane (not sheet content), so it is
/// reliably queryable on the CI runner.
final class LyricsLaneUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// One-call-per-line element lookup by identifier.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    /// Scenario: the lyric lane appears when toggled on for a doc with lyrics
    /// Given a seeded document carrying lyrics is open
    /// When the user enables View -> Show Lyrics Lane
    /// Then the lyric lane appears in the waveform pane.
    func test_showLyricsLane_displaysLane() throws {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.songWithLyrics.launchArgument]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(
            element("cueMarkersOverlay", in: app).waitForExistence(timeout: 20),
            "seed document waveform should load"
        )
        app.activate()

        app.menuBars.menuBarItems["View"].click()
        let toggle = app.menuItems["Show Lyrics Lane"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "View menu should offer Show Lyrics Lane")
        toggle.click()

        XCTAssertTrue(
            element("lyricsLane", in: app).waitForExistence(timeout: 5),
            "the lyric lane should appear in the waveform pane"
        )
    }
}
