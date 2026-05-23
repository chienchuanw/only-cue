import Foundation

@MainActor
extension CueCommands {

    /// Set the document's playback mode. No-op when the mode already matches —
    /// keeps the undo stack clean for menu clicks that re-pick the active mode.
    static func setPlaybackMode(
        _ mode: PlaybackMode,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        let previous = document.model.playbackMode
        guard previous != mode else { return }

        document.model.playbackMode = mode

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setPlaybackMode(previous, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Set Playback Mode")
    }

    /// Returns the id of the item immediately after `current` in `items`.
    /// Returns nil when `current` is the last item, when `current` is not in
    /// `items`, or when `items` is empty. Pure — no side effects.
    static func nextMediaItemID(
        after current: MediaItem.ID,
        in items: [MediaItem]
    ) -> MediaItem.ID? {
        guard let index = items.firstIndex(where: { $0.id == current }) else { return nil }
        let next = index + 1
        guard next < items.count else { return nil }
        return items[next].id
    }

    /// Advances `activeItemID` to the next item in `items[]` and triggers the
    /// caller's reload-and-play side effect. No-op at the end of the list, for
    /// nil `activeItemID`, or when the active id isn't in `items[]`.
    ///
    /// Non-undoable on purpose. Cmd-Z mid-show snapping back to the just-
    /// finished song is the wrong recovery path; the operator wants the
    /// sidebar instead. Selection changes already bypass undo (see
    /// `setActiveItem(id:in:)` in `CueCommands+Items.swift`).
    ///
    /// `reloadAndPlay` is the production seam for `MediaImporter.loadActive`
    /// + `engine.play()`. Tests pass a spy closure.
    static func advanceToNextMediaAndPlay(
        document: CueListDocument,
        reloadAndPlay: @MainActor (MediaItem.ID) async -> Void
    ) async {
        guard let current = document.model.activeItemID else { return }
        guard let nextID = nextMediaItemID(after: current, in: document.model.items) else { return }
        document.model.activeItemID = nextID
        await reloadAndPlay(nextID)
    }
}
