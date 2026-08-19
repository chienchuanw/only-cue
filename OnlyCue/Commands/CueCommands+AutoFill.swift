import Foundation

extension CueCommands {

    /// Fills the missing (`nil`) `cueNumber`s of one item (#763) using
    /// `CueNumberAutoFill`, committed as a single undo step. Item-targeted (not the
    /// active item) so a batch grandMA2 push (#765) can number any selected song.
    /// A no-op — no undo step — when every cue already has a number.
    static func autoFillCueNumbers(
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let assignments = CueNumberAutoFill.assignments(for: document.model.items[index].cues)
        guard !assignments.isEmpty else { return }

        let filled = document.model.items[index].cues.map { cue -> Cue in
            guard let number = assignments[cue.id] else { return cue }
            var copy = cue
            copy.cueNumber = number
            return copy
        }
        setCues(filled, itemID: itemID, document: document, undoManager: undoManager)
    }

    /// Replace one item's cues, registering the inverse for undo/redo.
    private static func setCues(
        _ cues: [Cue],
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let before = document.model.items[index].cues
        document.model.items[index].cues = cues
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setCues(before, itemID: itemID, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Auto-number Cues")
    }
}
