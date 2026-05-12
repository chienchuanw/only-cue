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
}
