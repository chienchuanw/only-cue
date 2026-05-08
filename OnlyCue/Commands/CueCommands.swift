import Foundation

@MainActor
enum CueCommands {

    static let defaultCueColorHex = "#4ECDC4"

    // MARK: - Cue mutations (scoped to the active item)

    static func addCueAtPlayhead(
        time: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        let cue = Cue(
            id: UUID(),
            name: "Cue",
            time: max(time, 0),
            colorHex: defaultCueColorHex,
            notes: ""
        )
        mutateCues(document, undoManager: undoManager, actionName: "Add Cue") { cues in
            (cues + [cue]).sorted { $0.time < $1.time }
        }
    }

    static func delete(cueId: Cue.ID, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Delete Cue") { cues in
            cues.filter { $0.id != cueId }
        }
    }

    static func rename(cueId: Cue.ID, to newName: String, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Rename Cue") { cues in
            cues.map { cue in
                guard cue.id == cueId else { return cue }
                var copy = cue
                copy.name = newName
                return copy
            }
        }
    }

    static func recolor(cueId: Cue.ID, to newColorHex: String, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Change Cue Color") { cues in
            cues.map { cue in
                guard cue.id == cueId else { return cue }
                var copy = cue
                copy.colorHex = newColorHex
                return copy
            }
        }
    }

    static func retime(cueId: Cue.ID, to newTime: TimeInterval, document: CueListDocument, undoManager: UndoManager?) {
        mutateCues(document, undoManager: undoManager, actionName: "Retime Cue") { cues in
            cues
                .map { cue -> Cue in
                    guard cue.id == cueId else { return cue }
                    var copy = cue
                    copy.time = max(newTime, 0)
                    return copy
                }
                .sorted { $0.time < $1.time }
        }
    }

    // MARK: - Item mutations

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

        registerUndo(
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

        registerUndo(
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

        registerUndo(
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

        registerUndo(
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

    // MARK: - Internals

    private static func mutateCues(
        _ document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String,
        _ change: ([Cue]) -> [Cue]
    ) {
        guard let index = document.model.activeItemIndex else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let before = document.model.items[index].cues
        document.model.items[index].cues = change(before)
        let itemID = document.model.items[index].id
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreCues(itemID: itemID, to: before, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private static func restoreCues(
        itemID: MediaItem.ID,
        to oldCues: [Cue],
        document: CueListDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        let current = document.model.items[index].cues
        document.model.items[index].cues = oldCues
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.restoreCues(itemID: itemID, to: current, document: doc, undoManager: undoManager, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private static func registerUndo(
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

    private static func restoreItems(
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

    private static func nextActiveID(after removedIndex: Int, in items: [MediaItem]) -> MediaItem.ID? {
        guard !items.isEmpty else { return nil }
        let nextIndex = min(removedIndex, items.count - 1)
        return items[nextIndex].id
    }
}
