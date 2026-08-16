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
        let itemA = makeItem("a"), itemB = makeItem("b"), itemC = makeItem("c")
        XCTAssertEqual(CueCommands.nextMediaItemID(after: itemA.id, in: [itemA, itemB, itemC]), itemB.id)
    }

    func test_nextMediaItemID_returnsNilAtLastItem() {
        let itemA = makeItem("a"), itemB = makeItem("b")
        XCTAssertNil(CueCommands.nextMediaItemID(after: itemB.id, in: [itemA, itemB]))
    }

    func test_nextMediaItemID_returnsNilForSingleItem() {
        let itemA = makeItem("a")
        XCTAssertNil(CueCommands.nextMediaItemID(after: itemA.id, in: [itemA]))
    }

    func test_nextMediaItemID_returnsNilForUnknownID() {
        let itemA = makeItem("a"), itemB = makeItem("b")
        XCTAssertNil(CueCommands.nextMediaItemID(after: UUID(), in: [itemA, itemB]))
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
        let itemA = makeItem("a"), itemB = makeItem("b")
        let document = seed([itemA, itemB], active: itemA.id)
        var playedID: MediaItem.ID?

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { playedID = $0 }
        )

        XCTAssertEqual(document.model.activeItemID, itemB.id)
        XCTAssertEqual(playedID, itemB.id)
    }

    func test_advance_atLastItem_isNoOp() async {
        let itemA = makeItem("a"), itemB = makeItem("b")
        let document = seed([itemA, itemB], active: itemB.id)
        var playCalled = false

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertEqual(document.model.activeItemID, itemB.id)
        XCTAssertFalse(playCalled, "no transition → no play")
    }

    func test_advance_capturesNextIDAtFireTime() async {
        let itemA = makeItem("a"), itemB = makeItem("b"), itemC = makeItem("c")
        let document = seed([itemA, itemB, itemC], active: itemA.id)
        // Mutate items[] between mode-set and fire time — remove itemB
        // so the "next" should now be itemC.
        document.model.items = [itemA, itemC]

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in }
        )

        XCTAssertEqual(document.model.activeItemID, itemC.id)
    }

    func test_advance_withNilActive_isNoOp() async {
        let itemA = makeItem("a")
        let document = seed([itemA], active: nil)
        var playCalled = false

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertNil(document.model.activeItemID)
        XCTAssertFalse(playCalled)
    }

    // MARK: - Pure helper: previousMediaItemID(before:in:)

    func test_previousMediaItemID_returnsPreviousWhenMiddle() {
        let itemA = makeItem("a"), itemB = makeItem("b"), itemC = makeItem("c")
        XCTAssertEqual(CueCommands.previousMediaItemID(before: itemB.id, in: [itemA, itemB, itemC]), itemA.id)
    }

    func test_previousMediaItemID_returnsNilAtFirstItem() {
        let itemA = makeItem("a"), itemB = makeItem("b")
        XCTAssertNil(CueCommands.previousMediaItemID(before: itemA.id, in: [itemA, itemB]))
    }

    func test_previousMediaItemID_returnsNilForSingleItem() {
        let itemA = makeItem("a")
        XCTAssertNil(CueCommands.previousMediaItemID(before: itemA.id, in: [itemA]))
    }

    func test_previousMediaItemID_returnsNilForUnknownID() {
        let itemA = makeItem("a"), itemB = makeItem("b")
        XCTAssertNil(CueCommands.previousMediaItemID(before: UUID(), in: [itemA, itemB]))
    }

    func test_previousMediaItemID_returnsNilForEmptyList() {
        XCTAssertNil(CueCommands.previousMediaItemID(before: UUID(), in: []))
    }

    // MARK: - Command: stepMediaAndPlay

    func test_stepPrevious_movesActiveToPreviousAndInvokesPlay() async {
        let itemA = makeItem("a"), itemB = makeItem("b")
        let document = seed([itemA, itemB], active: itemB.id)
        var playedID: MediaItem.ID?

        await CueCommands.stepMediaAndPlay(
            .previous,
            document: document,
            reloadAndPlay: { playedID = $0 }
        )

        XCTAssertEqual(document.model.activeItemID, itemA.id)
        XCTAssertEqual(playedID, itemA.id)
    }

    func test_stepPrevious_atFirstItem_isNoOp() async {
        let itemA = makeItem("a"), itemB = makeItem("b")
        let document = seed([itemA, itemB], active: itemA.id)
        var playCalled = false

        await CueCommands.stepMediaAndPlay(
            .previous,
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertEqual(document.model.activeItemID, itemA.id, "stops at boundary — no wrap")
        XCTAssertFalse(playCalled, "no transition → no play")
    }

    func test_stepPrevious_withNilActive_isNoOp() async {
        let itemA = makeItem("a")
        let document = seed([itemA], active: nil)
        var playCalled = false

        await CueCommands.stepMediaAndPlay(
            .previous,
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertNil(document.model.activeItemID)
        XCTAssertFalse(playCalled)
    }

    func test_stepNext_movesActiveToNextAndInvokesPlay() async {
        let itemA = makeItem("a"), itemB = makeItem("b")
        let document = seed([itemA, itemB], active: itemA.id)
        var playedID: MediaItem.ID?

        await CueCommands.stepMediaAndPlay(
            .next,
            document: document,
            reloadAndPlay: { playedID = $0 }
        )

        XCTAssertEqual(document.model.activeItemID, itemB.id)
        XCTAssertEqual(playedID, itemB.id)
    }

    func test_stepNext_atLastItem_isNoOp() async {
        let itemA = makeItem("a"), itemB = makeItem("b")
        let document = seed([itemA, itemB], active: itemB.id)
        var playCalled = false

        await CueCommands.stepMediaAndPlay(
            .next,
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertEqual(document.model.activeItemID, itemB.id, "stops at boundary — no wrap")
        XCTAssertFalse(playCalled)
    }
}
