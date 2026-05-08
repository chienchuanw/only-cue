import Foundation

@MainActor
enum CueCommands {

    // MARK: - Cue mutations (scoped to the active item)

    static func addCueAtPlayhead(
        time: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let defaultType = document.model.cuePointTypes.first else {
            assertionFailure("Project has no CuePointTypes — invariant violated by upstream code")
            return
        }
        let clampedTime = max(time, 0)
        let existingCues = document.model.activeItem?.cues ?? []
        let cue = Cue(
            id: UUID(),
            typeID: defaultType.id,
            cueNumber: CueNumberAssignment.next(forInsertionAt: clampedTime, in: existingCues),
            name: "Cue",
            time: clampedTime,
            colorHex: defaultType.colorHex,
            notes: "",
            fadeTime: .zero
        )
        mutateCues(document, undoManager: undoManager, actionName: "Add Cue") { cues in
            (cues + [cue]).sorted { $0.time < $1.time }
        }
    }

    static func delete(cueId: Cue.ID, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Delete Cue") { cues in
            cues.filter { $0.id != cueId }
        }
    }

    static func rename(cueId: Cue.ID, to newName: String, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Rename Cue") {
            $0.name = newName
        }
    }

    static func recolor(cueId: Cue.ID, to newColorHex: String, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Color") {
            $0.colorHex = newColorHex
        }
    }

    static func setType(cueId: Cue.ID, to newTypeID: CuePointType.ID, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Type") {
            $0.typeID = newTypeID
        }
    }

    static func setCueNumber(cueId: Cue.ID, to newNumber: Double, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Number") {
            $0.cueNumber = newNumber
        }
    }

    static func setFadeTime(cueId: Cue.ID, to newFade: FadeTime, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Fade") {
            $0.fadeTime = newFade
        }
    }

    static func setNotes(cueId: Cue.ID, to newNotes: String, document: CueListDocument, undoManager: UndoManager?) {
        updateCue(cueId: cueId, document: document, undoManager: undoManager, actionName: "Change Cue Notes") {
            $0.notes = newNotes
        }
    }

    static func retime(cueId: Cue.ID, to newTime: TimeInterval, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Retime Cue") { cues in
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

    // MARK: - Internals

    private static func updateCue(
        cueId: Cue.ID,
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        update: (inout Cue) -> Void
    ) {
        mutateCues(document, undoManager: undoManager, actionName: actionName) { cues in
            cues.map { cue in
                guard cue.id == cueId else { return cue }
                var copy = cue
                update(&copy)
                return copy
            }
        }
    }

    private static func mutateCues(
        _ document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        _ change: ([Cue]) -> [Cue]
    ) {
        guard let index = document.model.activeItemIndex else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let before = document.model.items[index].cues
        document.model.items[index].cues = change(before)
        let itemID = document.model.items[index].id
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreCues(itemID: itemID, to: before, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private static func restoreCues(
        itemID: MediaItem.ID,
        to oldCues: [Cue],
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let current = document.model.items[index].cues
        document.model.items[index].cues = oldCues
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreCues(itemID: itemID, to: current, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

}
