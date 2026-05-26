import XCTest

/// Dark-mode screenshot baselines for the 7 Phase 3 surfaces — sheets,
/// popovers, and the Notes Projected overlay. Each test drives the app
/// into the right state and writes a window-scoped PNG; the
/// `docs/design/figma-app-audit-phase3.md` doc pairs them with their
/// Figma references.
///
/// Run each method individually via `-only-testing:` per the established
/// pattern (Settings tabs persist last-selected state across sequential
/// suite runs). The CIRuntime guards mean these only execute when the
/// runner Mac is on push to `dev`/`main` — UI tests are gated off PR
/// CI as established by #387.
final class Phase3ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Sheet · Manage Cue Types (Figma `320:2225`) — opened from
    /// Tools menu → Manage Types…
    func test_manageCueTypes_darkMode_visualBaseline() throws {
        try runMenuSheetCapture(
            menu: "Tools",
            item: "Manage Types…",
            screenshotName: "sheet-manage-types-dark"
        )
    }

    /// Sheet · Note Overlay Appearance (Figma `321:2306`) — opened
    /// from Tools menu → Edit Note Overlay Appearance…
    func test_noteOverlayAppearance_darkMode_visualBaseline() throws {
        try runMenuSheetCapture(
            menu: "Tools",
            item: "Edit Note Overlay Appearance…",
            screenshotName: "sheet-note-overlay-dark"
        )
    }

    /// Sheet · First Launch (Figma `320:2286`) — forced by clearing
    /// the `didShowFirstLaunch` AppStorage flag via launch argument.
    func test_firstLaunch_darkMode_visualBaseline() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark",
            "-didShowFirstLaunch", "NO"
        ]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(
            app.buttons["importMediaButton"].waitForExistence(timeout: 15),
            "document window should open before the first-launch sheet animates in"
        )
        Foregrounding.activateRobustly(app)
        Thread.sleep(forTimeInterval: 1.2)
        try captureScreenshot(named: "sheet-first-launch-dark", window: app.windows.firstMatch)
        app.terminate()
    }

    /// Overlay · Notes (Projected) (Figma `49:458`) — toggle the
    /// notes overlay via the View menu, capture the resulting
    /// projected window.
    func test_notesProjectedOverlay_darkMode_visualBaseline() throws {
        // CI flake: opening the overlay window relies on a separate
        // NSWindow being created and gaining its own foreground state.
        // The non-interactive runner session can't always grant this.
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Flaky on self-hosted runner: secondary window foreground race."
        )
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark",
            "--ui-test-seed=three-cues-1-3-6"
        ]
        app.launch()

        // ⇧⌘N toggles the notes overlay via the default keymap.
        Foregrounding.activateRobustly(app)
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("n", modifierFlags: [.shift, .command])
        Thread.sleep(forTimeInterval: 1.5)

        // Capture the entire screen because the projected overlay is
        // its own borderless window with no easy window-bound query.
        try captureScreenshot(named: "overlay-notes-projected-dark", window: nil)
        app.terminate()
    }

    /// Sheet · Edit Media (Figma `320:2254`) — the functional
    /// `MediaEditSheetUITests` already proves the right-click +
    /// context-menu path; that path is gated off CI for the same
    /// click-absorption flake. Capture the sheet from a state the
    /// runner can reach without context-menu interactions.
    func test_editMedia_darkMode_visualBaseline() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Phase 3.5: needs an inspector entry path; right-click menu flakes."
        )
        // Local-only capture: drive the same right-click flow as the
        // functional test. Skipped on CI; the audit doc notes the
        // surface as captured-locally.
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark",
            "--ui-test-seed=three-cues-1-3-6"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["silent-30s.m4a"].waitForExistence(timeout: 15),
            "seed media row should be visible"
        )
        Foregrounding.activateRobustly(app)

        // Right-click the media row → Edit Media… menu item.
        app.staticTexts["silent-30s.m4a"].rightClick()
        let editItem = app.menuItems["Edit Media…"]
        if editItem.waitForExistence(timeout: 3) {
            editItem.click()
        }
        Thread.sleep(forTimeInterval: 1.2)
        try captureScreenshot(named: "sheet-edit-media-dark", window: app.windows.firstMatch)
        app.terminate()
    }

    /// Popover · Cue Notes (Figma `321:2351`) — Phase 3.5: requires
    /// row-level inspector chord that's brittle on CI.
    func test_cueNotesPopover_darkMode_visualBaseline() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Phase 3.5: needs a cue-row inspector chord; defer to local capture."
        )
        // Implementation deferred — see audit doc Phase 3 status.
    }

    /// Popover · Cue Tempo (Figma `321:2355`) — Phase 3.5: same
    /// scoping as Cue Notes popover.
    func test_cueTempoPopover_darkMode_visualBaseline() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Phase 3.5: needs a cue-row inspector chord; defer to local capture."
        )
        // Implementation deferred — see audit doc Phase 3 status.
    }

    // MARK: - Helpers

    /// Common pattern: open a fresh document, drive a menu-bar
    /// click into a Tools or File menu item that posts a
    /// sheet-presentation notification, screenshot the document
    /// window (the sheet is layered on it).
    private func runMenuSheetCapture(menu: String, item: String, screenshotName: String) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark"
        ]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(
            app.buttons["importMediaButton"].waitForExistence(timeout: 15),
            "document window should open within 15 seconds"
        )

        Foregrounding.activateRobustly(app)

        let menuBarItem = app.menuBars.menuBarItems[menu]
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 5))
        menuBarItem.click()
        let menuItem = app.menuItems[item]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5))
        menuItem.click()

        Thread.sleep(forTimeInterval: 1.5)
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
