import Foundation

enum CueNumberAssignment {

    /// Existing cues' numbers are never shifted — the rule produces a fractional value
    /// when needed so the new cue slots between its time-neighbors. Unnumbered cues
    /// (those with `cueNumber == nil`) are skipped when picking neighbors; the rule
    /// only considers cues that already carry a number.
    static func next(forInsertionAt time: TimeInterval, in cues: [Cue]) -> Double {
        let numbered = cues.compactMap { cue -> (TimeInterval, Double)? in
            cue.cueNumber.map { (cue.time, $0) }
        }
        if numbered.isEmpty { return 1.0 }
        let earlier = numbered.filter { $0.0 <= time }.max(by: { $0.0 < $1.0 })
        let later = numbered.filter { $0.0 > time }.min(by: { $0.0 < $1.0 })
        switch (earlier, later) {
        case (nil, .some(let next)):
            return next.1 - 1.0
        case (.some(let prev), nil):
            return prev.1 + 1.0
        case (.some(let prev), .some(let next)):
            return (prev.1 + next.1) / 2.0
        case (nil, nil):
            preconditionFailure(
                "CueNumberAssignment.next: numbered cues non-empty but neither neighbor found at time \(time)"
            )
        }
    }
}
