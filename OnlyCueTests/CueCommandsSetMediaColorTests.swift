import XCTest
@testable import OnlyCue

/// Coverage for `CueCommands.setMediaColor` — the undoable per-clip colour tag
/// shown as a leading stripe in the media panel (#782). `@MainActor` because
/// the `CueCommands` extension is.
@MainActor
final class CueCommandsSetMediaColorTests: XCTestCase {

    /// The palette the command accepts. Colours are authored, not free-form:
    /// the picker only ever offers these eight, so anything else reaching the
    /// command means a caller bug or a hand-edited `.cuelist`.
    private var green: String { CuePointType.defaultPalette[3] }
    private var blue: String { CuePointType.defaultPalette[5] }

    // MARK: - Assigning

    func test_setMediaColor_setsColorOnTargetItem() throws {
        let doc = makeDocument(itemCount: 1)
        let id = doc.model.items[0].id

        CueCommands.setMediaColor(itemID: id, colorHex: green, document: doc, undoManager: nil)

        XCTAssertEqual(doc.model.items[0].colorHex, green)
    }

    func test_setMediaColor_leavesOtherItemsUntouched() throws {
        let doc = makeDocument(itemCount: 3)
        let id = doc.model.items[1].id

        CueCommands.setMediaColor(itemID: id, colorHex: green, document: doc, undoManager: nil)

        XCTAssertNil(doc.model.items[0].colorHex)
        XCTAssertEqual(doc.model.items[1].colorHex, green)
        XCTAssertNil(doc.model.items[2].colorHex)
    }

    func test_setMediaColor_isASingleUndoStep_andUndoRestoresPreviousValue() throws {
        let doc = makeDocument(itemCount: 1)
        let id = doc.model.items[0].id
        let undo = makeUndoManager()

        CueCommands.setMediaColor(itemID: id, colorHex: green, document: doc, undoManager: undo)
        CueCommands.setMediaColor(itemID: id, colorHex: blue, document: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items[0].colorHex, blue)

        // One undo steps back exactly one assignment, not the whole run.
        undo.undo()
        XCTAssertEqual(doc.model.items[0].colorHex, green)
        undo.undo()
        XCTAssertNil(doc.model.items[0].colorHex)

        undo.redo()
        XCTAssertEqual(doc.model.items[0].colorHex, green)
    }

    // MARK: - Clearing

    func test_setMediaColor_nilClearsAnExistingColor() throws {
        let doc = makeDocument(itemCount: 1)
        let id = doc.model.items[0].id
        let undo = makeUndoManager()

        CueCommands.setMediaColor(itemID: id, colorHex: green, document: doc, undoManager: undo)
        CueCommands.setMediaColor(itemID: id, colorHex: nil, document: doc, undoManager: undo)

        XCTAssertNil(doc.model.items[0].colorHex)
        undo.undo()
        XCTAssertEqual(doc.model.items[0].colorHex, green)
    }

    // MARK: - No-ops

    func test_setMediaColor_unknownItemID_isANoOp() throws {
        let doc = makeDocument(itemCount: 1)
        let undo = makeUndoManager()

        CueCommands.setMediaColor(itemID: UUID(), colorHex: green, document: doc, undoManager: undo)

        XCTAssertNil(doc.model.items[0].colorHex)
        XCTAssertFalse(undo.canUndo)
    }

    func test_setMediaColor_settingTheCurrentColor_registersNoUndo() throws {
        let doc = makeDocument(itemCount: 1)
        let id = doc.model.items[0].id
        CueCommands.setMediaColor(itemID: id, colorHex: green, document: doc, undoManager: nil)
        let undo = makeUndoManager()

        CueCommands.setMediaColor(itemID: id, colorHex: green, document: doc, undoManager: undo)

        XCTAssertEqual(doc.model.items[0].colorHex, green)
        XCTAssertFalse(undo.canUndo)
    }

    func test_setMediaColor_nonPaletteHex_isRejected() throws {
        let doc = makeDocument(itemCount: 1)
        let id = doc.model.items[0].id
        let undo = makeUndoManager()

        CueCommands.setMediaColor(itemID: id, colorHex: "#123456", document: doc, undoManager: undo)

        XCTAssertNil(doc.model.items[0].colorHex)
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: - Helpers

    private func makeDocument(itemCount: Int) -> CueListDocument {
        let doc = CueListDocument()
        doc.model.items = (0..<itemCount).map { index in
            MediaItem(
                id: UUID(),
                media: MediaReference(
                    displayName: "clip-\(index).wav",
                    kind: .audio,
                    duration: 10,
                    bookmarkData: Data()
                ),
                cues: []
            )
        }
        doc.model.activeItemID = doc.model.items.first?.id
        return doc
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
