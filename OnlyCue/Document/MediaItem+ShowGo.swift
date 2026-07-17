import Foundation

extension MediaItem {

    /// The outcome of a Show-mode **GO** (#645): walk to the next cue and play,
    /// or do nothing.
    enum GoDecision: Equatable {
        /// Seek to this time and ensure playback is running.
        case seekAndPlay(TimeInterval)
        /// No cue after the playhead (past the last cue, or no cues) — do nothing.
        case noOp
    }

    /// The GO decision for the current playhead: the next cue strictly after
    /// `currentTime` (reusing `cue(steppingFrom:.next)`) means seek-and-play;
    /// none means no-op.
    func showGoDecision(from currentTime: TimeInterval) -> GoDecision {
        guard let next = cue(steppingFrom: currentTime, direction: .next) else { return .noOp }
        return .seekAndPlay(next.time)
    }
}
