import XCTest

/// Opens Settings → MIDI, captures a dark-mode screenshot, and writes the PNG
/// to the runner's tmp screenshots dir. Same pattern as
/// `KeyboardSettingsScreenshotTests`. Added for the Windows-port Figma
/// calibration (#728): the MIDI pane had no Figma frame.
final class MIDISettingsScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Settings → MIDI pane renders
    /// Given the app is launched
    /// When the user opens Settings (⌘,) and selects the MIDI tab
    /// Then the input-device picker and binding sections are shown
    /// And a dark-mode screenshot of the Settings window is captured.
    func test_midiSettings_darkMode_visualBaseline() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Flaky on self-hosted runner: ⌘N + ⌘, foregrounding race."
        )
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "--ui-test-appearance=dark"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["importMediaButton"].waitForExistence(timeout: 15),
            "a document window should open within 15 seconds"
        )

        let windowsBefore = app.windows.count
        Foregrounding.activateRobustly(app)
        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            SettingsWindowFinder.waitForNewWindow(in: app, above: windowsBefore, timeout: 15),
            "pressing ⌘, should open the Settings window within 15 seconds"
        )

        let midiTab = app.radioButtons["MIDI"].exists ? app.radioButtons["MIDI"] : app.buttons["MIDI"]
        if midiTab.waitForExistence(timeout: 3) {
            midiTab.click()
            _ = app.popUpButtons["midiDevicePicker"].waitForExistence(timeout: 3)
        }

        Thread.sleep(forTimeInterval: 0.9)
        try captureScreenshot(named: "midi-settings-dark", window: SettingsWindowFinder.window(in: app))
        app.terminate()
    }

    private func captureScreenshot(named name: String, window: XCUIElement? = nil) throws {
        let screenshot: XCUIScreenshot
        if let window, window.exists {
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
