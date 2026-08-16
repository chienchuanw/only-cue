import XCTest
@testable import OnlyCue

/// #752: change the `typeID` of every selected cue at once. Pure retype —
/// only `typeID` changes; time / name / fade are preserved. Committed as a
/// single undo step, mirroring `renumberSelected`.
@MainActor
final class CueCommandsSetTypeForSelectedTests: XCTestCase {

    func test_setTypeForSelected_changesAllSelected() throws {
        let document = makeDocument()
        let undo = makeUndoManager()
        let ids = Set(activeCues(document).map(\.id))

        CueCommands.setTypeForSelected(ids, to: typeB, document: document, undoManager: undo)

        XCTAssertEqual(Set(activeCues(document).map(\.typeID)), [typeB])
    }

    func test_setTypeForSelected_leavesUnselectedCuesUntouched() throws {
        let document = makeDocument()
        let undo = makeUndoManager()
        let firstID = try XCTUnwrap(activeCues(document).first?.id)

        CueCommands.setTypeForSelected([firstID], to: typeB, document: document, undoManager: undo)

        let byID = Dictionary(uniqueKeysWithValues: activeCues(document).map { ($0.id, $0.typeID) })
        XCTAssertEqual(byID[firstID], typeB)
        for cue in activeCues(document) where cue.id != firstID {
            XCTAssertEqual(cue.typeID, typeA)
        }
    }

    func test_setTypeForSelected_isOneUndoStep() throws {
        let document = makeDocument()
        let undo = makeUndoManager()
        let ids = Set(activeCues(document).map(\.id))

        CueCommands.setTypeForSelected(ids, to: typeB, document: document, undoManager: undo)
        XCTAssertEqual(Set(activeCues(document).map(\.typeID)), [typeB])

        undo.undo()
        XCTAssertEqual(activeCues(document).map(\.typeID), [typeA, typeA, typeB])
    }

    func test_setTypeForSelected_preservesTimeNameAndFade() throws {
        let document = makeDocument()
        let undo = makeUndoManager()
        let before = activeCues(document)
        let ids = Set(before.map(\.id))

        CueCommands.setTypeForSelected(ids, to: typeB, document: document, undoManager: undo)

        let after = activeCues(document)
        XCTAssertEqual(after.map(\.time), before.map(\.time))
        XCTAssertEqual(after.map(\.name), before.map(\.name))
        XCTAssertEqual(after.map(\.fadeTime), before.map(\.fadeTime))
    }

    func test_setTypeForSelected_emptySet_isNoOp() {
        let document = makeDocument()
        let undo = makeUndoManager()

        CueCommands.setTypeForSelected([], to: typeB, document: document, undoManager: undo)

        XCTAssertEqual(activeCues(document).map(\.typeID), [typeA, typeA, typeB])
    }

    // MARK: - Fixtures

    private let typeA = UUID()
    private let typeB = UUID()

    /// Three cues in time order: two of type A, one of type B, each with a
    /// distinct fade so preservation is observable.
    private func makeDocument() -> CueListDocument {
        let doc = CueListDocument()
        doc.model.cuePointTypes = [
            CuePointType(id: typeA, name: "Alpha", colorHex: "#4ECDC4"),
            CuePointType(id: typeB, name: "Beta", colorHex: "#FFD93D")
        ]
        let cues = [
            makeCue(typeID: typeA, name: "one", time: 1, fade: 1),
            makeCue(typeID: typeA, name: "two", time: 2, fade: 2),
            makeCue(typeID: typeB, name: "three", time: 3, fade: 3)
        ]
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "test.wav", kind: .audio, duration: 120, bookmarkData: Data([0x00])),
            cues: cues
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id
        return doc
    }

    private func makeCue(typeID: UUID, name: String, time: TimeInterval, fade: TimeInterval) -> Cue {
        Cue(id: UUID(), typeID: typeID, cueNumber: nil, name: name, time: time, notes: "", fadeTime: .symmetric(fade))
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
