# Data Model & File Format

## `.cuelist` file

A `.cuelist` is a UTF-8 JSON document. Pretty-printed, keys sorted, so files diff cleanly under git.

UTType: `com.onlycue.cuelist`, conforms to `public.json`.

### Example

```json
{
  "schemaVersion": 4,
  "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
  "name": "Show A",
  "activeItemID": "AABBCCDD-1111-2222-3333-444455556666",
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
          "colorHex": "#FF6B6B",
          "notes": "Wait for breath"
        },
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
          "cueNumber": 2,
          "name": "Wash full",
          "time": 12.000,
          "colorHex": "#4ECDC4",
          "notes": ""
        }
      ]
    }
  ]
}
```

## Swift types

```swift
struct ProjectModel: Codable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    var id: UUID
    var name: String
    var cuePointTypes: [CuePointType]   // always contains ≥ 1 (the default at [0])
    var items: [MediaItem]
    var activeItemID: UUID?

    var defaultCuePointTypeID: UUID? { cuePointTypes.first?.id }
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

struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference   // non-optional — items only exist after import
    var cues: [Cue]
}

struct Cue: Codable, Identifiable, Equatable {
    var id: UUID
    var typeID: UUID              // references CuePointType.id; required
    var cueNumber: Double         // user-facing cue number (1, 1.5, 2, ...); console-consumable; required
    var name: String
    var time: TimeInterval        // seconds from item's media start
    var colorHex: String          // "#RRGGBB" — kept transitionally; UI will read color from the Type in a follow-up leaf
    var notes: String
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
| `cuePointTypes` | Project-wide Type catalog. Must contain at least one entry; index `[0]` is the default Type. |
| `cuePointType.id` | Stable; never reused even after delete. Referenced by every `Cue.typeID`. |
| `cuePointType.colorHex` | `#RRGGBB`, uppercase. The color a cue picks up by default at creation; long-term, UI reads cue color from the Type. |
| `cuePointType.hotkey` | `0...9` or `nil`. Reserved for the number-key cue creation leaf — model layer accepts the value but does not yet wire keymaps. |
| `items` | Array of media items. Empty for new documents. Sidebar order matches array order; reorder = mutate the array. |
| `activeItemID` | Currently-selected item's id. `nil` only when `items` is empty. Persisted so users land on the same item after reopen. |
| `item.id` | Stable; never reused even after delete. |
| `item.media` | Required (non-optional). Items only exist because a file was imported. |
| `item.media.bookmarkData` | Base64-encoded security-scoped bookmark. Resolved at open. |
| `item.media.kind` | Determines preview pane (waveform vs video). |
| `item.media.duration` | Cached so we can render UI before the asset finishes loading. |
| `item.cues` | Cue list scoped to this item. Cues are not shared between items. |
| `cue.id` | Stable; never reused even after delete. |
| `cue.typeID` | Required. References a `CuePointType.id` in `cuePointTypes`. |
| `cue.cueNumber` | User-facing cue number consumed by lighting consoles. Required. Assigned by `CueCommands.addCueAtPlayhead`: empty list → 1.0; insertion at end → time-predecessor's number + 1; between two cues → mid-point of their numbers; before all → time-successor's number − 1 (may go negative on repeated inserts before the minimum; the future cue inspector will provide a "renumber from 1" command). Existing cues' numbers are never shifted on insert. |
| `cue.time` | Seconds, double precision. Must be `>= 0` and `<= item.media.duration`. |
| `cue.colorHex` | `#RRGGBB`, uppercase, validated on decode. Transitional duplication of the Type's color until the UI is updated to read from the Type. |
| `cue.notes` | Free text, may be empty. |

## Versioning policy

- `schemaVersion: 4` is the current file. We will **never** mutate v4 semantics; new fields go in v5.
- Adding optional fields → old readers ignore unknown keys via `Codable`; no version bump required.
- Adding a required field, or removing / repurposing a field → bump `schemaVersion` and write a migration.
- Migrations are pure functions `(JSONvN) -> ProjectModel`, applied during `ProjectModel.decode(from:)`. Every migration ends with a `assignCueNumbersBySort` pass so cues from any pre-v4 source land with sequential `cueNumber` values:
  - **v1 → current**: wraps the v1 (media, cues) into a single `MediaItem`; seeds a default `CuePointType` "General" with `colorHex` `#4ECDC4`; assigns that Type's id to every cue. v1 documents with no media decode to `items: []`.
  - **v2 → current**: keeps `items` and `activeItemID` as-is; seeds the default `CuePointType` "General"; assigns that Type's id to every existing cue.
  - **v3 → current**: keeps `cuePointTypes`, `items`, and `activeItemID` as-is; assigns sequential `cueNumber`s by time order within each item.
- v4 is a one-way upgrade: v0.1.0 (v1), the multi-items build (v2), and the CuePoint-Types build (v3) cannot open v4 files.

## Bookmark behavior

- Created with `URL.bookmarkData(options: .withSecurityScope)` after the user picks the file.
- Stored as base64 inside the JSON.
- On open: resolve with `URL(resolvingBookmarkData:options: .withSecurityScope, ..., bookmarkDataIsStale: &stale)`.
- If `stale`, refresh and rewrite the document silently.
- If unresolvable (file moved/deleted), surface a "Relink media…" alert. The cues remain intact; only playback is gated.

## What's deliberately NOT in the model

These are out of scope. Adding any of them is a `schemaVersion` bump.

- Tracks / channels within a single item (one media file per item)
- Cue groups or hierarchy (flat list per item)
- Per-cue timecode offsets (cues are in media-relative seconds)
- Per-cue OSC/MIDI payloads
- Cross-item cue references or shared cue lists
- Per-item playhead memory (active-item switch resets transport to 0)
- `Cue.fadeTime` with split-fade syntax (e.g. `1/2`) — separate leaf under epic #32
- Manual edit / "renumber all" of `cueNumber` — comes with the cue inspector leaf under epic #32
