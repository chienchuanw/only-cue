import XCTest

/// Captures the document window with the waveform in **split-channel** mode
/// (per-channel lanes, #720) and the LTC strip visible, as the Figma
/// calibration reference for the Windows port (#728). The split-channel
/// waveform / per-channel lanes / LTC badge (v0.22) had no Figma frame.
///
/// Driven by the `split-channels` seed (a single active stereo clip) plus
/// `-splitWaveformChannels 1`, which the app reads from the NSArgumentDomain
/// so the `@AppStorage("splitWaveformChannels")` flag starts on — no fragile
/// menu-bar driving.
final class SplitChannelWaveformScreenshotTests: XCTestCase {

    private static let captureWindowSize = CGSize(width: 1280, height: 820)

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: split-channel waveform + LTC strip render
    /// Given a document seeded with a stereo clip and split channels enabled
    /// When LTC routing is on
    /// Then the preview pane shows per-channel waveform lanes and the LTC strip
    /// And a dark-mode screenshot of the document window is captured.
    func test_splitChannelWaveform_darkMode_visualBaseline() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Flaky on self-hosted runner: foregrounding + waveform-bucket timing."
        )
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark",
            "--ui-test-window=\(Int(Self.captureWindowSize.width))x\(Int(Self.captureWindowSize.height))",
            "--ui-test-seed=split-channels",
            "--ui-test-ltc-enabled",
            // NSArgumentDomain override for @AppStorage("splitWaveformChannels").
            "-splitWaveformChannels", "1"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 15),
            "the seeded document window should open within 15 seconds"
        )
        Foregrounding.activateRobustly(app)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "the document window should exist")
        XCTAssertEqual(
            window.frame.size,
            Self.captureWindowSize,
            "window frame \(window.frame.size) was not pinned to \(Self.captureWindowSize) — the capture would clip"
        )

        // The per-channel lanes only exist once the stereo buckets finish
        // generating; wait for them so the baseline actually exercises the
        // split-channel path rather than the combined waveform.
        let lanes = window.descendants(matching: .any)["waveformLanes"]
        XCTAssertTrue(
            lanes.waitForExistence(timeout: 15),
            "split-channel waveform lanes did not render — the baseline would miss the #720 region"
        )
        let ltcStrip = window.descendants(matching: .any)["ltcStrip"]
        XCTAssertTrue(
            ltcStrip.waitForExistence(timeout: 5),
            "LTC strip did not render — the baseline would miss the LTC badge region"
        )

        Thread.sleep(forTimeInterval: 0.8)
        try captureScreenshot(named: "split-channels-waveform-dark", window: window)
        app.terminate()
    }

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
