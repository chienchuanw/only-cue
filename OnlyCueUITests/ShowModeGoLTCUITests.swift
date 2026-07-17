import XCTest

/// #647 — Behavioural integration coverage for Show-mode GO (#645) running
/// together with playback and LTC output. Seeds media + cues (at 1s/3s/6s),
/// enables LTC (in-memory routing via `--ui-test-ltc-enabled`), switches to Show
/// mode, and drives GO from both a stopped and a playing state.
///
/// **The GO assertions are isolated from playback drift.** GO's effect is pinned
/// to the *exact* cue the playhead should land on (`00:00:01` then `00:00:03`),
/// not merely "the readout changed" — otherwise ongoing playback would advance
/// the readout on its own and the test would pass even if GO were a no-op. The
/// first GO fires from a *stopped* state, so nothing but GO can move the readout
/// off `00:00:00`.
///
/// **Scope boundary.** This verifies the *behaviour* layer — GO drives the engine
/// to the right cue and starts/continues playback, and the LTC pipeline is
/// engaged (strip visible). It does NOT assert real LTC audio samples: CI has no
/// audio hardware and LTC routing is in-memory, so sample-level output is
/// untestable and would be flaky. LTC sample/encoding correctness stays covered
/// by the pure LTC unit tests; LTC output is gated on the *playing* state (not
/// `editorMode`), so this is the same output path as playback in any mode.
final class ShowModeGoLTCUITests: OnlyCueUITestCase {

    /// The transport's current-time readout (SMPTE of the playhead position),
    /// tolerant of whether SwiftUI exposes the `Text` via `.label` or `.value`.
    private func readout(_ app: XCUIApplication) -> String {
        let element = app.staticTexts["currentTimeReadout"]
        return element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    /// Polls until the readout's seconds field reaches `prefix` (e.g. `00:00:03`),
    /// which is fps-independent. Returns false on timeout. Preferred over a fixed
    /// sleep so a slow load/seek extends the wait instead of flaking.
    private func waitForReadoutPrefix(_ app: XCUIApplication, _ prefix: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if readout(app).hasPrefix(prefix) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    func test_go_seeksToCuesAndPlays_withLTCStripShown() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6, extraArguments: ["--ui-test-ltc-enabled"])

        // Transport renders for the seeded document.
        XCTAssertTrue(
            app.buttons["transportPlayPause"].waitForExistence(timeout: 15),
            "transport should render for the seeded document"
        )
        // LTC enabled ⇒ the LTC strip is shown.
        let ltcStrip = app.descendants(matching: .any).matching(identifier: "ltcStrip").firstMatch
        XCTAssertTrue(
            ltcStrip.waitForExistence(timeout: 5),
            "the LTC strip should be visible when LTC output is enabled"
        )

        // Enter Show mode — the GO button only renders there.
        app.buttons["editorModeSegment-show"].click()
        let go = app.buttons["transportGo"]
        XCTAssertTrue(go.waitForExistence(timeout: 5), "the GO button should render in Show mode")
        XCTAssertTrue(go.isHittable, "the GO button should be clickable")

        // Playhead starts stopped at zero. GO from a stopped state must seek to
        // the FIRST cue (1s) and start playback. This is fully isolated: nothing
        // but GO can move the readout off 00:00:00, so a no-op GO fails here.
        XCTAssertTrue(readout(app).hasPrefix("00:00:00"), "playhead should start at zero, was \(readout(app))")
        go.click()
        XCTAssertTrue(
            waitForReadoutPrefix(app, "00:00:01", timeout: 5),
            "GO from a stopped state should seek to the first cue (1s); readout was \(readout(app))"
        )

        // GO started playback (stopped → GO → playing) → the readout keeps moving.
        let afterFirstGo = readout(app)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertNotEqual(afterFirstGo, readout(app), "GO from a stopped state should start playback")

        // A second GO while playing (playhead now ~1.x s) seeks to the next cue (3s).
        // Deterministic: any position in (1s, 3s) selects cue@3s.
        go.click()
        XCTAssertTrue(
            waitForReadoutPrefix(app, "00:00:03", timeout: 5),
            "a second GO while playing should seek to the next cue (3s); readout was \(readout(app))"
        )

        // The LTC strip stays visible while walking cues in Show mode.
        XCTAssertTrue(ltcStrip.exists, "the LTC strip should stay visible in Show mode")

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "go-ltc-show-mode"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
