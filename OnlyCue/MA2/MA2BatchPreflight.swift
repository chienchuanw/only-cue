import Foundation

/// Pre-flight for a multi-song grandMA2 push (#765). Each selected song is validated with
/// the existing `MA2PushPreflight` — but on its *post-auto-fill* cues (#763), so a fillable
/// gap is not reported as unnumbered — and the batch as a whole is checked for cross-song
/// collisions: sequence slots must be unique, and assigned executors must be unique
/// (unassigned executors never collide, #764). All-or-nothing: the sheet blocks the push
/// while `isClear` is false.
enum MA2BatchPreflight {

    /// One selected song: its item id, its *full* cue list, the global type filter, and its
    /// push target. Pre-flight applies auto-fill to the full list and then the filter — the
    /// same order the push uses (`MA2BatchPushPlan`) — so the preview matches what is sent.
    struct Song: Equatable {
        let itemID: MediaItem.ID
        let cues: [Cue]
        let includedTypeIDs: Set<UUID>
        let target: MA2PushTarget
    }

    /// Cue-level issues for a single song (only songs with issues appear).
    struct SongIssues: Equatable {
        let itemID: MediaItem.ID
        let issues: [MA2PushPreflight.Issue]
    }

    /// A collision between songs.
    enum CrossIssue: Equatable {
        case duplicateSequenceSlot(slot: Int, itemIDs: [MediaItem.ID])
        case duplicateExecutor(page: Int, number: Int, itemIDs: [MediaItem.ID])
    }

    struct Result: Equatable {
        var perSong: [SongIssues]
        var cross: [CrossIssue]
        var isClear: Bool { perSong.isEmpty && cross.isEmpty }
    }

    static func validate(_ songs: [Song]) -> Result {
        let perSong = songs.compactMap { song -> SongIssues? in
            let filtered = CueExportFilter.cues(autoFilled(song.cues), onlyTypeIDs: song.includedTypeIDs)
            let issues = MA2PushPreflight.validate(filtered)
            return issues.isEmpty ? nil : SongIssues(itemID: song.itemID, issues: issues)
        }

        var cross: [CrossIssue] = []
        for (slot, ids) in duplicates(songs.map { ($0.target.sequenceSlot, $0.itemID) }) {
            cross.append(.duplicateSequenceSlot(slot: slot, itemIDs: ids))
        }
        let executors = songs.compactMap { song in song.target.executor.map { ($0, song.itemID) } }
        for (executor, ids) in duplicates(executors.map { (Executor($0.0), $0.1) }) {
            cross.append(.duplicateExecutor(page: executor.page, number: executor.number, itemIDs: ids))
        }

        return Result(perSong: perSong, cross: cross)
    }

    /// Apply the auto-fill assignments in-memory so the pre-flight previews the numbers the
    /// push will use, without mutating the document.
    private static func autoFilled(_ cues: [Cue]) -> [Cue] {
        let assignments = CueNumberAutoFill.assignments(for: cues)
        guard !assignments.isEmpty else { return cues }
        return cues.map { cue in
            guard let number = assignments[cue.id] else { return cue }
            var copy = cue
            copy.cueNumber = number
            return copy
        }
    }

    /// Hashable executor key so a `(page, number)` pair can group by identity.
    private struct Executor: Hashable {
        let page: Int
        let number: Int
        init(_ pair: (page: Int, number: Int)) { page = pair.page; number = pair.number }
    }

    /// Group `(key, id)` pairs and return, in first-appearance order, the keys used by more
    /// than one id along with those ids.
    private static func duplicates<Key: Hashable>(_ entries: [(Key, MediaItem.ID)]) -> [(Key, [MediaItem.ID])] {
        var idsByKey: [Key: [MediaItem.ID]] = [:]
        var order: [Key] = []
        for (key, id) in entries {
            if idsByKey[key] == nil { order.append(key) }
            idsByKey[key, default: []].append(id)
        }
        return order.compactMap { key in
            let ids = idsByKey[key] ?? []
            return ids.count > 1 ? (key, ids) : nil
        }
    }
}
