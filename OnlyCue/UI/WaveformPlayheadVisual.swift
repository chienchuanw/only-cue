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
    /// When set (during follow-scroll), the playhead is drawn at this time — the
    /// SAME per-frame sample that computes the scroll offset — instead of running
    /// its own `TimelineView`. That keeps the line and the offset on one time
    /// basis so the playhead can't jitter against the flowing waveform at high
    /// zoom (#681). nil (not following) → self-animate off `renderedTime()`.
    var overrideTime: TimeInterval?

    var body: some View {
        GeometryReader { _ in
            if let overrideTime {
                PlayheadOverlay(currentTime: overrideTime, duration: duration)
            } else {
                TimelineView(.animation) { _ in
                    PlayheadOverlay(currentTime: renderedTime(), duration: duration)
                }
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
}
