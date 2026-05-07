import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsTests: XCTestCase {

    func test_addCueAtPlayhead_appendsCueAtGivenTime() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.25, document: document, undoManager: undo)

        XCTAssertEqual(document.model.cues.count, 1)
        XCTAssertEqual(document.model.cues[0].time, 5.25, accuracy: 0.001)
        XCTAssertTrue(undo.canUndo)
    }

    func test_addCueAtPlayhead_undoEmptiesList_redoRestoresCue() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        let originalId = try XCTUnwrap(document.model.cues.first?.id)

        undo.undo()
        XCTAssertEqual(document.model.cues.count, 0)

        undo.redo()
        XCTAssertEqual(document.model.cues.count, 1)
        XCTAssertEqual(document.model.cues[0].id, originalId)
    }

    func test_delete_removesCue_undoRestoresIt() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(document.model.cues.first?.id)

        CueCommands.delete(cueId: cueId, document: document, undoManager: undo)
        XCTAssertEqual(document.model.cues.count, 0)

        undo.undo()
        XCTAssertEqual(document.model.cues.count, 1)
        XCTAssertEqual(document.model.cues[0].id, cueId)
        XCTAssertEqual(document.model.cues[0].time, 1.0, accuracy: 0.001)
    }

    func test_rename_updatesName_undoRestoresPriorName() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(document.model.cues.first?.id)
        let originalName = document.model.cues[0].name

        CueCommands.rename(cueId: cueId, to: "Chorus", document: document, undoManager: undo)
        XCTAssertEqual(document.model.cues[0].name, "Chorus")

        undo.undo()
        XCTAssertEqual(document.model.cues[0].name, originalName)
    }

    func test_recolor_updatesColorHex_undoRestoresPriorColor() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(document.model.cues.first?.id)
        let originalColor = document.model.cues[0].colorHex

        CueCommands.recolor(cueId: cueId, to: "#FF6B6B", document: document, undoManager: undo)
        XCTAssertEqual(document.model.cues[0].colorHex, "#FF6B6B")

        undo.undo()
        XCTAssertEqual(document.model.cues[0].colorHex, originalColor)
    }

    func test_retime_updatesTime_undoRestoresPriorTime() throws {
        let document = CueListDocument()
        let undo = makeUndoManager()
        CueCommands.addCueAtPlayhead(time: 1.0, document: document, undoManager: undo)
        let cueId = try XCTUnwrap(document.model.cues.first?.id)

        CueCommands.retime(cueId: cueId, to: 7.5, document: document, undoManager: undo)
        XCTAssertEqual(document.model.cues[0].time, 7.5, accuracy: 0.001)

        undo.undo()
        XCTAssertEqual(document.model.cues[0].time, 1.0, accuracy: 0.001)
    }

    func test_addMultiple_keepsCuesSortedByTime() {
        let document = CueListDocument()
        let undo = makeUndoManager()

        CueCommands.addCueAtPlayhead(time: 5.0, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 2.0, document: document, undoManager: undo)
        CueCommands.addCueAtPlayhead(time: 8.0, document: document, undoManager: undo)

        let times = document.model.cues.map(\.time)
        XCTAssertEqual(times, [2.0, 5.0, 8.0])
    }

    private func makeUndoManager() -> UndoManager {
        UndoManager()
    }
}
