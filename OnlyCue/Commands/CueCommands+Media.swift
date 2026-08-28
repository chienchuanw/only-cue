import Foundation

/// Bundle of user-editable per-media fields. Wraps the four values committed
/// by the "Edit Media…" sheet so `CueCommands.updateMediaItem` stays under
/// SwiftLint's parameter-count cap.
///
/// Fields: `alternateName`, `startTimecodeFrames`, `ltcMuted`,
/// `playsOriginalSourceAudio`.
struct MediaItemEdit: Equatable {
    var alternateName: String?
    var startTimecodeFrames: Int
    var ltcMuted: Bool
    var playsOriginalSourceAudio: Bool
}

@MainActor
extension CueCommands {

    /// Atomically update a media item's user-editable metadata
    /// (`alternateName`, `startTimecodeFrames`, `ltcMuted`,
    /// `playsOriginalSourceAudio`). Registers a single undo step covering all
    /// four fields so the modal "Edit Media…" sheet's Save is one
    /// user-perceived action. Unknown item IDs are no-ops; negative frames are
    /// clamped to zero. When the incoming values already match the current item
    /// the call is a no-op and no undo is registered, so spurious "Save"
    /// presses don't pollute the undo stack.
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
            ltcMuted: edit.ltcMuted,
            playsOriginalSourceAudio: edit.playsOriginalSourceAudio
        )

        let alreadyMatches = previous.alternateName == normalized.alternateName
            && previous.startTimecodeFrames == normalized.startTimecodeFrames
            && previous.ltcMuted == normalized.ltcMuted
            && previous.playsOriginalSourceAudio == normalized.playsOriginalSourceAudio
        if alreadyMatches { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].alternateName = normalized.alternateName
        document.model.items[index].startTimecodeFrames = normalized.startTimecodeFrames
        document.model.items[index].ltcMuted = normalized.ltcMuted
        document.model.items[index].playsOriginalSourceAudio = normalized.playsOriginalSourceAudio

        let previousEdit = MediaItemEdit(
            alternateName: previous.alternateName,
            startTimecodeFrames: previous.startTimecodeFrames,
            ltcMuted: previous.ltcMuted,
            playsOriginalSourceAudio: previous.playsOriginalSourceAudio
        )
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.updateMediaItem(id: id, edit: previousEdit, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Edit Media")
    }

    /// Set (or clear, with `colorHex == nil`) a clip's colour tag, undoably.
    /// The tag is purely visual — a leading stripe in the media panel (#782).
    ///
    /// The palette guard keeps arbitrary or malformed hex out of the model: the
    /// picker only ever offers those eight, so anything else means a caller bug.
    /// (A *hand-edited* `.cuelist` bypasses this and is handled at render time
    /// instead — `Color(hex:)` returns nil, so the row draws no stripe.)
    static func setMediaColor(
        itemID: MediaItem.ID,
        colorHex: String?,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard colorHex.map(CuePointType.defaultPalette.contains) ?? true else { return }
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let previous = document.model.items[index].colorHex
        guard previous != colorHex else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].colorHex = colorHex
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setMediaColor(itemID: itemID, colorHex: previous, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName(colorHex == nil ? "Clear Color" : "Set Color")
    }
}
