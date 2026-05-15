import Foundation

/// Bundle of user-editable per-media fields. Wraps the three values committed
/// by the "Edit Media…" sheet so `CueCommands.updateMediaItem` stays under
/// SwiftLint's parameter-count cap.
struct MediaItemEdit: Equatable {
    var alternateName: String?
    var startTimecodeFrames: Int
    var ltcMuted: Bool
}

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
        edit: MediaItemEdit,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        let clampedFrames = max(0, edit.startTimecodeFrames)
        let previous = document.model.items[index]
        let normalized = MediaItemEdit(
            alternateName: edit.alternateName,
            startTimecodeFrames: clampedFrames,
            ltcMuted: edit.ltcMuted
        )

        let alreadyMatches = previous.alternateName == normalized.alternateName
            && previous.startTimecodeFrames == normalized.startTimecodeFrames
            && previous.ltcMuted == normalized.ltcMuted
        if alreadyMatches { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].alternateName = normalized.alternateName
        document.model.items[index].startTimecodeFrames = normalized.startTimecodeFrames
        document.model.items[index].ltcMuted = normalized.ltcMuted

        let previousEdit = MediaItemEdit(
            alternateName: previous.alternateName,
            startTimecodeFrames: previous.startTimecodeFrames,
            ltcMuted: previous.ltcMuted
        )
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.updateMediaItem(id: id, edit: previousEdit, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Edit Media")
    }
}
