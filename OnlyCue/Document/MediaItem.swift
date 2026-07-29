import Foundation

struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference
    var cues: [Cue]
    /// Frames since `00:00:00:00` at the project framerate. Replaces the
    /// schema-v9 project-wide `timecodeSettings.startOffsetFrames` (v10).
    var startTimecodeFrames: Int = 0
    /// Persistent per-clip silence flag for the LTC output channel. Encoder
    /// keeps running; only the LTC channel's samples are zeroed when set.
    var ltcMuted: Bool = false
    /// Per-clip user-facing display override. nil/empty/whitespace falls back
    /// to `media.displayName` (the file basename). v12.
    var alternateName: String?
    /// Timestamped lyrics for this clip — a per-`MediaItem` reference/HUD layer
    /// decoupled from cues (ADR-022). Empty by default. Schema v13.
    var lyrics: Lyrics = .empty
    /// Last grandMA2 push destination for this clip (#683). nil until the clip
    /// is first pushed. Schema v17.
    var ma2PushTarget: MA2PushTarget?
}

extension MediaItem {
    /// User-facing name for this clip. Returns the trimmed `alternateName` when
    /// set to a non-empty string, otherwise falls back to the file basename in
    /// `media.displayName`. Use everywhere the clip's name is shown to the
    /// user; keep `media.displayName` for file-system lookups.
    var resolvedName: String {
        if let trimmed = alternateName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            return trimmed
        }
        return media.displayName
    }
}

extension MediaItem {

    enum PlayheadStep {
        case previous
        case next
    }

    /// Returns the cue to seek to when stepping the playhead one cue earlier
    /// (`.previous`) or later (`.next`). Both directions step relative to the
    /// *active* cue — the one the playhead is currently inside — so a press
    /// means the same thing wherever between cues the playhead happens to sit.
    /// Returns `nil` at the ends of the cue list (no wrap-around) and on empty
    /// cues.
    /// `typeID` (nil = all cues, the default) filters stepping to a single cue
    /// type — Show mode's GO-by-type (#657); the active cue is then resolved
    /// within the filtered set, so stepping stays inside one type.
    ///
    /// `.previous` used to be a plain `time < currentTime`, which during
    /// playback selects the active cue itself — so the button rewound the
    /// current cue instead of stepping back, and behaved differently depending
    /// on whether the playhead landed exactly on a cue (#709).
    func cue(
        steppingFrom currentTime: TimeInterval,
        direction: PlayheadStep,
        typeID: CuePointType.ID? = nil
    ) -> Cue? {
        let candidates = typeID.map { id in cues.filter { $0.typeID == id } } ?? cues
        switch direction {
        case .previous:
            guard let active = candidates.filter({ $0.time <= currentTime })
                .max(by: { $0.time < $1.time })
            else { return nil }
            return candidates.filter { $0.time < active.time }.max(by: { $0.time < $1.time })
        case .next:
            return candidates.filter { $0.time > currentTime }.min(by: { $0.time < $1.time })
        }
    }

    /// Returns the cue currently "active" at `currentTime` — the cue with the
    /// largest `time <= currentTime`. Use case: the notes overlay shows the
    /// notes of whichever cue the show caller is "in" right now. Returns nil
    /// when the playhead is before the first cue or `cues` is empty; returns
    /// the last cue when the playhead is past it (notes persist until show end).
    /// Inclusive on `currentTime` (`<=`), unlike `cue(steppingFrom:direction:)`
    /// which is strict — these are different semantic queries.
    /// `typeID` (nil = all cues, the default) filters to a single cue type —
    /// Show mode's GO-by-type highlight / notes (#657).
    func activeCue(at currentTime: TimeInterval, typeID: CuePointType.ID? = nil) -> Cue? {
        let candidates = typeID.map { id in cues.filter { $0.typeID == id } } ?? cues
        return candidates.filter { $0.time <= currentTime }.max(by: { $0.time < $1.time })
    }
}
