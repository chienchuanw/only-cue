import Foundation

@MainActor
extension CueCommands {

    /// Replace the project's timecode settings (SMPTE framerate + start-timecode
    /// offset, `ProjectModel.timecodeSettings`), undoably. A no-op when the
    /// value is unchanged, so committing on every editor keystroke is cheap.
    static func setProjectTimecodeSettings(
        _ settings: ProjectTimecodeSettings,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        let previous = document.model.timecodeSettings
        guard previous != settings else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.timecodeSettings = settings
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setProjectTimecodeSettings(previous, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Change Timecode Settings")
    }

    /// Set a media item's start timecode (in frames since `00:00:00:00` at the
    /// project framerate), undoably. Negative frames and unknown item IDs are
    /// no-ops that register no undo so spurious editor commits don't pollute
    /// the undo stack.
    static func setStartTimecode(
        itemID: MediaItem.ID,
        frames: Int,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard frames >= 0,
              let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let previous = document.model.items[index].startTimecodeFrames
        guard previous != frames else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].startTimecodeFrames = frames
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setStartTimecode(itemID: itemID, frames: previous, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Change Start Timecode")
    }

    /// Toggle the LTC mute flag for a specific item, undoably. When muted, the
    /// LTC output channel emits silence while this item is the active media;
    /// the encoder keeps running so unmute is instant. No-op when the value is
    /// unchanged or the item ID is unknown.
    static func setLTCMuted(
        itemID: MediaItem.ID,
        muted: Bool,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let previous = document.model.items[index].ltcMuted
        guard previous != muted else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].ltcMuted = muted
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setLTCMuted(itemID: itemID, muted: previous, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName(muted ? "Mute LTC" : "Unmute LTC")
    }
}
