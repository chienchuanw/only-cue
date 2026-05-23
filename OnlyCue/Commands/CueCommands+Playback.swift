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
}
