import XCTest

/// #661 — the cue list shows grandMA2-style `# · Name · Info` columns; the Time
/// and Fade columns are gone. PreviewPane/CueListPane stamp `cueListPane` on the
/// whole subtree, so cell identifiers are clobbered; the header text *labels*
/// survive, and are the robust handle here. Inline Info editing and the
/// blank-name default are pinned by unit tests (`CueCommandsTests`,
/// `CueRowViewStripeTests`).
final class CueListColumnsUITests: OnlyCueUITestCase {

    /// True if a header with either the given label or its uppercased form
    /// exists (the section header renders via `.textCase(.uppercase)`).
    private func headerExists(_ app: XCUIApplication, _ label: String) -> Bool {
        app.staticTexts[label].exists || app.staticTexts[label.uppercased()].exists
    }

    /// Scenario: the cue list uses # · Name · Info and drops Time/Fade
    func test_columns_areNumberNameInfo_noTimeOrFade() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        let pane = app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15))

        XCTAssertTrue(headerExists(app, "Name"), "the Name header is present")
        XCTAssertTrue(headerExists(app, "Info"), "the Info header is present")
        XCTAssertFalse(headerExists(app, "Time"), "the Time column was removed")
        XCTAssertFalse(headerExists(app, "Fade"), "the Fade column was removed")

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "cue-list-number-name-info-columns"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
