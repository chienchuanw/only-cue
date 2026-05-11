import XCTest

/// Opens Settings → OSC, captures a screenshot for visual review, and writes
/// the PNG to the runner's tmp screenshots dir (copied into the repo
/// `screenshots/` directory by the dev workflow). Same persistence pattern as
/// `ExportSheetScreenshotTests`.
final class OSCSettingsScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Settings → OSC pane renders
    /// Given the app is launched
    /// When the user opens Settings (⌘,)
    /// Then the OSC settings pane is shown with the enable toggle and address list
    /// And a screenshot of the Settings window is captured.
    func test_oscSettings_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        // A document isn't required for Settings, but ⌘N gives a stable focused
        // window state matching the other screenshot tests' setup.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["playPauseButton"].waitForExistence(timeout: 5),
            "playPauseButton should appear within 5 seconds of opening a document"
        )

        app.activate()
        app.typeKey(",", modifierFlags: .command)

        // SwiftUI `Form` content on macOS exposes a limited accessibility tree
        // (the export-sheet bugfix in PR #138 hit the same wall) — anchor on
        // the Settings *window* (titles ARE exposed) rather than an element
        // inside it, then screenshot that window for visual review.
        let settingsWindow = app.windows["OnlyCue Settings"]
        XCTAssertTrue(
            settingsWindow.waitForExistence(timeout: 3),
            "the Settings window should appear within 3 seconds of pressing ⌘,"
        )

        Thread.sleep(forTimeInterval: 0.8)
        try captureScreenshot(named: "osc-settings", window: settingsWindow)
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
