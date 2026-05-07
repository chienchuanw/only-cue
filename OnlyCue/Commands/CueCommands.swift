import Foundation

@MainActor
enum CueCommands {

    static let defaultCueColorHex = "#4ECDC4"

    static func addCueAtPlayhead(time: TimeInterval, document: CueListDocument, undoManager: UndoManager?) {
        let cue = Cue(
            id: UUID(),
            name: "Cue",
            time: max(time, 0),
            colorHex: defaultCueColorHex,
            notes: ""
        )
        mutate(document, undoManager: undoManager, actionName: "Add Cue") { cues in
            (cues + [cue]).sorted { $0.time < $1.time }
        }
    }

    static func delete(cueId: Cue.ID, document: CueListDocument, undoManager: UndoManager?) {
        mutate(document, undoManager: undoManager, actionName: "Delete Cue") { cues in
            cues.filter { $0.id != cueId }
        }
    }

    static func rename(cueId: Cue.ID, to newName: String, document: CueListDocument, undoManager: UndoManager?) {
        mutate(document, undoManager: undoManager, actionName: "Rename Cue") { cues in
            cues.map { cue in
                guard cue.id == cueId else { return cue }
                var copy = cue
                copy.name = newName
                return copy
            }
        }
    }

    static func recolor(cueId: Cue.ID, to newColorHex: String, document: CueListDocument, undoManager: UndoManager?) {
        mutate(document, undoManager: undoManager, actionName: "Change Cue Color") { cues in
            cues.map { cue in
                guard cue.id == cueId else { return cue }
                var copy = cue
                copy.colorHex = newColorHex
                return copy
            }
        }
    }

    static func retime(cueId: Cue.ID, to newTime: TimeInterval, document: CueListDocument, undoManager: UndoManager?) {
        mutate(document, undoManager: undoManager, actionName: "Retime Cue") { cues in
            cues
                .map { cue -> Cue in
                    guard cue.id == cueId else { return cue }
                    var copy = cue
                    copy.time = max(newTime, 0)
                    return copy
                }
                .sorted { $0.time < $1.time }
        }
    }

    private static func mutate(
        _ document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        _ change: ([Cue]) -> [Cue]
    ) {
        let before = document.model.cues
        document.model.cues = change(before)
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.mutate(doc, undoManager: undoManager, actionName: actionName) { _ in before }
        }
        undoManager?.setActionName(actionName)
    }
}
