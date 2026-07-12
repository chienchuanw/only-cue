import Foundation

/// Computes the playhead time to *render* between periodic time-observer ticks.
/// The observer remains the source of truth; this slides the visible playhead
/// forward by `rate × elapsedWallClock` so it glides at the display's refresh
/// rate instead of stepping. Snaps back to the observed value on each tick.
enum PlayheadInterpolator {

    /// `outputLatency` shifts the rendered playhead back by the audio output
    /// pipeline's latency so it tracks what is *audible now* rather than what
    /// the player has already queued (#611). Applied only while playing —
    /// paused there is nothing in flight, and seeks/edits must stay exact.
    static func renderedTime(
        observedTime: TimeInterval,
        observedAt: TimeInterval,
        now: TimeInterval,
        rate: Double,
        duration: TimeInterval,
        outputLatency: TimeInterval = 0
    ) -> TimeInterval {
        guard rate != 0 else { return clamp(observedTime, duration) }
        let elapsed = max(now - observedAt, 0)
        return clamp(observedTime + rate * elapsed - outputLatency, duration)
    }

    private static func clamp(_ time: TimeInterval, _ duration: TimeInterval) -> TimeInterval {
        min(max(time, 0), max(duration, 0))
    }
}
