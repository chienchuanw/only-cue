import XCTest
@testable import OnlyCue

/// Pins the timeline-breakdown lane-visibility mutations on `CueCommands` —
/// `CuePointType.isVisible` flips through the command seam (so it's undoable
/// and lands in the document's persisted model), and `showAllCuePointTypes`
/// clears every hidden lane in one undo step.
@MainActor
final class CueCommandsVisibilityTests: XCTestCase {

    func test_setVisibility_hidesAndShows_withUndoAndRedo() throws {
        let doc = makeDocumentWithTypes()
        let undo = makeUndoManager()
        let lighting = try XCTUnwrap(doc.model.cuePointTypes.first)
        XCTAssertTrue(lighting.isVisible)

        CueCommands.setCuePointTypeVisibility(id: lighting.id, to: false, document: doc, undoManager: undo)
        XCTAssertFalse(visibility(doc, lighting.id))

        undo.undo()
        XCTAssertTrue(visibility(doc, lighting.id))

        undo.redo()
        XCTAssertFalse(visibility(doc, lighting.id))
    }

    func test_visibilityChange_landsInTheDocumentSnapshot() throws {
        let doc = makeDocumentWithTypes()
        let lighting = try XCTUnwrap(doc.model.cuePointTypes.first)
        CueCommands.setCuePointTypeVisibility(id: lighting.id, to: false, document: doc, undoManager: nil)

        let snapshot = try doc.snapshot(contentType: .cueList)
        XCTAssertEqual(snapshot.cuePointTypes.first(where: { $0.id == lighting.id })?.isVisible, false)
    }

    func test_showAll_revealsEveryHiddenLane_inOneUndoStep() {
        let doc = makeDocumentWithTypes()
        let undo = makeUndoManager()
        for type in doc.model.cuePointTypes {
            CueCommands.setCuePointTypeVisibility(id: type.id, to: false, document: doc, undoManager: nil)
        }
        XCTAssertTrue(doc.model.cuePointTypes.allSatisfy { !$0.isVisible })

        CueCommands.showAllCuePointTypes(document: doc, undoManager: undo)
        XCTAssertTrue(doc.model.cuePointTypes.allSatisfy { $0.isVisible })

        undo.undo()
        XCTAssertTrue(doc.model.cuePointTypes.allSatisfy { !$0.isVisible }, "one undo restores all hidden lanes")
    }

    // MARK: - Helpers

    private func makeDocumentWithTypes() -> CueListDocument {
        let doc = CueListDocument()
        doc.model.cuePointTypes = [
            CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF0000"),
            CuePointType(id: UUID(), name: "Sound", colorHex: "#00FF00"),
            CuePointType(id: UUID(), name: "Video", colorHex: "#0000FF")
        ]
        return doc
    }

    private func visibility(_ doc: CueListDocument, _ id: UUID) -> Bool {
        doc.model.cuePointTypes.first(where: { $0.id == id })?.isVisible ?? false
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
