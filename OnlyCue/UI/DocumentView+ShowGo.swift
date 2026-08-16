import SwiftUI

/// Cue-navigation actions extracted from `DocumentView` to keep its body under
/// the SwiftLint `file_length` cap: `stepPlayhead` (transport/OSC prev-next cue,
/// seek only) and `performGo` (Show-mode GO, seek + play).
extension DocumentView {

    /// The resolved Show-mode GO/step/highlight cue-type filter (#657): nil = All
    /// cues. Non-nil only in Show mode when the stored id (`showGoTypeIDRaw`)
    /// still matches a live cue type — "", a deleted type, or any non-Show mode
    /// all read as All, preserving pre-#657 behaviour. Kept equivalent to
    /// `CueListPane.showGoTypeID` (which gates on `isReadOnly`) so the picker /
    /// row dim always agree with what GO walks.
    var showGoTypeID: CuePointType.ID? {
        guard editorMode == .show,
              let id = UUID(uuidString: showGoTypeIDRaw),
              document.model.cuePointTypes.contains(where: { $0.id == id })
        else { return nil }
        return id
    }

    /// Steps the playhead to the previous / next cue (transport prev/next-cue
    /// buttons, keyboard, OSC). Seeks without changing the play/pause state —
    /// unlike `performGo`, which also plays. Honours the Show-mode type filter.
    func stepPlayhead(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction, typeID: showGoTypeID)
        else { return }
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target.time) }
    }

    /// Steps the active media item to the previous / next song and plays it
    /// immediately (#753). No-op at the list boundary (no wrap) — the transport
    /// disables the button there. Routes through `CueCommands` (the mutation
    /// seam) rather than touching `ProjectModel` directly.
    func stepSong(_ direction: MediaItem.PlayheadStep) {
        Task {
            await CueCommands.stepMediaAndPlay(
                direction,
                document: document,
                reloadAndPlay: { _ in await reloadActiveAndPlay() }
            )
        }
    }

    /// Loads the active media item and plays it, posting a relink alert on
    /// failure. The production reload-and-play seam shared by Auto-Next
    /// (`handleMediaDidReachEnd`) and manual song stepping (#753).
    func reloadActiveAndPlay() async {
        do {
            try await MediaImporter.loadActive(into: document, engine: engine, documentDirectory: documentDirectory)
            engine.play()
        } catch {
            if let item = document.model.activeItem {
                pendingAlert = .relink(itemID: item.id, displayName: item.media.displayName)
            }
        }
    }

    /// Whether a previous / next song exists to step to (#753). Drives the
    /// transport's song-button disabled state — list-position only, independent
    /// of the playhead, so it is computed from the model rather than the engine.
    var canStepPrevSong: Bool {
        guard let id = document.model.activeItemID else { return false }
        return CueCommands.previousMediaItemID(before: id, in: document.model.items) != nil
    }

    var canStepNextSong: Bool {
        guard let id = document.model.activeItemID else { return false }
        return CueCommands.nextMediaItemID(after: id, in: document.model.items) != nil
    }

    /// Show-mode GO (#645): seek to the next cue after the playhead and play.
    /// No-op when there is no next cue. Not a `ProjectModel` mutation, so it
    /// drives the engine directly rather than going through `CueCommands`.
    /// Extracted from `DocumentView` to keep its body under the SwiftLint
    /// `file_length` cap.
    func performGo() {
        guard let item = document.model.activeItem,
              case .seekAndPlay(let time) = item.showGoDecision(from: engine.currentTime, typeID: showGoTypeID)
        else { return }
        seekTask?.cancel()
        seekTask = Task {
            await engine.seek(to: time)
            engine.play()
        }
    }

    /// Whether a cue may be created right now: a media item is loaded and the
    /// document is not in read-only Show mode (#592). Consulted by the keyboard
    /// shortcut hosts and the add-cue actions.
    var canCreateCue: Bool {
        CueCreationGate.allows(editorMode: editorMode, hasActiveItem: document.model.activeItem != nil)
    }
}
