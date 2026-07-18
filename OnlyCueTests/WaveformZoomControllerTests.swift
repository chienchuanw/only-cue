import XCTest
@testable import OnlyCue

@MainActor
final class WaveformZoomControllerTests: XCTestCase {

    func test_initialState_isOneXAndFollows() {
        let zoom = WaveformZoomController()
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
        XCTAssertTrue(zoom.followsPlayhead)
    }

    func test_snappedScrollOffset_scalesWithLeadingAnchorZoomAndViewport() {
        // #669: the anchor-snapped offset the LTC strip mirrors. It must scale
        // with the viewport width (a window resize) so the strip doesn't desync.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        // contentWidth = 100×4 = 400; anchorCount 10 → pxPerAnchor 40; anchor 3 → 120.
        XCTAssertEqual(zoom.snappedScrollOffset(leadingAnchor: 3, anchorCount: 10, viewportWidth: 100), 120)
        // Resize wider: contentWidth = 200×4 = 800; pxPerAnchor 80; anchor 3 → 240.
        XCTAssertEqual(zoom.snappedScrollOffset(leadingAnchor: 3, anchorCount: 10, viewportWidth: 200), 240)
        // Zero anchors → zero (no divide-by-zero).
        XCTAssertEqual(zoom.snappedScrollOffset(leadingAnchor: 3, anchorCount: 0, viewportWidth: 100), 0)
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

    // MARK: - Auto-follow

    func test_autoFollow_returnsNil_whenNotFollowing() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        zoom.followsPlayhead = false
        let result = zoom.autoFollowAdjustment(
            playheadTime: 90,
            duration: 100,
            viewportWidth: 100,
            currentScrollOffset: 0
        )
        XCTAssertNil(result)
    }

    func test_autoFollow_returnsNil_atOneX() {
        let zoom = WaveformZoomController()
        let result = zoom.autoFollowAdjustment(
            playheadTime: 90,
            duration: 100,
            viewportWidth: 100,
            currentScrollOffset: 0
        )
        XCTAssertNil(result)
    }

    func test_autoFollow_returnsNil_whenPlayheadBelowTrailingThreshold() {
        // zoom=2, viewport=100, content=200. Playhead t=70/100 → contentX=140.
        // viewportX = 140 - scroll(0) = 140 > 80? YES at scroll=0. But scroll=70 makes viewportX=70 < 80.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(2, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.autoFollowAdjustment(
            playheadTime: 70,
            duration: 100,
            viewportWidth: 100,
            currentScrollOffset: 70
        )
        XCTAssertNil(result)
    }

    func test_autoFollow_scrollsToLeadingFraction_whenPlayheadPastTrailing() {
        // zoom=2, viewport=100, content=200. Playhead t=90 → contentX=180. scroll=0 → viewportX=180 (off-screen!).
        // Trigger fires. Target: contentX - viewport × 0.2 = 180 - 20 = 160.
        // Clamp to [0, content - viewport] = [0, 100] → 100.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(2, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.autoFollowAdjustment(
            playheadTime: 90,
            duration: 100,
            viewportWidth: 100,
            currentScrollOffset: 0
        )
        XCTAssertEqual(result ?? .nan, 100, accuracy: 0.001)
    }

    func test_autoFollow_returnsTargetThatPlacesPlayheadAtLeadingFraction() {
        // zoom=4, viewport=100, content=400. Playhead t=50 → contentX=200. scroll=80 → viewportX=120 > 80.
        // Target: 200 - 20 = 180.
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.autoFollowAdjustment(
            playheadTime: 50,
            duration: 100,
            viewportWidth: 100,
            currentScrollOffset: 80
        )
        XCTAssertEqual(result ?? .nan, 180, accuracy: 0.001)
    }

    func test_autoFollow_returnsNil_whenZeroDuration() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(4, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        let result = zoom.autoFollowAdjustment(
            playheadTime: 1,
            duration: 0,
            viewportWidth: 100,
            currentScrollOffset: 0
        )
        XCTAssertNil(result)
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
