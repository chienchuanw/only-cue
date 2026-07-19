import Foundation

/// The ordered grandMA2 push plan (#683): two XML files to FTP into
/// `gma2/importexport/` and the telnet command list that rebuilds the target
/// sequence / timecode slots from them.
struct MA2PushPlan: Equatable {

    struct Upload: Equatable {
        /// File name inside `gma2/importexport/` (slot-stamped, `.xml`).
        var filename: String
        var xml: String
    }

    var sequenceUpload: Upload
    var timecodeUpload: Upload
    /// Telnet commands after login, in execution order.
    var commands: [String]
}

/// Pure planner — generates the XML payloads and the exact telnet command
/// strings. Import syntax is re-verified on the real rig before merge
/// (plan step 13).
enum MA2PushPlanner {

    // swiftlint:disable:next function_parameter_count
    static func plan(
        cues: [Cue],
        target: MA2PushTarget,
        sequenceName: String,
        timecodeName: String,
        startTimecodeFrames: Int,
        lengthFrames: Int,
        framerate: SMPTEFramerate,
        showfile: String,
        datetime: String
    ) -> MA2PushPlan {
        let sequenceFileBase = "onlycue_seq_\(target.sequenceSlot)"
        let timecodeFileBase = "onlycue_tc_\(target.timecodeSlot)"

        let sequenceUpload = MA2PushPlan.Upload(
            filename: "\(sequenceFileBase).xml",
            xml: MA2SequenceXMLGenerator.xml(
                cues: cues, sequenceName: sequenceName, showfile: showfile, datetime: datetime
            )
        )
        let timecodeUpload = MA2PushPlan.Upload(
            filename: "\(timecodeFileBase).xml",
            xml: MA2TimecodeXMLGenerator.xml(
                cues: cues,
                timecodeSlot: target.timecodeSlot,
                timecodeName: timecodeName,
                sequenceSlot: target.sequenceSlot,
                sequenceName: sequenceName,
                executorPage: target.executorPage,
                executorNumber: target.executorNumber,
                command: target.timecodeCommand,
                startTimecodeFrames: startTimecodeFrames,
                lengthFrames: lengthFrames,
                framerate: framerate,
                showfile: showfile,
                datetime: datetime
            )
        )

        // Delete ×2 first (idempotent rebuild), sequence import from inside
        // the sequence pool directory (`Import … At` argument order is flipped
        // vs Export — wrong order → Error #12), back to root, timecode import,
        // executor assign, labels.
        let commands = [
            "Delete Sequence \(target.sequenceSlot) /nc",
            "Delete Timecode \(target.timecodeSlot) /nc",
            "cd Sequences",
            "cd Global",
            "Import \"\(sequenceFileBase)\" At \(target.sequenceSlot) /nc",
            "cd /",
            "Import \"\(timecodeFileBase)\" At Timecode \(target.timecodeSlot) /nc",
            "Assign Sequence \(target.sequenceSlot) At Exec \(target.executorPage).\(target.executorNumber)",
            "Label Sequence \(target.sequenceSlot) \"\(commandQuotable(sequenceName))\"",
            "Label Timecode \(target.timecodeSlot) \"\(commandQuotable(timecodeName))\""
        ]

        return MA2PushPlan(
            sequenceUpload: sequenceUpload,
            timecodeUpload: timecodeUpload,
            commands: commands
        )
    }

    /// MA2 command lines quote names with double quotes and have no documented
    /// escape for embedded ones — strip them rather than break the command.
    private static func commandQuotable(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "")
    }
}
