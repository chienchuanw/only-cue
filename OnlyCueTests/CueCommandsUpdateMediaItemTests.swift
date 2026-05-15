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
        let itemA = makeItem(name: "a.wav")
        let itemB = makeItem(name: "b.wav")
        let doc = makeDocument(items: [itemA, itemB])

        CueCommands.updateMediaItem(
            id: itemA.id,
            edit: MediaItemEdit(alternateName: "Intro", startTimecodeFrames: 600, ltcMuted: true),
            document: doc,
            undoManager: nil
        )

        let updated = doc.model.items.first { $0.id == itemA.id }
        XCTAssertEqual(updated?.alternateName, "Intro")
        XCTAssertEqual(updated?.startTimecodeFrames, 600)
        XCTAssertEqual(updated?.ltcMuted, true)
    }

    func test_updateMediaItem_doesNotTouchOtherItems() {
        let itemA = makeItem(name: "a.wav")
        let itemB = makeItem(name: "b.wav")
        let doc = makeDocument(items: [itemA, itemB])

        CueCommands.updateMediaItem(
            id: itemA.id,
            edit: MediaItemEdit(alternateName: "X", startTimecodeFrames: 1, ltcMuted: true),
            document: doc,
            undoManager: nil
        )

        let other = doc.model.items.first { $0.id == itemB.id }
        XCTAssertNil(other?.alternateName)
        XCTAssertEqual(other?.startTimecodeFrames, 0)
        XCTAssertEqual(other?.ltcMuted, false)
    }

    func test_updateMediaItem_isSingleUndoStep() {
        let itemA = makeItem(name: "a.wav")
        let doc = makeDocument(items: [itemA])
        let undo = UndoManager()
        undo.groupsByEvent = false

        CueCommands.updateMediaItem(
            id: itemA.id,
            edit: MediaItemEdit(alternateName: "Intro", startTimecodeFrames: 600, ltcMuted: true),
            document: doc,
            undoManager: undo
        )

        XCTAssertTrue(undo.canUndo)
        undo.undo()

        let restored = doc.model.items.first { $0.id == itemA.id }
        XCTAssertNil(restored?.alternateName)
        XCTAssertEqual(restored?.startTimecodeFrames, 0)
        XCTAssertEqual(restored?.ltcMuted, false)
        XCTAssertTrue(undo.canRedo)
    }

    func test_updateMediaItem_unknownID_isNoOp() {
        let itemA = makeItem(name: "a.wav")
        let doc = makeDocument(items: [itemA])

        CueCommands.updateMediaItem(
            id: UUID(),
            edit: MediaItemEdit(alternateName: "X", startTimecodeFrames: 999, ltcMuted: true),
            document: doc,
            undoManager: nil
        )

        let unchanged = doc.model.items.first { $0.id == itemA.id }
        XCTAssertNil(unchanged?.alternateName)
        XCTAssertEqual(unchanged?.startTimecodeFrames, 0)
        XCTAssertEqual(unchanged?.ltcMuted, false)
    }

    func test_updateMediaItem_negativeFrames_clampedToZero() {
        let itemA = makeItem(name: "a.wav")
        let doc = makeDocument(items: [itemA])

        CueCommands.updateMediaItem(
            id: itemA.id,
            edit: MediaItemEdit(alternateName: nil, startTimecodeFrames: -10, ltcMuted: false),
            document: doc,
            undoManager: nil
        )

        XCTAssertEqual(doc.model.items.first?.startTimecodeFrames, 0)
    }
}
