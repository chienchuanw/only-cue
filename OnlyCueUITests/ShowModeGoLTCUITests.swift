import XCTest

/// #647 — Behavioural integration coverage for Show-mode GO (#645) running
/// together with playback and LTC output. Seeds media + cues (at 2s/12s/24s),
/// enables LTC (in-memory routing via `--ui-test-ltc-enabled`), switches to Show
/// mode, and drives GO from both a stopped and a playing state.
///
/// **The GO assertions are isolated from playback drift.** The first GO fires
/// from a *stopped* state, so nothing but GO can move the readout off
/// `00:00:00`, and it is pinned to the exact cue (`00:00:02`).
///
/// The second GO cannot be pinned that way (#822). It fires while playback is
/// running, so the cue it lands on depends on where the playhead is *when the
/// click actually lands* — and XCUITest's click/query latency between "the test
/// reads the position" and "the app receives the click" is unbounded. Pinning it
/// to `00:00:03` assumed that gap stayed under ~1.4s; on a loaded runner it does
/// not, the playhead crosses 3s first, GO correctly seeks to the 6s cue, and the
/// test failed while the app was behaving exactly as specified.
///
/// Hence the wider seed. At 1s/3s/6s the entire runway was 5s — shorter than two
/// XCUITest interactions here — so the playhead could reach the *last* cue before
/// a GO landed, at which point GO is a no-op by spec and there is nothing left to
/// observe. 2s/12s/24s puts ten seconds between cues, well clear of the latency.
///
/// So the second GO is verified by **measuring the discontinuity** instead: the
/// playhead position and the wall clock are sampled either side of one click. A
/// GO that seeks makes the playhead outrun real time; a GO that no-ops leaves
/// the two advancing together, however slow the runner is. Latency lands in both
/// quantities and cancels, so this is race-free rather than merely race-widened.
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

    /// The seeded cue times (`three-cues-2-12-24`), and the framerate the readout
    /// is rendered at. No seed overrides `ProjectTimecodeSettings.default`, so the
    /// `FF` field is thirtieths of a second and the readout parses exactly.
    private static let seededCueTimes: [Double] = [2, 12, 24]
    private static let seedFPS: Double = 30

    /// `HH:MM:SS:FF` → seconds. `nil` if the readout is not yet rendered.
    private func readoutSeconds(_ app: XCUIApplication) -> Double? {
        let parts = readout(app).split(separator: ":")
        guard parts.count == 4,
              let hours = Double(parts[0]), let minutes = Double(parts[1]),
              let seconds = Double(parts[2]), let frames = Double(parts[3])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds + frames / Self.seedFPS
    }

    /// How far one GO moved the playhead beyond what playback alone could account
    /// for — i.e. the distance it *seeked*.
    private struct Probe {
        let from: Double
        let to: Double
        /// Pessimistic bound (widest possible elapsed time). Assert on this: it
        /// cannot be inflated by a slow accessibility query.
        let leastSeek: Double
        /// Optimistic bound, carried for diagnostics only.
        let mostSeek: Double

        var description: String {
            String(format: "%.2f→%.2f seek %.2f…%.2f", from, to, leastSeek, mostSeek)
        }
    }

    /// Fires GO once and measures the seek distance across it.
    ///
    /// GO is fired by its keybinding (`Keymap.go` = Return) rather than by clicking
    /// the button. Not a style choice: `XCUIElement.click()` re-resolves the query
    /// and hit-tests the window, which measured ~2.4s here — long enough for
    /// playback to carry the playhead most of the way from the first seeded cue to
    /// the last *before the click even lands*, leaving a real seek distance of
    /// ~0.1s that no measurement can separate from noise. A synthesised keystroke
    /// skips that work. The button's own rendering and hittability are still
    /// asserted, and the first GO still goes through it.
    ///
    /// A readout value is only timestamped to within the accessibility query that
    /// produced it, so the elapsed wall time between two samples is bracketed
    /// rather than known. Both ends are returned: the assertion uses the
    /// pessimistic one, so a slow query can never manufacture an apparent seek.
    private func goSeekDistance(_ app: XCUIApplication) -> Probe? {
        let beforeStart = Date()
        guard let before = readoutSeconds(app) else { return nil }
        let beforeEnd = Date()
        app.typeKey(.return, modifierFlags: [])
        let afterStart = Date()
        guard let after = readoutSeconds(app) else { return nil }
        let afterEnd = Date()
        let advanced = after - before
        return Probe(
            from: before,
            to: after,
            leastSeek: advanced - afterEnd.timeIntervalSince(beforeStart),
            mostSeek: advanced - max(0, afterStart.timeIntervalSince(beforeEnd))
        )
    }

    func test_go_seeksToCuesAndPlays_withLTCStripShown() throws {
        let app = launchApp(seed: .threeCuesAt2And12And24, extraArguments: ["--ui-test-ltc-enabled"])

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
        // the FIRST cue (2s) and start playback. This is fully isolated: nothing
        // but GO can move the readout off 00:00:00, so a no-op GO fails here, and
        // it stays pinned to the exact cue because a stopped playhead cannot drift
        // while the click is in flight.
        XCTAssertTrue(readout(app).hasPrefix("00:00:00"), "playhead should start at zero, was \(readout(app))")
        go.click()
        XCTAssertTrue(
            waitForReadoutPrefix(app, "00:00:02", timeout: 5),
            "GO from a stopped state should seek to the first cue (2s); readout was \(readout(app))"
        )

        // GO started playback (stopped → GO → playing) → the readout keeps moving.
        let afterFirstGo = readout(app)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertNotEqual(afterFirstGo, readout(app), "GO from a stopped state should start playback")

        // A second GO, now from a *playing* state. Which cue it lands on is not
        // predictable from here (#822) — what must hold is that it seeks at all.
        //
        // A single probe can read ~0 through no fault of the app: if the click
        // lands just shy of a cue, the true seek distance really is negligible.
        // Retrying is self-correcting, because every GO parks the playhead *on* a
        // cue, which is the position furthest from the next one.
        let minimumSeek = 0.5
        var probes: [Probe] = []
        var seeked = false
        var stoppedPastLastCue = false
        for _ in 0..<3 {
            // Past the last seeded cue, GO is a no-op *by spec* (`showGoDecision`
            // returns `.noOp`), so probing further would be testing the wrong thing.
            guard let lastCue = Self.seededCueTimes.last,
                  let position = readoutSeconds(app), position < lastCue
            else { stoppedPastLastCue = true; break }
            guard let probe = goSeekDistance(app) else { continue }
            probes.append(probe)
            if probe.leastSeek > minimumSeek { seeked = true; break }
        }
        XCTAssertTrue(
            seeked,
            "a second GO while playing should seek forward to a cue, but the playhead never "
            + "outran the wall clock by more than \(minimumSeek)s"
            + (stoppedPastLastCue ? " (ran out of cues — the playhead reached the last cue first)" : "")
            + ". Probes: [\(probes.map(\.description).joined(separator: ", "))]"
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
