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

        let newSettings = ProjectTimecodeSettings(framerate: .fps25, startOffsetFrames: 90_000)
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
            ProjectTimecodeSettings(framerate: .fps30drop, startOffsetFrames: 1800),
            document: doc,
            undoManager: nil
        )
        let snapshot = try doc.snapshot(contentType: .cueList)
        XCTAssertEqual(snapshot.timecodeSettings.framerate, .fps30drop)
        XCTAssertEqual(snapshot.timecodeSettings.startOffsetFrames, 1800)
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }
}
