import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsBatchRetimeTests: XCTestCase {

    func test_nudgeCues_shiftsEverySelectedCueAndLeavesOthers() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 10, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 20, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 30, document: document, undoManager: undo)
        let ids = Dictionary(uniqueKeysWithValues: activeCues(document).map { ($0.time, $0.id) })
        let selected: Set<Cue.ID> = [try XCTUnwrap(ids[10]), try XCTUnwrap(ids[30])]

        CueCommands.nudgeCues(selected, by: 2, document: document, undoManager: undo)

        let byID = Dictionary(uniqueKeysWithValues: activeCues(document).map { ($0.id, $0.time) })
        XCTAssertEqual(byID[try XCTUnwrap(ids[10])] ?? -1, 12, accuracy: 0.001)
        XCTAssertEqual(byID[try XCTUnwrap(ids[30])] ?? -1, 32, accuracy: 0.001)
        XCTAssertEqual(byID[try XCTUnwrap(ids[20])] ?? -1, 20, accuracy: 0.001)
        // Re-sorted by time.
        XCTAssertEqual(activeCues(document).map(\.time), [12, 20, 32])
    }

    func test_nudgeCues_isOneUndoStep_revertingAllSelected() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 5, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 6, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 7, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.nudgeCues(selected, by: 1.0 / 30.0, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).map { ($0.time * 30).rounded() }, [151, 181, 211])

        undo.undo()
        XCTAssertEqual(activeCues(document).map(\.time), [5, 6, 7])
        undo.redo()
        XCTAssertEqual(activeCues(document).map { ($0.time * 30).rounded() }, [151, 181, 211])
    }

    func test_nudgeCues_clampsAtZero() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 0.01, document: document, undoManager: undo)
        let id = try XCTUnwrap(activeCues(document).first?.id)

        CueCommands.nudgeCues([id], by: -5, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).first?.time ?? -1, 0, accuracy: 0.0001)
    }

    func test_nudgeCues_emptySet_isNoOp() {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 9, document: document, undoManager: undo)
        CueCommands.nudgeCues([], by: 1, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).first?.time, 9)
    }

    func test_snapCues_movesEverySelectedCueToTheTarget() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 50, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.snapCues(selected, to: 12.5, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).map(\.time), [12.5, 12.5])

        undo.undo()
        XCTAssertEqual(activeCues(document).map(\.time), [1, 50])
    }

    // MARK: - Helpers

    private func makeDocumentWithItem() -> CueListDocument {
        let doc = CueListDocument()
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "test.wav", kind: .audio, duration: 120, bookmarkData: Data([0x00])),
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
