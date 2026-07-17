import XCTest
import CoreGraphics
@testable import OnlyCue

final class PreviewLayoutTests: XCTestCase {

    /// Figma 318:1639: under a video the waveform band is ~26% of the preview
    /// height (≈150pt of ≈602pt), with a usable floor.
    func test_videoTimelineHeight_atDesignHeight_isAboutAQuarter() {
        let height = PreviewLayout.videoTimelineHeight(totalHeight: 602, breakdown: false)
        XCTAssertEqual(height, 602 * 0.26, accuracy: 0.5) // ≈156
    }

    /// Breakdown mode gets a taller band so the lanes are legible.
    func test_videoTimelineHeight_breakdown_isTaller() {
        let plain = PreviewLayout.videoTimelineHeight(totalHeight: 602, breakdown: false)
        let breakdown = PreviewLayout.videoTimelineHeight(totalHeight: 602, breakdown: true)
        XCTAssertGreaterThan(breakdown, plain)
    }

    /// A small preview still gives the band a readable floor.
    func test_videoTimelineHeight_smallPreview_usesFloor() {
        let height = PreviewLayout.videoTimelineHeight(totalHeight: 300, breakdown: false)
        XCTAssertEqual(height, 120, accuracy: 0.5)
    }

    /// The band never eats more than half the preview (video must stay dominant).
    func test_videoTimelineHeight_neverExceedsHalf() {
        let height = PreviewLayout.videoTimelineHeight(totalHeight: 200, breakdown: false)
        XCTAssertLessThanOrEqual(height, 100)
    }

    /// #663: the waveform track and the LTC strip ruler must share the same
    /// total horizontal inset so both map time→x across the same x-range and
    /// their playheads stay collinear. The waveform reaches it as the outer
    /// gutter (`trackHorizontalInset`, PreviewPane) + the inner content inset
    /// (`trackContentInset`, WaveformContainer); the LTC strip applies
    /// `playheadTrackInset` directly. Pin all three so a change to one without
    /// the others is caught.
    func test_playheadTrackInset_isOuterGutterPlusContentInset() {
        XCTAssertEqual(PreviewLayout.trackHorizontalInset, DS.Space.lg)
        XCTAssertEqual(PreviewLayout.trackContentInset, DS.Space.sm)
        XCTAssertEqual(
            PreviewLayout.playheadTrackInset,
            PreviewLayout.trackHorizontalInset + PreviewLayout.trackContentInset
        )
    }
}
