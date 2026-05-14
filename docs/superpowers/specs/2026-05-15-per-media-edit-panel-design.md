# Per-Media Edit Panel — Design

**Status:** Approved
**Date:** 2026-05-15
**Spec section implemented:** `docs/data-model.md` (MediaItem fields), `docs/architecture.md` (commands seam)

## Problem

Today the only way to edit per-media settings is the project-wide **Timecode Settings** sheet, which exposes a list of per-clip start-timecode rows but nothing else. Users want to right-click a media row in the Media Library sidebar and open a focused editor for that single clip's metadata: an alternate display name, the LTC start-timecode offset, and the per-clip LTC mute flag.

## Goals

- Right-click on a sidebar media row reveals an **Edit Media…** action.
- That action opens a modal sheet (`MediaEditSheet`) with three editable fields for the selected clip.
- All edits commit atomically through `CueCommands` so a single undo reverts the whole sheet.
- The existing project-wide Timecode Settings sheet continues to work; per-clip TC rows there edit the same underlying data.

## Non-goals

- **Per-media framerate.** Framerate stays on `ProjectTimecodeSettings`. LTC encoding, the ruler, and timecode math remain single-rate.
- **Renaming the file on disk.** The alternate name is a display-only override stored on the project. The underlying file and its security-scoped bookmark are untouched.
- **Bulk / multi-select editing.** The sheet edits one `MediaItem` at a time. Adding multi-select is a separate change if needed later.

## Data model

### New field
Add one field to `MediaItem`:

```swift
struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference
    var cues: [Cue]
    var startTimecodeFrames: Int = 0   // v10, unchanged
    var ltcMuted: Bool = false          // v10, unchanged
    var alternateName: String? = nil    // v12, NEW
}
```

Semantics:
- `nil` or empty/whitespace-only string ⇒ fall back to `media.displayName` (the file basename).
- Any non-empty string ⇒ used as the clip's displayed name everywhere user-facing.

### Schema bump
Project schema version **v11 → v12**. Migration: when decoding a v11 document, set `alternateName = nil` on every `MediaItem`. The field is otherwise additive; no existing data is rewritten.

### Resolved name helper

```swift
extension MediaItem {
    var resolvedName: String {
        if let trimmed = alternateName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            return trimmed
        }
        return media.displayName
    }
}
```

Call sites that switch from `media.displayName` to `resolvedName`:
- Media Library sidebar row label.
- Main pane title (when a clip is active).
- Cue list per-clip groupings (if labelled).
- CSV/TSV export columns that emit the clip name.

Call sites that **stay on** `media.displayName`:
- File-lookup paths, bookmark resolution, logging, error messages — anywhere the original filename is the contract.

## UI

### Entry point
In `ItemListPane` (or whichever view renders the sidebar media rows), attach a `.contextMenu` to each `MediaItem` row:

```
Edit Media…
Remove          (existing)
```

`Edit Media…` sets a `@State var editingItemID: MediaItem.ID?` on the host; the sheet is presented when non-nil.

### `MediaEditSheet`
A new view file `OnlyCue/UI/MediaEditSheet.swift`. Modal sheet styled consistently with `TimecodeSettingsSheet`. Form layout:

| Field | Control | Notes |
|---|---|---|
| **Name** | `TextField` | Placeholder = `media.displayName`. Empty submission ⇒ stores `nil`. |
| **Start timecode** | `TextField` `HH:MM:SS:FF` | Same parsing/validation as `MediaTimecodeRow` (red outline on invalid; does not commit). Display rate = project framerate. |
| **Mute LTC for this clip** | `Toggle` | Binds to a local `Bool` draft. |

Buttons: **Cancel** (discards drafts) / **Save** (commits via `CueCommands`).

Local `@State` drafts mirror the pattern in `MediaTimecodeRow` so in-progress typing isn't clobbered. Save is disabled while the TC field is invalid.

### Existing `MediaTimecodeRow`
Stays. The per-clip TC rows inside `TimecodeSettingsSheet` remain a valid second entry point for editing `startTimecodeFrames` in bulk. They edit the same field; either surface produces the same result.

## Commands (undo seam)

Add one command to `Commands/CueCommands.swift`:

```swift
func updateMediaItem(
    id: MediaItem.ID,
    alternateName: String?,
    startTimecodeFrames: Int,
    ltcMuted: Bool
)
```

- Mutates only the targeted `MediaItem`.
- Single undo step covers all three fields.
- Existing per-field commands (if any) for start-TC and mute remain for callers that edit just one field (e.g., `MediaTimecodeRow`). The new command is for the sheet's atomic Save.

## Tests (TDD)

**Model**
- `MediaItem.resolvedName` returns `media.displayName` when `alternateName` is nil, empty, or whitespace-only.
- `MediaItem.resolvedName` returns the trimmed alternate when set.
- v11 → v12 migration on a real fixture: `alternateName == nil` on every item; all other fields preserved.

**Command**
- `updateMediaItem` mutates only the targeted item (other items untouched).
- Undo after `updateMediaItem` restores all three fields to prior values in one step.

**UI smoke (`OnlyCueUITests`)**
- Right-click a sidebar media row ⇒ `Edit Media…` menu item appears.
- Activating it opens a sheet with the current Name / Start TC / Mute values pre-filled.
- Save commits and sidebar label reflects the new name.
- Cancel discards drafts; values unchanged.

## Open questions

None — Q1, Q2, Q3 resolved during brainstorming (framerate stays project-wide; alt-name is display-only; modal sheet).
