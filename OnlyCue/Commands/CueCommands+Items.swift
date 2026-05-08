import Foundation

@MainActor
extension CueCommands {

    static func addItem(
        _ item: MediaItem,
        to document: CueListDocument,
        undoManager: UndoManager?
    ) {
        addItems([item], to: document, undoManager: undoManager)
    }

    static func addItems(
        _ items: [MediaItem],
        to document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard !items.isEmpty else { return }
        let beforeItems = document.model.items
        let beforeActive = document.model.activeItemID

        document.model.items.append(contentsOf: items)
        if document.model.activeItemID == nil, let firstID = items.first?.id {
            document.model.activeItemID = firstID
        }

        registerItemUndo(
            document: document,
            undoManager: undoManager,
            actionName: items.count == 1 ? "Add Item" : "Add Items",
            beforeItems: beforeItems,
            beforeActive: beforeActive
        )
    }

    static func removeItem(
        id: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        let beforeItems = document.model.items
        let beforeActive = document.model.activeItemID

        document.model.items.remove(at: index)
        if beforeActive == id {
            document.model.activeItemID = nextActiveID(after: index, in: document.model.items)
        }

        registerItemUndo(
            document: document,
            undoManager: undoManager,
            actionName: "Remove Item",
            beforeItems: beforeItems,
            beforeActive: beforeActive
        )
    }

    static func renameItem(
        id: MediaItem.ID,
        to newName: String,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        let beforeItems = document.model.items
        let beforeActive = document.model.activeItemID

        document.model.items[index].media.displayName = newName

        registerItemUndo(
            document: document,
            undoManager: undoManager,
            actionName: "Rename Item",
            beforeItems: beforeItems,
            beforeActive: beforeActive
        )
    }

    static func reorderItems(
        from source: IndexSet,
        to destination: Int,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        let beforeItems = document.model.items
        let beforeActive = document.model.activeItemID

        document.model.items.move(fromOffsets: source, toOffset: destination)
        guard document.model.items != beforeItems else { return }

        registerItemUndo(
            document: document,
            undoManager: undoManager,
            actionName: "Reorder Items",
            beforeItems: beforeItems,
            beforeActive: beforeActive
        )
    }

    /// Selection change. Not registered with undo on purpose: selection is a
    /// view-state concern, and undoing selection is annoying.
    static func setActiveItem(id: MediaItem.ID?, in document: CueListDocument) {
        guard id != document.model.activeItemID else { return }
        document.model.activeItemID = id
    }

    /// Stale-bookmark refresh routed through the seam so all `ProjectModel`
    /// writes stay in this file. Not undoable: the user didn't ask for this,
    /// the OS did.
    static func refreshBookmark(itemID: MediaItem.ID, to data: Data, in document: CueListDocument) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        document.model.items[index].media.bookmarkData = data
    }

    // MARK: - Internals

    fileprivate static func registerItemUndo(
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        beforeItems: [MediaItem],
        beforeActive: MediaItem.ID?
    ) {
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreItems(
                to: beforeItems,
                activeID: beforeActive,
                document: doc,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    fileprivate static func restoreItems(
        to oldItems: [MediaItem],
        activeID oldActive: MediaItem.ID?,
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        let currentItems = document.model.items
        let currentActive = document.model.activeItemID

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items = oldItems
        document.model.activeItemID = oldActive

        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreItems(
                to: currentItems,
                activeID: currentActive,
                document: doc,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    fileprivate static func nextActiveID(after removedIndex: Int, in items: [MediaItem]) -> MediaItem.ID? {
        guard !items.isEmpty else { return nil }
        let nextIndex = min(removedIndex, items.count - 1)
        return items[nextIndex].id
    }
}
