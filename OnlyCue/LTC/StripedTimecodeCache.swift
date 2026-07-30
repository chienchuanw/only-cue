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
        entries[id] = decoded
        return decoded
    }

    /// Drops everything — for tests, and for a future "rescan" affordance.
    func removeAll() {
        entries.removeAll()
    }
}
