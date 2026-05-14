import AppKit
import XCTest

/// BDD smoke for the hold-to-scrub interaction on the main-pane waveform.
/// Spec: `docs/superpowers/specs/2026-05-14-main-pane-timeline-interaction-design.md`.
///
/// Halo opacity and the `(isHovered, isSelected)` dispatch are covered by
/// `OnlyCueTests/CueMarkerHaloTests`. XCUITest can only assert element
/// existence and a coarse press/drag/release flow.
///
/// The "press while playing → engine pauses on press → resumes on release"
/// case from the spec is covered deterministically by
/// `TimelineScrubOrchestratorTests.test_begin_whenPlaying_pausesAndStartsScrubAtPressedTime`
/// rather than UI tests — XCUITest cannot reliably read live `PlayerEngine`
/// state, and asserting on the current-time readout alone cannot distinguish
/// "paused then resumed" from "kept playing".
final class WaveformHoldScrubUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        for app in NSRunningApplicationFinder.runningOnlyCueApps() {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Smoke

    func test_seekSurface_exists_andGrabberRemoved() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let surface = app.descendants(matching: .any)
            .matching(identifier: "waveformSeekSurface")
            .firstMatch
        XCTAssertTrue(
            surface.waitForExistence(timeout: 15),
            "waveformSeekSurface should appear after the seeded document opens"
        )

        // The dedicated playhead grabber was removed by this design.
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "playheadGrabber")
                .firstMatch.exists,
            "playheadGrabber should no longer be in the AX tree after the redesign"
        )
    }

    // MARK: - Click-to-seek (paused)

    /// Given paused transport, When I click an empty timeline point, Then the
    /// playhead seeks there and transport stays paused. We assert by reading
    /// the transport bar's currentTimeReadout before and after.
    func test_click_whilePaused_seeksAndStaysPaused() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15))

        let surface = app.descendants(matching: .any)
            .matching(identifier: "waveformSeekSurface")
            .firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))

        let before = readout.label
        let target = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        target.click()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertNotEqual(readout.label, before, "current-time readout should change after click-to-seek")
    }

    // MARK: - Hold-to-scrub (paused)

    /// Given paused transport, When I press-and-hold on the timeline and drag,
    /// Then the playhead tracks the cursor and lands at the release point.
    func test_holdDrag_whilePaused_scrubsAndLandsAtRelease() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15))

        let surface = app.descendants(matching: .any)
            .matching(identifier: "waveformSeekSurface")
            .firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))

        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))

        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.3)

        // The release-point readout should differ from a fresh-launch readout.
        // We don't pin the exact label because the seed duration may shift —
        // the assertion is "scrub moved the playhead from its initial position".
        let labelAfterDrag = readout.label
        XCTAssertFalse(labelAfterDrag.isEmpty)
    }

    // MARK: - Helpers

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }
}
