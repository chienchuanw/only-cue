import XCTest

/// #671 — in Cue mode the cue at the playhead is highlighted in the cue list
/// (previously Show-mode only). The highlight is a row background colour, which
/// isn't directly XCUITest-queryable, so this seeks the playhead onto a cue's
/// section and screenshot-verifies; the precedence logic is unit-pinned by
/// `CueRowFillTests`.
final class CueListCurrentCueHighlightUITests: OnlyCueUITestCase {

    func test_currentCue_highlightsInCueMode() throws {
        let app = launchApp(seed: .setListActI)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch.waitForExistence(timeout: 15)
        )
        // Still in Cue mode (default). Step the playhead onto the first cue's
        // section (18s) so its row becomes the current cue.
        app.buttons["transportNextCue"].click()
        Thread.sleep(forTimeInterval: 0.6)

        // Sanity: a cue name is present (the list rendered).
        XCTAssertTrue(app.staticTexts["Lights Up"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "cue-list-current-cue-highlight-cue-mode"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
