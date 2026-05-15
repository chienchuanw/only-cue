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
            TimelineView(.animation) { _ in
                let displayedTime = renderedTime()
                PlayheadOverlay(currentTime: displayedTime, duration: duration)
                    .onChange(of: displayedTime) { _, _ in maybeAutoFollow() }
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
            duration: duration
        )
    }

    private func maybeAutoFollow() {
        guard let zoom,
              let applyAutoFollow,
              viewportWidth > 0 else { return }
        let target = zoom.autoFollowAdjustment(
            playheadTime: scrub.state?.scrubTime ?? engine.currentTime,
            duration: duration,
            viewportWidth: viewportWidth,
            currentScrollOffset: scrollOffset
        )
        if let target {
            applyAutoFollow(target, viewportWidth)
        }
    }
}
