import Foundation

/// Generates the grandMA2 timecode-show import XML (#683): one Go/Goto event
/// per cue on the chosen executor, times in **frames** at the project SMPTE
/// framerate, offset by the clip's start timecode. Structure per the spec's
/// `## XML schemas` section (verified against a real v3.9.60 console export).
enum MA2TimecodeXMLGenerator {

    // swiftlint:disable:next function_parameter_count
    static func xml(
        cues: [Cue],
        timecodeSlot: Int,
        timecodeName: String,
        sequenceSlot: Int,
        sequenceName: String,
        executorPage: Int,
        executorNumber: Int,
        command: MA2TimecodeCommand,
        startTimecodeFrames: Int,
        lengthFrames: Int,
        framerate: SMPTEFramerate,
        showfile: String,
        datetime: String
    ) -> String {
        fatalError("unimplemented")
    }
}
