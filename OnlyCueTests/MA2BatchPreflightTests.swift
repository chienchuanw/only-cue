import XCTest
@testable import OnlyCue

/// #765 — batch pre-flight: composes each song's `MA2PushPreflight` (evaluated on the
/// post-auto-fill cues, #763) with cross-song uniqueness — sequence slot always, executor
/// only when assigned (#764). All-or-nothing: any issue blocks the whole batch.
final class MA2BatchPreflightTests: XCTestCase {

    private func cue(_ number: Double?, time: TimeInterval) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: number,
            name: "c",
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    private func song(
        _ itemID: MediaItem.ID = UUID(),
        cues: [Cue],
        slot: Int,
        executor: (Int, Int)? = nil
    ) -> MA2BatchPreflight.Song {
        MA2BatchPreflight.Song(
            itemID: itemID,
            cues: cues,
            includedTypeIDs: [],
            target: MA2PushTarget(
                sequenceSlot: slot,
                timecodeSlot: 1,
                executorPage: executor?.0,
                executorNumber: executor?.1,
                timecodeCommand: .goto,
                includedTypeIDs: []
            )
        )
    }

    func test_uniqueSlotsAndExecutors_isClear() {
        let result = MA2BatchPreflight.validate([
            song(cues: [cue(1, time: 0)], slot: 11, executor: (1, 1)),
            song(cues: [cue(1, time: 0)], slot: 12, executor: (1, 2))
        ])
        XCTAssertTrue(result.isClear)
    }

    func test_duplicateSequenceSlot_isFlagged() {
        let idA = UUID(), idB = UUID()
        let result = MA2BatchPreflight.validate([
            song(idA, cues: [cue(1, time: 0)], slot: 12),
            song(idB, cues: [cue(1, time: 0)], slot: 12)
        ])
        XCTAssertFalse(result.isClear)
        XCTAssertEqual(result.cross, [.duplicateSequenceSlot(slot: 12, itemIDs: [idA, idB])])
    }

    func test_duplicateAssignedExecutor_isFlagged() {
        let idA = UUID(), idB = UUID()
        let result = MA2BatchPreflight.validate([
            song(idA, cues: [cue(1, time: 0)], slot: 11, executor: (1, 5)),
            song(idB, cues: [cue(1, time: 0)], slot: 12, executor: (1, 5))
        ])
        XCTAssertEqual(result.cross, [.duplicateExecutor(page: 1, number: 5, itemIDs: [idA, idB])])
    }

    func test_blankExecutorsDoNotCollide() {
        let result = MA2BatchPreflight.validate([
            song(cues: [cue(1, time: 0)], slot: 11, executor: nil),
            song(cues: [cue(1, time: 0)], slot: 12, executor: nil)
        ])
        XCTAssertTrue(result.isClear)
    }

    func test_perSongDuplicateNumber_surfacesForThatSong() {
        // Two user-numbered cues share number 1 — auto-fill never touches numbered cues,
        // so this stays a per-song duplicate.
        let idA = UUID()
        let dupes = [cue(1, time: 0), cue(1, time: 1)]
        let result = MA2BatchPreflight.validate([song(idA, cues: dupes, slot: 11)])
        XCTAssertFalse(result.isClear)
        XCTAssertEqual(result.perSong.first?.itemID, idA)
        XCTAssertEqual(result.perSong.first?.issues, [.duplicateNumber(number: 1, cues: dupes)])
    }

    func test_autoFillableGap_isNotFlaggedUnnumbered() {
        // [1, nil, 3] → auto-fill assigns 2, so the pre-flight sees no unnumbered cue.
        let result = MA2BatchPreflight.validate([
            song(cues: [cue(1, time: 0), cue(nil, time: 1), cue(3, time: 2)], slot: 11)
        ])
        XCTAssertTrue(result.isClear)
    }
}
