import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsTempoTests: XCTestCase {

    private func makeDocumentWithItem() -> (CueListDocument, MediaItem.ID) {
        let doc = CueListDocument()
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "song.wav", kind: .audio, duration: 200, bookmarkData: Data([0x00])),
            cues: []
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id
        return (doc, item.id)
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func tempoMap(_ doc: CueListDocument, _ id: MediaItem.ID) -> TempoMap {
        doc.model.items.first { $0.id == id }?.tempoMap ?? TempoMap()
    }

    func test_setTempoMap_appliesAndIsOneUndoStep() {
        let (doc, id) = makeDocumentWithItem()
        let undo = makeUndoManager()
        let map = TempoMap(sections: [TempoSection(startSeconds: 0, bpm: 128, beatsPerBar: 4)])

        CueCommands.setTempoMap(map, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id).sections.first?.bpm, 128)

        undo.undo()
        XCTAssertTrue(tempoMap(doc, id).isEmpty)
        undo.redo()
        XCTAssertEqual(tempoMap(doc, id).sections.first?.bpm, 128)
    }

    func test_setTempoMap_sameValue_isNoOp() {
        let (doc, id) = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setTempoMap(TempoMap(), item: id, document: doc, undoManager: undo)
        XCTAssertFalse(undo.canUndo, "setting an already-empty map to empty must not register an undo step")
    }

    func test_addTempoSection_emptyThenNonEmpty() {
        let (doc, id) = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addTempoSection(atSeconds: 30, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id).sections.count, 1)
        XCTAssertEqual(tempoMap(doc, id).sections.first?.startSeconds, 0)

        CueCommands.addTempoSection(atSeconds: 50, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id).sections.count, 2)

        undo.undo()
        XCTAssertEqual(tempoMap(doc, id).sections.count, 1)
    }

    func test_splitTempoSection_addsABoundary_andNoOpsOnAnExistingOne() {
        let (doc, id) = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setTempoMap(TempoMap.singleSection(bpm: 120, beatsPerBar: 4), item: id, document: doc, undoManager: undo)

        CueCommands.splitTempoSection(atSeconds: 40, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id).sections.count, 2)
        XCTAssertEqual(tempoMap(doc, id).sections[1].startSeconds, 40)

        let before = tempoMap(doc, id)
        CueCommands.splitTempoSection(atSeconds: 40, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id), before, "splitting on an existing boundary is a no-op")
    }

    func test_removeTempoSection_dropsItAndUndoRestores() {
        let (doc, id) = makeDocumentWithItem()
        let undo = makeUndoManager()
        let twoSections = TempoMap(sections: [
            TempoSection(startSeconds: 0, bpm: 120),
            TempoSection(startSeconds: 60, bpm: 140)
        ])
        CueCommands.setTempoMap(twoSections, item: id, document: doc, undoManager: undo)
        let secondID = tempoMap(doc, id).sections[1].id

        CueCommands.removeTempoSection(secondID, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id).sections.count, 1)

        undo.undo()
        XCTAssertEqual(tempoMap(doc, id).sections.count, 2)
    }

    func test_updateTempoSection_changesBPM_andAllNilIsNoOp() {
        let (doc, id) = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setTempoMap(TempoMap.singleSection(bpm: 120, beatsPerBar: 4), item: id, document: doc, undoManager: undo)
        let sectionID = tempoMap(doc, id).sections[0].id

        CueCommands.updateTempoSection(sectionID, bpm: 90, beatsPerBar: 3, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id).sections[0].bpm, 90)
        XCTAssertEqual(tempoMap(doc, id).sections[0].beatsPerBar, 3)

        let before = tempoMap(doc, id)
        CueCommands.updateTempoSection(sectionID, item: id, document: doc, undoManager: undo)
        XCTAssertEqual(tempoMap(doc, id), before, "an update with no changed fields is a no-op")

        undo.undo()
        XCTAssertEqual(tempoMap(doc, id).sections[0].bpm, 120)
    }

    func test_clearTempoMap_emptiesItAndUndoRestores() {
        let (doc, id) = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setTempoMap(TempoMap.singleSection(bpm: 120), item: id, document: doc, undoManager: undo)
        CueCommands.clearTempoMap(item: id, document: doc, undoManager: undo)
        XCTAssertTrue(tempoMap(doc, id).isEmpty)
        undo.undo()
        XCTAssertFalse(tempoMap(doc, id).isEmpty)
    }
}
