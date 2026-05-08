import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsTypesTests: XCTestCase {

    func test_addCuePointType_appends_undoRemoves() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        let initialCount = document.model.cuePointTypes.count
        let newType = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF6B6B")

        CueCommands.addCuePointType(newType, document: document, undoManager: undo)
        XCTAssertEqual(document.model.cuePointTypes.count, initialCount + 1)
        XCTAssertEqual(document.model.cuePointTypes.last?.id, newType.id)

        undo.undo()
        XCTAssertEqual(document.model.cuePointTypes.count, initialCount)
    }

    func test_setCuePointTypeName_updates_undoRestores() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        let typeID = try XCTUnwrap(document.model.cuePointTypes.first?.id)
        let originalName = try XCTUnwrap(document.model.cuePointTypes.first?.name)

        CueCommands.setCuePointTypeName(id: typeID, to: "Lighting", document: document, undoManager: undo)
        XCTAssertEqual(document.model.cuePointTypes.first?.name, "Lighting")

        undo.undo()
        XCTAssertEqual(document.model.cuePointTypes.first?.name, originalName)
    }

    func test_setCuePointTypeColor_updates_undoRestores() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        let typeID = try XCTUnwrap(document.model.cuePointTypes.first?.id)
        let originalColor = try XCTUnwrap(document.model.cuePointTypes.first?.colorHex)

        CueCommands.setCuePointTypeColor(id: typeID, to: "#FF6B6B", document: document, undoManager: undo)
        XCTAssertEqual(document.model.cuePointTypes.first?.colorHex, "#FF6B6B")

        undo.undo()
        XCTAssertEqual(document.model.cuePointTypes.first?.colorHex, originalColor)
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
