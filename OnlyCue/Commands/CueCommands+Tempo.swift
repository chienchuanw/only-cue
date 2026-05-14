import Foundation

/// Per-cue tempo commands (v11). The cue's time is bar 1, beat 1 of the segment
/// it opens; `bpm`/`beatsPerBar` are clamped (20…400 / 1…16) and either nil
/// (no tempo change at this cue) or set. Passing both `nil` clears tempo from
/// the cue.
///
/// Legacy section-based commands (`setTempoMap`, `addTempoSection`, etc.) live
/// at the bottom as `@available(*, deprecated)` no-op stubs so the soon-to-be-
/// deleted `TempoMapSheet` keeps compiling. Both the sheet and these stubs go
/// away in #248.
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

    // MARK: - Legacy stubs (deleted in #248)

    @available(*, deprecated, message: "Removed in #248 along with TempoMapSheet")
    static func setTempoMap(_ map: TempoMap, item itemID: MediaItem.ID, document: CueListDocument, undoManager: UndoManager?) {
        _ = (map, itemID, document, undoManager)
    }

    @available(*, deprecated, message: "Removed in #248 along with TempoMapSheet")
    static func addTempoSection(
        atSeconds seconds: TimeInterval,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        _ = (seconds, itemID, document, undoManager)
    }

    @available(*, deprecated, message: "Removed in #248 along with TempoMapSheet")
    static func splitTempoSection(
        atSeconds seconds: TimeInterval,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        _ = (seconds, itemID, document, undoManager)
    }

    @available(*, deprecated, message: "Removed in #248 along with TempoMapSheet")
    static func removeTempoSection(
        _ id: TempoSection.ID,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        _ = (id, itemID, document, undoManager)
    }

    @available(*, deprecated, message: "Removed in #248 along with TempoMapSheet")
    static func updateTempoSection(
        _ id: TempoSection.ID,
        startSeconds: TimeInterval? = nil,
        bpm: Double? = nil,
        beatsPerBar: Int? = nil,
        downbeatOffsetSeconds: TimeInterval? = nil,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        _ = (id, startSeconds, bpm, beatsPerBar, downbeatOffsetSeconds, itemID, document, undoManager)
    }

    @available(*, deprecated, message: "Removed in #248 along with TempoMapSheet")
    static func clearTempoMap(item itemID: MediaItem.ID, document: CueListDocument, undoManager: UndoManager?) {
        _ = (itemID, document, undoManager)
    }
}
