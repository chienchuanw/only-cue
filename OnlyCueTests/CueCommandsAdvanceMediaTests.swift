import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsAdvanceMediaTests: XCTestCase {

    private func makeItem(_ name: String) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 1,
                bookmarkData: Data([0x01])
            ),
            cues: []
        )
    }

    // MARK: - Pure helper: nextMediaItemID(after:in:)

    func test_nextMediaItemID_returnsNextWhenMiddle() {
        let a = makeItem("a"), b = makeItem("b"), c = makeItem("c")
        XCTAssertEqual(CueCommands.nextMediaItemID(after: a.id, in: [a, b, c]), b.id)
    }

    func test_nextMediaItemID_returnsNilAtLastItem() {
        let a = makeItem("a"), b = makeItem("b")
        XCTAssertNil(CueCommands.nextMediaItemID(after: b.id, in: [a, b]))
    }

    func test_nextMediaItemID_returnsNilForSingleItem() {
        let a = makeItem("a")
        XCTAssertNil(CueCommands.nextMediaItemID(after: a.id, in: [a]))
    }

    func test_nextMediaItemID_returnsNilForUnknownID() {
        let a = makeItem("a"), b = makeItem("b")
        XCTAssertNil(CueCommands.nextMediaItemID(after: UUID(), in: [a, b]))
    }

    func test_nextMediaItemID_returnsNilForEmptyList() {
        XCTAssertNil(CueCommands.nextMediaItemID(after: UUID(), in: []))
    }

    // MARK: - Command: advanceToNextMediaAndPlay

    private func seed(_ items: [MediaItem], active: MediaItem.ID?) -> CueListDocument {
        let document = CueListDocument()
        document.model.items = items
        document.model.activeItemID = active
        return document
    }

    func test_advance_movesActiveToNextAndInvokesPlay() async {
        let a = makeItem("a"), b = makeItem("b")
        let document = seed([a, b], active: a.id)
        var playedID: MediaItem.ID?

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { playedID = $0 }
        )

        XCTAssertEqual(document.model.activeItemID, b.id)
        XCTAssertEqual(playedID, b.id)
    }

    func test_advance_atLastItem_isNoOp() async {
        let a = makeItem("a"), b = makeItem("b")
        let document = seed([a, b], active: b.id)
        var playCalled = false

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertEqual(document.model.activeItemID, b.id)
        XCTAssertFalse(playCalled, "no transition → no play")
    }

    func test_advance_capturesNextIDAtFireTime() async {
        let a = makeItem("a"), b = makeItem("b"), c = makeItem("c")
        let document = seed([a, b, c], active: a.id)
        // Mutate items[] between mode-set and fire time — remove `b`
        // so the "next" should now be `c`.
        document.model.items = [a, c]

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in }
        )

        XCTAssertEqual(document.model.activeItemID, c.id)
    }

    func test_advance_withNilActive_isNoOp() async {
        let a = makeItem("a")
        let document = seed([a], active: nil)
        var playCalled = false

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertNil(document.model.activeItemID)
        XCTAssertFalse(playCalled)
    }
}
