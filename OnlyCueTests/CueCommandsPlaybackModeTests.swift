import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsPlaybackModeTests: XCTestCase {

    func test_setPlaybackMode_updatesModel() {
        let document = CueListDocument()
        XCTAssertEqual(document.model.playbackMode, .playOnce)

        CueCommands.setPlaybackMode(.loop, document: document, undoManager: nil)

        XCTAssertEqual(document.model.playbackMode, .loop)
    }

    func test_setPlaybackMode_noOpWhenAlreadyEqual() {
        let document = CueListDocument()
        let undoManager = UndoManager()

        CueCommands.setPlaybackMode(.playOnce, document: document, undoManager: undoManager)

        XCTAssertEqual(document.model.playbackMode, .playOnce)
        XCTAssertFalse(undoManager.canUndo, "no-op write must not register an undo step")
    }

    func test_setPlaybackMode_undoRestoresPrevious() {
        let document = CueListDocument()
        let undoManager = UndoManager()

        CueCommands.setPlaybackMode(.autoNext, document: document, undoManager: undoManager)
        XCTAssertEqual(document.model.playbackMode, .autoNext)

        undoManager.undo()
        XCTAssertEqual(document.model.playbackMode, .playOnce)

        undoManager.redo()
        XCTAssertEqual(document.model.playbackMode, .autoNext)
    }
}
