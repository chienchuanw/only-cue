import Foundation

/// Per-cue tempo command (v11). The cue's time is bar 1, beat 1 of the segment
/// it opens; `bpm`/`beatsPerBar` are clamped (20…400 / 1…16) and either nil
/// (no tempo change at this cue) or set. Passing both `nil` clears tempo from
/// the cue.
@MainActor
extension CueCommands {

    // swiftlint:disable:next function_parameter_count
    static func setCueTempo(
        cueID: Cue.ID,
        bpm: Double?,
        beatsPerBar: Int?,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let itemIndex = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        guard let cueIndex = document.model.items[itemIndex].cues.firstIndex(where: { $0.id == cueID }) else { return }

        // NaN / infinity defeats min/max clamping (IEEE 754 comparisons with
        // NaN are always false). Drop to nil rather than corrupt the model.
        let clampedBPM: Double?
        if let bpm, bpm.isFinite {
            clampedBPM = min(max(bpm, 20), 400)
        } else {
            clampedBPM = nil
        }
        let clampedMeter = beatsPerBar.map { max(1, min($0, 16)) }
        let before = document.model.items[itemIndex].cues[cueIndex]
        guard before.bpm != clampedBPM || before.beatsPerBar != clampedMeter else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        document.model.items[itemIndex].cues[cueIndex].bpm = clampedBPM
        document.model.items[itemIndex].cues[cueIndex].beatsPerBar = clampedMeter
        let oldBPM = before.bpm
        let oldMeter = before.beatsPerBar
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setCueTempo(
                cueID: cueID,
                bpm: oldBPM,
                beatsPerBar: oldMeter,
                item: itemID,
                document: doc,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName("Change Cue Tempo")
    }
}
