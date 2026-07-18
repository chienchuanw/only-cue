import XCTest

/// #675 — during playback (zoom > 1, Auto-Scroll on) the playhead is pinned at
/// ~1/3 of the viewport and the waveform scrolls continuously under it. Once the
/// playhead has passed the 1/3 mark it should hold there, not run to the edge or
/// jump. (Smoothness itself is visual — this pins the fixed 1/3 position.)
final class WaveformFollowUITests: OnlyCueUITestCase {

    /// The waveform track's horizontal inset inside the preview pane
    /// (`PreviewLayout.playheadTrackInset`, #663) — outer gutter + content inset.
    private let trackInset: CGFloat = 24

    func test_playbackFollow_pinsPlayheadNearOneThird_whenZoomed() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        XCTAssertTrue(app.buttons["transportPlayPause"].waitForExistence(timeout: 15))

        // Zoom in deep (≈1.5^8 ≈ 26×) so the 30s clip scrolls fast during
        // playback — the high-zoom regime that used to hang the app by
        // re-rasterizing the wide waveform Canvas every frame (#681). It must
        // now run smoothly and hold the playhead near 1/3.
        for _ in 0..<8 {
            app.menuBars.menuBarItems["View"].click()
            app.menuItems["Zoom In Horizontally"].click()
        }
        // Play long enough for the playhead to pass the 1/3 mark and be held there.
        app.buttons["transportPlayPause"].click()
        Thread.sleep(forTimeInterval: 6.0)
        app.buttons["transportPlayPause"].click() // pause to sample a stable frame

        let preview = app.descendants(matching: .any).matching(identifier: "previewPane").firstMatch
        let playhead = app.descendants(matching: .any).matching(identifier: "playheadOverlay").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(playhead.waitForExistence(timeout: 5))

        let trackLeft = preview.frame.minX + trackInset
        let trackWidth = preview.frame.width - 2 * trackInset
        let fraction = (playhead.frame.midX - trackLeft) / trackWidth
        print("PLAYHEAD fraction: \(fraction)  (target ~0.333)")
        XCTAssertEqual(
            fraction,
            1.0 / 3.0,
            accuracy: 0.12,
            "the playhead should be held near 1/3 of the viewport during playback"
        )

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "waveform-follow-playhead-at-one-third"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
