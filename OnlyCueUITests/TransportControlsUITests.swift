import XCTest

/// Verifies the B+ `TransportControls` renders visible playback controls when
/// media is loaded — the gap the Quiet Pro redesign closes (the old
/// `TransportBar` had no on-screen play/step controls).
final class TransportControlsUITests: OnlyCueUITestCase {

    private func launchSeeded() -> XCUIApplication {
        launchApp(seed: .threeCuesAt1And3And6)
    }

    func test_transportShowsControlsWhenMediaLoaded() throws {
        let app = launchSeeded()
        XCTAssertTrue(
            app.buttons["transportPlayPause"].waitForExistence(timeout: 15),
            "play/pause control should render when media is loaded"
        )
        XCTAssertTrue(app.buttons["transportPrevCue"].exists, "previous-cue control missing")
        XCTAssertTrue(app.buttons["transportNextCue"].exists, "next-cue control missing")
        // Song navigation (#753) flanks the cue controls.
        XCTAssertTrue(app.buttons["transportPrevSong"].exists, "previous-song control missing")
        XCTAssertTrue(app.buttons["transportNextSong"].exists, "next-song control missing")
        XCTAssertTrue(app.staticTexts["currentTimeReadout"].exists, "current-time readout missing")
    }

    func test_playButtonIsHittable() throws {
        let app = launchSeeded()
        let play = app.buttons["transportPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        XCTAssertTrue(play.isHittable, "play/pause control should be clickable")
        play.click()
    }

    /// Figma 318:1309/318:1249: the transport is a thin row pinned to the bottom
    /// of the center pane. It previously floated ~60pt above the bottom because
    /// invisible keyboard-shortcut hosts added VStack spacing below it (#514).
    func test_transportPinnedToBottom() throws {
        let app = launchSeeded()
        let transport = app.descendants(matching: .any)
            .matching(identifier: "transportControls").firstMatch
        XCTAssertTrue(transport.waitForExistence(timeout: 15), "transport bar should render")
        let gapBelow = app.windows.firstMatch.frame.maxY - transport.frame.maxY
        XCTAssertLessThan(
            gapBelow,
            transport.frame.height,
            "transport should sit at the bottom of the window, not float above it "
                + "(gapBelow=\(gapBelow), barHeight=\(transport.frame.height))"
        )
    }
}
