import XCTest

/// #663 — the LTC strip ruler shares the waveform's horizontal inset
/// (`PreviewLayout.trackHorizontalInset`, unit-pinned), so the LTC playhead is
/// collinear with the waveform playhead. Both map time→x via the same
/// `CueMarkersGeometry.position`, so equal insets ⇒ equal x. This confirms both
/// playheads render at a fixed mid-track position and captures the visual result;
/// pixel collinearity is a layout property, screenshot-verified.
final class LTCStripAlignmentUITests: OnlyCueUITestCase {

    func test_ltcAndWaveformPlayheads_renderAligned() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6, extraArguments: ["--ui-test-ltc-enabled"])
        XCTAssertTrue(app.buttons["transportPlayPause"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "ltcStrip").firstMatch.waitForExistence(timeout: 5),
            "the LTC strip is visible when LTC is enabled"
        )

        // Step to a mid-list cue (6s of 30s) so both playheads sit clearly inside
        // the track, then let the views settle.
        app.buttons["transportNextCue"].click()
        app.buttons["transportNextCue"].click()
        app.buttons["transportNextCue"].click()
        Thread.sleep(forTimeInterval: 0.5)

        let waveform = app.descendants(matching: .any).matching(identifier: "playheadOverlay").firstMatch
        let ltc = app.descendants(matching: .any).matching(identifier: "ltcStripPlayhead").firstMatch
        XCTAssertTrue(waveform.waitForExistence(timeout: 5), "the waveform playhead renders")
        XCTAssertTrue(ltc.waitForExistence(timeout: 5), "the LTC strip playhead renders")

        // At this mid-track cue the waveform's time-label is centered on its
        // playhead line, so `playheadOverlay.midX` is the waveform playhead's x;
        // `ltcStripPlayhead` is the 1pt LTC line. Aligned tracks ⇒ equal x.
        print("WAVEFORM midX: \(waveform.frame.midX)  LTC midX: \(ltc.frame.midX)")
        XCTAssertEqual(
            ltc.frame.midX,
            waveform.frame.midX,
            accuracy: 2.0,
            "the LTC playhead must be collinear with the waveform playhead"
        )

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "ltc-waveform-playhead-alignment"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
