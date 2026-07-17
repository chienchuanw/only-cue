import XCTest

/// #647 — Behavioural integration coverage for Show-mode GO (#645) running
/// together with playback and LTC output. Seeds media + cues, enables LTC
/// (in-memory routing via `--ui-test-ltc-enabled`), switches to Show mode, and
/// exercises play + GO: the playhead advances, GO seeks to a cue, playback
/// continues, and the LTC strip stays visible throughout.
///
/// **Scope boundary.** This verifies the *behaviour* layer — that GO drives the
/// engine and the LTC pipeline is engaged (strip visible) while playing. It does
/// NOT assert real LTC audio samples: CI has no audio hardware and LTC routing
/// is in-memory here, so sample-level output is untestable and would be flaky.
/// LTC sample/encoding correctness is covered by the pure LTC unit tests, and
/// LTC output is gated on the *playing* state (not `editorMode`), so this is the
/// same output path as playback in any mode.
final class ShowModeGoLTCUITests: OnlyCueUITestCase {

    /// The transport's current-time readout string, tolerant of whether SwiftUI
    /// exposes the `Text` via `.label` or `.value`.
    private func readout(_ app: XCUIApplication) -> String {
        let element = app.staticTexts["currentTimeReadout"]
        return element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    func test_go_advancesCuesWhilePlaying_withLTCStripShown() throws {
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

        // Play → the playhead advances.
        let readoutAtStart = readout(app)
        app.buttons["transportPlayPause"].click()
        Thread.sleep(forTimeInterval: 1.0)
        let readoutWhilePlaying = readout(app)
        XCTAssertNotEqual(readoutAtStart, readoutWhilePlaying, "the playhead should advance while playing")

        // GO → seeks to the next cue (the readout jumps).
        go.click()
        Thread.sleep(forTimeInterval: 0.4)
        let readoutAfterGo = readout(app)
        XCTAssertNotEqual(readoutWhilePlaying, readoutAfterGo, "GO should seek to the next cue")

        // Playback continues after GO → the playhead keeps advancing.
        Thread.sleep(forTimeInterval: 0.8)
        let readoutStillPlaying = readout(app)
        XCTAssertNotEqual(readoutAfterGo, readoutStillPlaying, "playback should continue after GO")

        // The LTC strip stays visible while playing in Show mode.
        XCTAssertTrue(ltcStrip.exists, "the LTC strip should stay visible while playing in Show mode")

        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "go-ltc-show-mode"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
