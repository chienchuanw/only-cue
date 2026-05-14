import XCTest

/// Captures the Timecode Settings sheet's visual baseline. Opens a fresh
/// document, invokes Tools → Timecode Settings…, then writes a window-scoped
/// PNG to the runner's tmp screenshots dir for review — same pattern as
/// `OSCMonitorScreenshotTests` (SwiftUI sheets expose a limited a11y tree on
/// macOS, so we screenshot the parent window the sheet layers over).
final class TimecodeSettingsSheetScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Timecode Settings opens from the Tools menu
    /// Given the app is launched and an untitled document is opened
    /// When the user invokes Tools → Timecode Settings…
    /// Then the Timecode Settings sheet is presented (framerate picker + start-timecode field)
    /// And a screenshot of the document window (sheet attached) is captured.
    func test_timecodeSettings_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 5),
            "currentTimeReadout should appear within 5 seconds of opening a document"
        )

        app.activate()

        let toolsMenu = app.menuBars.menuBarItems["Tools"]
        XCTAssertTrue(toolsMenu.waitForExistence(timeout: 2))
        toolsMenu.click()
        let item = app.menuItems["Timecode Settings…"]
        XCTAssertTrue(item.waitForExistence(timeout: 2))
        item.click()

        // Fixed delay so the sheet animates in before the screenshot fires.
        Thread.sleep(forTimeInterval: 1.2)

        try captureScreenshot(named: "timecode-settings", window: app.windows.firstMatch)
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
