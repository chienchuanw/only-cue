import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsLyricsTests: XCTestCase {

    private func makeDocumentWithItem() -> CueListDocument {
        let doc = CueListDocument()
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "t.wav", kind: .audio, duration: 60, bookmarkData: Data([0])),
            cues: []
        )
        doc.model.items = [item]
        doc.model.activeItemID = item.id
        return doc
    }

    private func makeUndoManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    private func itemID(_ doc: CueListDocument) -> MediaItem.ID { doc.model.items[0].id }
    private func lyrics(_ doc: CueListDocument) -> Lyrics { doc.model.items[0].lyrics }

    func test_setLyrics_replacesValue_undoRestores() {
        let doc = makeDocumentWithItem()
        let undo = makeUndoManager()
        let newLyrics = Lyrics(lines: [LyricLine(time: 2, text: "a")], offsetSeconds: 5)

        CueCommands.setLyrics(newLyrics, itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertEqual(lyrics(doc), newLyrics)
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        XCTAssertEqual(lyrics(doc), .empty)
    }

    func test_setLyrics_noOpWhenUnchanged() {
        let doc = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setLyrics(.empty, itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertFalse(undo.canUndo, "setting the same value registers no undo step")
    }

    func test_setLyricsOffset_changesOnlyOffset_undoRestores() {
        let doc = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setLyricLines([LyricLine(time: 1, text: "a")], itemID: itemID(doc), document: doc, undoManager: undo)

        CueCommands.setLyricsOffset(60, itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertEqual(lyrics(doc).offsetSeconds, 60)
        XCTAssertEqual(lyrics(doc).lines.map(\.text), ["a"], "offset change leaves lines untouched")

        undo.undo()
        XCTAssertEqual(lyrics(doc).offsetSeconds, 0)
    }

    func test_setLyricLines_replacesLines_keepsOffset() {
        let doc = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setLyricsOffset(30, itemID: itemID(doc), document: doc, undoManager: undo)

        CueCommands.setLyricLines([LyricLine(time: 4, text: "b")], itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertEqual(lyrics(doc).lines.map(\.text), ["b"])
        XCTAssertEqual(lyrics(doc).offsetSeconds, 30, "editing lines preserves the offset")
    }

    func test_pasteLyrics_replacesWithUntimedRows() {
        let doc = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.pasteLyrics(plainText: "one\ntwo", itemID: itemID(doc), document: doc, undoManager: undo)
        XCTAssertEqual(lyrics(doc).lines.map(\.text), ["one", "two"])
        XCTAssertTrue(lyrics(doc).lines.allSatisfy { $0.time == 0 })
    }

    func test_unknownItemID_isNoOp() {
        let doc = makeDocumentWithItem()
        let undo = makeUndoManager()
        CueCommands.setLyricsOffset(99, itemID: UUID(), document: doc, undoManager: undo)
        XCTAssertEqual(lyrics(doc), .empty)
        XCTAssertFalse(undo.canUndo)
    }
}
