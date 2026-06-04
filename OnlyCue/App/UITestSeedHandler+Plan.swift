#if DEBUG
import Foundation

/// The seed *plan* for `UITestSeedHandler`: which media items, cues, lyrics, and
/// cue-point types each `--ui-test-seed=<key>` produces. Split from the launch /
/// document-IO logic in `UITestSeedHandler.swift` so each type stays small.
///
/// `cueTypes(for:)` and `itemSeeds(for:)` are internal so unit tests can pin the
/// plan without standing up the app or staging fixtures.
extension UITestSeedHandler {

    /// A bundled fixture file a seeded media item bookmarks. Audio items reuse
    /// the short clip unless they need a long timeline (the active set-list
    /// clip carries cues out to 6:48, so its waveform must span ~7:30).
    enum Fixture {
        case silentAudioShort   // silent-30s.m4a
        case silentAudioLong    // silent-450s.m4a (7:30 — spans the set-list cues)
        case toneAudioLong      // tone-450s.m4a (7:30, amplitude-modulated — renders a real waveform)
        case silentVideo        // silent-video-90s.mov

        var resource: (name: String, ext: String) {
            switch self {
            case .silentAudioShort: return ("silent-30s", "m4a")
            case .silentAudioLong: return ("silent-450s", "m4a")
            case .toneAudioLong: return ("tone-450s", "m4a")
            case .silentVideo: return ("silent-video-90s", "mov")
            }
        }
    }

    /// One cue in a seed plan. `typeIndex` selects into the project's
    /// `cuePointTypes` (built by `cueTypes(for:)`).
    struct CueSpec {
        let time: TimeInterval
        var name: String = ""
        var fadeTime: FadeTime = .zero
        var typeIndex: Int = 0
        var cueNumber: Double?
        var bpm: Double?
        var beatsPerBar: Int?
    }

    /// One media item in a seed plan. Exactly one item per plan is `isActive`
    /// (it becomes `ProjectModel.activeItemID`); only the active item carries
    /// cues and lyrics in the populated seeds.
    struct ItemSeed {
        let displayName: String
        let kind: MediaKind
        let duration: TimeInterval
        let fixture: Fixture
        var isActive: Bool = false
        var cues: [CueSpec] = []
        var lyrics: Lyrics = .empty
    }

    /// The cue-point-type palette for a seed. The populated `set-list-act-i`
    /// seed uses the six Figma type-bar colors (Cue frame `318:1228`); every
    /// other seed keeps the single legacy "General" type.
    static func cueTypes(for key: String) -> [CuePointType] {
        switch key {
        case "set-list-act-i", "video-project":
            return [
                CuePointType(id: UUID(), name: "Amber", colorHex: "#FFA94D"),
                CuePointType(id: UUID(), name: "Teal", colorHex: "#4ECDC4"),
                CuePointType(id: UUID(), name: "Gold", colorHex: "#FFD93D"),
                CuePointType(id: UUID(), name: "Violet", colorHex: "#9D7EE0"),
                CuePointType(id: UUID(), name: "Azure", colorHex: "#4D96FF"),
                CuePointType(id: UUID(), name: "Coral", colorHex: "#FF6B6B")
            ]
        default:
            return [CuePointType(id: UUID(), name: "General", colorHex: "#4ECDC4")]
        }
    }

    /// The media-item plan for a seed key. Throws on an unknown key.
    static func itemSeeds(for key: String) throws -> [ItemSeed] {
        switch key {
        case "set-list-act-i":
            return setListActISeeds()
        case "video-project":
            return videoProjectSeeds()
        case "three-cues-1-3-6":
            return [legacyAudioItem(cues: [CueSpec(time: 1), CueSpec(time: 3), CueSpec(time: 6)])]
        case "three-cues-1-3-6-with-120bpm-tempo":
            return [legacyAudioItem(cues: [
                CueSpec(time: 0, bpm: 120, beatsPerBar: 4),
                CueSpec(time: 1),
                CueSpec(time: 3),
                CueSpec(time: 6)
            ])]
        case "song-with-lyrics":
            return [legacyAudioItem(cues: [CueSpec(time: 1)], lyrics: songWithLyrics())]
        case "lyrics-with-placed-lines":
            return [legacyAudioItem(cues: [CueSpec(time: 1)], lyrics: lyricsWithPlacedLines())]
        default:
            throw NSError(
                domain: "UITestSeedHandler",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown UI-test seed key: \(key)"]
            )
        }
    }

    /// A human-facing document name for seeds whose title bar is part of the
    /// visual baseline; `nil` keeps the anonymous `seed-<uuid>` filename.
    static func documentBaseName(for key: String) -> String? {
        switch key {
        case "set-list-act-i", "video-project": return "Set List — Act I"
        default: return nil
        }
    }

    // MARK: - Plans

    /// The single-item shape every pre-`set-list` seed used: one short-audio
    /// clip, active, with the legacy bundled-fixture display name.
    private static func legacyAudioItem(cues: [CueSpec], lyrics: Lyrics = .empty) -> ItemSeed {
        ItemSeed(
            displayName: "silent-30s.m4a",
            kind: .audio,
            duration: 30,
            fixture: .silentAudioShort,
            isActive: true,
            cues: cues,
            lyrics: lyrics
        )
    }

    /// The 8 mixed media items of "Set List — Act I" (Figma sidebar `318:1238`),
    /// none active and cue-free. The Dialogue / video active variants are minted
    /// by `activate(_:name:cues:lyrics:)`. Durations mirror the Figma row labels
    /// except where a clip must be long enough to host its cues (see Dialogue).
    private static func setListBaseItems() -> [ItemSeed] {
        [
            ItemSeed(displayName: "Act I — Opening.wav", kind: .audio, duration: 222, fixture: .silentAudioShort),
            // duration matches the long fixture (7:30), not the Figma sidebar's
            // 5:12 label: cue marker x-positions are `time / media.duration`
            // (CueMarkersGeometry), so the clip MUST be at least as long as the
            // last cue (Blackout @ 6:48) or cues #5–6 render off the timeline.
            // The active clip uses an amplitude-modulated tone (not silence) so
            // the preview renders a real waveform envelope for the figma↔app
            // capture (#476); its 7:30 length still spans the cues to 6:48.
            ItemSeed(displayName: "Dialogue — Scene 2.wav", kind: .audio, duration: 450, fixture: .toneAudioLong),
            ItemSeed(displayName: "Projection — Storm.mp4", kind: .video, duration: 90, fixture: .silentVideo),
            ItemSeed(displayName: "Underscore — Bridge.wav", kind: .audio, duration: 128, fixture: .silentAudioShort),
            ItemSeed(displayName: "Set Change.mov", kind: .video, duration: 41, fixture: .silentVideo),
            ItemSeed(displayName: "Finale.wav", kind: .audio, duration: 235, fixture: .silentAudioShort),
            ItemSeed(displayName: "Curtain Call.mov", kind: .video, duration: 75, fixture: .silentVideo),
            ItemSeed(displayName: "Ambient Loop.wav", kind: .audio, duration: 480, fixture: .silentAudioShort)
        ]
    }

    /// Marks the named base item active and attaches its cues / lyrics, leaving
    /// every other item untouched. The shared seam for the populated seeds.
    private static func activate(
        _ items: [ItemSeed],
        name: String,
        cues: [CueSpec],
        lyrics: Lyrics
    ) -> [ItemSeed] {
        items.map { item in
            guard item.displayName == name else { return item }
            var active = item
            active.isActive = true
            active.cues = cues
            active.lyrics = lyrics
            return active
        }
    }

    /// The populated "Set List — Act I" plan — the active "Dialogue — Scene
    /// 2.wav" clip carries the six colored, faded, numbered cues (Cue frame
    /// `318:1228`) and the 12-line lyric sheet (Lyric frame `318:1369`).
    private static func setListActISeeds() -> [ItemSeed] {
        let cues: [CueSpec] = [
            CueSpec(time: 18, name: "Lights Up", fadeTime: .symmetric(1.5), typeIndex: 0, cueNumber: 1),
            CueSpec(time: 90, name: "Verse 1", fadeTime: .symmetric(2.0), typeIndex: 1, cueNumber: 2),
            CueSpec(time: 165, name: "Chorus Hit", fadeTime: .symmetric(0.5), typeIndex: 2, cueNumber: 3),
            CueSpec(time: 242, name: "Bridge", fadeTime: .symmetric(3.0), typeIndex: 3, cueNumber: 4),
            CueSpec(time: 320, name: "Final Chorus", fadeTime: .symmetric(2.0), typeIndex: 4, cueNumber: 5),
            CueSpec(time: 408, name: "Blackout", fadeTime: .symmetric(1.0), typeIndex: 5, cueNumber: 6)
        ]
        return activate(setListBaseItems(), name: "Dialogue — Scene 2.wav", cues: cues, lyrics: setListLyrics())
    }

    /// The "video-project" plan (Figma `318:1614`) — the same populated sidebar,
    /// but the video clip "Projection — Storm.mp4" is active so the preview pane
    /// renders video. Its four cues all fall within the 90s clip.
    private static func videoProjectSeeds() -> [ItemSeed] {
        let cues: [CueSpec] = [
            CueSpec(time: 12, name: "Storm In", fadeTime: .symmetric(1.0), typeIndex: 0, cueNumber: 1),
            CueSpec(time: 36, name: "Lightning", fadeTime: .symmetric(0.5), typeIndex: 2, cueNumber: 2),
            CueSpec(time: 60, name: "Rain Peak", fadeTime: .symmetric(2.0), typeIndex: 4, cueNumber: 3),
            CueSpec(time: 84, name: "Storm Out", fadeTime: .symmetric(1.5), typeIndex: 5, cueNumber: 4)
        ]
        return activate(setListBaseItems(), name: "Projection — Storm.mp4", cues: cues, lyrics: .empty)
    }

    /// The 12-line "Set List — Act I" lyric sheet (Lyric frame `318:1369`):
    /// four placed lines at the Figma timecodes + eight unplaced queue lines
    /// (the three visible in the frame, then five continuation lines).
    private static func setListLyrics() -> Lyrics {
        Lyrics(
            lines: [
                LyricLine(time: 6.3, text: "the morning came too soon for us"),
                LyricLine(time: 51.6, text: "and the night gave way to morning light"),
                LyricLine(time: 132.0, text: "every street we walked felt new"),
                LyricLine(time: 175.0, text: "painted gold in everything we knew"),
                LyricLine(time: nil, text: "we were dancing in the open air"),
                LyricLine(time: nil, text: "with nothing but the stars to guide"),
                LyricLine(time: nil, text: "holding on to summer one more night"),
                LyricLine(time: nil, text: "and we never once looked down"),
                LyricLine(time: nil, text: "the music pulled us through the dark"),
                LyricLine(time: nil, text: "every chorus felt like coming home"),
                LyricLine(time: nil, text: "till the lights came up too soon"),
                LyricLine(time: nil, text: "and the morning called us back")
            ],
            offsetSeconds: 0
        )
    }

    private static func songWithLyrics() -> Lyrics {
        Lyrics(
            lines: [
                LyricLine(time: 0, text: "Seeded opening line"),
                LyricLine(time: 5, text: "Seeded second line")
            ],
            offsetSeconds: 0
        )
    }

    private static func lyricsWithPlacedLines() -> Lyrics {
        Lyrics(
            lines: [
                LyricLine(time: 2, text: "first placed line"),
                LyricLine(time: 5, text: "second placed line"),
                LyricLine(time: nil, text: "an unplaced line")
            ],
            offsetSeconds: 0
        )
    }
}
#endif
