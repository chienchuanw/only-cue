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
        try runOSCSettingsCapture(appearance: nil, screenshotName: "osc-settings")
    }

    /// Dark-mode sibling for the figma↔app audit (issue #373). There is no
    /// dedicated Figma frame for the OSC settings pane — capture serves as
    /// the baseline so the audit doc can flag any token/layout drift.
    func test_oscSettings_darkMode_visualBaseline() throws {
        try runOSCSettingsCapture(appearance: "dark", screenshotName: "osc-settings-dark")
    }

    private func runOSCSettingsCapture(appearance: String?, screenshotName: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        if let appearance {
            app.launchArguments += ["--ui-test-appearance=\(appearance)"]
        }
        app.launch()
        // A document isn't required for Settings, but ⌘N gives a stable focused
        // window state matching the other screenshot tests' setup.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["importMediaButton"].waitForExistence(timeout: 15),
            "a document window should open within 5 seconds"
        )

        // Settings is a `TabView` on macOS, so the window's *title* follows the
        // selected pane ("OSC" by default) rather than being "OnlyCue Settings",
        // and SwiftUI `Form` rows aren't reliably in the a11y tree (PR #138's
        // export-sheet bugfix hit the same wall). Just confirm a new window
        // opened, then screenshot it.
        XCTAssertTrue(
            SettingsWindowFinder.open(in: app, above: app.windows.count),
            "pressing ⌘, should open the Settings window"
        )
        _ = app.checkBoxes["oscEnableToggle"].waitForExistence(timeout: 2)

        Thread.sleep(forTimeInterval: 0.8)
        try captureScreenshot(named: screenshotName, window: SettingsWindowFinder.window(in: app))
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
