import Foundation

/// Computes the playhead time to *render* between periodic time-observer ticks.
/// The observer remains the source of truth; this slides the visible playhead
/// forward by `rate × elapsedWallClock` so it glides at the display's refresh
/// rate instead of stepping. Snaps back to the observed value on each tick.
enum PlayheadInterpolator {

    static func renderedTime(
        observedTime: TimeInterval,
        observedAt: TimeInterval,
        now: TimeInterval,
        rate: Double,
        duration: TimeInterval
    ) -> TimeInterval {
        guard rate != 0 else { return clamp(observedTime, duration) }
        let elapsed = max(now - observedAt, 0)
        return clamp(observedTime + rate * elapsed, duration)
    }

    private static func clamp(_ time: TimeInterval, _ duration: TimeInterval) -> TimeInterval {
        min(max(time, 0), max(duration, 0))
    }
}
