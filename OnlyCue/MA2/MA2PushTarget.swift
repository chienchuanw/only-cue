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
    /// Executor page the sequence is assigned to (`page.exec`). `nil` = leave the
    /// sequence unassigned (#764) — Store it into the pool and let the operator
    /// place it. Page and number are set or cleared together.
    var executorPage: Int?
    /// Executor number within the page (`page.exec`). `nil` = unassigned (#764).
    var executorNumber: Int?
    /// Command each timecode event fires on the executor.
    var timecodeCommand: MA2TimecodeCommand
    /// Cue-type filter used for the last push. Empty = all types
    /// (same convention as `CueExportFilter`).
    var includedTypeIDs: Set<UUID>

    /// User-facing English sequence name (#686). `nil` = derive from the clip's
    /// sanitized resolved name at push time. Persisted (schema v18).
    var sequenceName: String?

    /// Explicit memberwise init so `sequenceName` can default to nil and existing
    /// call sites stay source-compatible (Codable/Equatable stay synthesized).
    init(
        sequenceSlot: Int,
        timecodeSlot: Int,
        executorPage: Int?,
        executorNumber: Int?,
        timecodeCommand: MA2TimecodeCommand,
        includedTypeIDs: Set<UUID>,
        sequenceName: String? = nil
    ) {
        self.sequenceSlot = sequenceSlot
        self.timecodeSlot = timecodeSlot
        self.executorPage = executorPage
        self.executorNumber = executorNumber
        self.timecodeCommand = timecodeCommand
        self.includedTypeIDs = includedTypeIDs
        self.sequenceName = sequenceName
    }

    /// The executor as a `page.exec` pair when assigned, else `nil` (#764). Page and
    /// number are only meaningful together, so a half-set executor resolves to `nil`.
    var executor: (page: Int, number: Int)? {
        guard let page = executorPage, let number = executorNumber else { return nil }
        return (page, number)
    }

    /// Console slots, pages and executors are 1-based; anything below 1 would
    /// emit invalid XML indices (`index="-1"`) and telnet commands
    /// (`Delete Sequence 0`). The executor is optional (#764): valid when both
    /// fields are cleared (unassigned) or both are 1-based. The push sheet refuses
    /// invalid targets.
    var isValid: Bool {
        guard sequenceSlot >= 1, timecodeSlot >= 1 else { return false }
        switch (executorPage, executorNumber) {
        case (nil, nil):
            return true
        case let (page?, number?):
            return page >= 1 && number >= 1
        default:
            return false  // half-set executor
        }
    }
}
