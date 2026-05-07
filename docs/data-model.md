# Data Model & File Format

## `.cuelist` file

A `.cuelist` is a UTF-8 JSON document. Pretty-printed, keys sorted, so files diff cleanly under git.

UTType: `com.onlycue.cuelist`, conforms to `public.json`.

### Example

```json
{
  "schemaVersion": 1,
  "id": "9F2E0F8A-9C2D-4F2A-9E1A-0E1A2D3C4B5A",
  "name": "Opening Number",
  "media": {
    "displayName": "act1-music.wav",
    "kind": "audio",
    "duration": 184.32,
    "bookmarkData": "Ym9va21hcmstYmFzZTY0..."
  },
  "cues": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "name": "Spot up SR",
      "time": 4.250,
      "colorHex": "#FF6B6B",
      "notes": "Wait for breath"
    },
    {
      "id": "22222222-2222-2222-2222-222222222222",
      "name": "Wash full",
      "time": 12.000,
      "colorHex": "#4ECDC4",
      "notes": ""
    }
  ]
}
```

## Swift types

```swift
struct ProjectModel: Codable {
    var schemaVersion: Int = 1
    var id: UUID
    var name: String
    var media: MediaReference?
    var cues: [Cue]
}

struct Cue: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var time: TimeInterval        // seconds from media start
    var colorHex: String          // "#RRGGBB"
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
| `schemaVersion` | Always set on write. Reader rejects unknown major versions. Migrations live in `ProjectModel.migrate(_:)`. |
| `id` | Stable per document; survives "Save As". |
| `name` | Free text; defaults to media display name on first import. |
| `media` | Optional. Templates and empty docs have no media. |
| `media.bookmarkData` | Base64-encoded security-scoped bookmark. Resolved at open. |
| `media.kind` | Determines preview pane (waveform vs video). |
| `media.duration` | Cached so we can render UI before the asset finishes loading. |
| `cues` | Array order is the cue list order (the `#` shown in UI). Resort = reorder the array. |
| `cue.id` | Stable; never reused even after delete. |
| `cue.time` | Seconds, double precision. Must be `>= 0` and `<= media.duration` when media is present. |
| `cue.colorHex` | `#RRGGBB`, uppercase, validated on decode. |
| `cue.notes` | Free text, may be empty. |

## Versioning policy

- `schemaVersion: 1` is the v1 file. We will **never** mutate v1 semantics; new fields go in v2.
- Adding optional fields → bump minor (still v1 from the loader's POV; old readers ignore unknown keys via `Codable`).
- Removing or repurposing a field → bump `schemaVersion` and write a migration.
- Migrations are pure functions `(JSONv N) -> JSONv N+1`, applied in sequence.

## Bookmark behavior

- Created with `URL.bookmarkData(options: .withSecurityScope)` after the user picks the file.
- Stored as base64 inside the JSON.
- On open: resolve with `URL(resolvingBookmarkData:options: .withSecurityScope, ..., bookmarkDataIsStale: &stale)`.
- If `stale`, refresh and rewrite the document silently.
- If unresolvable (file moved/deleted), surface a "Relink media…" alert. The cues remain intact; only playback is gated.

## What's deliberately NOT in the model

These are out of scope for v1. Adding any of them is a `schemaVersion` bump.

- Tracks / channels (single media per document)
- Cue groups or hierarchy (flat list only)
- Per-cue timecode offsets (cues are in media-relative seconds)
- Cue types (lighting / sound / video) — all cues are generic
- Per-cue OSC/MIDI payloads
