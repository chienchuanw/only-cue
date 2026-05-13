import Foundation

/// Tempo-grid commands (epic #199): snapping selected cues to the nearest beat /
/// bar of a `TempoMap`, and bulk-inserting cues on a grid. Split out of
/// `CueCommands.swift` so that file stays under the `type_body_length` cap; both
/// build on the shared `mutateCues` snapshot/undo primitive.
extension CueCommands {

    /// A beat grid or a bar (downbeat) grid — the resolution snapping / bulk-insert works at.
    enum GridResolution { case beat, bar }

    /// Cap on cues inserted by `addCuesOnGrid` — past it the timeline would be unusable
    /// mush; the bulk-insert just stops rather than locking up.
    private static let maxGridInsert = 5_000

    /// Move every selected cue to the nearest beat of `map` (clamped at 0), re-sort, in
    /// one undo step. No-op for an empty selection or an empty map.
    static func snapCues(
        _ ids: Set<Cue.ID>,
        toBeatIn map: TempoMap,
        itemDuration: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard !ids.isEmpty, !map.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Snap Cues to Beat") { cues in
            snapping(cues, ids) { map.nearestBeat(toSeconds: $0, itemDuration: itemDuration) }
        }
    }

    /// Move every selected cue to the nearest bar line (downbeat) of `map`, re-sort, in
    /// one undo step. No-op for an empty selection or an empty map.
    static func snapCues(
        _ ids: Set<Cue.ID>,
        toBarIn map: TempoMap,
        itemDuration: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard !ids.isEmpty, !map.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Snap Cues to Bar") { cues in
            snapping(cues, ids) { map.nearestBar(toSeconds: $0, itemDuration: itemDuration) }
        }
    }

    /// Move the cues in `ids` to the grid line `nearest` their time (clamped at 0); other
    /// cues are untouched. Re-sorted by time. Pure.
    private static func snapping(_ cues: [Cue], _ ids: Set<Cue.ID>, to nearest: (TimeInterval) -> TimeInterval?) -> [Cue] {
        cues
            .map { cue -> Cue in
                guard ids.contains(cue.id), let target = nearest(cue.time) else { return cue }
                var copy = cue
                copy.time = max(target, 0)
                return copy
            }
            .sorted { $0.time < $1.time }
    }

    /// Insert a cue at every grid position (beats or downbeats) of the active item's
    /// tempo map within `range`, in one undo step. New cues get `type` (or the default
    /// `CuePointType`) and cue numbers assigned by the usual rule. No-op on an empty tempo
    /// map, an empty range, or when there's no default Type; the insert count is capped
    /// (see `maxGridInsert`).
    static func addCuesOnGrid(
        in range: ClosedRange<TimeInterval>,
        every resolution: GridResolution,
        type typeID: CuePointType.ID?,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.activeItemIndex else { return }
        let item = document.model.items[index]
        guard !item.tempoMap.isEmpty, let resolvedType = typeID ?? document.model.defaultCuePointTypeID else { return }
        let gridTimes: [TimeInterval]
        switch resolution {
        case .beat: gridTimes = item.tempoMap.beatTimes(in: range, itemDuration: item.media.duration).map(\.time)
        case .bar: gridTimes = item.tempoMap.barTimes(in: range, itemDuration: item.media.duration)
        }
        let capped = Array(gridTimes.prefix(maxGridInsert))
        guard !capped.isEmpty else { return }
        mutateCues(document, undoManager: undoManager, actionName: "Add Cues on Grid") { cues in
            var result = cues
            for time in capped {
                let number = CueNumberAssignment.next(forInsertionAt: time, in: result)
                result.append(
                    Cue(id: UUID(), typeID: resolvedType, cueNumber: number, name: "", time: time, notes: "", fadeTime: .zero)
                )
            }
            return result.sorted { $0.time < $1.time }
        }
    }
}
