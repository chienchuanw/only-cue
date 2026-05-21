import XCTest

/// Verifies the B+ `TransportControls` renders visible playback controls when
/// media is loaded — the gap the Quiet Pro redesign closes (the old
/// `TransportBar` had no on-screen play/step controls).
final class TransportControlsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            SeedKey.threeCuesAt1And3And6.launchArgument
        ]
        app.launch()
        return app
    }

    func test_transportShowsControlsWhenMediaLoaded() throws {
        let app = launchSeeded()
        XCTAssertTrue(
            app.buttons["transportPlayPause"].waitForExistence(timeout: 15),
            "play/pause control should render when media is loaded"
        )
        XCTAssertTrue(app.buttons["transportPrevCue"].exists, "previous-cue control missing")
        XCTAssertTrue(app.buttons["transportNextCue"].exists, "next-cue control missing")
        XCTAssertTrue(app.staticTexts["currentTimeReadout"].exists, "current-time readout missing")
    }

    func test_playButtonIsHittable() throws {
        let app = launchSeeded()
        let play = app.buttons["transportPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(play.isHittable, "play/pause control should be clickable")
        play.click()
    }
}
