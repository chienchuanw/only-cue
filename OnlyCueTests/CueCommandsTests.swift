import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsTests: XCTestCase {

    func test_addCueAtPlayhead_appendsCueAtGivenTime() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.25, document: document, undoManager: undo)

        let cues = activeCues(document)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].time, 5.25, accuracy: 0.001)
        XCTAssertTrue(undo.canUndo)
    }

    func test_addCueAtPlayhead_undoEmptiesList_redoRestoresCue() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        let originalId = try XCTUnwrap(activeCues(document).first?.id)

        undo.undo()
        XCTAssertEqual(activeCues(document).count, 0)

        undo.redo()
        XCTAssertEqual(activeCues(document).count, 1)
        XCTAssertEqual(activeCues(document)[0].id, originalId)
    }

    func test_delete_removesCue_undoRestoresIt() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)

        CueCommands.delete(cueId: cueId, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).count, 0)

        undo.undo()
        XCTAssertEqual(activeCues(document).count, 1)
        XCTAssertEqual(activeCues(document)[0].id, cueId)
        XCTAssertEqual(activeCues(document)[0].time, 1.0, accuracy: 0.001)
    }

    func test_rename_updatesName_undoRestoresPriorName() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)
        let originalName = activeCues(document)[0].name

        CueCommands.rename(cueId: cueId, to: "Chorus", document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document)[0].name, "Chorus")

        undo.undo()
        XCTAssertEqual(activeCues(document)[0].name, originalName)
    }

    func test_recolor_updatesColorHex_undoRestoresPriorColor() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)
        let originalColor = activeCues(document)[0].colorHex

        CueCommands.recolor(cueId: cueId, to: "#FF6B6B", document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document)[0].colorHex, "#FF6B6B")

        undo.undo()
        XCTAssertEqual(activeCues(document)[0].colorHex, originalColor)
    }

    func test_retime_updatesTime_undoRestoresPriorTime() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)

        CueCommands.retime(cueId: cueId, to: 7.5, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document)[0].time, 7.5, accuracy: 0.001)

        undo.undo()
        XCTAssertEqual(activeCues(document)[0].time, 1.0, accuracy: 0.001)
    }

    func test_addMultiple_keepsCuesSortedByTime() {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2.0, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 8.0, document: document, undoManager: undo)

        let times = activeCues(document).map(\.time)
        XCTAssertEqual(times, [2.0, 5.0, 8.0])
    }

    func test_addCueAtPlayhead_assignsDefaultCuePointTypeID() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        let defaultTypeID = try XCTUnwrap(document.model.defaultCuePointTypeID)

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)

        let cue = try XCTUnwrap(activeCues(document).first)
        XCTAssertEqual(cue.typeID, defaultTypeID)
    }

    func test_cueMutations_noActiveItem_areNoOps() {
        let document = CueListDocument()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        XCTAssertTrue(document.model.items.isEmpty)
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: helpers

    func makeDocumentWithItem() -> CueListDocument {
        let doc = CueListDocument()
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "test.wav",
                kind: .audio,
                duration: 60,
                bookmarkData: Data([0x00])
            ),
            cues: []
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id
        return doc
    }

    func activeCues(_ doc: CueListDocument) -> [Cue] {
        doc.model.activeItem?.cues ?? []
    }

    func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
