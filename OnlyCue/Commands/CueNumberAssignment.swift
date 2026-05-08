import Foundation

enum CueNumberAssignment {

    /// Existing cues' numbers are never shifted — the rule produces a fractional value
    /// when needed so the new cue slots between its time-neighbors.
    static func next(forInsertionAt time: TimeInterval, in cues: [Cue]) -> Double {
        if cues.isEmpty { return 1.0 }
        let sorted = cues.sorted { $0.time < $1.time }
        let earlier = sorted.last { $0.time <= time }
        let later = sorted.first { $0.time > time }
        switch (earlier, later) {
        case (nil, .some(let next)):
            return next.cueNumber - 1.0
        case (.some(let prev), nil):
            return prev.cueNumber + 1.0
        case (.some(let prev), .some(let next)):
            return (prev.cueNumber + next.cueNumber) / 2.0
        case (nil, nil):
            preconditionFailure("CueNumberAssignment.next: cues non-empty but neither neighbor found — every cue's time partitions on \(time)")
        }
    }
}
