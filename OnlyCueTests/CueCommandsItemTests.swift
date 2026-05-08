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
        let a = makeItem(name: "a"); let b = makeItem(name: "b"); let c = makeItem(name: "c")
        CueCommands.addItems([a, b, c], to: doc, undoManager: nil)
        CueCommands.setActiveItem(id: b.id, in: doc)

        CueCommands.removeItem(id: b.id, document: doc, undoManager: nil)
        XCTAssertEqual(doc.model.items.map(\.id), [a.id, c.id])
        XCTAssertEqual(doc.model.activeItemID, c.id)
    }

    func test_removeItem_lastInList_advancesActiveToPrevious() {
        let doc = CueListDocument()
        let a = makeItem(name: "a"); let b = makeItem(name: "b")
        CueCommands.addItems([a, b], to: doc, undoManager: nil)
        CueCommands.setActiveItem(id: b.id, in: doc)

        CueCommands.removeItem(id: b.id, document: doc, undoManager: nil)
        XCTAssertEqual(doc.model.activeItemID, a.id)
    }

    func test_removeItem_onlyItem_clearsActive() {
        let doc = CueListDocument()
        let a = makeItem(name: "a")
        CueCommands.addItem(a, to: doc, undoManager: nil)

        CueCommands.removeItem(id: a.id, document: doc, undoManager: nil)
        XCTAssertNil(doc.model.activeItemID)
        XCTAssertTrue(doc.model.items.isEmpty)
    }

    func test_removeItem_undoRestoresItemAndPriorActive() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let a = makeItem(name: "a"); let b = makeItem(name: "b")
        CueCommands.addItems([a, b], to: doc, undoManager: undo)
        CueCommands.setActiveItem(id: b.id, in: doc)

        CueCommands.removeItem(id: b.id, document: doc, undoManager: undo)
        undo.undo()

        XCTAssertEqual(doc.model.items.map(\.id), [a.id, b.id])
        XCTAssertEqual(doc.model.activeItemID, b.id)
    }

    func test_renameItem_updatesDisplayName_undoRestores() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let a = makeItem(name: "a.wav")
        CueCommands.addItem(a, to: doc, undoManager: undo)

        CueCommands.renameItem(id: a.id, to: "Act 1", document: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items[0].media.displayName, "Act 1")

        undo.undo()
        XCTAssertEqual(doc.model.items[0].media.displayName, "a.wav")
    }

    func test_reorderItems_movesWithinArray_preservesActiveIdentity() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let a = makeItem(name: "a"); let b = makeItem(name: "b"); let c = makeItem(name: "c")
        CueCommands.addItems([a, b, c], to: doc, undoManager: undo)
        CueCommands.setActiveItem(id: b.id, in: doc)

        CueCommands.reorderItems(from: IndexSet(integer: 2), to: 0, document: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(doc.model.activeItemID, b.id)

        undo.undo()
        XCTAssertEqual(doc.model.items.map(\.id), [a.id, b.id, c.id])
    }

    func test_setActiveItem_isNotUndoable() {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        let a = makeItem(name: "a"); let b = makeItem(name: "b")
        CueCommands.addItems([a, b], to: doc, undoManager: undo)
        let beforeCount = undo.canUndo ? 1 : 0

        CueCommands.setActiveItem(id: b.id, in: doc)

        XCTAssertEqual(doc.model.activeItemID, b.id)
        XCTAssertEqual(undo.canUndo ? 1 : 0, beforeCount, "setActiveItem must not register undo")
    }

    func test_cueMutations_scopedToActiveItem() throws {
        let doc = CueListDocument()
        let a = makeItem(name: "a"); let b = makeItem(name: "b")
        CueCommands.addItems([a, b], to: doc, undoManager: nil)

        CueCommands.setActiveItem(id: a.id, in: doc)
        CueCommands.addCueAtPlayhead(time: 1.0, document: doc, undoManager: nil)

        CueCommands.setActiveItem(id: b.id, in: doc)
        CueCommands.addCueAtPlayhead(time: 2.0, document: doc, undoManager: nil)

        let aCues = doc.model.items.first { $0.id == a.id }?.cues ?? []
        let bCues = doc.model.items.first { $0.id == b.id }?.cues ?? []

        XCTAssertEqual(aCues.count, 1)
        XCTAssertEqual(try XCTUnwrap(aCues.first).time, 1.0, accuracy: 0.001)
        XCTAssertEqual(bCues.count, 1)
        XCTAssertEqual(try XCTUnwrap(bCues.first).time, 2.0, accuracy: 0.001)
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
