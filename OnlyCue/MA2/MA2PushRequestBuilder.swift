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
        fatalError("unimplemented")
    }
}
