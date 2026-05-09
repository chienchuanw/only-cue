import Foundation

extension Sequence where Element == Cue {
    /// Returns the first cue with `time` in the half-open-then-closed interval
    /// `(previousTime, newTime]`. Strict `>` on `previousTime` avoids re-detecting
    /// a cue we just paused at when the user resumes; inclusive `<=` on `newTime`
    /// ensures a cue exactly at the new playhead triggers (auto-pause fires *at*
    /// the cue, not after it). Returns nil for backward motion or when no cue
    /// lands in the range — both are no-ops for pause-at-each-cue mode.
    func cueCrossed(
        movingFrom previousTime: TimeInterval,
        to newTime: TimeInterval
    ) -> Cue? {
        guard newTime > previousTime else { return nil }
        return first { $0.time > previousTime && $0.time <= newTime }
    }
}
