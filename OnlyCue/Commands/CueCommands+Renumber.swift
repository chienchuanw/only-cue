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
            assigned[cue.id] = (raw * 1000).rounded() / 1000 // keep <= 3 decimals
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
