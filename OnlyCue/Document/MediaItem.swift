import Foundation

struct MediaItem: Identifiable, Equatable {
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
    /// Per-clip source-audio playback preference (#715). When `false` (the
    /// default, "music-only"), the LTC timecode tone channel is muted during
    /// playback so the audience hears only the music content. When `true`
    /// ("original"), the file plays back as-is — timecode tone included.
    /// This is a user-facing preference distinct from `ltcMuted`, which
    /// controls LTC *output* (the encoder → console path) regardless of what
    /// the speaker hears. Schema v19.
    var playsOriginalSourceAudio: Bool = false
    /// The song's remembered LTC (#754). Written once when detection first
    /// succeeds; used as a fallback when a later heuristic scan fails (so the
    /// music-only muting, FILE readout, and detected badge don't vanish). nil
    /// until a successful detection or after Clear/relink. Schema v20.
    var rememberedLTC: StripedTimecodeTrack?
}

// MARK: - Codable

extension MediaItem: Codable {

    // Explicit CodingKeys so that new Bool fields with property defaults can
    // use `decodeIfPresent` — Swift's synthesized `Decodable` throws on a
    // missing required key even when a property default exists.
    enum CodingKeys: String, CodingKey {
        case id
        case media
        case cues
        case startTimecodeFrames
        case ltcMuted
        case alternateName
        case lyrics
        case ma2PushTarget
        case playsOriginalSourceAudio
        case rememberedLTC
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        media = try container.decode(MediaReference.self, forKey: .media)
        cues = try container.decode([Cue].self, forKey: .cues)
        startTimecodeFrames = try container.decodeIfPresent(Int.self, forKey: .startTimecodeFrames) ?? 0
        ltcMuted = try container.decodeIfPresent(Bool.self, forKey: .ltcMuted) ?? false
        alternateName = try container.decodeIfPresent(String.self, forKey: .alternateName)
        lyrics = try container.decodeIfPresent(Lyrics.self, forKey: .lyrics) ?? .empty
        ma2PushTarget = try container.decodeIfPresent(MA2PushTarget.self, forKey: .ma2PushTarget)
        // v18 documents lack this key; default to false (music-only).
        playsOriginalSourceAudio = try container.decodeIfPresent(Bool.self, forKey: .playsOriginalSourceAudio) ?? false
        // v19 documents lack this key; default to nil (no remembered LTC).
        rememberedLTC = try container.decodeIfPresent(StripedTimecodeTrack.self, forKey: .rememberedLTC)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(media, forKey: .media)
        try container.encode(cues, forKey: .cues)
        try container.encode(startTimecodeFrames, forKey: .startTimecodeFrames)
        try container.encode(ltcMuted, forKey: .ltcMuted)
        try container.encodeIfPresent(alternateName, forKey: .alternateName)
        try container.encode(lyrics, forKey: .lyrics)
        try container.encodeIfPresent(ma2PushTarget, forKey: .ma2PushTarget)
        try container.encode(playsOriginalSourceAudio, forKey: .playsOriginalSourceAudio)
        try container.encodeIfPresent(rememberedLTC, forKey: .rememberedLTC)
    }
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
    ///
    /// Note the consequence past the last cue: with cues at 5/10/15 and the
    /// playhead at 20 the active cue is 15, so `.previous` returns 10 and the
    /// last cue is not reachable by stepping back (`.next` is already nil
    /// there). With a single cue — or a single cue of the filtered type —
    /// `.previous` is therefore always nil. That is the cost of "one press,
    /// one meaning"; `Stop` and a direct click still reach those cues.
    func cue(
        steppingFrom currentTime: TimeInterval,
        direction: PlayheadStep,
        typeID: CuePointType.ID? = nil
    ) -> Cue? {
        let candidates = typeID.map { id in cues.filter { $0.typeID == id } } ?? cues
        switch direction {
        case .previous:
            guard let active = activeCue(at: currentTime, typeID: typeID) else { return nil }
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
    /// This is also the anchor `cue(steppingFrom:direction:)` steps away from
    /// (#709), so the two stay consistent by construction.
    /// `typeID` (nil = all cues, the default) filters to a single cue type —
    /// Show mode's GO-by-type highlight / notes (#657).
    func activeCue(at currentTime: TimeInterval, typeID: CuePointType.ID? = nil) -> Cue? {
        let candidates = typeID.map { id in cues.filter { $0.typeID == id } } ?? cues
        return candidates.filter { $0.time <= currentTime }.max(by: { $0.time < $1.time })
    }
}
