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
        try runTimecodeSettingsCapture(appearance: nil, screenshotName: "timecode-settings")
    }

    /// Dark-mode sibling of `test_timecodeSettings_visualBaseline`. Forces
    /// Dark appearance so the capture lines up with the Figma reference
    /// (frame 321:2279) for the figma↔app audit (issue #373).
    func test_timecodeSettings_darkMode_visualBaseline() throws {
        try runTimecodeSettingsCapture(appearance: "dark", screenshotName: "timecode-settings-dark")
    }

    private func runTimecodeSettingsCapture(appearance: String?, screenshotName: String) throws {
        let app = XCUIApplication()
        // Seed a document with media so the sheet shows its "Media start
        // timecodes" card (Figma 321:2279) — the handler opens the doc, so no ⌘N.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", SeedKey.setListActI.launchArgument]
        if let appearance {
            app.launchArguments += ["--ui-test-appearance=\(appearance)"]
        }
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "itemRow").firstMatch.waitForExistence(timeout: 15),
            "the seeded document's media should load within 15 seconds"
        )

        Foregrounding.activateRobustly(app)

        let toolsMenu = app.menuBars.menuBarItems["Tools"]
        XCTAssertTrue(toolsMenu.waitForExistence(timeout: 3))
        toolsMenu.click()
        let item = app.menuItems["Timecode Settings…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()

        let mediaCard = app.descendants(matching: .any).matching(identifier: "timecodeSheetItemList").firstMatch
        _ = mediaCard.waitForExistence(timeout: 3)
        // Fixed delay so the sheet animates in before the screenshot fires.
        Thread.sleep(forTimeInterval: 1.2)

        try captureScreenshot(named: screenshotName, window: app.windows.firstMatch)
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
