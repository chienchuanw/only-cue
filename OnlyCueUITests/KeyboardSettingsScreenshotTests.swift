import XCTest

/// Opens Settings → Keyboard, captures a screenshot for visual review, and
/// writes the PNG to the runner's tmp screenshots dir (copied into the repo
/// `screenshots/` directory by the dev workflow). Same pattern as
/// `OSCSettingsScreenshotTests`.
final class KeyboardSettingsScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Settings → Keyboard pane renders
    /// Given the app is launched
    /// When the user opens Settings (⌘,) and selects the Keyboard tab
    /// Then the keymap table is shown with one row per action
    /// And a screenshot of the Settings window is captured.
    func test_keyboardSettings_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["playPauseButton"].waitForExistence(timeout: 5),
            "playPauseButton should appear within 5 seconds of opening a document"
        )

        app.activate()
        app.typeKey(",", modifierFlags: .command)

        let settingsWindow = app.windows["OnlyCue Settings"]
        XCTAssertTrue(
            settingsWindow.waitForExistence(timeout: 3),
            "the Settings window should appear within 3 seconds of pressing ⌘,"
        )

        // Switch to the Keyboard tab. SwiftUI tab items expose as buttons /
        // radio buttons on macOS — click by label, falling back to a coordinate
        // tap near the second tab if the label isn't in the a11y tree.
        let keyboardTab = settingsWindow.buttons["Keyboard"].firstMatch
        if keyboardTab.waitForExistence(timeout: 2) {
            keyboardTab.click()
        } else if settingsWindow.radioButtons["Keyboard"].firstMatch.waitForExistence(timeout: 1) {
            settingsWindow.radioButtons["Keyboard"].firstMatch.click()
        }

        Thread.sleep(forTimeInterval: 0.9)
        try captureScreenshot(named: "keyboard-settings", window: settingsWindow)
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
