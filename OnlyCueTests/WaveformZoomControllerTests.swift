import XCTest
@testable import OnlyCue

@MainActor
final class WaveformZoomControllerTests: XCTestCase {

    func test_initialState_isOneXAndFollows() {
        let zoom = WaveformZoomController()
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
        XCTAssertTrue(zoom.followsPlayhead)
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

    func test_reset_restoresOneXFollowAndZeroOffset() {
        let zoom = WaveformZoomController()
        var offset: CGFloat = 0
        zoom.setZoom(8, anchorFraction: 0.5, viewportWidth: 100, scrollOffset: &offset)
        zoom.followsPlayhead = false
        zoom.reset(scrollOffset: &offset)
        XCTAssertEqual(zoom.zoom, 1, accuracy: 0.0001)
        XCTAssertTrue(zoom.followsPlayhead)
        XCTAssertEqual(offset, 0, accuracy: 0.001)
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
}
