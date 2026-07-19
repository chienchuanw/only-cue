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
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        let previous = document.model.items[index].ma2PushTarget
        guard previous != target else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].ma2PushTarget = target

        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setMA2PushTarget(previous, itemID: itemID, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Set grandMA2 Target")
    }
}
