import Foundation

extension CueCommands {

    /// Resequences the `cueNumber` of the selected cues in time order, starting
    /// at `start` and incrementing by `interval` (#535). This is a pure relabel:
    /// cue *times* never change, the array is not re-sorted (only `cueNumber`
    /// changes), and unselected cues keep their existing numbers. Assigning in
    /// time order keeps the renumbered cues monotonic with time. Committed as a
    /// single undo step.
    static func renumberSelected(
        _ ids: Set<Cue.ID>,
        start: Double,
        interval: Double,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard !ids.isEmpty else { return }
        let cues = document.model.activeItem?.cues ?? []
        let ordered = cues.filter { ids.contains($0.id) }.sorted { $0.time < $1.time }
        guard !ordered.isEmpty else { return }

        var assigned: [Cue.ID: Double] = [:]
        for (index, cue) in ordered.enumerated() {
            let raw = start + Double(index) * interval
            let number = (raw * 1000).rounded() / 1000 // keep <= 3 decimals
            // Reject the whole run if any number leaves grandMA2's numbering
            // domain (#830). `RenumberCuesSheet` binds `start` to a plain
            // `TextField` — the `Stepper(in:)` beside it constrains only the
            // stepper buttons — so a negative or absurd value arrives here
            // unfiltered and would otherwise reach the MA2 generators, which
            // spell it as the malformed token `-1.-5`. Rejecting whole rather
            // than per-cue: half a renumber is worse than none.
            guard CueNumberValidator.isInDomain(number) else { return }
            assigned[cue.id] = number
        }

        mutateCues(document, undoManager: undoManager, actionName: "Renumber Cues") { current in
            current.map { cue in
                guard let number = assigned[cue.id] else { return cue }
                var copy = cue
                copy.cueNumber = number
                return copy
            }
        }
    }
}
