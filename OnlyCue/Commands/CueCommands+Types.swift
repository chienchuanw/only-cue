import Foundation

@MainActor
extension CueCommands {

    static func addCuePointType(
        _ type: CuePointType,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        mutateTypes(document, undoManager: undoManager, actionName: "Add Type") { types in
            types + [type]
        }
    }

    static func setCuePointTypeName(
        id: CuePointType.ID,
        to newName: String,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        updateType(id: id, document: document, undoManager: undoManager, actionName: "Rename Type") {
            $0.name = newName
        }
    }

    static func setCuePointTypeColor(
        id: CuePointType.ID,
        to newColorHex: String,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        updateType(id: id, document: document, undoManager: undoManager, actionName: "Change Type Color") {
            $0.colorHex = newColorHex
        }
    }

    /// Shows or hides a Type's lane in the timeline breakdown view (`CuePointType.isVisible`,
    /// persisted in `.cuelist`). Doesn't touch cues or the regular waveform overlay.
    static func setCuePointTypeVisibility(
        id: CuePointType.ID,
        to isVisible: Bool,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        updateType(id: id, document: document, undoManager: undoManager, actionName: isVisible ? "Show Type Lane" : "Hide Type Lane") {
            $0.isVisible = isVisible
        }
    }

    /// Marks every Type visible in one undo step — the "+N hidden" affordance in the
    /// breakdown view. No-op (still registers undo) if none were hidden.
    static func showAllCuePointTypes(document: CueListDocument, undoManager: UndoManager?) {
        mutateTypes(document, undoManager: undoManager, actionName: "Show All Type Lanes") { types in
            types.map { type in
                var copy = type
                copy.isVisible = true
                return copy
            }
        }
    }

    /// Removes a Type and reassigns every cue currently referencing it to `reassignTo`.
    /// Both mutations land in one undo group: ⌘Z restores the Type and the prior typeIDs.
    /// Caller is responsible for: blocking the call when this is the last Type, and showing
    /// any confirmation dialog before invoking.
    static func removeCuePointType(
        id: CuePointType.ID,
        reassignTo: CuePointType.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        mutateProject(document, undoManager: undoManager, actionName: "Delete Type") { model in
            for itemIndex in model.items.indices {
                model.items[itemIndex].cues = model.items[itemIndex].cues.map { cue in
                    guard cue.typeID == id else { return cue }
                    var copy = cue
                    copy.typeID = reassignTo
                    return copy
                }
            }
            model.cuePointTypes.removeAll(where: { $0.id == id })
        }
    }

    /// Sets the target Type's hotkey. If `newHotkey` is non-nil and another Type already
    /// holds it, that Type's hotkey is cleared atomically (move semantics). Single
    /// `mutateTypes` snapshot so undo restores both Types' hotkeys in one step.
    static func setCuePointTypeHotkey(
        id: CuePointType.ID,
        to newHotkey: Int?,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        mutateTypes(document, undoManager: undoManager, actionName: "Change Type Hotkey") { types in
            types.map { type in
                var copy = type
                if type.id == id {
                    copy.hotkey = newHotkey
                } else if let key = newHotkey, type.hotkey == key {
                    copy.hotkey = nil
                }
                return copy
            }
        }
    }

    // MARK: - Internals

    private static func updateType(
        id: CuePointType.ID,
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        update: (inout CuePointType) -> Void
    ) {
        mutateTypes(document, undoManager: undoManager, actionName: actionName) { types in
            types.map { type in
                guard type.id == id else { return type }
                var copy = type
                update(&copy)
                return copy
            }
        }
    }

    /// Wide undo seam: snapshots the entire (cuePointTypes, items, activeItemID) tuple
    /// and restores all three on undo. Used by mutations that cross the Type/cue boundary
    /// (currently only `removeCuePointType`, which both deletes a Type and rewrites
    /// referenced cues' typeIDs).
    fileprivate static func mutateProject(
        _ document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        _ change: (inout ProjectModel) -> Void
    ) {
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let snapshot = ProjectSnapshot(model: document.model)
        change(&document.model)

        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreProject(snapshot, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    fileprivate static func restoreProject(
        _ snapshot: ProjectSnapshot,
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let current = ProjectSnapshot(model: document.model)
        snapshot.apply(to: &document.model)

        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreProject(current, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    /// Snapshots only `cuePointTypes` and `items` — `activeItemID` is intentionally
    /// excluded so that undoing a Type-level change after switching items does not
    /// silently revert the user's selection.
    fileprivate struct ProjectSnapshot {
        let cuePointTypes: [CuePointType]
        let items: [MediaItem]

        init(model: ProjectModel) {
            self.cuePointTypes = model.cuePointTypes
            self.items = model.items
        }

        func apply(to model: inout ProjectModel) {
            model.cuePointTypes = cuePointTypes
            model.items = items
        }
    }

    fileprivate static func mutateTypes(
        _ document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        _ change: ([CuePointType]) -> [CuePointType]
    ) {
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let before = document.model.cuePointTypes
        document.model.cuePointTypes = change(before)
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreTypes(to: before, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    fileprivate static func restoreTypes(
        to oldTypes: [CuePointType],
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let current = document.model.cuePointTypes
        document.model.cuePointTypes = oldTypes
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreTypes(to: current, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }
}
