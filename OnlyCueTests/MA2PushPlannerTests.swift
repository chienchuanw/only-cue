import XCTest
@testable import OnlyCue

/// #683 — the ordered push plan: two FTP uploads (sequence + timecode XML into
/// `gma2/importexport/`) and the telnet command list that rebuilds the target
/// slots. Command strings are locked here verbatim; the exact import syntax is
/// re-verified on the real rig before merge (plan step 13).
final class MA2PushPlannerTests: XCTestCase {

    private func cue(number: Double, name: String = "", time: TimeInterval = 0) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: number,
            name: name,
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    private var target: MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: 18,
            timecodeSlot: 3,
            executorPage: 2,
            executorNumber: 3,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
    }

    private func plan(cues: [Cue]) -> MA2PushPlan {
        MA2PushPlanner.plan(
            cues: cues,
            target: target,
            sequenceName: "Opening",
            timecodeName: "Opening TC",
            startTimecodeFrames: 0,
            lengthFrames: 900,
            framerate: .fps30,
            showfile: "MyShow",
            datetime: "2026-07-19T12:00:00"
        )
    }

    func test_uploads_slotStampedFilenames_andGeneratorPayloads() {
        let cues = [cue(number: 1, name: "Intro"), cue(number: 2, name: "Drop", time: 10)]
        let plan = plan(cues: cues)

        XCTAssertEqual(plan.sequenceUpload.filename, "onlycue_seq_18.xml")
        XCTAssertEqual(plan.timecodeUpload.filename, "onlycue_tc_3.xml")

        // Payloads are exactly the two generators' output — the planner adds
        // no formatting of its own.
        XCTAssertEqual(plan.sequenceUpload.xml, MA2SequenceXMLGenerator.xml(
            cues: cues, sequenceName: "Opening", showfile: "MyShow", datetime: "2026-07-19T12:00:00"
        ))
        XCTAssertEqual(plan.timecodeUpload.xml, MA2TimecodeXMLGenerator.xml(
            cues: cues,
            timecodeSlot: 3,
            timecodeName: "Opening TC",
            sequenceSlot: 18,
            sequenceName: "Opening",
            executorPage: 2,
            executorNumber: 3,
            command: .goto,
            startTimecodeFrames: 0,
            lengthFrames: 900,
            framerate: .fps30,
            showfile: "MyShow",
            datetime: "2026-07-19T12:00:00"
        ))
    }

    func test_telnetCommands_exactStringsInOrder() {
        // Delete ×2 first (idempotent rebuild), then the sequence import from
        // inside the sequence pool directory (`Import … At` argument order is
        // flipped vs Export — wrong order → Error #12), back to root, timecode
        // import, executor assign, labels.
        XCTAssertEqual(plan(cues: [cue(number: 1)]).commands, [
            "Delete Sequence 18 /nc",
            "Delete Timecode 3 /nc",
            "cd Sequences",
            "cd Global",
            "Import \"onlycue_seq_18\" At 18 /nc",
            "cd /",
            "Import \"onlycue_tc_3\" At Timecode 3 /nc",
            "Assign Sequence 18 At Exec 2.3",
            "Label Sequence 18 \"Opening\"",
            "Label Timecode 3 \"Opening TC\""
        ])
    }

    func test_names_areQuoteEscapedInLabelCommands() {
        // MA2 quoting: embedded double quotes would break the command line —
        // strip them rather than guessing an escape syntax.
        let plan = MA2PushPlanner.plan(
            cues: [cue(number: 1)],
            target: target,
            sequenceName: "My \"Show\"",
            timecodeName: "TC \"2\"",
            startTimecodeFrames: 0,
            lengthFrames: 900,
            framerate: .fps30,
            showfile: "MyShow",
            datetime: "2026-07-19T12:00:00"
        )
        XCTAssertTrue(plan.commands.contains("Label Sequence 18 \"My Show\""))
        XCTAssertTrue(plan.commands.contains("Label Timecode 3 \"TC 2\""))
    }
}
