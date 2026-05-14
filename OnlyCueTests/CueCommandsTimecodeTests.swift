import XCTest
@testable import OnlyCue

/// Coverage for `CueCommands.setProjectTimecodeSettings` — undoable edits to
/// `ProjectModel.timecodeSettings` (epic #33 leaf 6, timecode half).
/// `@MainActor` because the `CueCommands` extension is.
@MainActor
final class CueCommandsTimecodeTests: XCTestCase {

    func test_setProjectTimecodeSettings_changesModel_andUndoRestores() throws {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        XCTAssertEqual(doc.model.timecodeSettings, .default)

        let newSettings = ProjectTimecodeSettings(framerate: .fps25)
        CueCommands.setProjectTimecodeSettings(newSettings, document: doc, undoManager: undo)
        XCTAssertEqual(doc.model.timecodeSettings, newSettings)

        undo.undo()
        XCTAssertEqual(doc.model.timecodeSettings, .default)
        undo.redo()
        XCTAssertEqual(doc.model.timecodeSettings, newSettings)
    }

    func test_setProjectTimecodeSettings_noOpWhenUnchanged_registersNoUndo() throws {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        CueCommands.setProjectTimecodeSettings(.default, document: doc, undoManager: undo)
        XCTAssertFalse(undo.canUndo)
        XCTAssertEqual(doc.model.timecodeSettings, .default)
    }

    func test_change_landsInDocumentSnapshot() throws {
        let doc = CueListDocument()
        CueCommands.setProjectTimecodeSettings(
            ProjectTimecodeSettings(framerate: .fps30drop),
            document: doc,
            undoManager: nil
        )
        let snapshot = try doc.snapshot(contentType: .cueList)
        XCTAssertEqual(snapshot.timecodeSettings.framerate, .fps30drop)
    }

    // MARK: - setLTCMuted

    func test_setLTCMuted_flipsField_andIsUndoable() throws {
        let doc = CueListDocument()
        let item = Self.fixtureItem()
        doc.model.items = [item]
        let undo = makeUndoManager()

        CueCommands.setLTCMuted(itemID: item.id, muted: true, document: doc, undoManager: undo)
        XCTAssertTrue(doc.model.items[0].ltcMuted)

        undo.undo()
        XCTAssertFalse(doc.model.items[0].ltcMuted)
        undo.redo()
        XCTAssertTrue(doc.model.items[0].ltcMuted)
    }

    func test_setLTCMuted_noOpWhenUnchanged_registersNoUndo() throws {
        let doc = CueListDocument()
        let item = Self.fixtureItem()
        doc.model.items = [item]
        let undo = makeUndoManager()

        CueCommands.setLTCMuted(itemID: item.id, muted: false, document: doc, undoManager: undo)
        XCTAssertFalse(undo.canUndo)
        XCTAssertFalse(doc.model.items[0].ltcMuted)
    }

    func test_setLTCMuted_unknownItemID_isANoOp() throws {
        let doc = CueListDocument()
        let undo = makeUndoManager()
        CueCommands.setLTCMuted(itemID: UUID(), muted: true, document: doc, undoManager: undo)
        XCTAssertFalse(undo.canUndo)
    }

    private static func fixtureItem() -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "a.wav", kind: .audio, duration: 10, bookmarkData: Data()),
            cues: [],
            tempoMap: TempoMap(),
            startTimecodeFrames: 0,
            ltcMuted: false
        )
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
