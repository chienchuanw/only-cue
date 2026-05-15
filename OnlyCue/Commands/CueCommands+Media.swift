import Foundation

@MainActor
extension CueCommands {

    /// Atomically update a media item's user-editable metadata
    /// (`alternateName`, `startTimecodeFrames`, `ltcMuted`). Registers a single
    /// undo step covering all three fields so the modal "Edit Media…" sheet's
    /// Save is one user-perceived action. Unknown item IDs are no-ops; negative
    /// frames are clamped to zero. When the incoming values already match the
    /// current item the call is a no-op and no undo is registered, so spurious
    /// "Save" presses don't pollute the undo stack.
    static func updateMediaItem(
        id: MediaItem.ID,
        alternateName: String?,
        startTimecodeFrames: Int,
        ltcMuted: Bool,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        let clampedFrames = max(0, startTimecodeFrames)
        let previous = document.model.items[index]

        let alreadyMatches = previous.alternateName == alternateName
            && previous.startTimecodeFrames == clampedFrames
            && previous.ltcMuted == ltcMuted
        if alreadyMatches { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].alternateName = alternateName
        document.model.items[index].startTimecodeFrames = clampedFrames
        document.model.items[index].ltcMuted = ltcMuted

        undoManager?.registerUndo(withTarget: document) { doc in
            Self.updateMediaItem(
                id: id,
                alternateName: previous.alternateName,
                startTimecodeFrames: previous.startTimecodeFrames,
                ltcMuted: previous.ltcMuted,
                document: doc,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName("Edit Media")
    }
}
