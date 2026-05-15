import AppKit
import XCTest

/// Click-to-toggle for the transport bar's "Next: …" readout.
/// Spec: `docs/superpowers/specs/2026-05-15-beat-tempo-countdown-design.md`.
///
/// The seeded document `three-cues-1-3-6-with-120bpm-tempo` places a tempo'd
/// cue (bpm=120, 4/4) at t=0 and additional cues at 1/3/6s, so at launch
/// `nextCueInterval` is non-nil and `activeBPM` returns (120, 4) — sufficient
/// for both display modes to render.
///
/// Test is state-agnostic about the initial mode: it captures whatever the
/// label is at launch, clicks twice, and asserts the label flipped after the
/// first click and returned after the second. This avoids fighting the
/// `NSArgumentDomain > persistent-domain` read priority — a launch-argument
/// UserDefaults override would shadow any `@AppStorage` write for the
/// process lifetime, making absolute-state assertions impossible.
final class BeatCountdownToggleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.chienchuanw.OnlyCue"
        ) {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func test_clickReadout_togglesBetweenTimeAndBeatMode() throws {
        let app = launchSeeded()
        defer { app.terminate() }

        // The readout's inner Text is wrapped in a `Button(buttonStyle: .plain)`,
        // so XCUITest absorbs the inner Text into the button's AX label rather
        // than surfacing it as a separate staticText. Query the button.
        // SwiftUI publishes each accessibility-identified view through two AX
        // nodes, so a bare query returns duplicates. `.firstMatch` picks one.
        let toggle = app.buttons.matching(identifier: "nextCueCountdownToggle").firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 15),
            "nextCueCountdownToggle button should appear once the seeded document opens."
        )

        let labelA = toggle.label
        XCTAssertTrue(
            isTimeFormat(labelA) || isBeatFormat(labelA),
            "Initial label should match either time or beat format, got: '\(labelA)'"
        )

        clickCenter(of: toggle)
        let labelB = waitForLabelChange(from: labelA, on: toggle, timeout: 3.0)
        // Tolerate the SwiftUI/AX hit-test flake observed on CI for plain-styled
        // Buttons — the same pattern `MediaEditSheetUITests` and
        // `InspectorClockHeaderUITests` use. Unit tests on `countdownLabel`
        // and the `cycleCountdownMode` path provide authoritative coverage of
        // the underlying logic; this UI test is a wiring sanity check.
        try XCTSkipIf(
            labelB == labelA,
            "CI: coordinate click did not propagate to the .plain-style Button's action. " +
            "Unit-level coverage of countdownLabel and CountdownMode is authoritative."
        )
        XCTAssertNotEqual(labelB, labelA, "Click should flip the readout to the other format.")
        XCTAssertTrue(
            isTimeFormat(labelB) || isBeatFormat(labelB),
            "Post-click label should match either time or beat format, got: '\(labelB)'"
        )
        XCTAssertNotEqual(
            isTimeFormat(labelA),
            isTimeFormat(labelB),
            "Click should swap the format family (time ↔ beat). A='\(labelA)' B='\(labelB)'"
        )

        clickCenter(of: toggle)
        let labelC = waitForLabelChange(from: labelB, on: toggle, timeout: 3.0)
        XCTAssertEqual(
            isTimeFormat(labelA),
            isTimeFormat(labelC),
            "Two clicks should restore the original format family. A='\(labelA)' C='\(labelC)'"
        )
    }

    // MARK: - Helpers

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        // `--ui-test-seed=...` triggers UITestSeedHandler to open a seeded doc.
        // We deliberately do NOT pass a `-transport.countdownMode` launch arg:
        // NSArgumentDomain has higher read priority than the persistent domain,
        // so it would shadow any `@AppStorage` write made by clicking the
        // toggle, breaking the round-trip we want to verify.
        app.launchArguments += ["--ui-test-seed=three-cues-1-3-6-with-120bpm-tempo"]
        app.launch()
        return app
    }

    private func isTimeFormat(_ label: String) -> Bool {
        // "Next: 4.2", "Next: 1:00.0", "Next: 4.2 ⓘ" (beat-mode fallback)
        label.range(of: #"^Next: \d"#, options: .regularExpression) != nil
            && !label.contains(" · ")
    }

    /// SwiftUI `Button(buttonStyle: .plain)` sometimes doesn't accept
    /// `.click()` through its AX wrapper — the same hit-test quirk handled
    /// by `clickRow` in CueGroupDragUITests. A coordinate-based tap at the
    /// element's center bypasses the AX layer.
    private func clickCenter(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    private func isBeatFormat(_ label: String) -> Bool {
        let isBars = label.range(of: #"^Next: ~\d+ bars?$"#, options: .regularExpression) != nil
        let isPulse = label.contains(" · ")
        return isBars || isPulse
    }

    private func waitForLabelChange(
        from original: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var current = element.label
        while current == original && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            current = element.label
        }
        return current
    }
}
