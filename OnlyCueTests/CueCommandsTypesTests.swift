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

    func test_removeCuePointType_reassignsReferencedCues_andDeletes_undoRestoresBoth() throws {
        let document = makeDocumentWithItem()
        let undo = makeUndoManager()
        let defaultID = try XCTUnwrap(document.model.defaultCuePointTypeID)
        let lighting = CuePointType(id: UUID(), name: "Lighting", colorHex: "#FF6B6B")
        CueCommands.addCuePointType(lighting, document: document, undoManager: undo)

        // Two cues, both on Lighting.
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2.0, document: document, undoManager: undo)
        let cueIDs = activeCues(document).map(\.id)
        for cueID in cueIDs {
            CueCommands.setType(cueId: cueID, to: lighting.id, document: document, undoManager: undo)
        }
        XCTAssertTrue(activeCues(document).allSatisfy { $0.typeID == lighting.id })

        // Delete Lighting; the two cues should be reassigned to the default.
        CueCommands.removeCuePointType(
            id: lighting.id,
            reassignTo: defaultID,
            document: document,
            undoManager: undo
        )
        XCTAssertFalse(document.model.cuePointTypes.contains(where: { $0.id == lighting.id }))
        XCTAssertTrue(
            activeCues(document).allSatisfy { $0.typeID == defaultID },
            "all cues must be reassigned to the default Type"
        )

        // Undo restores both the Type and the cues' typeIDs.
        undo.undo()
        XCTAssertTrue(document.model.cuePointTypes.contains(where: { $0.id == lighting.id }))
        XCTAssertTrue(activeCues(document).allSatisfy { $0.typeID == lighting.id })
    }

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
