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
