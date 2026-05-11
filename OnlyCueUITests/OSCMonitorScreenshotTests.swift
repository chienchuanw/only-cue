import XCTest

/// Captures the OSC monitor sheet's visual baseline. Opens a fresh document,
/// invokes Tools → OSC Monitor…, then writes a window-scoped PNG to the
/// runner's tmp screenshots dir for review. Same persistence + sheet-screenshot
/// pattern as `ExportSheetScreenshotTests` — SwiftUI sheets expose a limited
/// accessibility tree on macOS, so we screenshot the parent window (which the
/// sheet layers over) and rely on visual review.
final class OSCMonitorScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: OSC monitor opens from the Tools menu
    /// Given the app is launched and an untitled document is opened
    /// When the user invokes Tools → OSC Monitor…
    /// Then the OSC monitor sheet is presented
    /// And a screenshot of the document window (sheet attached) is captured.
    func test_oscMonitor_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let playPauseButton = app.buttons["playPauseButton"]
        XCTAssertTrue(
            playPauseButton.waitForExistence(timeout: 5),
            "playPauseButton should appear within 5 seconds of opening a document"
        )

        app.activate()

        let toolsMenu = app.menuBars.menuBarItems["Tools"]
        XCTAssertTrue(toolsMenu.waitForExistence(timeout: 2))
        toolsMenu.click()
        let monitorItem = app.menuItems["OSC Monitor…"]
        XCTAssertTrue(monitorItem.waitForExistence(timeout: 2))
        monitorItem.click()

        // Fixed delay so the sheet animates in before the screenshot fires.
        Thread.sleep(forTimeInterval: 1.5)

        try captureScreenshot(named: "osc-monitor", window: app.windows.firstMatch)
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
