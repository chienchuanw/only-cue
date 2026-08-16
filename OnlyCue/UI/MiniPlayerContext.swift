import Foundation

/// Live, observable context the Mini Player panel reads for the values that
/// aren't already carried by the shared `PlayerEngine` / `CueListDocument` —
/// the per-window editor mode and its resolved Show-mode type filter.
/// `DocumentView` keeps these current so the panel mirrors mode changes even
/// while paused. See `docs/superpowers/specs/2026-08-16-miniplay-design.md`.
@Observable
@MainActor
final class MiniPlayerContext {
    var editorMode: EditorMode = .cue
    var showGoTypeID: CuePointType.ID?
}
