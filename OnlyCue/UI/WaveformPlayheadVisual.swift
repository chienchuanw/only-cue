import AppKit
import QuartzCore
import SwiftUI

/// Visual-only playhead: the vertical line + time-label badge, ticking
/// each frame off `TimelineView(.animation)`. Hit-testing is disabled
/// on the root so a press at the playhead's x-position reaches the
/// markers / seek surface below; only `WaveformSeekSurface` carries the
/// click-to-seek gesture.
///
/// Sits ABOVE `CueMarkersOverlay` in `WaveformContainer`'s `ZStack` so
/// the playhead line is never visually occluded by a selected (wider)
/// cue-marker cap.
struct WaveformPlayheadVisual: View {

    let engine: PlayerEngine
    let duration: TimeInterval
    @Binding var scrub: ScrubController
    var zoom: WaveformZoomController?
    var viewportWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var applyAutoFollow: ((CGFloat, CGFloat) -> Void)?

    var body: some View {
        GeometryReader { _ in
            TimelineView(.animation) { context in
                PlayheadOverlay(currentTime: renderedTime(), duration: duration)
                    // Drive auto-follow off the frame date, NOT the interpolated
                    // time: the latter uses `CACurrentMediaTime()` and so changes
                    // on every re-render, which — since setting the scroll offset
                    // re-renders — would spin an infinite render loop (#675). The
                    // frame date is stable across non-frame re-renders, so this
                    // fires once per frame.
                    .onChange(of: context.date) { _, _ in maybeAutoFollow(displayedTime: renderedTime()) }
            }
        }
        .allowsHitTesting(false)
    }

    private func renderedTime() -> TimeInterval {
        if let scrubTime = scrub.state?.scrubTime { return scrubTime }
        return PlayheadInterpolator.renderedTime(
            observedTime: engine.currentTime,
            observedAt: engine.currentTimeObservedAt,
            now: CACurrentMediaTime(),
            rate: Double(engine.rate),
            duration: duration,
            outputLatency: engine.outputLatency
        )
    }

    /// Continuously pins the playhead at `followFraction` of the viewport while
    /// playing (#675): every frame, set the scroll offset so `displayedTime`'s
    /// content-x lands at the fixed follow position. Only while actually playing,
    /// zoomed in, and the Auto-Scroll preference is on.
    private func maybeAutoFollow(displayedTime: TimeInterval) {
        guard let zoom, let applyAutoFollow, viewportWidth > 0,
              zoom.followsPlayhead, engine.isPlaying, zoom.zoom > 1, duration > 0 else { return }
        let contentWidth = zoom.contentWidth(viewportWidth: viewportWidth)
        let playheadContentX = CueMarkersGeometry.position(
            forTime: displayedTime,
            width: contentWidth,
            duration: duration
        )
        let target = zoom.followScrollOffset(
            playheadContentX: playheadContentX,
            viewportWidth: viewportWidth,
            contentWidth: contentWidth
        )
        applyAutoFollow(target, viewportWidth)
    }
}
