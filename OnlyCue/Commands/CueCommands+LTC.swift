import Foundation

@MainActor
extension CueCommands {

    /// Remembers a song's detected LTC (#754), write-once: only stores when the
    /// item has none yet, so a rare false-positive re-detection can't clobber a
    /// good value — an explicit Re-detect (Clear + remember) is the way to refresh.
    /// No-op for an unknown id. Non-undoable: this is derived data, not authored;
    /// Cmd-Z should not resurrect a stale LTC (Re-detect / Clear are the controls).
    /// Contrast `setLTCChannelSelection`, which is authored and undoable.
    static func rememberLTC(
        _ track: StripedTimecodeTrack,
        forItemID id: MediaItem.ID,
        document: CueListDocument
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        guard document.model.items[index].rememberedLTC == nil else { return }
        document.model.items[index].rememberedLTC = track
    }

    /// Upgrades a remembered LTC with the bounds the full-file pass measured
    /// (#793). `rememberLTC` is deliberately write-once, so Phase 2 — which
    /// always runs after Phase 1 has filled the slot — needs its own door.
    ///
    /// Guarded to the same channel: refining is for adding measured bounds to
    /// an answer already agreed on, never for overruling which channel the
    /// LTC is on. Non-undoable, like its neighbours, because this is derived
    /// data (contrast `setLTCChannelSelection`, which is authored and IS
    /// undoable).
    /// A `nil` existing value fails the guard on purpose: it means the user
    /// cleared the remembered LTC while the pass was still running, and a
    /// refinement must not resurrect what Clear removed.
    static func refineRememberedLTC(
        _ track: StripedTimecodeTrack,
        forItemID id: MediaItem.ID,
        document: CueListDocument
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        let existing = document.model.items[index].rememberedLTC
        guard existing?.ltcChannel == track.ltcChannel else { return }
        document.model.items[index].rememberedLTC = track
    }

    /// Forgets a song's remembered LTC (#754) — the Clear action, and the relink
    /// reset (a new file may not carry the old LTC). No-op for an unknown id.
    /// Non-undoable, like `rememberLTC`. Contrast `setLTCChannelSelection`, which
    /// is authored and undoable.
    static func clearRememberedLTC(forItemID id: MediaItem.ID, document: CueListDocument) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        document.model.items[index].rememberedLTC = nil
    }

    /// Records which channel the user says carries LTC (#793).
    ///
    /// Undoable, deliberately unlike `rememberLTC` / `clearRememberedLTC` /
    /// `refineRememberedLTC` in this same file. Those three carry data derived
    /// from the media, where Cmd-Z resurrecting a stale value would be wrong.
    /// This one carries a decision the user made, and every user decision in
    /// this app is undoable. Do not "make these consistent".
    static func setLTCChannelSelection(
        _ selection: LTCChannelSelection,
        forItemID id: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        let previous = document.model.items[index].ltcChannelSelection
        guard previous != selection else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].ltcChannelSelection = selection
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setLTCChannelSelection(
                previous, forItemID: id, document: doc, undoManager: undoManager
            )
        }
        undoManager?.setActionName("Set LTC Channel")
    }
}
