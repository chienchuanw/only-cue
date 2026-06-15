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

    // The Lyric-mode "dimmed markers" screenshot-smoke was removed (#548): opacity
    // / allowsHitTesting aren't queryable via XCUITest so it asserted nothing.
}
