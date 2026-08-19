import XCTest
@testable import OnlyCue

/// #765 — the batch push planner persists auto-fill (#763) for each selected song and builds
/// its command list. Executor-optional targets (#764) omit the `At Exec` line.
@MainActor
final class MA2BatchPushPlanTests: XCTestCase {

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

    private func item(_ name: String, cues: [Cue]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: name, kind: .audio, duration: 60, bookmarkData: Data([0x00])),
            cues: cues
        )
    }

    private func target(slot: Int, executor: (Int, Int)?) -> MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: slot,
            timecodeSlot: 1,
            executorPage: executor?.0,
            executorNumber: executor?.1,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
    }

    func test_build_persistsAutoFill_andBuildsCommandsPerSong() {
        let doc = CueListDocument()
        let songA = item("A.wav", cues: [cue(1, time: 0), cue(nil, time: 1), cue(3, time: 2)])
        let songB = item("B.wav", cues: [cue(1, time: 0)])
        doc.model.items = [songA, songB]

        let result = MA2BatchPushPlan.build(
            [.init(itemID: songA.id, target: target(slot: 11, executor: (1, 1))),
             .init(itemID: songB.id, target: target(slot: 12, executor: nil))],
            document: doc,
            undoManager: nil,
            framerate: .fps30
        )

        XCTAssertEqual(result.count, 2)
        // Auto-fill was persisted: songA's middle cue now has number 2.
        let persisted = doc.model.items.first { $0.id == songA.id }?.cues[1].cueNumber
        XCTAssertEqual(persisted, 2)
        // Song A (executor 1.1) ends with an At Exec; song B (unassigned) omits it.
        XCTAssertTrue(result[0].commands.contains { $0.contains("At Exec 1.1") })
        XCTAssertFalse(result[1].commands.contains { $0.contains("At Exec") })
    }

    func test_build_skipsSongWithNoCuesAfterFilter() {
        let doc = CueListDocument()
        let empty = item("empty.wav", cues: [])
        doc.model.items = [empty]
        let result = MA2BatchPushPlan.build(
            [.init(itemID: empty.id, target: target(slot: 11, executor: nil))],
            document: doc,
            undoManager: nil,
            framerate: .fps30
        )
        XCTAssertTrue(result.isEmpty)
    }
}
