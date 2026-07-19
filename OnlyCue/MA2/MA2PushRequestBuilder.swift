import Foundation

/// Glue between a media item and a push plan (#683): applies the saved
/// cue-type filter (`CueExportFilter` contract: empty = all), runs the
/// pre-flight, and assembles the plan from the clip's resolved name, start
/// timecode and duration.
enum MA2PushRequestBuilder {

    enum Outcome: Equatable {
        case blocked([MA2PushPreflight.Issue])
        case ready(MA2PushPlan)
    }

    static func outcome(
        item: MediaItem,
        target: MA2PushTarget,
        framerate: SMPTEFramerate,
        showfile: String,
        datetime: String
    ) -> Outcome {
        let cues = CueExportFilter.cues(item.cues, onlyTypeIDs: target.includedTypeIDs)
        let issues = MA2PushPreflight.validate(cues)
        guard issues.isEmpty else { return .blocked(issues) }

        let framesPerSecond = Double(framerate.framesPerSecond)
        let lengthFrames = item.startTimecodeFrames
            + Int((item.media.duration * framesPerSecond).rounded(.up))
        let sequenceName = item.resolvedName

        return .ready(MA2PushPlanner.plan(
            cues: cues,
            target: target,
            sequenceName: sequenceName,
            timecodeName: "\(sequenceName) TC",
            startTimecodeFrames: item.startTimecodeFrames,
            lengthFrames: lengthFrames,
            framerate: framerate,
            showfile: showfile,
            datetime: datetime
        ))
    }

    enum CommandOutcome: Equatable {
        case blocked([MA2PushPreflight.Issue])
        case ready([String])
    }

    /// Approach A (#683): the same filter + pre-flight, then a pure telnet
    /// command list (no XML, no FTP). `showfile` / `datetime` are irrelevant to
    /// the command path and omitted.
    static func commandOutcome(
        item: MediaItem,
        target: MA2PushTarget,
        framerate: SMPTEFramerate
    ) -> CommandOutcome {
        let cues = CueExportFilter.cues(item.cues, onlyTypeIDs: target.includedTypeIDs)
        let issues = MA2PushPreflight.validate(cues)
        guard issues.isEmpty else { return .blocked(issues) }
        return .ready(MA2CommandPlanner.commands(
            cues: cues,
            target: target,
            sequenceName: item.resolvedName,
            startTimecodeFrames: item.startTimecodeFrames,
            framerate: framerate
        ))
    }
}
