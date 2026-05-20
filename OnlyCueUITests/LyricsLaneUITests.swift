import XCTest

/// The lyric lane in the waveform pane. The `Show Lyrics Lane` menu toggle was
/// retired with the editor-mode system — the lane is now shown automatically
/// for a document that carries placed lyrics (and always in Lyric mode). The
/// lane is a main-window overlay, reliably queryable on the CI runner.
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

    /// Scenario: the lyric lane shows for a document with placed lyrics
    /// Given a seeded document carrying placed lyrics is open
    /// Then the lyric lane appears in the waveform pane without any toggle.
    func test_lyricLane_displaysForDocumentWithPlacedLyrics() throws {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.songWithLyrics.launchArgument]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(
            element("cueMarkersOverlay", in: app).waitForExistence(timeout: 20),
            "seed document waveform should load"
        )
        XCTAssertTrue(
            element("lyricsLane", in: app).waitForExistence(timeout: 5),
            "the lyric lane should appear for a document with placed lyrics"
        )
    }
}
