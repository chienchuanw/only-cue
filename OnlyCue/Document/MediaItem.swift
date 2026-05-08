import Foundation

struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference
    var cues: [Cue]
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
}
