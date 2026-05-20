import XCTest

/// Cue markers are interactive only in Cue mode. In Lyric mode the cue-markers
/// overlay is rendered dimmed and stops hit-testing. Uses the existing three-cue
/// seed.
final class EditorModeGatingUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [SeedKey.threeCuesAt1And3And6.launchArgument]
        app.launch()
        return app
    }

    private func firstMarker(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueMarker-'"))
            .firstMatch
    }

    /// Scenario: cue markers stay present in Cue mode
    /// Given a seeded document in the default Cue mode
    /// Then the cue markers overlay is present and on screen.
    func test_cueMode_markersOverlayPresent() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        XCTAssertTrue(firstMarker(app).waitForExistence(timeout: 15))
    }

    /// Scenario: entering Lyric mode dims the cue markers
    /// Given a seeded document
    /// When the user switches to Lyric mode
    /// Then the cue markers overlay is rendered dimmed and non-hit-testable.
    ///
    /// Screenshot-smoke — opacity / `allowsHitTesting` are not queryable via
    /// XCUITest, so this captures the dimmed state rather than asserting it.
    func test_lyricMode_markersDimmed_smoke() throws {
        let app = launchSeeded()
        defer { app.terminate() }
        XCTAssertTrue(firstMarker(app).waitForExistence(timeout: 15))
        let lyricSegment = app.descendants(matching: .any).matching(identifier: "editorModeSegment-lyric").firstMatch
        XCTAssertTrue(lyricSegment.waitForExistence(timeout: 5))
        lyricSegment.click()
        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "lyric-mode-markers-dimmed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
