import Foundation

struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference
    var cues: [Cue]
    /// Frames since `00:00:00:00` at the project framerate. Replaces the
    /// schema-v9 project-wide `timecodeSettings.startOffsetFrames` (v10).
    var startTimecodeFrames: Int = 0
    /// Persistent per-clip silence flag for the LTC output channel. Encoder
    /// keeps running; only the LTC channel's samples are zeroed when set.
    var ltcMuted: Bool = false
}

extension MediaItem {

    enum PlayheadStep {
        case previous
        case next
    }

    /// Returns the cue to seek to when stepping the playhead one cue earlier
    /// (`.previous`) or later (`.next`). Strict on `currentTime` — a cue whose
    /// `time` exactly equals `currentTime` is skipped, so repeated step presses
    /// always advance instead of getting stuck. Returns `nil` at the ends of
    /// the cue list (no wrap-around) and on empty cues.
    func cue(steppingFrom currentTime: TimeInterval, direction: PlayheadStep) -> Cue? {
        switch direction {
        case .previous:
            return cues.filter { $0.time < currentTime }.max(by: { $0.time < $1.time })
        case .next:
            return cues.filter { $0.time > currentTime }.min(by: { $0.time < $1.time })
        }
    }

    /// Returns the cue currently "active" at `currentTime` — the cue with the
    /// largest `time <= currentTime`. Use case: the notes overlay shows the
    /// notes of whichever cue the show caller is "in" right now. Returns nil
    /// when the playhead is before the first cue or `cues` is empty; returns
    /// the last cue when the playhead is past it (notes persist until show end).
    /// Inclusive on `currentTime` (`<=`), unlike `cue(steppingFrom:direction:)`
    /// which is strict — these are different semantic queries.
    func activeCue(at currentTime: TimeInterval) -> Cue? {
        cues.filter { $0.time <= currentTime }.max(by: { $0.time < $1.time })
    }
}
