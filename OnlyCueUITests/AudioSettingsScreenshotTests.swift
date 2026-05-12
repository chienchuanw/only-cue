import XCTest

/// Opens Settings → Audio, captures a screenshot for visual review, and writes
/// the PNG to the runner's tmp screenshots dir (copied into the repo
/// `screenshots/` directory by the dev workflow). Same pattern as
/// `KeyboardSettingsScreenshotTests`.
final class AudioSettingsScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Settings → Audio pane renders
    /// Given the app is launched
    /// When the user opens Settings (⌘,) and selects the Audio tab
    /// Then the "Enable LTC output" toggle is shown (the device picker and
    ///   per-channel role table appear once it is turned on)
    /// And a screenshot of the Settings window is captured.
    func test_audioSettings_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["playPauseButton"].waitForExistence(timeout: 5),
            "playPauseButton should appear within 5 seconds of opening a document"
        )

        let windowsBefore = app.windows.count
        app.activate()
        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            SettingsWindowFinder.waitForNewWindow(in: app, above: windowsBefore, timeout: 5),
            "pressing ⌘, should open the Settings window within 5 seconds"
        )

        let audioTab = app.radioButtons["Audio"].exists ? app.radioButtons["Audio"] : app.buttons["Audio"]
        if audioTab.waitForExistence(timeout: 3) {
            audioTab.click()
            _ = app.otherElements["audioSettings"].waitForExistence(timeout: 3)
        }

        Thread.sleep(forTimeInterval: 0.9)
        try captureScreenshot(named: "audio-settings", window: SettingsWindowFinder.window(in: app))
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
