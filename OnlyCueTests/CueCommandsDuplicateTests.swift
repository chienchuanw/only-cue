import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsDuplicateTests: XCTestCase {

    func test_duplicateAtPlayhead_inheritsAllPropertiesExceptIdTimeCueNumber() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 12.0, document: document, undoManager: undo)
        let sourceID = try XCTUnwrap(activeCues(document).first?.id)
        CueCommands.rename(cueId: sourceID, to: "GO Wash", document: document, undoManager: undo)
        CueCommands.setNotes(cueId: sourceID, to: "clear out", document: document, undoManager: undo)
        CueCommands.setFadeTime(
            cueId: sourceID,
            to: FadeTime(fadeIn: 2.0, fadeOut: 0.5),
            document: document,
            undoManager: undo
        )
        let source = try XCTUnwrap(activeCues(document).first { $0.id == sourceID })

        CueCommands.duplicateAtPlayhead(cueId: sourceID, time: 30.0, document: document, undoManager: undo)

        let cues = activeCues(document)
        XCTAssertEqual(cues.count, 2)
        let duplicate = try XCTUnwrap(cues.first { $0.id != sourceID })
        XCTAssertEqual(duplicate.typeID, source.typeID)
        XCTAssertEqual(duplicate.name, source.name)
        XCTAssertEqual(duplicate.notes, source.notes)
        XCTAssertEqual(duplicate.fadeTime, source.fadeTime)
        XCTAssertEqual(duplicate.time, 30.0, accuracy: 0.001)
        XCTAssertNotEqual(duplicate.id, source.id)
        XCTAssertNil(duplicate.cueNumber, "duplicates are unnumbered; the user assigns a number manually")
    }

    func test_duplicateAtPlayhead_sourceCueIsNumbered_duplicateIsStillNil() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        let sourceID = try XCTUnwrap(activeCues(document).first?.id)
        CueCommands.setCueNumber(cueId: sourceID, to: 1.0, document: document, undoManager: undo)

        CueCommands.duplicateAtPlayhead(cueId: sourceID, time: 20.0, document: document, undoManager: undo)

        let duplicate = try XCTUnwrap(activeCues(document).first { $0.id != sourceID })
        XCTAssertEqual(activeCues(document).first { $0.id == sourceID }?.cueNumber, 1.0)
        XCTAssertNil(duplicate.cueNumber)
    }

    func test_duplicateAtPlayhead_undoRemovesDuplicate_redoRestores() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        let sourceID = try XCTUnwrap(activeCues(document).first?.id)

        CueCommands.duplicateAtPlayhead(cueId: sourceID, time: 20.0, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).count, 2)

        undo.undo()
        XCTAssertEqual(activeCues(document).count, 1)

        undo.redo()
        XCTAssertEqual(activeCues(document).count, 2)
    }

    func test_duplicateAtPlayhead_unknownCueId_isSilentNoOp() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        let countBefore = activeCues(document).count

        CueCommands.duplicateAtPlayhead(cueId: UUID(), time: 20.0, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).count, countBefore)
    }

    // MARK: helpers

    private func makeDocumentWithItem() -> CueListDocument {
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

    private func activeCues(_ doc: CueListDocument) -> [Cue] {
        doc.model.activeItem?.cues ?? []
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
