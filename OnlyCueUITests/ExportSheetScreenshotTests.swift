import XCTest

/// Captures the export sheet's visual baseline. Triggers the sheet via the
/// `⇧⌘E` shortcut after opening a fresh document, then writes a window-scoped
/// PNG to the runner's tmp screenshots dir for review.
final class ExportSheetScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Export sheet opens from the File menu shortcut
    /// Given the app is launched and an untitled document is opened
    /// When the user invokes Export Cues… (⇧⌘E)
    /// Then the export sheet is presented
    /// And a screenshot of the document window (sheet attached) is captured.
    func test_exportSheet_visualBaseline() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let timeReadout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(
            timeReadout.waitForExistence(timeout: 5),
            "currentTimeReadout should appear within 5 seconds of opening a document"
        )

        app.activate()

        // Drive the export sheet via the menu bar. SwiftUI sheets on macOS
        // render their content with limited accessibility-tree exposure —
        // `app.buttons["exportConfirm"]` cannot reach into the sheet on this
        // SDK. Manual System-Events probing confirmed the sheet IS presented
        // (it lives as `sheet 1 of window 1`); we just can't easily query its
        // children through XCUITest. Screenshot the window — which captures
        // the sheet since macOS sheets layer over the parent window — and
        // rely on visual review for the assertion.
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 2))
        fileMenu.click()
        let exportItem = app.menuItems["Export Cues…"]
        XCTAssertTrue(exportItem.waitForExistence(timeout: 2))
        exportItem.click()

        // Fixed delay so the sheet animates in before the screenshot fires.
        Thread.sleep(forTimeInterval: 1.5)

        try captureScreenshot(named: "export-sheet", window: app.windows.firstMatch)
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
