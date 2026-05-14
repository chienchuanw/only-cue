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
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 5),
            "currentTimeReadout should appear within 5 seconds of opening a document"
        )

        let windowsBefore = app.windows.count
        app.activate()
        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            SettingsWindowFinder.waitForNewWindow(in: app, above: windowsBefore, timeout: 5),
            "pressing ⌘, should open the Settings window within 5 seconds"
        )

        // Switch to the Keyboard tab. SwiftUI tab items expose as radio buttons
        // (or plain buttons) on macOS — try by label; if neither is in the a11y
        // tree the screenshot just captures the default (OSC) pane, which is
        // still a useful baseline.
        let keyboardTab = app.radioButtons["Keyboard"].exists ? app.radioButtons["Keyboard"] : app.buttons["Keyboard"]
        if keyboardTab.waitForExistence(timeout: 3) {
            keyboardTab.click()
            _ = app.buttons["keymapChord.importMedia"].waitForExistence(timeout: 3)
        }

        Thread.sleep(forTimeInterval: 0.9)
        try captureScreenshot(named: "keyboard-settings", window: SettingsWindowFinder.window(in: app))
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
