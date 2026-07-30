import Foundation

/// Remembers what a media file's LTC scan found, so switching between clips
/// doesn't re-read and re-decode audio that has already been examined.
///
/// Negative results are cached too, and that is the point: establishing that a
/// file has *no* LTC costs a full scan of every channel across both scan
/// windows — strictly more work than finding some — so a hits-only cache would
/// re-scan every ordinary music file on every clip switch (#712).
///
/// Keyed by `MediaItem.ID`, not by file URL: the id is stable for the life of
/// the document and needs no bookmark resolution to compute. In-memory only —
/// the decoded timecode is derived from the media, never authored data, so
/// nothing here is persisted and no `.cuelist` schema is involved.
@MainActor
final class StripedTimecodeCache {

    static let shared = StripedTimecodeCache()

    /// Nested optional on purpose: the outer level is "have we looked?", the
    /// inner is "did we find anything?".
    private var entries: [MediaItem.ID: StripedTimecodeTrack?] = [:]

    /// The track for `id`, decoding via `decode` only on the first ask.
    func track(
        for id: MediaItem.ID,
        decode: () async -> StripedTimecodeTrack?
    ) async -> StripedTimecodeTrack? {
        if let cached = entries[id] { return cached }
        let decoded = await decode()
        // A cancelled scan reports whatever it had reached, which is not an
        // answer about the file — remembering it would make an interrupted
        // clip switch permanently mislabel that file for the rest of the run.
        guard !Task.isCancelled else { return decoded }
        entries[id] = decoded
        return decoded
    }

    /// Forgets `id`'s scan, so the next ask re-reads the audio. Needed because
    /// the key is the item id, which survives a relink: the user can point the
    /// same item at a different file, and a remembered "no LTC" would otherwise
    /// outlive the file it was true of.
    func invalidate(_ id: MediaItem.ID) {
        entries.removeValue(forKey: id)
    }
}
