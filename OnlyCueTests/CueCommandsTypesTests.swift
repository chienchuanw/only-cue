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

    func test_setCuePointTypeHotkey_setsTarget_undoRestores() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        let typeID = try XCTUnwrap(document.model.cuePointTypes.first?.id)

        CueCommands.setCuePointTypeHotkey(id: typeID, to: 1, document: document, undoManager: undo)
        XCTAssertEqual(document.model.cuePointTypes.first?.hotkey, 1)

        undo.undo()
        XCTAssertNil(document.model.cuePointTypes.first?.hotkey)
    }

    func test_setCuePointTypeHotkey_clearsPriorHolder_undoRestoresBoth() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        let typeA = try XCTUnwrap(document.model.cuePointTypes.first?.id)
        let typeB = CuePointType(id: UUID(), name: "Sound", colorHex: "#FF6B6B")
        CueCommands.addCuePointType(typeB, document: document, undoManager: undo)
        CueCommands.setCuePointTypeHotkey(id: typeA, to: 1, document: document, undoManager: undo)
        XCTAssertEqual(document.model.cuePointTypes.first(where: { $0.id == typeA })?.hotkey, 1)

        // Now move hotkey 1 to Type B; Type A's hotkey should clear.
        CueCommands.setCuePointTypeHotkey(id: typeB.id, to: 1, document: document, undoManager: undo)
        XCTAssertEqual(document.model.cuePointTypes.first(where: { $0.id == typeB.id })?.hotkey, 1)
        XCTAssertNil(
            document.model.cuePointTypes.first(where: { $0.id == typeA })?.hotkey,
            "move semantics: prior holder must clear"
        )

        undo.undo()
        XCTAssertEqual(document.model.cuePointTypes.first(where: { $0.id == typeA })?.hotkey, 1)
        XCTAssertNil(document.model.cuePointTypes.first(where: { $0.id == typeB.id })?.hotkey)
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
