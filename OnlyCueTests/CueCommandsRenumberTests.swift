import XCTest
@testable import OnlyCue

/// #535: resequence the `cueNumber` of the selected cues in time order from a
/// start value. Pure relabel — cue times never change and unselected cues keep
/// their numbers.
@MainActor
final class CueCommandsRenumberTests: XCTestCase {

    func test_renumberSelected_assignsSequentialByTime_leavingTimesUnchanged() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 2, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 5, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 9, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(selected, start: 10, interval: 1, document: document, undoManager: undo)

        XCTAssertEqual(try XCTUnwrap(number(document, at: 2)), 10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(number(document, at: 5)), 11, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(number(document, at: 9)), 12, accuracy: 0.001)
        XCTAssertEqual(activeCues(document).map(\.time), [2, 5, 9])
    }

    func test_renumberSelected_leavesUnselectedCuesUntouched() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 2, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 5, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 9, document: document, undoManager: undo)
        let ids = Dictionary(uniqueKeysWithValues: activeCues(document).map { ($0.time, $0.id) })
        // Give the middle cue a pre-existing number, then renumber only the ends.
        CueCommands.setCueNumber(cueId: try XCTUnwrap(ids[5]), to: 99, document: document, undoManager: undo)
        let selected: Set<Cue.ID> = [try XCTUnwrap(ids[2]), try XCTUnwrap(ids[9])]

        CueCommands.renumberSelected(selected, start: 1, interval: 1, document: document, undoManager: undo)

        XCTAssertEqual(try XCTUnwrap(number(document, at: 2)), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(number(document, at: 9)), 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(number(document, at: 5)), 99, accuracy: 0.001)
    }

    func test_renumberSelected_respectsInterval() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(selected, start: 5, interval: 5, document: document, undoManager: undo)

        XCTAssertEqual(try XCTUnwrap(number(document, at: 1)), 5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(number(document, at: 2)), 10, accuracy: 0.001)
    }

    func test_renumberSelected_isOneUndoStep() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(selected, start: 3, interval: 1, document: document, undoManager: undo)
        XCTAssertEqual(activeCues(document).compactMap(\.cueNumber), [3, 4])

        undo.undo()
        XCTAssertEqual(activeCues(document).compactMap(\.cueNumber), [])
    }

    func test_renumberSelected_emptySet_isNoOp() {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 9, document: document, undoManager: undo)

        CueCommands.renumberSelected([], start: 1, interval: 1, document: document, undoManager: undo)

        XCTAssertNil(activeCues(document).first?.cueNumber)
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

    private func number(_ doc: CueListDocument, at time: TimeInterval) -> Double? {
        activeCues(doc).first { abs($0.time - time) < 0.0001 }?.cueNumber
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
