import Foundation

/// Undoable mutations of a media item's `TempoMap` (epic #199). Mirrors the
/// `mutateCues` shape: each call is exactly one undo step with a clear action
/// name, and a no-op when the resulting map equals the current one (so
/// committing on every editor keystroke is cheap). Operates on an explicit
/// `item` id rather than the active item, so callers (the Tempo Map sheet) are
/// unambiguous.
@MainActor
extension CueCommands {

    /// Replace the item's tempo map with `map` (normalized).
    static func setTempoMap(_ map: TempoMap, item itemID: MediaItem.ID, document: CueListDocument, undoManager: UndoManager?) {
        mutateTempoMap(item: itemID, document: document, undoManager: undoManager, actionName: "Edit Tempo Map") { _ in
            TempoMap(sections: map.sections)
        }
    }

    /// Add a tempo section: seeds a whole-item section on an empty map, otherwise
    /// inserts a boundary at `seconds` cloning the covering section's tempo.
    static func addTempoSection(
        atSeconds seconds: TimeInterval,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        mutateTempoMap(item: itemID, document: document, undoManager: undoManager, actionName: "Add Tempo Section") {
            $0.addingSection(atSeconds: seconds)
        }
    }

    /// Split the section covering `seconds` at `seconds`, keeping the beat/bar grid
    /// continuous across the cut. No-op when `seconds` is at/before a boundary.
    static func splitTempoSection(
        atSeconds seconds: TimeInterval,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        mutateTempoMap(item: itemID, document: document, undoManager: undoManager, actionName: "Split Tempo Section") {
            $0.splitting(atSeconds: seconds)
        }
    }

    /// Remove the section with `id`; the previous section's span extends to cover it.
    static func removeTempoSection(
        _ id: TempoSection.ID,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        mutateTempoMap(item: itemID, document: document, undoManager: undoManager, actionName: "Delete Tempo Section") {
            $0.removingSection(id)
        }
    }

    /// Change fields on the section with `id` (any argument left `nil` is unchanged).
    static func updateTempoSection(
        _ id: TempoSection.ID,
        startSeconds: TimeInterval? = nil,
        bpm: Double? = nil,
        beatsPerBar: Int? = nil,
        downbeatOffsetSeconds: TimeInterval? = nil,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        mutateTempoMap(item: itemID, document: document, undoManager: undoManager, actionName: "Change Tempo") {
            $0.updatingSection(
                id,
                startSeconds: startSeconds,
                bpm: bpm,
                beatsPerBar: beatsPerBar,
                downbeatOffsetSeconds: downbeatOffsetSeconds
            )
        }
    }

    /// Remove the whole tempo map (no grid).
    static func clearTempoMap(item itemID: MediaItem.ID, document: CueListDocument, undoManager: UndoManager?) {
        mutateTempoMap(item: itemID, document: document, undoManager: undoManager, actionName: "Clear Tempo Map") { _ in
            TempoMap()
        }
    }

    // MARK: - Internals

    private static func mutateTempoMap(
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        _ change: (TempoMap) -> TempoMap
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let before = document.model.items[index].tempoMap
        let after = change(before)
        guard after != before else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        document.model.items[index].tempoMap = after
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreTempoMap(itemID: itemID, to: before, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private static func restoreTempoMap(
        itemID: MediaItem.ID,
        to oldMap: TempoMap,
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        let current = document.model.items[index].tempoMap
        document.model.items[index].tempoMap = oldMap
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreTempoMap(itemID: itemID, to: current, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }
}
