import XCTest
@testable import OnlyCue

/// Pins the command-level contract that `CueMarkersOverlay` depends on when it
/// dispatches drag results. The overlay routes group drags through
/// `CueCommands.nudgeCues` and single-cue retimes through `CueCommands.retime`;
/// these tests freeze the semantics (group shift, per-cue clamp at zero,
/// single-cue isolation) the overlay's UI code assumes.
@MainActor
final class CueMarkersOverlayDispatchTests: XCTestCase {

    func test_nudgeCues_shiftsAllByDelta_singleUndoEntry() throws {
        let document = makeDocument(cueTimes: [1.0, 3.0, 6.0])
        let undo = makeUndoManager()
        let ids = Set(activeCues(document).map(\.id))

        CueCommands.nudgeCues(ids, by: 5.0, document: document, undoManager: undo)

        XCTAssertEqual(activeCues(document).map(\.time), [6.0, 8.0, 11.0])
        XCTAssertTrue(undo.canUndo, "nudgeCues should register a single undoable edit")
    }

    func test_nudgeCues_clampsEachCueAtZero() throws {
        let document = makeDocument(cueTimes: [0.1, 2.0, 5.0])
        let undo = makeUndoManager()
        let ids = Set(activeCues(document).map(\.id))

        CueCommands.nudgeCues(ids, by: -1.0, document: document, undoManager: undo)

        let times = activeCues(document).map(\.time)
        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(times[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(times[1], 1.0, accuracy: 0.0001)
        XCTAssertEqual(times[2], 4.0, accuracy: 0.0001)
    }

    func test_retime_movesOnlyOneCue() throws {
        let document = makeDocument(cueTimes: [1.0, 3.0, 6.0])
        let cues = activeCues(document)
        let target = try XCTUnwrap(cues.first(where: { $0.time == 3.0 })?.id)

        CueCommands.retime(cueId: target, to: 4.5, document: document, undoManager: nil)

        XCTAssertEqual(activeCues(document).map(\.time), [1.0, 4.5, 6.0])
    }

    // MARK: - Helpers

    private func makeDocument(cueTimes: [TimeInterval]) -> CueListDocument {
        let doc = CueListDocument()
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "test.wav",
                kind: .audio,
                duration: 120,
                bookmarkData: Data([0x00])
            ),
            cues: []
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id

        let undo = makeUndoManager()
        for time in cueTimes {
            CueCommands.addCueAtPlayhead(time: time, document: doc, undoManager: undo)
        }
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
