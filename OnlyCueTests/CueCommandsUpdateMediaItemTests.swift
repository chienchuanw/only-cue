import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsUpdateMediaItemTests: XCTestCase {

    private func makeItem(name: String) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 60,
                bookmarkData: Data([0x00])
            ),
            cues: [],
            startTimecodeFrames: 0,
            ltcMuted: false,
            alternateName: nil
        )
    }

    private func makeDocument(items: [MediaItem]) -> CueListDocument {
        let doc = CueListDocument()
        doc.model.items = items
        doc.model.activeItemID = items.first?.id
        return doc
    }

    func test_updateMediaItem_setsAllThreeFields_inOneStep() {
        let a = makeItem(name: "a.wav")
        let b = makeItem(name: "b.wav")
        let doc = makeDocument(items: [a, b])

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: "Intro",
            startTimecodeFrames: 600,
            ltcMuted: true,
            document: doc,
            undoManager: nil
        )

        let updated = doc.model.items.first { $0.id == a.id }
        XCTAssertEqual(updated?.alternateName, "Intro")
        XCTAssertEqual(updated?.startTimecodeFrames, 600)
        XCTAssertEqual(updated?.ltcMuted, true)
    }

    func test_updateMediaItem_doesNotTouchOtherItems() {
        let a = makeItem(name: "a.wav")
        let b = makeItem(name: "b.wav")
        let doc = makeDocument(items: [a, b])

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: "X",
            startTimecodeFrames: 1,
            ltcMuted: true,
            document: doc,
            undoManager: nil
        )

        let other = doc.model.items.first { $0.id == b.id }
        XCTAssertNil(other?.alternateName)
        XCTAssertEqual(other?.startTimecodeFrames, 0)
        XCTAssertEqual(other?.ltcMuted, false)
    }

    func test_updateMediaItem_isSingleUndoStep() {
        let a = makeItem(name: "a.wav")
        let doc = makeDocument(items: [a])
        let undo = UndoManager()
        undo.groupsByEvent = false

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: "Intro",
            startTimecodeFrames: 600,
            ltcMuted: true,
            document: doc,
            undoManager: undo
        )

        XCTAssertTrue(undo.canUndo)
        undo.undo()

        let restored = doc.model.items.first { $0.id == a.id }
        XCTAssertNil(restored?.alternateName)
        XCTAssertEqual(restored?.startTimecodeFrames, 0)
        XCTAssertEqual(restored?.ltcMuted, false)
        XCTAssertTrue(undo.canRedo)
    }

    func test_updateMediaItem_unknownID_isNoOp() {
        let a = makeItem(name: "a.wav")
        let doc = makeDocument(items: [a])

        CueCommands.updateMediaItem(
            id: UUID(),
            alternateName: "X",
            startTimecodeFrames: 999,
            ltcMuted: true,
            document: doc,
            undoManager: nil
        )

        let unchanged = doc.model.items.first { $0.id == a.id }
        XCTAssertNil(unchanged?.alternateName)
        XCTAssertEqual(unchanged?.startTimecodeFrames, 0)
        XCTAssertEqual(unchanged?.ltcMuted, false)
    }

    func test_updateMediaItem_negativeFrames_clampedToZero() {
        let a = makeItem(name: "a.wav")
        let doc = makeDocument(items: [a])

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: nil,
            startTimecodeFrames: -10,
            ltcMuted: false,
            document: doc,
            undoManager: nil
        )

        XCTAssertEqual(doc.model.items.first?.startTimecodeFrames, 0)
    }
}
