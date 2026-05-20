import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsLyricPlacementTests: XCTestCase {

    private func makeDoc(lines: [LyricLine] = [], offset: TimeInterval = 0) -> CueListDocument {
        let doc = CueListDocument()
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "t.wav", kind: .audio, duration: 300, bookmarkData: Data([0])),
            cues: [],
            lyrics: Lyrics(lines: lines, offsetSeconds: offset)
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id
        return doc
    }

    private func makeUndo() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func itemID(_ doc: CueListDocument) -> MediaItem.ID { doc.model.items[0].id }
    private func lyrics(_ doc: CueListDocument) -> Lyrics { doc.model.items[0].lyrics }

    func test_placeLyricLine_setsSongRelativeTime() {
        let line = LyricLine(time: nil, text: "a")
        let doc = makeDoc(lines: [line], offset: 60)
        let undo = makeUndo()

        CueCommands.placeLyricLine(id: line.id, atMediaTime: 122, itemID: itemID(doc), document: doc, undoManager: undo)

        XCTAssertEqual(lyrics(doc).lines[0].time, 62, "stored time is media time minus the offset")
    }

    func test_placeLyricLine_clampsNegativeToZero() {
        let line = LyricLine(time: nil, text: "a")
        let doc = makeDoc(lines: [line], offset: 60)
        let undo = makeUndo()

        CueCommands.placeLyricLine(id: line.id, atMediaTime: 5, itemID: itemID(doc), document: doc, undoManager: undo)

        XCTAssertEqual(lyrics(doc).lines[0].time, 0)
    }

    func test_placeLyricLine_undoRestoresUnplaced() {
        let line = LyricLine(time: nil, text: "a")
        let doc = makeDoc(lines: [line])
        let undo = makeUndo()

        CueCommands.placeLyricLine(id: line.id, atMediaTime: 10, itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertEqual(lyrics(doc).lines[0].time, 10)
        undo.undo()
        XCTAssertNil(lyrics(doc).lines[0].time, "undo returns the line to the queue")
    }

    func test_placeLyricLine_unknownLineID_isNoOp() {
        let doc = makeDoc(lines: [LyricLine(time: nil, text: "a")])
        let undo = makeUndo()
        CueCommands.placeLyricLine(id: UUID(), atMediaTime: 10, itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertFalse(undo.canUndo)
    }

    func test_unplaceLyricLine_clearsTime() {
        let line = LyricLine(time: 30, text: "a")
        let doc = makeDoc(lines: [line])
        let undo = makeUndo()

        CueCommands.unplaceLyricLine(id: line.id, itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertNil(lyrics(doc).lines[0].time)

        undo.undo()
        XCTAssertEqual(lyrics(doc).lines[0].time, 30)
    }

    func test_deleteLyricLine_removesIt() {
        let keep = LyricLine(time: 1, text: "keep")
        let drop = LyricLine(time: 2, text: "drop")
        let doc = makeDoc(lines: [keep, drop])
        let undo = makeUndo()

        CueCommands.deleteLyricLine(id: drop.id, itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertEqual(lyrics(doc).lines.map(\.text), ["keep"])

        undo.undo()
        XCTAssertEqual(lyrics(doc).lines.map(\.text), ["keep", "drop"])
    }
}
