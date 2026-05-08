import Foundation

@MainActor
enum CueCommands {

    // MARK: - Cue mutations (scoped to the active item)

    static func addCueAtPlayhead(
        time: TimeInterval,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let defaultType = document.model.cuePointTypes.first else {
            assertionFailure("Project has no CuePointTypes — invariant violated by upstream code")
            return
        }
        let clampedTime = max(time, 0)
        let existingCues = document.model.activeItem?.cues ?? []
        let cue = Cue(
            id: UUID(),
            typeID: defaultType.id,
            cueNumber: nextCueNumber(forInsertionAt: clampedTime, in: existingCues),
            name: "Cue",
            time: clampedTime,
            colorHex: defaultType.colorHex,
            notes: ""
        )
        mutateCues(document, undoManager: undoManager, actionName: "Add Cue") { cues in
            (cues + [cue]).sorted { $0.time < $1.time }
        }
    }

    /// Existing cues' numbers are never shifted — the rule produces a fractional value
    /// when needed so the new cue slots between its time-neighbors.
    static func nextCueNumber(forInsertionAt time: TimeInterval, in cues: [Cue]) -> Double {
        if cues.isEmpty { return 1.0 }
        let sorted = cues.sorted { $0.time < $1.time }
        let earlier = sorted.last { $0.time <= time }
        let later = sorted.first { $0.time > time }
        switch (earlier, later) {
        case (nil, .some(let next)):
            return next.cueNumber - 1.0
        case (.some(let prev), nil):
            return prev.cueNumber + 1.0
        case (.some(let prev), .some(let next)):
            return (prev.cueNumber + next.cueNumber) / 2.0
        case (nil, nil):
            preconditionFailure("nextCueNumber: cues non-empty but neither neighbor found — every cue's time partitions on \(time)")
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

    /// Stale-bookmark refresh routed through the seam so all `ProjectModel`
    /// writes stay in this file. Not undoable: the user didn't ask for this,
    /// the OS did.
    static func refreshBookmark(itemID: MediaItem.ID, to data: Data, in document: CueListDocument) {
        guard let index = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        document.model.items[index].media.bookmarkData = data
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
