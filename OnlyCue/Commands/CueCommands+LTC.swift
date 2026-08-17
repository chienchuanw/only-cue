import Foundation

@MainActor
extension CueCommands {

    /// Remembers a song's detected LTC (#754), write-once: only stores when the
    /// item has none yet, so a rare false-positive re-detection can't clobber a
    /// good value — an explicit Re-detect (Clear + remember) is the way to refresh.
    /// No-op for an unknown id. Non-undoable: this is derived data, not authored;
    /// Cmd-Z should not resurrect a stale LTC (Re-detect / Clear are the controls).
    static func rememberLTC(
        _ track: StripedTimecodeTrack,
        forItemID id: MediaItem.ID,
        document: CueListDocument
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        guard document.model.items[index].rememberedLTC == nil else { return }
        document.model.items[index].rememberedLTC = track
    }

    /// Forgets a song's remembered LTC (#754) — the Clear action, and the relink
    /// reset (a new file may not carry the old LTC). No-op for an unknown id.
    /// Non-undoable, like `rememberLTC`.
    static func clearRememberedLTC(forItemID id: MediaItem.ID, document: CueListDocument) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        document.model.items[index].rememberedLTC = nil
    }
}
