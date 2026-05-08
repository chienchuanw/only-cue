import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsItemTests: XCTestCase {

    func test_addItem_appendsAndActivatesFirstItem() {
        let doc = CueListDocument()
        let item = makeItem(name: "a.wav")

        CueCommands.addItem(item, to: doc, undoManager: nil)

        XCTAssertEqual(doc.model.items.count, 1)
        XCTAssertEqual(doc.model.activeItemID, item.id)
    }

    func test_addItem_doesNotChangeActive_whenAlreadySet() {
        let doc = CueListDocument()
        let first = makeItem(name: "a.wav")
        CueCommands.addItem(first, to: doc, undoManager: nil)

        let second = makeItem(name: "b.wav")
        CueCommands.addItem(second, to: doc, undoManager: nil)

        XCTAssertEqual(doc.model.items.count, 2)
        XCTAssertEqual(doc.model.activeItemID, first.id)
    }

    func test_addItems_groupsAsSingleUndo() {
        let doc = CueListDocument()
        let undo = makeUndoManager()

        CueCommands.addItems([makeItem(name: "a"), makeItem(name: "b"), makeItem(name: "c")], to: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items.count, 3)

        undo.undo()
        XCTAssertEqual(doc.model.items.count, 0)
        XCTAssertNil(doc.model.activeItemID)
    }

    func test_removeItem_advancesActiveToNext() {
        let doc = CueListDocument()
        let first = makeItem(name: "a")
        let middle = makeItem(name: "b")
        let last = makeItem(name: "c")
        CueCommands.addItems([first, middle, last], to: doc, undoManager: nil)
        CueCommands.setActiveItem(id: middle.id, in: doc)

        CueCommands.removeItem(id: middle.id, document: doc, undoManager: nil)
        XCTAssertEqual(doc.model.items.map(\.id), [first.id, last.id])
        XCTAssertEqual(doc.model.activeItemID, last.id)
    }

    func test_removeItem_lastInList_advancesActiveToPrevious() {
        let doc = CueListDocument()
        let first = makeItem(name: "a")
        let last = makeItem(name: "b")
        CueCommands.addItems([first, last], to: doc, undoManager: nil)
        CueCommands.setActiveItem(id: last.id, in: doc)

        CueCommands.removeItem(id: last.id, document: doc, undoManager: nil)
        XCTAssertEqual(doc.model.activeItemID, first.id)
    }

    func test_removeItem_onlyItem_clearsActive() {
        let doc = CueListDocument()
        let only = makeItem(name: "a")
        CueCommands.addItem(only, to: doc, undoManager: nil)

        CueCommands.removeItem(id: only.id, document: doc, undoManager: nil)
        XCTAssertNil(doc.model.activeItemID)
        XCTAssertTrue(doc.model.items.isEmpty)
    }

    func test_removeItem_undoRestoresItemAndPriorActive() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let first = makeItem(name: "a")
        let last = makeItem(name: "b")
        CueCommands.addItems([first, last], to: doc, undoManager: undo)
        CueCommands.setActiveItem(id: last.id, in: doc)

        CueCommands.removeItem(id: last.id, document: doc, undoManager: undo)
        undo.undo()

        XCTAssertEqual(doc.model.items.map(\.id), [first.id, last.id])
        XCTAssertEqual(doc.model.activeItemID, last.id)
    }

    func test_renameItem_updatesDisplayName_undoRestores() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let item = makeItem(name: "a.wav")
        CueCommands.addItem(item, to: doc, undoManager: undo)

        CueCommands.renameItem(id: item.id, to: "Act 1", document: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items[0].media.displayName, "Act 1")

        undo.undo()
        XCTAssertEqual(doc.model.items[0].media.displayName, "a.wav")
    }

    func test_reorderItems_movesWithinArray_preservesActiveIdentity() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let first = makeItem(name: "a")
        let middle = makeItem(name: "b")
        let last = makeItem(name: "c")
        CueCommands.addItems([first, middle, last], to: doc, undoManager: undo)
        CueCommands.setActiveItem(id: middle.id, in: doc)

        CueCommands.reorderItems(from: IndexSet(integer: 2), to: 0, document: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items.map(\.id), [last.id, first.id, middle.id])
        XCTAssertEqual(doc.model.activeItemID, middle.id)

        undo.undo()
        XCTAssertEqual(doc.model.items.map(\.id), [first.id, middle.id, last.id])
    }

    func test_setActiveItem_isNotUndoable() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let first = makeItem(name: "a")
        let last = makeItem(name: "b")
        CueCommands.addItems([first, last], to: doc, undoManager: undo)
        let beforeCount = undo.canUndo ? 1 : 0

        CueCommands.setActiveItem(id: last.id, in: doc)

        XCTAssertEqual(doc.model.activeItemID, last.id)
        XCTAssertEqual(undo.canUndo ? 1 : 0, beforeCount, "setActiveItem must not register undo")
    }

    func test_cueMutations_scopedToActiveItem() throws {
        let doc = CueListDocument()
        let first = makeItem(name: "a")
        let second = makeItem(name: "b")
        CueCommands.addItems([first, second], to: doc, undoManager: nil)

        CueCommands.setActiveItem(id: first.id, in: doc)
        CueCommands.addCueAtPlayhead(time: 1.0, document: doc, undoManager: nil)

        CueCommands.setActiveItem(id: second.id, in: doc)
        CueCommands.addCueAtPlayhead(time: 2.0, document: doc, undoManager: nil)

        let firstCues = doc.model.items.first { $0.id == first.id }?.cues ?? []
        let secondCues = doc.model.items.first { $0.id == second.id }?.cues ?? []

        XCTAssertEqual(firstCues.count, 1)
        XCTAssertEqual(try XCTUnwrap(firstCues.first).time, 1.0, accuracy: 0.001)
        XCTAssertEqual(secondCues.count, 1)
        XCTAssertEqual(try XCTUnwrap(secondCues.first).time, 2.0, accuracy: 0.001)
    }

    // MARK: helpers

    private func makeItem(name: String) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 30,
                bookmarkData: Data([0x00])
            ),
            cues: []
        )
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
