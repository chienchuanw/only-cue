import XCTest

/// Show mode is read-only. Screenshot-smoke — the cue list's `.disabled` state
/// and current-cue emphasis are not directly XCUITest-queryable, so this
/// switches to Show mode via the View ▸ Mode menu and captures the result.
/// `EditorModeTests` covers `EditorMode.isReadOnly`.
final class ShowModeUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scenario: Show mode keeps the cue list visible but read-only
    /// Given a seeded document
    /// When the user switches to Show mode
    /// Then the cue list pane is still present (rendered read-only).
    func test_showMode_cueListReadOnly_smoke() throws {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.threeCuesAt1And3And6.launchArgument]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(element(app, "cueListPane").waitForExistence(timeout: 15))
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Show Mode"].click()
        XCTAssertTrue(
            element(app, "cueListPane").waitForExistence(timeout: 5),
            "the cue list stays visible in Show mode"
        )

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "show-mode-readonly-cue-list"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
