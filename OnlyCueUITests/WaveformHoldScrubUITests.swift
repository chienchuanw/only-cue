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
///
/// Asserting on `app.staticTexts["currentTimeReadout"].label` is unreliable on
/// macOS XCUITest — the monospaced-digit `Text` exposes an empty AX label in
/// the test runner even when the readout is rendered on screen. These smokes
/// therefore assert on element survival across the gesture rather than label
/// content.
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

        let surface = seekSurface(in: app)
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
    /// click is dispatched without errors and the seek surface stays queryable.
    /// The actual seek math is covered by `CueMarkersGeometryTests`; the
    /// gesture dispatch is covered by `TimelineScrubOrchestratorTests`. This
    /// UI smoke only verifies the click reaches the surface and does not
    /// crash, hang, or remove the surface from the AX tree.
    func test_click_whilePaused_dispatchesWithoutCrash() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let surface = seekSurface(in: app)
        XCTAssertTrue(surface.waitForExistence(timeout: 15))

        let target = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        target.click()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertTrue(seekSurface(in: app).exists, "seek surface should still be queryable after a click")
    }

    // MARK: - Hold-to-scrub (paused)

    /// Given paused transport, When I press-and-hold on the timeline and drag,
    /// Then the gesture completes without errors and the seek surface stays
    /// queryable. As with the click smoke, the value-level assertions live in
    /// the unit tests; this guards against crashes / hangs / regressions in
    /// gesture wiring.
    func test_holdDrag_whilePaused_dispatchesWithoutCrash() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let surface = seekSurface(in: app)
        XCTAssertTrue(surface.waitForExistence(timeout: 15))

        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))

        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertTrue(seekSurface(in: app).exists, "seek surface should still be queryable after a hold-drag")
    }

    // MARK: - Helpers

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }

    private func seekSurface(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "waveformSeekSurface")
            .firstMatch
    }
}
