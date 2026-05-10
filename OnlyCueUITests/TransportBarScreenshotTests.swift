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

    /// Scenario: Transport bar renders on a fresh document
    /// Given the app is launched and an untitled document is opened
    /// Then the play/pause button is visible
    /// And a screenshot of the document window is captured for review.
    func test_transportBar_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let playPauseButton = app.buttons["playPauseButton"]
        XCTAssertTrue(
            playPauseButton.waitForExistence(timeout: 5),
            "playPauseButton should appear within 5 seconds of opening a document"
        )

        try captureScreenshot(named: "transport-bar-baseline")

        // Explicit terminate avoids the "Failed to terminate" tear-down error
        // observed when leaving the launched app + attachment processing for
        // the harness to clean up. Pinning the lifecycle inside the test keeps
        // the run deterministic.
        app.terminate()
    }

    // MARK: - Screenshot helpers

    /// Attaches a screenshot to the xcresult bundle AND writes a PNG copy to
    /// `<repo>/screenshots/<name>.png`. The repo root is resolved from the
    /// compile-time path of this source file, so the location works whether
    /// the test runs from CLI or Xcode and survives moving DerivedData. If
    /// the source file is ever relocated, update `repoRoot` accordingly.
    private func captureScreenshot(named name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()

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
