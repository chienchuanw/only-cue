# Data Model & File Format

## `.cuelist` file

A `.cuelist` is an encrypted binary container (see ADR-021): ASCII magic `OCUE`, a
1-byte format version, a 12-byte AES-GCM nonce, then AES-256-GCM ciphertext + tag.
The **decrypted payload** is a UTF-8 JSON document, pretty-printed with sorted keys.
Saved files are therefore *not* git-diffable or text-inspectable; the JSON shape
documented below is what you get after decryption. Pre-encryption plaintext
`.cuelist` files still open (detected by the absent `OCUE` magic) and are
re-written encrypted on the next save.

UTType: `com.onlycue.cuelist`, conforms to `public.data`. Finder Kind: "OnlyCue Document".

### Example

```json
{
  "schemaVersion": 8,
  "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
  "name": "Show A",
  "activeItemID": "AABBCCDD-1111-2222-3333-444455556666",
  "timecodeSettings": { "framerate": "25", "startOffsetFrames": 90000 },
  "cuePointTypes": [
    {
      "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
      "name": "General",
      "colorHex": "#4ECDC4",
      "defaultFadeTime": 0,
      "defaultNamePattern": "Cue",
      "hotkey": null,
      "isVisible": true,
      "isExportEnabled": true
    }
  ],
  "items": [
    {
      "id": "AABBCCDD-1111-2222-3333-444455556666",
      "media": {
        "displayName": "act1-music.wav",
        "kind": "audio",
        "duration": 184.32,
        "bookmarkData": "Ym9va21hcmstYmFzZTY0..."
      },
      "cues": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "cueNumber": 1,
          "name": "Spot up SR",
          "time": 4.250,
          "notes": "Wait for breath",
          "fadeTime": { "fadeIn": 1.5, "fadeOut": 1.5 }
        },
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "cueNumber": 2,
          "name": "Wash full",
          "time": 12.000,
          "notes": "",
          "fadeTime": { "fadeIn": 1.0, "fadeOut": 2.0 }
        }
      ]
    }
  ]
}
```

## Swift types

```swift
struct ProjectModel: Codable {
    static let currentSchemaVersion = 19

    var schemaVersion: Int
    var id: UUID
    var name: String
    var cuePointTypes: [CuePointType]   // always contains ≥ 1 (the default at [0])
    var items: [MediaItem]
    var activeItemID: UUID?
    var timecodeSettings: ProjectTimecodeSettings   // since v7; defaults to .default

    var defaultCuePointTypeID: UUID? { cuePointTypes.first?.id }

    /// Resolves a cue's display color from its `CuePointType`. nil when typeID dangles.
    func colorHex(for cue: Cue) -> String? { ... }
}

struct ProjectTimecodeSettings: Codable, Equatable {
    var framerate: SMPTEFramerate       // "24" | "25" | "30" | "30df"
    var startOffsetFrames: Int          // project start timecode as a frame count (drop-frame aware)
    // .default → 30 fps, offset 0
    // derived: startTimecode: Timecode, timecode(atPlaybackSeconds:) -> Timecode
}

struct CuePointType: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String                // "#RRGGBB"
    var defaultFadeTime: TimeInterval   // seconds; reserved for the fade-time leaf
    var defaultNamePattern: String      // template string for new cues of this Type
    var hotkey: Int?                    // 0...9; reserved for the number-key leaf
    var isVisible: Bool                 // reserved for the breakdown view (#37)
    var isExportEnabled: Bool           // reserved for the export filter (#34)
}

// Codable conformance (init(from:)/encode(to:)) lives in an extension — hand-written for migration safety.
struct MediaItem: Identifiable, Equatable {
    var id: UUID
    var media: MediaReference          // non-optional — items only exist after import
    var cues: [Cue]
    var startTimecodeFrames: Int       // since v10; per-clip start timecode
    var ltcMuted: Bool                 // since v10; per-clip LTC output channel mute
    var alternateName: String?         // since v12; per-clip display-name override
    var lyrics: Lyrics                 // since v13; timestamped lyrics (ADR-022)
    var ma2PushTarget: MA2PushTarget?  // since v17; last MA2 push destination (#683)
    var playsOriginalSourceAudio: Bool // since v19; false = music-only (default), true = play with timecode tone (#715)
    var rememberedLTC: StripedTimecodeTrack? // since v20; persisted detected LTC, fallback when a scan fails (#754)
}

struct LyricLine: Codable, Identifiable, Equatable {
    var id: UUID
    var time: TimeInterval?       // SONG-relative seconds, >= 0; nil = unplaced (since v14)
    var text: String              // may be empty — an instrumental gap
}

struct Lyrics: Codable, Equatable {
    private(set) var lines: [LyricLine]   // authoring order (v14 — no longer sorted on init)
    var offsetSeconds: TimeInterval       // media time the song begins at
    // .empty == no lyrics
    // derived: placedLines (time != nil, sorted by time) / unplacedLines (time == nil, authoring order);
    //          effectiveTime(of:) -> time + offset, nil for an unplaced line;
    //          activeLine(atMediaSeconds:); nextLine(afterMediaSeconds:)
}

struct TempoMap: Codable, Equatable {
    var sections: [TempoSection]   // sorted by startSeconds; if non-empty, sections[0].startSeconds == 0
}

struct TempoSection: Codable, Identifiable, Equatable {
    var id: UUID
    var startSeconds: TimeInterval          // where this constant-tempo span begins
    var bpm: Double                         // clamped to [20, 400]
    var beatsPerBar: Int                    // >= 1 (time-signature numerator)
    var downbeatOffsetSeconds: TimeInterval // time from startSeconds to bar 1 / beat 1; in [0, barDuration)
}

struct Cue: Codable, Identifiable, Equatable {
    var id: UUID
    var typeID: UUID              // references CuePointType.id; required
    var cueNumber: Double         // user-facing cue number (1, 1.5, 2, ...); console-consumable; required
    var name: String
    var time: TimeInterval        // seconds from item's media start
    var notes: String
    var fadeTime: FadeTime        // required; .symmetric(0) means no fade
    // No per-cue color: UI reads it from the Type via ProjectModel.colorHex(for:).
}

struct FadeTime: Codable, Equatable, Hashable {
    var fadeIn: TimeInterval      // seconds; >= 0 (parser-enforced; struct does not trap)
    var fadeOut: TimeInterval     // seconds; >= 0
    // .symmetric(t) → FadeTime(fadeIn: t, fadeOut: t)
    // Canonical string form: "1.5" when fadeIn == fadeOut, otherwise "1/2"
}

struct MediaReference: Codable {
    var displayName: String
    var kind: MediaKind           // .audio | .video
    var duration: TimeInterval
    var bookmarkData: Data        // security-scoped bookmark
}

enum MediaKind: String, Codable {
    case audio
    case video
}
```

## Field rules

| Field | Rule |
|---|---|
| `schemaVersion` | Always set on write. Reader rejects unknown future versions. Migrations live in `ProjectModel.decode(from:)`. |
| `id` | Stable per document; survives "Save As". |
| `name` | Free text; defaults to "Untitled". |
| `cuePointTypes` | Project-wide Type catalog. Must contain at least one entry; index `[0]` is the default Type. Editable via the **Manage Types** sheet (driven from the cue inspector's "Manage Types…" button → `CueCommands.addCuePointType` / `removeCuePointType` / `setCuePointType*`). |
| `cuePointType.id` | Stable; never reused even after delete. Referenced by every `Cue.typeID`. |
| `cuePointType.colorHex` | `#RRGGBB`, uppercase. Source of truth for cue color since schema v6 — UI resolves via `ProjectModel.colorHex(for:)`. Editable via the Manage Types sheet's `ColorPicker` → `CueCommands.setCuePointTypeColor`. |
| `cuePointType.hotkey` | `0...9` or `nil`. Settable via the Manage Types sheet (move semantics: assigning a digit already held by another Type clears the prior holder atomically). Pressing the bound digit in the document window creates a cue at the playhead with that Type — `DocumentView.digitShortcuts` looks up the Type via `ProjectModel.cuePointType(forHotkey:)` and calls `CueCommands.addCueAtPlayhead(time:typeID:document:undoManager:)`. SwiftUI's `.keyboardShortcut` yields to focused TextFields, so digits typed into the inspector or the Manage Types sheet land in those fields rather than firing the dispatch. Pressing a digit not bound to any Type is a no-op. |
| `items` | Array of media items. Empty for new documents. Sidebar order matches array order; reorder = mutate the array. |
| `activeItemID` | Currently-selected item's id. `nil` only when `items` is empty. Persisted so users land on the same item after reopen. |
| `item.id` | Stable; never reused even after delete. |
| `item.media` | Required (non-optional). Items only exist because a file was imported. |
| `item.media.bookmarkData` | Base64-encoded security-scoped bookmark. Resolved at open. |
| `item.media.kind` | Determines preview pane (waveform vs video). |
| `item.media.duration` | Cached so we can render UI before the asset finishes loading. |
| `item.cues` | Cue list scoped to this item. Cues are not shared between items. |
| `cue.id` | Stable; never reused even after delete. |
| `cue.typeID` | Required. References a `CuePointType.id` in `cuePointTypes`. Editable via the cue inspector pane (Type picker → `CueCommands.setType`). |
| `cue.cueNumber` | User-facing cue number consumed by lighting consoles. Required. Assigned by `CueCommands.addCueAtPlayhead`: empty list → 1.0; insertion at end → time-predecessor's number + 1; between two cues → mid-point of their numbers; before all → time-successor's number − 1 (may go negative on repeated inserts before the minimum; a future "renumber from 1" command is still pending). Existing cues' numbers are never shifted on insert. Manually editable via the cue inspector (text field → `CueCommands.setCueNumber`). |
| `cue.time` | Seconds, double precision. Must be `>= 0` and `<= item.media.duration`. |
| `cue.notes` | Free text, may be empty. Editable via the cue inspector (multi-line editor → `CueCommands.setNotes`). |
| `cue.fadeTime` | Required. `FadeTime(fadeIn:fadeOut:)`. New cues default to `.symmetric(0)` (no fade); v4 → v5 migration backfills the same. The cue inspector parses input via `FadeTime.parse(_:)` (accepts `"1"` / `"1.5"` symmetric and `"1/2"` split, trims whitespace, rejects empty/non-numeric/negative/multi-slash/half-empty), routes valid edits through `CueCommands.setFadeTime`, and reverts the field to `FadeTime.format()`'s canonical form on rejection. The struct itself does not trap on negative values; the parser is the gate. |
| `timecodeSettings` | Since v7. `framerate` is `"24"` / `"25"` / `"30"` / `"30df"` (`SMPTEFramerate` raw value); `startOffsetFrames` is the project's start timecode expressed as a count of frames since `00:00:00:00` (drop-frame aware via `Timecode`). Defaults to `{framerate: "30", startOffsetFrames: 0}`. Used by the LTC generator (epic #33) and the Audio & Timecode preferences pane (leaf 6 — the pane edits these; the field is pre-provisioned here, same as `isVisible` was before the breakdown view). v6 → v7 migration seeds the default. |
| `tempoMap` (per `MediaItem`) | Since v8. A `TempoMap` of `TempoSection`s — an empty map means "no tempo grid". Persisted per media item. The map is normalized on construction: sections sorted by `startSeconds`, de-duplicated by start (last wins), the first section forced to `startSeconds == 0`, and each section's `downbeatOffsetSeconds` reduced into `[0, barDuration)`. `bpm` is clamped to `[20, 400]` and `beatsPerBar` to `>= 1`. It is a visual + snap aid only — it does not move cues (ADR-020). Mutated via `CueCommands` (epic #199); the DSP tempo analyzer can seed a section's `bpm` + `downbeatOffsetSeconds`. v7 → v8 migration seeds an empty map on every item. |
| `playbackMode` | Since v15. End-of-media transport policy — `"playOnce"` (default; transport pauses at end of media), `"loop"` (seek to 0 and continue, rate preserved), or `"autoNext"` (advance `activeItemID` to the next item in `items[]` and resume playback; stops at the end of the list). Set via the Playback menu and routed through `CueCommands.setPlaybackMode`. Loop and Auto-Next transitions are *suppressed* while LTC output is enabled — the dispatcher posts `.ltcInterlockEngaged` and leaves the mode unchanged so it resumes when LTC is disabled. v14 → v15 seeds `.playOnce` so existing documents preserve the pre-v15 behavior. |
| `item.lyrics` | Since v13; `LyricLine.time` made optional at v14. A `Lyrics` — `[LyricLine]` in authoring order plus `offsetSeconds`. Empty (`.empty`) means no lyrics. A reference / playback-HUD layer decoupled from cues (ADR-022). `LyricLine.time` is song-relative and **optional** — `nil` means the line is *unplaced* (text but no timestamp yet); `placedLines` / `unplacedLines` split the array. `offsetSeconds` is the media time the song begins at; `effectiveTime = time + offset` for placed lines. Authored directly on the waveform in Lyric mode (ADR-023), routed through `CueCommands` (`setLyrics` / `setLyricsOffset` / `setLyricLines` / `pasteLyrics` / `placeLyricLine` / `unplaceLyricLine` / `deleteLyricLine`). v12 → v13 seeds an empty `Lyrics`; v13 → v14 makes `time` optional. |
| `item.ma2PushTarget` | Since v17. Optional `MA2PushTarget` — the last grandMA2 push destination for this clip (#683). `nil` until the clip is first pushed. `MA2PushTarget` holds the console address and executor number. v16 → v17 migration leaves it `nil` for all existing items. |
| `item.playsOriginalSourceAudio` | Since v19. `Bool`, default `false`. User-facing per-clip source-audio playback preference (#715). `false` = music-only: the LTC timecode tone channel is muted during playback so the audience hears only the music content. `true` = original: the file plays back as-is, timecode tone included. Distinct from `ltcMuted`, which gates the LTC *output* (encoder → console path). v18 → v19 migration seeds `false` on all existing items. |
| `item.rememberedLTC` | Since v20. Optional `StripedTimecodeTrack` (`anchorTimecode` + `anchorPlaybackSeconds` + `ltcChannel`) — the song's remembered LTC (#754). Written **once** when heuristic detection first succeeds; used as a fallback when a later scan fails (the identifier is signal-based and can false-negative), so the music-only muting, `FILE` readout, and detected badge don't vanish. `nil` until a successful detection, and cleared on relink or the sheet's **Clear** action. A deliberate exception to "detected data is never authored" (ADR-031). v19 → v20 migration leaves it `nil` (missing key → `nil`). |

## Versioning policy

- `schemaVersion: 20` is the current file. We will **never** mutate v20 semantics; new fields go in v21.
- Adding optional fields → old readers ignore unknown keys via `Codable`; no version bump required.
- Adding a required field, or removing / repurposing a field → bump `schemaVersion` and write a migration.
- Migrations are pure functions `(JSONvN) -> ProjectModel`, applied during `ProjectModel.decode(from:)`. Pre-v4 chains run `assignCueNumbersBySort` so cues land with sequential `cueNumber` values; every chain backfills `fadeTime = .symmetric(0)` at the cue boundary so pre-v5 sources land with a valid `fadeTime`; every chain drops the legacy per-cue `colorHex` at the boundary so any pre-v6 source lands with color resolving via the Type; every chain seeds `timecodeSettings = .default` so any pre-v7 source lands with valid timecode settings; and every chain lands an empty `tempoMap` on every item so any pre-v8 source has a valid (empty) tempo map:
  - **v1 → current**: wraps the v1 (media, cues) into a single `MediaItem`; seeds a default `CuePointType` "General" with `colorHex` `#4ECDC4`; assigns that Type's id to every cue; backfills `fadeTime = .symmetric(0)`; drops `cue.colorHex`; seeds `timecodeSettings = .default`. v1 documents with no media decode to `items: []`.
  - **v2 → current**: keeps `items` and `activeItemID` as-is; seeds the default `CuePointType` "General"; assigns that Type's id to every existing cue; backfills `fadeTime = .symmetric(0)`; drops `cue.colorHex`; seeds `timecodeSettings = .default`.
  - **v3 → current**: keeps `cuePointTypes`, `items`, and `activeItemID` as-is; assigns sequential `cueNumber`s by time order within each item; backfills `fadeTime = .symmetric(0)`; drops `cue.colorHex`; seeds `timecodeSettings = .default`.
  - **v4 → current**: keeps `cuePointTypes`, `items`, `activeItemID`, and per-cue `cueNumber` as-is; backfills `fadeTime = .symmetric(0)` on every cue; drops `cue.colorHex`; seeds `timecodeSettings = .default`.
  - **v5 → current**: keeps everything except `cue.colorHex` (dropped); color resolves through `ProjectModel.colorHex(for:)`; seeds `timecodeSettings = .default`.
  - **v6 → current**: keeps everything; seeds `timecodeSettings = .default` (v6 had no timecode settings); seeds an empty `tempoMap` on every item.
  - **v7 → current**: keeps everything (including `timecodeSettings`); seeds an empty `tempoMap` on every item (v7 had no tempo maps).
  - **v12 → current**: keeps everything; seeds an empty `Lyrics` on every item (`MediaItem.lyrics`, ADR-022). The intervening v8–v11 schema bumps (from earlier epics) are additive in the same way.
  - **v13 → current**: keeps everything; `LyricLine.time` became optional (`nil` = unplaced, ADR-023). A v13 lyric line always wrote a concrete `time`, which decodes straight into the optional. Delegates to the v14 migration so the post-v14 `playbackMode` default is seeded uniformly.
  - **v14 → current**: keeps every top-level field; seeds `playbackMode = .playOnce` on every document so existing `.cuelist` files preserve the pre-v15 "stop at end of media" behavior.
  - **v16 → current**: keeps everything; adds `playbackMode = .playOnce` (same as v15 migration) when loading a v16 document that omits it.
  - **v17 → current**: keeps everything; `MA2PushTarget` gains optional `sequenceName` — missing key decodes to `nil`.
  - **v18 → current**: keeps everything; seeds `playsOriginalSourceAudio = false` on every item (missing key → `false`, music-only default).
  - **v19 → current**: keeps everything; `MediaItem` gains `rememberedLTC` (#754) — missing key decodes to `nil`.
- v20 is a one-way upgrade: every prior build (v1 through v19) cannot open v20 files.

## Bookmark behavior

- Created with `URL.bookmarkData(options: .withSecurityScope)` after the user picks the file.
- Stored as base64 inside the JSON.
- On open: resolve with `URL(resolvingBookmarkData:options: .withSecurityScope, ..., bookmarkDataIsStale: &stale)`.
- If `stale`, refresh and rewrite the document silently.
- If unresolvable (file moved/deleted), surface a "Relink media…" alert. The cues remain intact; only playback is gated.

## `.occues` interchange file

A `.occues` file is a portable, one-song cue list — used to copy a marked-up
song's cues from one project into another as a starting point (ADR-025). It is
**not** part of `ProjectModel` and does **not** affect `schemaVersion`: it is an
external artifact produced by `Cue ▸ Export Cue List…` and consumed by
`Cue ▸ Import Cue List…`.

It uses the same encrypted envelope as `.cuelist` (ADR-021) with a distinct
`OCCU` magic. The decrypted payload is JSON with its own `formatVersion`
(currently `1`, independent of `schemaVersion`): `exportedAt`, a `sourceMedia`
identity (`displayName` + `duration`), the referenced `cuePointTypes`, and the
`cues`. On import, types are reconciled additively (new ids, `hotkey` dropped,
`(imported)` suffix on a name collision) and cues get fresh ids with remapped
`typeID`s; `cueNumber` is preserved. UTType `com.onlycue.cues`.

## What's deliberately NOT in the model

These are out of scope. Adding any of them is a `schemaVersion` bump.

- Tracks / channels within a single item (one media file per item)
- Cue groups or hierarchy (flat list per item)
- Per-cue timecode offsets (cues are in media-relative seconds)
- Per-cue OSC/MIDI payloads
- Cross-item cue references or shared cue lists
- Per-item playhead memory (active-item switch resets transport to 0)
- A "renumber all from 1" command on `cueNumber` — manual per-cue editing exists via the cue inspector, but a bulk normalize command is still pending
- `CuePointType.defaultFadeTime` applied at cue creation — currently unused; wiring is a separate leaf that may also convert that field to `FadeTime`
