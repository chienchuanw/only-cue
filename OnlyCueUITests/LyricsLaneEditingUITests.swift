import XCTest

/// In Lyric mode the lyric lane is a tall editing strip. Screenshot-smoke — the
/// lane's chip drag is a pixel gesture, not a queryable control. Uses a seed
/// that carries placed lyric lines.
final class LyricsLaneEditingUITests: OnlyCueUITestCase {

    /// Scenario: Lyric mode shows the tall editing lane
    /// Given a document seeded with placed lyrics
    /// When the user switches to Lyric mode
    /// Then the lyric lane is present and rendered tall.
    func test_lyricMode_showsTallLane_smoke() throws {
        let app = launchApp(seed: .lyricsWithPlacedLines)

        let switcher = app.descendants(matching: .any).matching(identifier: "editorModeSwitcher").firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 15))
        let lyricSegment = app.descendants(matching: .any).matching(identifier: "editorModeSegment-lyric").firstMatch
        XCTAssertTrue(lyricSegment.waitForExistence(timeout: 5))
        lyricSegment.click()

        let lane = app.descendants(matching: .any).matching(identifier: "lyricsLane").firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5), "the lyric lane should be present in Lyric mode")

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "lyric-mode-tall-lane"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
