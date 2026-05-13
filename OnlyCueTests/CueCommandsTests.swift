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

    func test_addCueAtPlayhead_leavesCueNumberNil() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)

        let cue = try XCTUnwrap(activeCues(document).first)
        XCTAssertNil(cue.cueNumber, "new cues are unnumbered; user assigns the number manually")
    }

    func test_addCueAtPlayhead_amongExistingNumberedCues_stillLeavesNewCueNil() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let firstID = try XCTUnwrap(activeCues(document).first?.id)
        CueCommands.setCueNumber(cueId: firstID, to: 1.0, document: document, undoManager: undo)

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)

        let cues = activeCues(document)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].cueNumber, 1.0, "existing numbered cue keeps its number")
        XCTAssertNil(cues[1].cueNumber, "newly added cue is unnumbered regardless of siblings")
    }

    func test_addCueAtPlayhead_withExplicitTypeID_assignsThatTypeID_undoRemoves() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        let lighting = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF6B6B", hotkey: 1)
        document.model.cuePointTypes.append(lighting)

        CueCommands.addCueAtPlayhead(time: 4.25, typeID: lighting.id, document: document, undoManager: undo)

        let cue = try XCTUnwrap(activeCues(document).first)
        XCTAssertEqual(cue.time, 4.25, accuracy: 0.001)
        XCTAssertEqual(cue.typeID, lighting.id, "explicit typeID overload must use the passed Type")

        undo.undo()
        XCTAssertEqual(activeCues(document).count, 0)
    }

    func test_setType_updatesTypeID_undoRestoresPriorTypeID() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        let originalTypeID = try XCTUnwrap(document.model.defaultCuePointTypeID)
        let newType = CuePointType(
            id: UUID(),
            name: "Sound",
            colorHex: "#FF6B6B",
            defaultFadeTime: 0,
            defaultNamePattern: "Sound",
            hotkey: nil,
            isVisible: true,
            isExportEnabled: true
        )
        document.model.cuePointTypes.append(newType)
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)

        CueCommands.setType(cueId: cueId, to: newType.id, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document)[0].typeID, newType.id)

        undo.undo()
        XCTAssertEqual(activeCues(document)[0].typeID, originalTypeID)
    }

    func test_setCueNumber_updatesNumber_undoRestoresPriorNumber() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)
        let originalNumber = activeCues(document)[0].cueNumber

        CueCommands.setCueNumber(cueId: cueId, to: 1.5, document: document, undoManager: undo)
        XCTAssertEqual(try XCTUnwrap(activeCues(document)[0].cueNumber), 1.5, accuracy: 0.0001)

        undo.undo()
        XCTAssertEqual(activeCues(document)[0].cueNumber, originalNumber)
    }

    func test_setFadeTime_updatesFade_undoRestoresPriorFade() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)
        let originalFade = activeCues(document)[0].fadeTime

        let split = FadeTime(fadeIn: 1.0, fadeOut: 2.0)
        CueCommands.setFadeTime(cueId: cueId, to: split, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document)[0].fadeTime, split)

        undo.undo()
        XCTAssertEqual(activeCues(document)[0].fadeTime, originalFade)
    }

    func test_setNotes_updatesNotes_undoRestoresPriorNotes() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(activeCues(document).first?.id)
        let originalNotes = activeCues(document)[0].notes

        CueCommands.setNotes(cueId: cueId, to: "Wait for the breath", document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document)[0].notes, "Wait for the breath")

        undo.undo()
        XCTAssertEqual(activeCues(document)[0].notes, originalNotes)
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
