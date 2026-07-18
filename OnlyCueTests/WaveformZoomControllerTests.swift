import XCTest
@testable import OnlyCue

@MainActor
final class WaveformZoomControllerTests: XCTestCase {

    func test_initialState_isOneXAndFollows() {
        let zoom = WaveformZoomController()
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
        XCTAssertTrue(zoom.followsPlayhead)
    }

    func test_renderedScrollOffset_equalsScrollOffset() {
        // #675: continuous rendering ⇒ the offset the LTC strip mirrors is just
        // the (continuous) scroll offset — no anchor snapping.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        zoom.scrollOffset = 137
        XCTAssertEqual(zoom.renderedScrollOffset, 137)
    }

    func test_followScrollOffset_placesPlayheadAtFollowFraction() {
        // #675: continuous auto-follow keeps the playhead at ~1/3 of the viewport.
        // viewport 100, follow fraction 1/3 ⇒ target = playheadX − 33.33.
        let zoom = WaveformZoomController()
        let target = zoom.followScrollOffset(playheadContentX: 300, viewportWidth: 100, contentWidth: 400)
        XCTAssertEqual(target, 300 - 100 * WaveformZoomController.followFraction, accuracy: 0.001)
    }

    func test_followScrollOffset_clampsAtStart() {
        // Near the start the target goes negative → clamp to 0 (playhead sits left of 1/3).
        let zoom = WaveformZoomController()
        XCTAssertEqual(zoom.followScrollOffset(playheadContentX: 10, viewportWidth: 100, contentWidth: 400), 0)
    }

    func test_followScrollOffset_clampsAtEnd() {
        // Near the end the target exceeds maxOffset (contentWidth − viewport) → clamp.
        let zoom = WaveformZoomController()
        XCTAssertEqual(zoom.followScrollOffset(playheadContentX: 395, viewportWidth: 100, contentWidth: 400), 300)
    }

    // MARK: - Pixel-snapped follow offset (#677: shimmer + pause jump)

    func test_snappedFollowScrollOffset_alignsToDevicePixels() {
        // #677A: the render offset must land on whole device pixels so the dense
        // envelope translates without sub-pixel resampling (shimmer). With
        // displayScale 2, the offset snaps to the nearest 0.5 pt.
        // viewport 100, follow 1/3 ⇒ raw target = 137 − 33.333… = 103.666…
        // → nearest 0.5 pt = 103.5.
        let zoom = WaveformZoomController()
        let snapped = zoom.snappedFollowScrollOffset(
            playheadContentX: 137, viewportWidth: 100, contentWidth: 400, displayScale: 2
        )
        XCTAssertEqual(snapped, 103.5, accuracy: 0.0001)
    }

    func test_snappedFollowScrollOffset_clampsToContentBounds() {
        // Snapping never pushes the offset outside [0, contentWidth − viewport].
        let zoom = WaveformZoomController()
        XCTAssertEqual(
            zoom.snappedFollowScrollOffset(
                playheadContentX: 10, viewportWidth: 100, contentWidth: 400, displayScale: 2
            ),
            0
        )
        XCTAssertEqual(
            zoom.snappedFollowScrollOffset(
                playheadContentX: 395, viewportWidth: 100, contentWidth: 400, displayScale: 2
            ),
            300
        )
    }

    func test_snappedFollowScrollOffset_nonPositiveScale_fallsBackToUnsnapped() {
        // displayScale ≤ 0 (unknown scale) ⇒ the plain clamped follow offset.
        let zoom = WaveformZoomController()
        let raw = zoom.followScrollOffset(playheadContentX: 137, viewportWidth: 100, contentWidth: 400)
        XCTAssertEqual(
            zoom.snappedFollowScrollOffset(
                playheadContentX: 137, viewportWidth: 100, contentWidth: 400, displayScale: 0
            ),
            raw,
            accuracy: 0.0001
        )
    }

    func test_snappedFollowOffset_pinsPlayheadAtFollowFraction_withinOnePixel() {
        // #677B: the invariant that makes the pause jump impossible — because the
        // offset and the playhead come from the SAME time sample, the on-screen
        // playhead (playheadContentX − snappedOffset) sits at viewport × 1/3
        // across the whole follow region, within one device pixel of snapping.
        let zoom = WaveformZoomController()
        let viewport: CGFloat = 100
        let contentWidth: CGFloat = 640 // 6.4× — deep enough to stay off both clamps
        let displayScale: CGFloat = 2
        let expected = viewport * WaveformZoomController.followFraction
        // Sweep content-x through the clamp-free interior.
        for x in stride(from: expected + 1, through: contentWidth - (viewport - expected) - 1, by: 3.7) {
            let offset = zoom.snappedFollowScrollOffset(
                playheadContentX: x, viewportWidth: viewport, contentWidth: contentWidth, displayScale: displayScale
            )
            let onScreen = x - offset
            XCTAssertEqual(onScreen, expected, accuracy: 1.0 / displayScale,
                           "playhead should stay at 1/3 within one device pixel at x=\(x)")
        }
    }

    func test_contentWidth_scalesWithZoom_neverBelowViewport() {
        // #669: the shared helper the waveform and LTC strip both use to size
        // the zoomed content so their playhead tracks stay identical.
        let zoom = WaveformZoomController()
        XCTAssertEqual(zoom.contentWidth(viewportWidth: 100), 100) // 1× = viewport
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(zoom.contentWidth(viewportWidth: 100), 400) // 4× = 4 × viewport
    }

    func test_setZoom_clampsBelowMin() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(0.5, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(zoom.zoom, WaveformZoomController.minZoom, accuracy: 0.0001)
    }

    func test_setZoom_clampsAboveMax() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(99, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(zoom.zoom, WaveformZoomController.maxZoom, accuracy: 0.0001)
    }

    func test_maxZoom_allowsDeepZoom() {
        // Raised 16→64 so long tracks can be zoomed in far enough for precise
        // cue placement (grilling decision).
        XCTAssertEqual(WaveformZoomController.maxZoom, 64)
    }

    func test_zoomIn_reachesMaxZoom() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        for _ in 0..<20 { // more than enough ×1.5 steps to saturate
            zoom.zoomIn(anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        }
        XCTAssertEqual(zoom.zoom, 64, accuracy: 0.0001)
    }

    func test_setZoom_anchoredAtCenter_keepsCenterTimeUnderCenter() {
        // viewport=100, zoom 1→2, anchor=0.5, scroll=0.
        // Time under center is at content-x=50 in content-width=100; fraction=0.5.
        // After zoom: content-width=200, fraction=0.5 → content-x=100.
        // To keep that under center (viewport-x=50): scrollOffset = 100 - 50 = 50.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(2, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(offset, 50, accuracy: 0.001)
    }

    func test_setZoom_anchoredAtLeadingEdge_keepsScrollAtZero() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func test_setZoom_anchoredAtTrailingEdge_clampsToMaxScroll() {
        // anchor=1, zoom 1→4: fraction=1 → target content-x=400 → unclamped scroll=400-100=300.
        // contentWidth=400, viewport=100, maxScroll=300. So clamp leaves 300.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 1, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(offset, 300, accuracy: 0.001)
    }

    func test_setZoom_zoomingOut_clampsScrollToZero() {
        // Start zoomed to 4× with offset=200, then zoom back to 1×.
        // contentWidth=100; scroll must clamp to 0.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        // Now zoom out fully:
        zoom.setZoom(1, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func test_zoomIn_thenZoomOut_returnsToOriginalZoom() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.zoomIn(anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        zoom.zoomOut(anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
    }

    func test_reset_restoresOneXAndZeroOffset() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(8, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        zoom.reset(scrollOffset: &offset)
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    /// `followsPlayhead` is the persisted "Auto-Scroll Waveform" user
    /// preference (issue #532), not transient view state. A media load resets
    /// zoom + scroll offset but must NOT flip the user's auto-scroll choice
    /// back on — otherwise disabling it would silently re-enable on the next
    /// clip.
    func test_reset_preservesFollowsPlayheadPreference() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(8, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        zoom.followsPlayhead = false
        zoom.reset(scrollOffset: &offset)
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
        XCTAssertEqual(offset, 0, accuracy: 0.001)
        XCTAssertFalse(zoom.followsPlayhead, "reset must preserve the auto-scroll preference")
    }

    // MARK: - Scroll-to-reveal (selected cue, #536)

    func test_scrollToReveal_returnsNil_atOneX() {
        let zoom = WaveformZoomController()
        let result = zoom.scrollToRevealAdjustment(
            targetTime: 50, duration: 100, viewportWidth: 100, currentScrollOffset: 0
        )
        XCTAssertNil(result)
    }

    func test_scrollToReveal_returnsNil_whenTargetAlreadyVisible() {
        // zoom=2, viewport=100, content=200. target t=40 → contentX=80, scroll=0 → visible [0,100].
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(2, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.scrollToRevealAdjustment(
            targetTime: 40, duration: 100, viewportWidth: 100, currentScrollOffset: 0
        )
        XCTAssertNil(result)
    }

    func test_scrollToReveal_centersTarget_whenOffScreenRight() {
        // zoom=4, viewport=100, content=400. target t=50 → contentX=200, visible [0,100] → off-screen.
        // Centered: 200 - 50 = 150. maxOffset = 300 → 150.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.scrollToRevealAdjustment(
            targetTime: 50, duration: 100, viewportWidth: 100, currentScrollOffset: 0
        )
        XCTAssertEqual(result ?? .nan, 150, accuracy: 0.001)
    }

    func test_scrollToReveal_clampsAtStart() {
        // zoom=4, viewport=100, content=400. target t=5 → contentX=20. Centered = 20-50 = -30 → clamp 0.
        // Need it off-screen: scroll=200 → visible [200,300], contentX 20 not visible.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.scrollToRevealAdjustment(
            targetTime: 5, duration: 100, viewportWidth: 100, currentScrollOffset: 200
        )
        XCTAssertEqual(result ?? .nan, 0, accuracy: 0.001)
    }

    func test_scrollToReveal_clampsAtEnd() {
        // zoom=4, viewport=100, content=400. target t=98 → contentX=392. Centered = 392-50 = 342 → clamp maxOffset 300.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.scrollToRevealAdjustment(
            targetTime: 98, duration: 100, viewportWidth: 100, currentScrollOffset: 0
        )
        XCTAssertEqual(result ?? .nan, 300, accuracy: 0.001)
    }

    func test_scrollToReveal_returnsNil_whenZeroDuration() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.scrollToRevealAdjustment(
            targetTime: 1, duration: 0, viewportWidth: 100, currentScrollOffset: 0
        )
        XCTAssertNil(result)
    }
}
