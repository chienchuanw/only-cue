import Foundation

@Observable
@MainActor
final class WaveformZoomController {

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 16
    static let zoomStep: CGFloat = 1.5
    static let followLeadingFraction: CGFloat = 0.2
    static let followTrailingFraction: CGFloat = 0.8

    private(set) var zoom: CGFloat = 1
    var followsPlayhead: Bool = true

    func setZoom(
        _ next: CGFloat,
        anchorFraction: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        let clampedZoom = min(max(next, Self.minZoom), Self.maxZoom)
        guard viewportWidth > 0 else {
            zoom = clampedZoom
            return
        }
        let oldContentWidth = viewportWidth * zoom
        let anchorContentX = scrollOffset + anchorFraction * viewportWidth
        let timeFraction = oldContentWidth > 0 ? anchorContentX / oldContentWidth : 0

        let newContentWidth = viewportWidth * clampedZoom
        let newAnchorContentX = timeFraction * newContentWidth
        let newOffset = newAnchorContentX - anchorFraction * viewportWidth
        let maxOffset = max(newContentWidth - viewportWidth, 0)
        scrollOffset = min(max(newOffset, 0), maxOffset)
        zoom = clampedZoom
    }

    func zoomIn(
        anchorFraction: CGFloat = 0.5,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        setZoom(
            zoom * Self.zoomStep,
            anchorFraction: anchorFraction,
            viewportWidth: viewportWidth,
            scrollOffset: &scrollOffset
        )
    }

    func zoomOut(
        anchorFraction: CGFloat = 0.5,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        setZoom(
            zoom / Self.zoomStep,
            anchorFraction: anchorFraction,
            viewportWidth: viewportWidth,
            scrollOffset: &scrollOffset
        )
    }

    func reset(scrollOffset: inout CGFloat) {
        if zoom == 1 && followsPlayhead && scrollOffset == 0 { return }
        zoom = 1
        followsPlayhead = true
        scrollOffset = 0
    }

    /// Returns a new scroll offset that places the playhead at the leading fraction
    /// of the viewport, when auto-follow is engaged and the playhead has crossed
    /// the trailing threshold. Returns nil otherwise.
    func autoFollowAdjustment(
        playheadTime: TimeInterval,
        duration: TimeInterval,
        viewportWidth: CGFloat,
        currentScrollOffset: CGFloat
    ) -> CGFloat? {
        guard followsPlayhead, zoom > 1, duration > 0, viewportWidth > 0 else { return nil }
        let contentWidth = viewportWidth * zoom
        let playheadContentX = CueMarkersGeometry.position(
            forTime: playheadTime,
            width: contentWidth,
            duration: duration
        )
        let playheadViewportX = playheadContentX - currentScrollOffset
        let trailingThreshold = viewportWidth * Self.followTrailingFraction
        guard playheadViewportX > trailingThreshold else { return nil }
        let targetOffset = playheadContentX - viewportWidth * Self.followLeadingFraction
        let maxOffset = max(contentWidth - viewportWidth, 0)
        return min(max(targetOffset, 0), maxOffset)
    }
}
