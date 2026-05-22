# Portable Cue Lists — export & import a song's cues across projects

**Date**: 2026-05-22
**Status**: Approved (brainstorming)
**Spec section implemented**: `docs/roadmap.md#phase-2` (Pro handoff — closes a CuePoints gap); new behavior, not yet in `docs/data-model.md`.

## Problem

Cues live inside each `.cuelist` document's `MediaItem.cues` and are sealed there.
When a lighting designer marks up a song in project A and later imports the same
media file into project B, project B gets a fresh `MediaItem` with `cues: []` —
all of A's cue work is unreachable. `docs/data-model.md` lists *"Cross-item cue
references or shared cue lists"* under "What's deliberately NOT in the model", so
today there is no path to reuse cues across projects.

## Goal

Let a user **export one song's cue list to a portable file** from project A and
**import it onto a song in project B** as a starting point. The copy is
one-time: after import the two projects diverge with no ongoing relationship.

### Non-goals

- Live sync, a global/app-wide cue library, or sidecar files beside media.
- Carrying tempo maps, lyrics, or per-clip config — **cues only**.
- Cross-item references inside `ProjectModel`.
- **No `ProjectModel` change and no `schemaVersion` bump.** The `.occues` file is
  an external artifact; `data-model.md`'s "no shared cue lists in the model"
  non-goal continues to hold.

## File format — `.occues`

A new document type, separate from `.cuelist`:

- Extension: `.occues`
- UTType: `com.onlycue.cues`, conforms to `public.data`
- Finder Kind: "OnlyCue Cue List"

### Container

The same envelope scheme as `.cuelist` (ADR-021), with a **distinct 4-byte
magic** so the two file types can never be confused:

| Field | `.cuelist` | `.occues` |
|---|---|---|
| Magic | `OCUE` | `OCCU` |
| Version byte | `0x01` | `0x01` |
| Nonce | 12-byte AES-GCM | 12-byte AES-GCM |
| Body | AES-256-GCM ciphertext + 16-byte tag | same |
| Key | fixed app key | **same fixed app key** |

`CuelistCrypto` is currently hardcoded to the `OCUE` magic. Refactor `seal`/`open`
to take a `magic: Data` parameter (default `OCUE` for existing callers); the
`.occues` path passes `OCCU`. The AES-256-GCM logic, key, version byte, nonce and
tag handling are unchanged and shared. `CuelistCrypto.open`'s legacy-plaintext
fallback (return bytes unchanged when the magic is absent) is **not** wanted for
`.occues` — a `.occues` file with no `OCCU` magic is a malformed-envelope error,
since there is no legacy plaintext era for this format.

### Payload

The decrypted body is UTF-8 JSON, pretty-printed with sorted keys (matching the
`.cuelist` convention), with its **own independent `formatVersion`** unrelated to
`ProjectModel.schemaVersion`:

```json
{
  "formatVersion": 1,
  "exportedAt": "2026-05-22T17:04:00Z",
  "sourceMedia": {
    "displayName": "act1-music.wav",
    "duration": 184.32
  },
  "cuePointTypes": [
    {
      "id": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
      "name": "Spotlight",
      "colorHex": "#4ECDC4",
      "defaultFadeTime": 0,
      "defaultNamePattern": "Cue",
      "hotkey": 3,
      "isVisible": true,
      "isExportEnabled": true
    }
  ],
  "cues": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "typeID": "CCCC3333-CCCC-3333-CCCC-3333CCCC3333",
      "cueNumber": 1,
      "name": "Spot up SR",
      "time": 4.25,
      "notes": "Wait for breath",
      "fadeTime": { "fadeIn": 1.5, "fadeOut": 1.5 }
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `formatVersion` | `.occues` payload version. Starts at `1`. A reader rejects unknown values with a clear error. Independent of `schemaVersion`. |
| `exportedAt` | ISO-8601 UTC timestamp of the export. Informational only. |
| `sourceMedia.displayName` / `.duration` | Copied from the exported `MediaItem.media`. Drives the import-time mismatch warning. |
| `cuePointTypes` | **Only** the `CuePointType`s referenced by `cues` — not project A's whole catalog. Each carries its full struct as written (`hotkey` included; the importer drops it, see below). |
| `cues` | The exported `MediaItem.cues`, verbatim — full `Cue` structs. |

The payload `Cue` and `CuePointType` shapes are exactly the current Swift
structs' `Codable` form. `.occues` files are tied to those shapes; a future
breaking change to either struct bumps `formatVersion` and adds an `.occues`
migration (a separate, smaller migration chain than `ProjectModel`'s).

## Export — `Cue ▸ Export Cue List…`

- Menu item in the **Cue menu**. Enabled only when `document.model.activeItem`
  is non-nil; disabled otherwise.
- Operates on `activeItem`. Builds the payload:
  - `sourceMedia` from `activeItem.media`.
  - `cues` = `activeItem.cues`.
  - `cuePointTypes` = the subset of `document.model.cuePointTypes` whose `id`
    appears as some cue's `typeID` (deduplicated; preserves catalog order).
- A cue list with no cues exports a valid file with `cues: []` — allowed.
- Presents an `NSSavePanel`, default filename `<displayName> cues.occues`.
- **Pure read** — no `ProjectModel` mutation, no command, no undo entry.
- Encoding/decoding lives in a new `CueListTransfer` module (mirrors
  `MediaImporter`'s role): payload structs + encode/decode + crypto calls.

## Import — `Cue ▸ Import Cue List…`

- Menu item in the **Cue menu**. Enabled only when `activeItem` is non-nil
  (an import needs a target song); disabled otherwise.
- Presents an `NSOpenPanel` filtered to the `.occues` UTType.
- Decode: open the envelope, parse JSON. Failures map to a single clear error
  alert — malformed envelope, decryption failure, or unknown `formatVersion`.

### Mismatch check

Compare the payload's `sourceMedia` against `activeItem.media`:

- Match when `displayName` is equal **and** the two durations differ by no
  more than 0.5 s (`abs(payload.sourceMedia.duration − activeItem.media.duration) ≤ 0.5`).
- On a mismatch, show a confirmation alert quoting both
  (`"This cue list was exported from 'act1-music.wav' (3:04). The selected item
  is 'finale.wav' (4:12). Import anyway?"`) with **Import** / **Cancel**.
- On a match, proceed without the alert.

### Conflict check

- `activeItem.cues` empty → proceed silently (behaves as Replace).
- `activeItem.cues` non-empty → alert with three choices:
  - **Replace** — imported cues become the item's whole cue list.
  - **Add** — imported cues are appended to the existing cues.
  - **Cancel** — abort, no change.

### Type reconciliation — always additive

Project B's `cuePointTypes` catalog is **never modified in place**. For each
`CuePointType` in the payload:

1. Create a **new** `CuePointType` with a freshly generated `id`.
2. `name`: the source name; if that name already exists in `document.model.cuePointTypes`
   (case-insensitive, trimmed comparison), append `(imported)`. If
   `"<name> (imported)"` also exists, try `(imported 2)`, `(imported 3)`, …
   until unique. Uniqueness is also checked against types added earlier in the
   same import.
3. `hotkey`: **dropped to `nil`** — an imported type must never hijack a digit
   binding already held by one of B's types.
4. `colorHex`, `defaultFadeTime`, `defaultNamePattern`, `isVisible`,
   `isExportEnabled`: carried verbatim.

Build a map `sourceTypeID → newTypeID` for cue remapping.

Importing the same `.occues` file twice produces a second `(imported)` /
`(imported 2)` set — accepted; the user consolidates later via Manage Types.

### Cue reconciliation

For each `Cue` in the payload:

- `id`: freshly generated (guarantees uniqueness, including against re-imports).
- `typeID`: remapped through the `sourceTypeID → newTypeID` map. (Every payload
  cue's `typeID` is guaranteed present, because export collected exactly the
  referenced types.)
- `cueNumber`, `time`, `name`, `notes`, `fadeTime`: **preserved verbatim**.
  `cueNumber` is console-facing and is never silently rewritten — under **Add**,
  duplicate numbers against B's existing cues are possible and left for the user
  to renumber.

Replace → the remapped cues become `activeItem.cues`.
Add → the remapped cues are appended to `activeItem.cues`.

### Command seam & undo

All writes go through a single new command
`CueCommands.importCueList(payload:mode:document:undoManager:)` (`mode` =
`.replace` / `.add`). It adds the new types to `cuePointTypes` and writes the
cues to the active item within **one undo group** named **"Import Cue List"**, so
a single undo reverts both the catalog additions and the cue changes. This
follows the existing `CueCommands+Items.swift` before/after snapshot pattern.

## Edge cases

| Case | Behavior |
|---|---|
| No active media item | Both menu items disabled. |
| Exported cue list is empty | Valid `.occues` with `cues: []`; importing it adds no cues (and no types). |
| `.occues` with wrong/absent magic | Malformed-envelope error alert. |
| Decryption / tampered file | Decryption-failure error alert. |
| Unknown `formatVersion` | Clear "made by a newer version of OnlyCue" error alert. |
| Same file imported twice | Second pass adds another `(imported)` type set; cues get fresh ids. No crash, no silent dedup. |

## Files

**New**

- `OnlyCue/Commands/CueListTransfer.swift` — `.occues` payload structs
  (`CueListExport`, `ExportedSourceMedia`), encode/decode, crypto calls,
  `formatVersion` checks, the export/import orchestration entry points.
- `OnlyCue/Commands/CueCommands+Transfer.swift` — `CueCommands.importCueList(…)`
  command with undo grouping.

**Modified**

- `OnlyCue/Document/CuelistCrypto.swift` — parameterize `seal`/`open` by `magic`
  (default `OCUE`); `.occues` passes `OCCU`. No legacy-plaintext fallback for
  the `OCCU` path.
- `OnlyCue/App/AppCommands.swift` (or wherever the Cue menu is built) — add
  `Export Cue List…` / `Import Cue List…`, gated on `activeItem`.
- `project.yml` / `Info.plist` — register the `com.onlycue.cues` exported
  UTType and `.occues` extension; regenerate the Xcode project with `xcodegen`.

## Testing (TDD)

**Unit (`OnlyCueTests/`)**

- `CueListTransfer` round-trip: encode a payload, decode it, assert equality.
- Crypto: `.occues` envelope seals/opens; `OCCU` magic enforced; a `.cuelist`
  (`OCUE`) file is rejected as malformed when opened as `.occues` and vice versa.
- `formatVersion`: an unknown version is rejected with the typed error.
- Type reconciliation: unique name added as-is; colliding name → `(imported)`;
  double collision → `(imported 2)`; `hotkey` dropped to `nil`; B's existing
  catalog unchanged.
- Cue reconciliation: ids regenerated; `typeID` remapped to the new type;
  `cueNumber`/`time`/`name`/`notes`/`fadeTime` preserved.
- Replace vs Add against an item with existing cues.
- `CueCommands.importCueList` undo restores both `items` and `cuePointTypes`;
  redo re-applies; one undo step covers the whole import.

**UITests (`OnlyCueUITests/`, BDD)**

- Given a project with a marked-up song, When the user runs Export Cue List…,
  Then a `.occues` file is written.
- Given a project B with a freshly imported, cue-less song, When the user
  imports a matching `.occues`, Then the cue list is populated and the new
  type(s) appear in the catalog.
- Given the selected song does not match the export's `sourceMedia`, When the
  user imports, Then the mismatch confirmation alert appears.
- Given the selected song already has cues, When the user imports, Then the
  Replace / Add / Cancel dialog appears and each path behaves correctly.

## Follow-up

- Add a short ADR (next number after ADR-024) recording the `.occues` format,
  the `OCCU` magic, and the always-additive type-reconciliation rule.
- Update `docs/data-model.md` with a short "`.occues` interchange file" section
  and note that it does not change `ProjectModel`.
- `docs/roadmap.md` Phase 2 may note portable cue lists as delivered.
