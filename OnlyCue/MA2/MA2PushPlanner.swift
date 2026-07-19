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
        fatalError("unimplemented")
    }
}
