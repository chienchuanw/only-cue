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

    /// #669 — the playheads must stay collinear when the waveform is zoomed in.
    /// Zooming moves the playhead's on-screen x (the ruler stretches), so this
    /// distinguishes a synced LTC strip from the old unzoomed one even at scroll
    /// offset 0.
    func test_ltcAndWaveformPlayheads_stayAligned_whenZoomed() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6, extraArguments: ["--ui-test-ltc-enabled"])
        XCTAssertTrue(app.buttons["transportPlayPause"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "ltcStrip").firstMatch.waitForExistence(timeout: 5)
        )

        // Zoom in a few steps (×1.5 each → ~3.4×). Menu zoom anchors on the
        // viewport centre, so the visible window is around the clip's midpoint.
        for _ in 0..<3 {
            app.menuBars.menuBarItems["View"].click()
            app.menuItems["Zoom In Horizontally"].click()
        }
        // Click the waveform's horizontal centre to seek to the window-centre
        // time, so the playhead lands mid-viewport — visible and (being centred)
        // with its time-label unclamped, so `playheadOverlay.midX` is the line x.
        let preview = app.descendants(matching: .any).matching(identifier: "previewPane").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        Thread.sleep(forTimeInterval: 0.5)

        let waveform = app.descendants(matching: .any).matching(identifier: "playheadOverlay").firstMatch
        let ltc = app.descendants(matching: .any).matching(identifier: "ltcStripPlayhead").firstMatch
        XCTAssertTrue(waveform.waitForExistence(timeout: 5), "the waveform playhead renders")
        XCTAssertTrue(ltc.waitForExistence(timeout: 5), "the LTC strip playhead renders")

        print("ZOOMED WAVEFORM midX: \(waveform.frame.midX)  LTC midX: \(ltc.frame.midX)")
        XCTAssertEqual(
            ltc.frame.midX,
            waveform.frame.midX,
            accuracy: 2.0,
            "the LTC playhead must stay collinear with the waveform playhead when zoomed"
        )

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "ltc-waveform-playhead-alignment-zoomed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
