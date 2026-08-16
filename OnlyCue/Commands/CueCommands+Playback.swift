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

    /// Returns the id of the item immediately before `current` in `items`.
    /// Returns nil when `current` is the first item, when `current` is not in
    /// `items`, or when `items` is empty. Pure — no side effects.
    static func previousMediaItemID(
        before current: MediaItem.ID,
        in items: [MediaItem]
    ) -> MediaItem.ID? {
        guard let index = items.firstIndex(where: { $0.id == current }) else { return nil }
        let previous = index - 1
        guard previous >= 0 else { return nil }
        return items[previous].id
    }

    /// Whether a previous / next media item exists to step to (#753). Pure — the
    /// single source of truth for both hosts' song-button disabled state, so the
    /// main-window transport and the mini player can't drift.
    static func canStepSong(
        _ direction: MediaItem.PlayheadStep,
        activeID: MediaItem.ID?,
        in items: [MediaItem]
    ) -> Bool {
        guard let activeID else { return false }
        switch direction {
        case .previous: return previousMediaItemID(before: activeID, in: items) != nil
        case .next: return nextMediaItemID(after: activeID, in: items) != nil
        }
    }

    /// Steps `activeItemID` to the previous / next item in `items[]` and triggers
    /// the caller's reload-and-play side effect. No-op at the list boundary (no
    /// wrap), for nil `activeItemID`, or when the active id isn't in `items[]` —
    /// the transport disables the button in those cases (#753).
    ///
    /// Non-undoable on purpose, like `advanceToNextMediaAndPlay`: Cmd-Z snapping
    /// back to the previous song is the wrong recovery path; the operator wants
    /// the sidebar instead. Selection changes already bypass undo (see
    /// `setActiveItem(id:in:)` in `CueCommands+Items.swift`).
    ///
    /// `reloadAndPlay` is the production seam for `MediaImporter.loadActive`
    /// + `engine.play()`. Tests pass a spy closure.
    static func stepMediaAndPlay(
        _ direction: MediaItem.PlayheadStep,
        document: CueListDocument,
        reloadAndPlay: @MainActor (MediaItem.ID) async -> Void
    ) async {
        guard let current = document.model.activeItemID else { return }
        let targetID: MediaItem.ID?
        switch direction {
        case .previous: targetID = previousMediaItemID(before: current, in: document.model.items)
        case .next: targetID = nextMediaItemID(after: current, in: document.model.items)
        }
        guard let targetID else { return }
        document.model.activeItemID = targetID
        await reloadAndPlay(targetID)
    }

    /// Advances `activeItemID` to the next item in `items[]` and triggers the
    /// caller's reload-and-play side effect. No-op at the end of the list, for
    /// nil `activeItemID`, or when the active id isn't in `items[]`.
    ///
    /// The auto-next end-of-media path (`DocumentView+PlaybackMode`); thin
    /// forward-only alias over `stepMediaAndPlay(.next:)`.
    static func advanceToNextMediaAndPlay(
        document: CueListDocument,
        reloadAndPlay: @MainActor (MediaItem.ID) async -> Void
    ) async {
        await stepMediaAndPlay(.next, document: document, reloadAndPlay: reloadAndPlay)
    }
}
