import XCTest

/// Seeds a populated document, opens `File → Send to grandMA2…`, and captures a
/// dark-mode screenshot of the MA2 Push sheet. Written for the Windows-port
/// Figma calibration (#728): the MA2 Push sheet had no Figma frame.
final class MA2PushSheetScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: File → Send to grandMA2… presents the batch MA2 push sheet (#765)
    /// Given a populated document with an active media item
    /// When the user chooses File → Send to grandMA2…
    /// Then the batch "Send to grandMA2" sheet is shown listing the project's songs
    /// And a dark-mode screenshot of the sheet is captured.
    func test_ma2BatchSheet_darkMode_visualBaseline() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Flaky on self-hosted runner: menu-bar driving + foregrounding race."
        )
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark",
            "--ui-test-seed=set-list-act-i"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 15),
            "the seeded document window should open within 15 seconds"
        )
        Foregrounding.activateRobustly(app)

        // Drive File → Send to grandMA2… (posts .sendToMA2Requested for the
        // active item, which the seed activates).
        let fileMenu = app.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5), "the File menu should exist")
        fileMenu.click()

        let sendItem = app.menuItems["sendToMA2MenuItem"].exists
            ? app.menuItems["sendToMA2MenuItem"]
            : app.menuItems["Send to grandMA2…"]
        XCTAssertTrue(sendItem.waitForExistence(timeout: 3), "the Send to grandMA2 menu item should exist")
        sendItem.click()

        // The accessibilityIdentifier resolves to more than one element (the
        // container plus its accessibility children), so scope to firstMatch —
        // a bare query can't produce a single snapshot.
        let sheet = app.descendants(matching: .any).matching(identifier: "ma2BatchSheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the batch MA2 push sheet should present")

        // Batch-specific affordance: the multi-song push button is present.
        let pushButton = app.descendants(matching: .any).matching(identifier: "ma2BatchPushButton").firstMatch
        XCTAssertTrue(pushButton.waitForExistence(timeout: 3), "the batch push button should exist")

        Thread.sleep(forTimeInterval: 0.9)
        // Capture the frontmost window (the sheet overlays the document window),
        // which reliably includes the whole sheet region.
        let target: XCUIElement? = app.windows.firstMatch
        try captureScreenshot(named: "ma2-batch-sheet-dark", window: target)
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
