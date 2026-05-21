import Foundation

/// The editing mode of one document window — which surface accepts edits.
/// Per-window working state (held in `@SceneStorage`), not document data.
enum EditorMode: String, CaseIterable, Codable {
    case cue
    case lyric
    case show

    /// Human-readable label for the switcher and menu.
    var title: String {
        switch self {
        case .cue: return "Cue"
        case .lyric: return "Lyric"
        case .show: return "Show"
        }
    }

    /// Cue markers accept select / drag / nudge only in Cue mode.
    var cueMarkersEditable: Bool { self == .cue }

    /// The lyric lane accepts placement / drag only in Lyric mode.
    var lyricsEditable: Bool { self == .lyric }

    /// Show mode is fully read-only.
    var isReadOnly: Bool { self == .show }

    /// The SF Symbol shown leading the segment label — carries mode identity
    /// by shape now that the switcher is achromatic (ADR-023 amendment).
    var symbolName: String {
        switch self {
        case .cue: return "smallcircle.filled.circle"
        case .lyric: return "text.quote"
        case .show: return "lock.fill"
        }
    }
}
