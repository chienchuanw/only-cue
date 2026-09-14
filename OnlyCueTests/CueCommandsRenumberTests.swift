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

    // MARK: - domain (#830)
    //
    // `renumberSelected` computes `start + index * interval` and writes it
    // straight onto the cue — the only `cueNumber` writer that never consults
    // `CueNumberValidator`. `RenumberCuesSheet` binds `start` to a plain
    // `TextField`, and the neighbouring `Stepper(in:)` constrains only the
    // stepper buttons, so a typed value reaches this command unfiltered. That
    // makes #830's `-1.-5` token reachable from the UI, not just from a
    // hand-edited document.

    func test_renumberSelected_rejectsNegativeStart() {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(selected, start: -1.5, interval: 1, document: document, undoManager: undo)

        XCTAssertEqual(activeCues(document).compactMap(\.cueNumber), [])
    }

    func test_renumberSelected_rejectsStartBelowTheMinimum() {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(selected, start: 0, interval: 1, document: document, undoManager: undo)

        XCTAssertEqual(activeCues(document).compactMap(\.cueNumber), [])
    }

    // A run that starts in range but walks out of it is rejected whole: half a
    // renumber is worse than none, and the caller asked for something the
    // numbering domain cannot express.
    func test_renumberSelected_rejectsRunThatLeavesTheDomain() {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(selected, start: 9999.5, interval: 1, document: document, undoManager: undo)

        XCTAssertEqual(activeCues(document).compactMap(\.cueNumber), [])
    }

    func test_renumberSelected_rejectsNonFiniteStart() {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(selected, start: .nan, interval: 1, document: document, undoManager: undo)
        CueCommands.renumberSelected(selected, start: 1, interval: .infinity, document: document, undoManager: undo)

        XCTAssertEqual(activeCues(document).compactMap(\.cueNumber), [])
    }

    // The bounds themselves stay usable — the guard rejects, it does not shrink.
    func test_renumberSelected_acceptsTheDomainBounds() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1, document: document, undoManager: undo)
        let selected = Set(activeCues(document).map(\.id))

        CueCommands.renumberSelected(
            selected, start: CueNumberValidator.minimum, interval: 1, document: document, undoManager: undo
        )
        XCTAssertEqual(try XCTUnwrap(number(document, at: 1)), CueNumberValidator.minimum, accuracy: 0.0001)

        CueCommands.renumberSelected(
            selected, start: CueNumberValidator.maximum, interval: 1, document: document, undoManager: undo
        )
        XCTAssertEqual(try XCTUnwrap(number(document, at: 1)), CueNumberValidator.maximum, accuracy: 0.0001)
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
