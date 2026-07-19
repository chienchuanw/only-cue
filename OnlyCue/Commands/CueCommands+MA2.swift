import Foundation

@MainActor
extension CueCommands {

    /// Persist the grandMA2 push target on a media item (#683) so the next
    /// push pre-fills the same slots. Unknown item IDs are no-ops; setting the
    /// current value again registers no undo.
    static func setMA2PushTarget(
        _ target: MA2PushTarget?,
        itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        fatalError("unimplemented")
    }
}
