import XCTest

/// Click-to-drop places the cursor line on the lyric lane. Screenshot-smoke —
/// the drop is a pixel click on the lane, not a queryable control.
final class LyricsPlacementUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    /// Scenario: click-to-drop places a queued line
    /// Given a Lyric-mode document with an unplaced line in the queue
    /// When the user clicks the lyric lane
    /// Then the click path runs and the window is captured.
    func test_clickToDrop_placesCursorLine_smoke() throws {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.lyricsWithPlacedLines.launchArgument]
        app.launch()
        defer { app.terminate() }

        let switcher = app.descendants(matching: .any).matching(identifier: "editorModeSwitcher").firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 15))
        let lyricSegment = app.descendants(matching: .any).matching(identifier: "editorModeSegment-lyric").firstMatch
        XCTAssertTrue(lyricSegment.waitForExistence(timeout: 5))
        lyricSegment.click()

        let lane = app.descendants(matching: .any).matching(identifier: "lyricsLane").firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5))
        lane.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "lyric-click-to-drop"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
