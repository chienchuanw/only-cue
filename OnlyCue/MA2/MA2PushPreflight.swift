import Foundation

/// Pre-flight validation for a grandMA2 push (#683): after the cue-type filter,
/// every cue must carry a unique, non-nil `cueNumber` — OnlyCue and MA2 cue
/// numbers must match so called cues agree across both. No renumbering, no
/// auto-fill: offending cues are named and the push is blocked.
enum MA2PushPreflight {

    enum Issue: Equatable {
        /// The filtered cue set is empty — almost always a filter mistake.
        case noCues
        /// Cues with no `cueNumber`, in cue-list order.
        case unnumbered(cues: [Cue])
        /// Cues sharing one `cueNumber`, in cue-list order.
        case duplicateNumber(number: Double, cues: [Cue])
    }

    static func validate(_ cues: [Cue]) -> [Issue] {
        guard !cues.isEmpty else { return [.noCues] }

        var issues: [Issue] = []

        let unnumbered = cues.filter { $0.cueNumber == nil }
        if !unnumbered.isEmpty {
            issues.append(.unnumbered(cues: unnumbered))
        }

        // Group numbered cues by number, keeping first-appearance order of the
        // duplicated numbers so the report is stable across runs.
        var cuesByNumber: [Double: [Cue]] = [:]
        var numberOrder: [Double] = []
        for cue in cues {
            guard let number = cue.cueNumber else { continue }
            if cuesByNumber[number] == nil { numberOrder.append(number) }
            cuesByNumber[number, default: []].append(cue)
        }
        for number in numberOrder {
            let group = cuesByNumber[number] ?? []
            if group.count > 1 {
                issues.append(.duplicateNumber(number: number, cues: group))
            }
        }

        return issues
    }
}
