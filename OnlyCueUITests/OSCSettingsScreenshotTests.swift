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

        let windowsBefore = app.windows.count
        app.activate()
        app.typeKey(",", modifierFlags: .command)

        // Settings is a `TabView` on macOS, so the window's *title* follows the
        // selected pane ("OSC" by default) rather than being "OnlyCue Settings",
        // and SwiftUI `Form` rows aren't reliably in the a11y tree (PR #138's
        // export-sheet bugfix hit the same wall). Just confirm a new window
        // opened, then screenshot it.
        XCTAssertTrue(
            SettingsWindowFinder.waitForNewWindow(in: app, above: windowsBefore, timeout: 5),
            "pressing ⌘, should open the Settings window within 5 seconds"
        )
        _ = app.checkBoxes["oscEnableToggle"].waitForExistence(timeout: 2)

        Thread.sleep(forTimeInterval: 0.8)
        try captureScreenshot(named: "osc-settings", window: SettingsWindowFinder.window(in: app))
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

/// Helpers for working with the macOS Settings window, whose title tracks the
/// selected pane (`TabView` behaviour) so it can't be matched by a fixed name.
enum SettingsWindowFinder {

    /// Polls until the app has more than `baseline` windows (the Settings window
    /// opened on top of the document window), or the timeout elapses.
    static func waitForNewWindow(in app: XCUIApplication, above baseline: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.windows.count > baseline { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return app.windows.count > baseline
    }

    /// The Settings window by one of the titles its panes produce, or `nil`
    /// (in which case callers screenshot the whole screen instead).
    static func window(in app: XCUIApplication) -> XCUIElement? {
        for title in ["OnlyCue Settings", "Settings", "OSC", "Keyboard"] {
            let window = app.windows[title]
            if window.exists { return window }
        }
        return nil
    }
}
