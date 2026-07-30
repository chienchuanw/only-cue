import XCTest

/// Pioneers the XCUITest screenshot-validation pattern for OnlyCue.
/// Captures the full screen via `XCUIScreen.main.screenshot()`, attaches it
/// to the test result with `lifetime = .keepAlways`, AND writes a PNG copy
/// to a `screenshots/` subdirectory under `NSTemporaryDirectory()` so the
/// latest baseline is browsable from the shell without launching Xcode's
/// result navigator.
///
/// Why `NSTemporaryDirectory()` rather than the repo root: the XCUITest
/// runner runs in a TCC-restricted context and is denied write access to
/// `~/Documents` (where this repo lives). Writing to the temp dir avoids the
/// sandbox dance entirely; the path is logged on each run so the developer
/// can grab the artifact with `open "$(...)"`. The `XCTAttachment` copy in
/// the xcresult bundle is still the canonical artifact for CI / review.
final class TransportBarScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Transport bar renders on a fresh document with LTC output disabled
    /// Given the app is launched and an untitled document is opened
    /// And LTCRoutingStore.shared.settings.isEnabled is false (the fresh-launch default)
    /// And the seeded media carries no LTC
    /// Then the HMS time readout is visible
    /// And the timecode readout is hidden
    /// And a screenshot of the document window is captured for review.
    func test_transportBar_visualBaseline() throws {
        let app = XCUIApplication()
        // Seed a document with media so the transport renders — it is hidden
        // in the no-media empty state (Quiet Pro redesign).
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-seed=three-cues-1-3-6"
        ]
        app.launch()

        let timeReadout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(
            timeReadout.waitForExistence(timeout: 10),
            "the transport should render for the seeded document within 10 seconds"
        )
        // Wait rather than check instantly: the striped-LTC scan is async, so an
        // immediate `exists` would pass before it could have published (#712).
        XCTAssertFalse(
            app.staticTexts["smpteTimecode"].waitForExistence(timeout: 5),
            "the timecode readout must be hidden with no file timecode and LTC output off (#712)"
        )

        // Activate the app so it comes to the front before screenshot — without
        // this the OnlyCue window may be hidden behind whatever else is on the
        // user's screen, leaving the captured PNG visually unhelpful even
        // though accessibility queries still work.
        Foregrounding.activateRobustly(app)

        try captureScreenshot(named: "transport-bar-baseline", window: app.windows.firstMatch)

        // Explicit terminate avoids the "Failed to terminate" tear-down error
        // observed when leaving the launched app + attachment processing for
        // the harness to clean up. Pinning the lifecycle inside the test keeps
        // the run deterministic.
        app.terminate()
    }

    /// Scenario: Transport bar renders correctly in Dark appearance
    /// Given the app is launched pinned to Dark appearance via
    ///   `--ui-test-appearance=dark`
    /// And an untitled document seeded with three cues is opened
    /// Then the HMS time readout is visible
    /// And a screenshot of the document window is captured for the
    ///   dark-mode visual sanity pass (spec §9 — issue #365).
    func test_transportBar_darkMode_visualBaseline() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark",
            "--ui-test-seed=three-cues-1-3-6"
        ]
        app.launch()

        let timeReadout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(
            timeReadout.waitForExistence(timeout: 10),
            "the transport should render for the seeded document in Dark appearance within 10 seconds"
        )

        Foregrounding.activateRobustly(app)

        try captureScreenshot(named: "transport-bar-dark-baseline", window: app.windows.firstMatch)

        app.terminate()
    }

    // MARK: - Screenshot helpers

    /// Attaches a screenshot to the xcresult bundle AND writes a PNG copy to
    /// `<repo>/screenshots/<name>.png`. The repo root is resolved from the
    /// compile-time path of this source file, so the location works whether
    /// the test runs from CLI or Xcode and survives moving DerivedData. If
    /// the source file is ever relocated, update `repoRoot` accordingly.
    /// Captures `window` (or the full screen if `window` is nil), attaches
    /// to the xcresult, and writes a PNG to the runner's tmp screenshots dir.
    /// Window-scoped capture keeps the artifact tightly framed on the app
    /// under test rather than whatever else happens to be on the developer's
    /// display.
    private func captureScreenshot(named name: String, window: XCUIElement? = nil) throws {
        let screenshot: XCUIScreenshot
        if let window, window.waitForExistence(timeout: 2) {
            screenshot = window.screenshot()
        } else {
            screenshot = XCUIScreen.main.screenshot()
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = Self.screenshotsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: fileURL)
        print("[screenshot] wrote \(fileURL.path)")
    }

    private static var screenshotsDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("screenshots", isDirectory: true)
    }
}
