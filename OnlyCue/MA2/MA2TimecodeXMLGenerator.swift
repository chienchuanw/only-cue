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
        // The sequence import is number-ordered; the third <No> of each event's
        // cue reference is that number-sorted 1-based index. Events themselves
        // run in time order (cue numbers need not be monotonic with time).
        let numberOrdered = cues.sorted { ($0.cueNumber ?? 0) < ($1.cueNumber ?? 0) }
        var sequenceIndexByCueID: [UUID: Int] = [:]
        for (position, cue) in numberOrdered.enumerated() {
            sequenceIndexByCueID[cue.id] = position + 1
        }
        let timeOrdered = cues.sorted { $0.time < $1.time }

        let escape = MA2SequenceXMLGenerator.escape

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
        lines.append("<?xml-stylesheet type=\"text/xsl\" href=\"styles/timecode@sheet.xsl\"?>")
        lines.append(
            "<MA xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
            + "xmlns=\"http://schemas.malighting.de/grandma2/xml/MA\" "
            + "xsi:schemaLocation=\"http://schemas.malighting.de/grandma2/xml/MA "
            + "http://schemas.malighting.de/grandma2/xml/3.9.60/MA.xsd\" "
            + "major_vers=\"3\" minor_vers=\"9\" stream_vers=\"60\">"
        )
        lines.append("\t<Info datetime=\"\(escape(datetime))\" showfile=\"\(escape(showfile))\" />")
        lines.append(
            "\t<Timecode index=\"\(timecodeSlot - 1)\" name=\"\(escape(timecodeName))\" "
            + "lenght=\"\(lengthFrames)\" play_mode=\"Play\" "
            + "frame_format=\"\(framerate.framesPerSecond) FPS\""
        // `lenght` (sic) is MA2's real attribute spelling. The TC-slot link
        // (which LTC input drives the show) is left for the operator: imports
        // without a `slot` attribute keep the pool default.
            + ">"
        )
        lines.append("\t\t<Track index=\"0\" active=\"true\" expanded=\"true\">")
        // The track object is the executor: object path 30/1/page/exec; the
        // name attribute is cosmetic ("SequName page.exec" in real exports).
        lines.append("\t\t\t<Object name=\"\(escape(sequenceName)) \(executorPage).\(executorNumber)\">")
        for number in [30, 1, executorPage, executorNumber] {
            lines.append("\t\t\t\t<No>\(number)</No>")
        }
        lines.append("\t\t\t</Object>")
        lines.append("\t\t\t<SubTrack index=\"0\">")
        for (eventIndex, cue) in timeOrdered.enumerated() {
            lines.append(contentsOf: eventElement(
                cue,
                eventIndex: eventIndex,
                sequenceIndex: sequenceIndexByCueID[cue.id] ?? 0,
                sequenceSlot: sequenceSlot,
                command: command,
                startTimecodeFrames: startTimecodeFrames,
                framerate: framerate
            ))
        }
        lines.append("\t\t\t</SubTrack>")
        lines.append("\t\t</Track>")
        lines.append("\t</Timecode>")
        lines.append("</MA>")
        return lines.joined(separator: "\n")
    }

    // swiftlint:disable:next function_parameter_count
    private static func eventElement(
        _ cue: Cue,
        eventIndex: Int,
        sequenceIndex: Int,
        sequenceSlot: Int,
        command: MA2TimecodeCommand,
        startTimecodeFrames: Int,
        framerate: SMPTEFramerate
    ) -> [String] {
        // For `.fps30drop` this emits *physical* frame counts under a
        // non-drop "30 FPS" format label (MA2 has no drop-frame format); how
        // the console maps them when chasing DF LTC is a rig-validation item
        // (#683 plan step 13) — do not ship DF pushes as verified until then.
        let frame = startTimecodeFrames + Int((cue.time * Double(framerate.framesPerSecond)).rounded())
        var attributes = ["index=\"\(eventIndex)\""]
        if frame != 0 {
            // Real exports omit `time` at frame 0.
            attributes.append("time=\"\(frame)\"")
        }
        attributes.append("command=\"\(commandKeyword(command))\"")
        attributes.append("pressed=\"true\"")
        attributes.append("step=\"\(eventIndex + 1)\"")

        let cueName = cue.name.isEmpty ? "" : " name=\"\(MA2SequenceXMLGenerator.escape(cue.name))\""
        var lines: [String] = []
        lines.append("\t\t\t\t<Event \(attributes.joined(separator: " "))>")
        lines.append("\t\t\t\t\t<Cue\(cueName)>")
        // Cue reference object path: 1 = sequence object type, then the
        // sequence pool slot, then the number-sorted cue index within it.
        for number in [1, sequenceSlot, sequenceIndex] {
            lines.append("\t\t\t\t\t\t<No>\(number)</No>")
        }
        lines.append("\t\t\t\t\t</Cue>")
        lines.append("\t\t\t\t</Event>")
        return lines
    }

    /// XML wants the MA keyword casing (`Go` / `Goto`), not the persisted
    /// lowercase raw value.
    private static func commandKeyword(_ command: MA2TimecodeCommand) -> String {
        switch command {
        case .go: return "Go"
        case .goto: return "Goto"
        }
    }
}
