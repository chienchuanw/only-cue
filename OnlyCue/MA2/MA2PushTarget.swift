import Foundation

/// The timecode-event command written for each cue when pushing to grandMA2
/// (#683). Raw values are persisted in `.cuelist` documents — do not rename.
/// Default is `.goto`: when jumping around in rehearsal a Goto lands on the
/// exact cue, while Go only ever steps forward and drifts out of sync.
enum MA2TimecodeCommand: String, Codable, Equatable, CaseIterable {
    case go
    case goto
}

/// Per-clip grandMA2 push destination (#683), persisted in the document so a
/// re-push of the same song lands in the same console slots on any machine.
/// Schema v17.
struct MA2PushTarget: Codable, Equatable {
    /// Sequence pool slot the cues are imported into.
    var sequenceSlot: Int
    /// Timecode pool slot the timecode show is imported into.
    var timecodeSlot: Int
    /// Executor page the sequence is assigned to (`page.exec`).
    var executorPage: Int
    /// Executor number within the page (`page.exec`).
    var executorNumber: Int
    /// Command each timecode event fires on the executor.
    var timecodeCommand: MA2TimecodeCommand
    /// Cue-type filter used for the last push. Empty = all types
    /// (same convention as `CueExportFilter`).
    var includedTypeIDs: Set<UUID>

    /// Console slots, pages and executors are 1-based; anything below 1 would
    /// emit invalid XML indices (`index="-1"`) and telnet commands
    /// (`Delete Sequence 0`). The push sheet refuses invalid targets.
    var isValid: Bool {
        sequenceSlot >= 1 && timecodeSlot >= 1 && executorPage >= 1 && executorNumber >= 1
    }
}
