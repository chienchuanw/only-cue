import Foundation

/// Tempo-grid commands (v11): snapping selected cues to the nearest beat / bar
/// of a `DerivedTempoGrid` (built at the call site from the item's cues).
/// Bulk-grid insertion (`addCuesOnGrid`) was dropped in v11 — it had no users
/// and the feature is documented as removed in the cue-anchored tempo spec.
extension CueCommands {

    /// A beat grid or a bar (downbeat) grid — the resolution snapping works at.
    enum GridResolution { case beat, bar }

    /// Move every selected cue to the nearest beat of `grid` (clamped at 0),
    /// re-sort, in one undo step. No-op for an empty selection or an empty grid.
    static func snapCues(
        _ ids: Set<Cue.ID>,
        toBeatIn grid: DerivedTempoGrid,
        itemDuration: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard !ids.isEmpty, !grid.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Snap Cues to Beat") { cues in
            snapping(cues, ids) { grid.nearestBeat(toSeconds: $0, itemDuration: itemDuration) }
        }
    }

    /// Move every selected cue to the nearest bar line (downbeat) of `grid`,
    /// re-sort, in one undo step. No-op for an empty selection or an empty grid.
    static func snapCues(
        _ ids: Set<Cue.ID>,
        toBarIn grid: DerivedTempoGrid,
        itemDuration: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard !ids.isEmpty, !grid.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Snap Cues to Bar") { cues in
            snapping(cues, ids) { grid.nearestBar(toSeconds: $0, itemDuration: itemDuration) }
        }
    }

    /// Move the cues in `ids` to the grid line `nearest` their time (clamped at
    /// 0); other cues are untouched. Re-sorted by time. Pure.
    private static func snapping(
        _ cues: [Cue],
        _ ids: Set<Cue.ID>,
        to nearest: (TimeInterval) -> TimeInterval?
    ) -> [Cue] {
        cues
            .map { cue -> Cue in
                guard ids.contains(cue.id), let target = nearest(cue.time) else { return cue }
                var copy = cue
                copy.time = max(target, 0)
                return copy
            }
            .sorted { $0.time < $1.time }
    }

    /// Removed in v11 (#245). The notification receivers in `CueListPane` still
    /// reference this entry point until #248 deletes those wires; the body is
    /// a deliberate no-op so the build stays green.
    static func addCuesOnGrid(
        in range: ClosedRange<TimeInterval>,
        every resolution: GridResolution,
        type typeID: CuePointType.ID?,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        _ = (range, resolution, typeID, document, undoManager)
    }
}
