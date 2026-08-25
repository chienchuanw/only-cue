import XCTest

/// Behavioral + screenshot coverage for the Mini Player panel (macOS, #748):
/// ⌘⌥M opens a floating panel over the seeded document, toggling again hides it,
/// and a dark-mode capture backs the Figma↔app review.
final class MiniPlayerUITests: OnlyCueUITestCase {

    func test_toggleMiniPlayer_showsAndHidesFloatingPanel() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Flaky on self-hosted runner: menu-shortcut + foregrounding race."
        )
        let app = launchApp(seed: .setListActI, extraArguments: ["--ui-test-appearance=dark"])
        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 15),
            "the seeded document window should open"
        )
        Foregrounding.activateRobustly(app)

        let bar = app.descendants(matching: .any)["miniPlayerBar"]
        XCTAssertFalse(bar.exists, "Mini Player should start hidden")

        // ⌘⌥M opens it.
        app.typeKey("m", modifierFlags: [.command, .option])
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "⌘⌥M should open the Mini Player panel")

        Thread.sleep(forTimeInterval: 0.6)
        try captureScreenshot(named: "miniplayer-panel-dark")

        // ⌘⌥M again hides it.
        app.typeKey("m", modifierFlags: [.command, .option])
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: bar)
        waitForExpectations(timeout: 5)
    }

    /// #770 — the end-to-end proof that a focused Mini Player owns the keyboard.
    ///
    /// This is the only place the key-window path can actually run: a unit-test
    /// host never becomes the active app, so no in-process test can put a real
    /// panel into key state. The shipped bug (a gate keyed off
    /// `NSApp.orderedWindows`, which omits `NSPanel`) survived three releases
    /// precisely because nothing exercised this path.
    ///
    /// Isolated from playback drift: the playhead starts stopped at zero, so
    /// only the Space keypress can move the readout.
    func test_spaceInFocusedMiniPlayer_startsPlayback() throws {
        try XCTSkipIf(
            CIRuntime.isGitHubActions,
            "Flaky on self-hosted runner: menu-shortcut + foregrounding race."
        )
        let app = launchApp(seed: .threeCuesAt1And3And6)
        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 15),
            "the seeded document window should open"
        )
        Foregrounding.activateRobustly(app)

        app.typeKey("m", modifierFlags: [.command, .option])
        let bar = app.descendants(matching: .any)["miniPlayerBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "⌘⌥M should open the Mini Player panel")

        // Focus the panel by its title bar — clicking the body would hit the
        // scrub gesture or a transport button and move the playhead itself.
        let panelWindow = app.windows.containing(.any, identifier: "miniPlayerBar").firstMatch
        XCTAssertTrue(panelWindow.waitForExistence(timeout: 5), "the Mini Player panel window should exist")
        panelWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 8))
            .click()

        XCTAssertTrue(
            readout(app).hasPrefix("00:00:00"),
            "playhead should start at zero, was \(readout(app))"
        )
        app.typeKey(.space, modifierFlags: [])

        XCTAssertTrue(
            waitForReadoutToLeaveZero(app, timeout: 5),
            "Space in the focused Mini Player should start playback; readout stayed \(readout(app))"
        )
    }

    /// The transport's current-time readout, tolerant of whether SwiftUI exposes
    /// the `Text` via `.label` or `.value`.
    private func readout(_ app: XCUIApplication) -> String {
        let element = app.staticTexts["currentTimeReadout"]
        return element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    private func waitForReadoutToLeaveZero(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !readout(app).hasPrefix("00:00:00") { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func captureScreenshot(named name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)
        print("[screenshot] wrote \(url.path)")
    }
}
