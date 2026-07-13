import XCTest

/// Dark-mode screenshot baselines for every visual variant of `DocumentView` —
/// driven by the Figma design system's Screens page (frames 318:1228, 42:212,
/// 318:1334, 318:1369, 318:1504, 318:1614). Powers Phase 2 of the figma↔app
/// audit (issue #376).
///
/// Each test pins `-ApplePersistenceIgnoreState=YES` and runs a single mode
/// in isolation — DO NOT batch within one `xcodebuild test` invocation; per
/// Phase 1 lessons macOS state restoration interferes with sequential new-doc
/// creation, and the Settings window remembers its last-selected pane across
/// tests. Run each method via its own `-only-testing:.../<method>` flag.
final class DocumentViewModeScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Cue Mode (Figma 318:1228) — default editor mode with a seeded
    /// three-cue media item visible. Captures the full document window.
    func test_cueMode_darkMode_visualBaseline() throws {
        try runDocumentCapture(
            seed: "three-cues-1-3-6",
            modeSwitch: nil,
            screenshotName: "main-cue-dark"
        )
    }

    /// Populated (Figma 42:212) — same seed as Cue Mode; expected to be
    /// visually identical at this resolution. Captured so the audit can
    /// confirm-or-distinguish.
    func test_populated_darkMode_visualBaseline() throws {
        try runDocumentCapture(
            seed: "three-cues-1-3-6",
            modeSwitch: nil,
            screenshotName: "main-populated-dark"
        )
    }

    /// Empty (Figma 318:1334) — fresh document, no seed, no media. Tests the
    /// no-media import-well chrome.
    func test_empty_darkMode_visualBaseline() throws {
        try runDocumentCapture(
            seed: nil,
            modeSwitch: nil,
            screenshotName: "main-empty-dark"
        )
    }

    /// Lyric Mode (Figma 318:1369) — seeded `song-with-lyrics`, switched to
    /// the Lyric editor via `EditorModeSwitcher`.
    func test_lyricMode_darkMode_visualBaseline() throws {
        try runDocumentCapture(
            seed: "song-with-lyrics",
            modeSwitch: "Lyric",
            screenshotName: "main-lyric-dark"
        )
    }

    /// Show Mode (Figma 318:1504) — seeded `three-cues-1-3-6`, switched to
    /// the Show editor (lock state).
    func test_showMode_darkMode_visualBaseline() throws {
        try runDocumentCapture(
            seed: "three-cues-1-3-6",
            modeSwitch: "Show",
            screenshotName: "main-show-dark"
        )
    }

    /// Populated Set List — Act I (Figma 318:1228) — the `set-list-act-i` seed:
    /// 8 mixed video/audio media items, 6 named/faded/colored cues, and a
    /// 12-line lyric sheet. Captures the populated Cue-mode document for the
    /// 1:1 audit against Figma's populated frames (§7.1/§7.5/§8.4/§9.2, #416).
    /// LTC routing is enabled (`ltcEnabled: true`) so the LTC strip renders
    /// between the waveform and transport bar, matching the mock's composition
    /// (Figma 318:1228 §7.8, #616). The committed twin is `app-main-populated-dark.png`.
    func test_setListActI_darkMode_visualBaseline() throws {
        try runDocumentCapture(
            seed: "set-list-act-i",
            modeSwitch: nil,
            screenshotName: "main-setlist-cue-dark",
            ltcEnabled: true
        )
    }

    /// Video Project (Figma 318:1614) — the `video-project` seed: the populated
    /// Set List sidebar with the "Projection — Storm.mp4" video clip active, so
    /// the preview pane shows video over the timeline strip (#417).
    func test_videoProject_darkMode_visualBaseline() throws {
        try runDocumentCapture(
            seed: "video-project",
            modeSwitch: nil,
            screenshotName: "main-video-dark"
        )
    }

    // MARK: - Helpers

    /// The deterministic capture frame: Figma's 1280x812 design frame rounded to
    /// the app's `defaultSize` height. `UITestWindowFrameHandler` pins the
    /// document window to this, anchored on-screen, so the full inspector is
    /// captured regardless of the capture display's size/orientation (#614).
    private static let captureWindowSize = CGSize(width: 1280, height: 820)

    private func runDocumentCapture(
        seed: String?,
        modeSwitch: String?,
        screenshotName: String,
        ltcEnabled: Bool = false
    ) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-test-appearance=dark",
            "--ui-test-window=\(Int(Self.captureWindowSize.width))x\(Int(Self.captureWindowSize.height))"
        ]
        if let seed {
            app.launchArguments += ["--ui-test-seed=\(seed)"]
        }
        app.launch()

        // The seed handler opens a document on its own; otherwise drive ⌘N
        // so the empty-state document window appears.
        if seed == nil {
            app.typeKey("n", modifierFlags: .command)
        }

        // Wait for some part of the document window to appear. The import-well
        // exists only in empty state, so for seeded launches we look for the
        // sidebar/media row instead.
        let docReady = seed == nil
            ? app.buttons["importMediaButton"].waitForExistence(timeout: 15)
            : app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 15)
        XCTAssertTrue(docReady, "the document window should open within 15 seconds")

        if let modeSwitch {
            // `EditorModeSwitcher` exposes its segments as buttons with the
            // mode label. Tolerate either kind in the a11y tree.
            let segment = app.radioButtons[modeSwitch].exists
                ? app.radioButtons[modeSwitch]
                : app.buttons[modeSwitch]
            if segment.waitForExistence(timeout: 3) {
                segment.click()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        Foregrounding.activateRobustly(app)
        Thread.sleep(forTimeInterval: 0.8)

        // The capture is only meaningful if the window is exactly the requested
        // frame — a silent clamp (the #617 symptom) would otherwise produce yet
        // another clipped baseline that looks fine to the test. Assert the
        // achieved size before capturing so a clamp fails loudly (#614).
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "the document window should exist")
        XCTAssertEqual(
            window.frame.size,
            Self.captureWindowSize,
            "window frame \(window.frame.size) was not pinned to \(Self.captureWindowSize) — "
                + "the capture would clip (a min-width clamp regressed #617)"
        )

        // When LTC routing is enabled the LTC strip must render between the
        // waveform and transport bar, or the baseline would silently miss the
        // region the fidelity gate is meant to guard (Figma 318:1228 §7.8, #616).
        if ltcEnabled {
            let ltcStrip = window.descendants(matching: .any)["ltcStrip"]
            XCTAssertTrue(
                ltcStrip.waitForExistence(timeout: 3),
                "LTC strip did not render — the populated baseline would not exercise the LTC region (#616)"
            )
        }

        try captureScreenshot(named: screenshotName, window: window)
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
