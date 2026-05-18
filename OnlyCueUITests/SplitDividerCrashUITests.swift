import XCTest

/// Regression for issue #297 — dragging the divider between the main
/// (waveform) pane and the cue-list (`.inspector`) pane drove an
/// `NSSplitView` constraint-update recursion (`SplitViewChildController.
/// hostingView_didUpdateMinSize:maxSize:`) until AppKit asserted with
/// `NSGenericException: ... more Update Constraints passes than there are
/// views`. The manual repro is timing-dependent; this test oscillates the
/// divider across its full range many times to tip the latent loop
/// deterministically and asserts the app survives.
///
/// Locating the inspector splitter is hit-test fragile on the headless CI
/// runner (same family as the right-click tolerance documented in
/// `MediaEditSheetUITests`); when it cannot be resolved we `XCTSkip` —
/// `CueListInspectorMetricsTests` is the deterministic invariant guard.
final class SplitDividerCrashUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
    }

    func test_draggingMainCueListDivider_doesNotCrash() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let cueListPane = window.descendants(matching: .any)
            .matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(cueListPane.waitForExistence(timeout: 15), "cueListPane should appear")

        // The inspector divider is the window splitter whose center is
        // nearest the cue-list pane's leading edge. Splitter element
        // coordinates are finite (unlike app-relative offsets), which keeps
        // the synthesized drag valid.
        let paneLeadingX = cueListPane.frame.minX
        let splitters = window.splitters.allElementsBoundByIndex
        let splitter = splitters.min(by: {
            abs($0.frame.midX - paneLeadingX) < abs($1.frame.midX - paneLeadingX)
        })
        try XCTSkipIf(
            splitter == nil,
            "CI: inspector splitter not resolvable; CueListInspectorMetricsTests is authoritative."
        )
        guard let divider = splitter else { return }

        let center = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let toMax = center.withOffset(CGVector(dx: -120, dy: 0)) // widen inspector toward max
        let toMin = center.withOffset(CGVector(dx: 120, dy: 0))  // shrink inspector toward min

        // 40 rapid full-range cycles — far more aggressive than a human
        // drag; reliably tips the min<->max bistable loop if reintroduced.
        for _ in 0..<40 {
            toMax.press(forDuration: 0.01, thenDragTo: toMin)
            toMin.press(forDuration: 0.01, thenDragTo: toMax)
        }

        XCTAssertEqual(
            app.state,
            .runningForeground,
            "App must still run after rapid divider drags (issue #297 crash)."
        )
        XCTAssertTrue(
            cueListPane.exists,
            "cueListPane must still exist — app did not crash during divider tracking."
        )
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }

    private func waitForSeedWindow(in app: XCUIApplication, timeout: TimeInterval = 15) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = app.windows.allElementsBoundByIndex
            if let match = windows.first(where: { $0.title.hasPrefix("seed-") }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
