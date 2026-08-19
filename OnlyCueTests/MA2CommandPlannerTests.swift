import XCTest
@testable import OnlyCue

/// #683 Approach A — the pure telnet command list for a per-cue Trig=Timecode push.
final class MA2CommandPlannerTests: XCTestCase {

    private func cue(
        _ number: Double,
        _ name: String,
        time: TimeInterval,
        fadeIn: Double = 0,
        fadeOut: Double = 0
    ) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: number,
            name: name,
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: fadeIn, fadeOut: fadeOut)
        )
    }

    private func target(seq: Int = 900, page: Int = 1, exec: Int = 15) -> MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: seq,
            timecodeSlot: 9,
            executorPage: page,
            executorNumber: exec,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
    }

    func test_buildsOrderedCommandList_deleteFirst_numberSorted() {
        let cues = [cue(2.001, "Drop", time: 10), cue(1.15, "Intro", time: 5, fadeIn: 3)]
        let commands = MA2CommandPlanner.commands(
            cues: cues,
            target: target(),
            sequenceName: "Song A",
            startTimecodeFrames: 0,
            framerate: .fps30
        )
        XCTAssertEqual(commands, [
            "Delete Sequence 900 /nc",
            "Store Sequence 900 Cue 1.15 \"Intro\" /nc",
            "Assign Sequence 900 Cue 1.15 /Trig=Timecode",
            "Assign Sequence 900 Cue 1.15 /TrigTime=5",
            "Assign Sequence 900 Cue 1.15 /fade=3",
            "Store Sequence 900 Cue 2.001 \"Drop\" /nc",
            "Assign Sequence 900 Cue 2.001 /Trig=Timecode",
            "Assign Sequence 900 Cue 2.001 /TrigTime=10",
            "Label Sequence 900 \"Song A\"",
            "Assign Sequence 900 At Exec 1.15"
        ])
    }

    func test_emitsOutfade_whenFadeOutPositive() {
        let commands = MA2CommandPlanner.commands(
            cues: [cue(1, "C", time: 0, fadeIn: 0, fadeOut: 2)],
            target: target(),
            sequenceName: "S",
            startTimecodeFrames: 0,
            framerate: .fps30
        )
        XCTAssertTrue(commands.contains("Assign Sequence 900 Cue 1 /outfade=2"))
        XCTAssertFalse(commands.contains(where: { $0.contains("/fade=") }))
    }

    func test_stripsEmbeddedQuotes_inCueAndSequenceNames() {
        let commands = MA2CommandPlanner.commands(
            cues: [cue(1, "he said \"hi\"", time: 0)],
            target: target(seq: 5, page: 2, exec: 3),
            sequenceName: "a\"b",
            startTimecodeFrames: 0,
            framerate: .fps25
        )
        XCTAssertTrue(commands.contains("Store Sequence 5 Cue 1 \"he said hi\" /nc"))
        XCTAssertTrue(commands.contains("Label Sequence 5 \"ab\""))
        XCTAssertTrue(commands.contains("Assign Sequence 5 At Exec 2.3"))
    }

    // MARK: - Cue info (#686)

    private func cueWithNotes(_ notes: String) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "C",
            time: 0,
            notes: notes,
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    func test_emitsInfo_forCueWithNotes_singleLinedAndQuoteStripped() {
        let commands = MA2CommandPlanner.commands(
            cues: [cueWithNotes("line1\nline2 \"q\"")],
            target: target(),
            sequenceName: "S",
            startTimecodeFrames: 0,
            framerate: .fps30
        )
        XCTAssertTrue(commands.contains("Assign Sequence 900 Cue 1 /info=\"line1 line2 q\""))
    }

    func test_omitsInfo_whenNotesEmpty() {
        let commands = MA2CommandPlanner.commands(
            cues: [cueWithNotes("")],
            target: target(),
            sequenceName: "S",
            startTimecodeFrames: 0,
            framerate: .fps30
        )
        XCTAssertFalse(commands.contains(where: { $0.contains("/info=") }))
    }

    // MARK: - Optional executor (#764)

    private func unassignedTarget(seq: Int = 900) -> MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: seq,
            timecodeSlot: 9,
            executorPage: nil,
            executorNumber: nil,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
    }

    func test_unassignedExecutor_omitsAtExecCommand() {
        let cues = [cue(1, "C", time: 0)]
        let assigned = MA2CommandPlanner.commands(
            cues: cues, target: target(), sequenceName: "S", startTimecodeFrames: 0, framerate: .fps30
        )
        let unassigned = MA2CommandPlanner.commands(
            cues: cues, target: unassignedTarget(), sequenceName: "S", startTimecodeFrames: 0, framerate: .fps30
        )
        // The assigned case ends with an At Exec; the unassigned case omits exactly that line.
        XCTAssertTrue(assigned.contains { $0.contains("At Exec") })
        XCTAssertFalse(unassigned.contains { $0.contains("At Exec") })
        XCTAssertEqual(unassigned, assigned.filter { !$0.contains("At Exec") })
    }
}
