# Multi-media items per project — design

**Date:** 2026-05-08
**Status:** Approved
**Spec sections:** `docs/data-model.md`, `docs/architecture.md`, `docs/verification.md`, `docs/decisions.md` (new ADR)

## Problem

A `.cuelist` document holds exactly one media file (`ProjectModel.media: MediaReference?`) and one cue list (`ProjectModel.cues: [Cue]`). Lighting designers running a show with multiple acts, songs, or scenes have to juggle one window per file, with no single project that contains the whole set. Imports overwrite the existing media via `MediaImporter`.

## Goal

A single `.cuelist` document can hold N independent media items. Each item has its own media reference and its own cue list — cues are not shared across items. The user can:

- Import multiple files in one action (file picker or drag-drop).
- Switch the active item via a sidebar.
- Reorder items.
- Rename, remove, and undo/redo all of the above.

## Decisions

Captured during brainstorming, all user-confirmed:

1. **Container:** One `.cuelist` holds N `MediaItem`s. Not N separate documents. Not a workspace-of-files.
2. **Switcher UI:** Left sidebar list (three-pane layout: items | preview | cues).
3. **End-of-item playback:** Stop, stay on item. No auto-advance (matches v0.1.0; avoids surprises during live shows).
4. **v1 migration:** Auto-migrate v1 (single media + cues) into one `MediaItem` on open. One-way upgrade. Save always writes v2.
5. **Item ordering:** Drag-to-reorder. New imports append to end. Reorder is undoable via the `CueCommands` seam.
6. **Multi-import:** `fileImporter` with `allowsMultipleSelection: true`. Drop targets accept multiple URLs. Each becomes a `MediaItem` in selection/drop order.

## Design

### Data model (schema v2)

```swift
struct ProjectModel: Codable {
    var schemaVersion: Int = 2
    var id: UUID
    var name: String
    var items: [MediaItem]
    var activeItemID: MediaItem.ID?   // nil only if items is empty
}

struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference   // required — items only exist because a file was imported
    var cues: [Cue]
}
```

`MediaReference` and `Cue` are unchanged.

The "empty document, no media" state is `items: []` with `activeItemID: nil`. `activeItemID` lives in the document so users land on the same item after save/reopen.

### Migration v1 → v2

Pure function in `ProjectModel.migrate(_:)`:

- v1 with `media != nil` → wrap `(media, cues)` in a single `MediaItem` with a fresh UUID; set as active.
- v1 with `media == nil` → `items: []`, `activeItemID: nil`.

Save always writes v2. v1 readers (v0.1.0) cannot open v2 files — accepted by bumping `schemaVersion`.

### UI layout

`DocumentView` becomes a `NavigationSplitView` with three columns:

```
┌─────────────┬──────────────────────┬──────────────┐
│ Items       │ Preview              │ Cues         │
│ (sidebar)   │ (video/waveform +    │ (existing    │
│             │  transport)          │  CueListPane)│
│ ▸ Act 1.wav │                      │              │
│ ▸ Act 2.mp4 │  [active item only]  │  [active     │
│ ▸ Act 3.wav │                      │   item's     │
│             │                      │   cues]      │
└─────────────┴──────────────────────┴──────────────┘
```

**`ItemListPane`** (new, `OnlyCue/UI/ItemListPane.swift`):

- `List` of `model.items`, selection bound to `model.activeItemID` via `setActiveItem(id:)`.
- Each row (`ItemRowView`): media-kind icon (audio/video), `displayName`, formatted duration.
- `.onMove` for drag-reorder → `CueCommands.reorderItems(from:to:)`.
- Context menu / ⌫: `removeItem` (undoable).
- Drop target: accepts multiple file URLs; routes through `MediaImporter.importMedia(from: [URL], …)`.
- Empty state copy: "No media. Import or drag files here."

**Preview pane and `CueListPane`** stay structurally identical but bind to the *active item* (`model.items.first(where: { $0.id == model.activeItemID })`) instead of `model.media` / `model.cues`.

### Active-item switch behavior

1. `engine.pause()` then `engine.unload()` (new method).
2. Resolve bookmark for the new item, build `AVURLAsset`, `engine.load(asset:)`.
3. Reset transport to `0.0`. (No per-item playhead memory in v1.)
4. Cue list pane and waveform re-render automatically via `@Observable` invalidation.

The waveform cache is already keyed by asset URL, so each item gets its own cached peaks for free.

### Commands (CueCommands seam)

All mutations continue to flow through `Commands/CueCommands.swift` per the project hard rules.

Existing per-cue commands (`addCue`, `renameCue`, `retime`, `recolor`, `delete`) become **active-item-scoped**: they read `model.activeItemID`, locate the item, and mutate its `cues`. If `activeItemID == nil`, they no-op.

New item-level commands, all undoable except `setActiveItem`:

| Command | Behavior |
|---|---|
| `addItem(_ item: MediaItem)` | Append to `items`. If first item, set as active. Undo removes it and restores prior `activeItemID`. |
| `addItems(_ items: [MediaItem])` | Batch append in one undo group. Used by multi-import. |
| `removeItem(id:)` | Remove from `items`. If it was active, advance to the next item (or previous if last). Undo restores item at original index and prior active. |
| `renameItem(id:to:)` | Edit `media.displayName`. Undoable. |
| `reorderItems(from:to:)` | Move within array. Undoable. Doesn't change active item identity. |
| `setActiveItem(id:)` | **Not undoable.** Selection isn't a document mutation; undoing selection changes is annoying. Mirrors Finder. |

### MediaImporter rewrite

```swift
@MainActor
static func importMedia(
    from urls: [URL],
    into document: CueListDocument,
    engine: PlayerEngine
) async throws {
    var newItems: [MediaItem] = []
    var failures: [MediaImportError] = []
    for url in urls {
        do { newItems.append(try await makeItem(from: url)) }
        catch let e as MediaImportError { failures.append(e) }
    }
    if !newItems.isEmpty {
        let firstNewID = newItems.first!.id
        CueCommands.addItems(newItems, to: document)
        if document.model.activeItemID == nil
            || document.model.items.count == newItems.count {
            CueCommands.setActiveItem(id: firstNewID, in: document)
            try await loadActive(into: document, engine: engine)
        }
    }
    if !failures.isEmpty { throw MediaImportError.batch(failures) }
}
```

- Per-file failures don't poison the batch — successes import; failures surface as a single aggregate error the UI shows in an alert (e.g., "3 of 5 files imported. 2 unsupported: foo.txt, bar.psd").
- `loadActive(into:engine:)` is the existing single-file load path, factored out for reuse on active-item switch.

### PlayerEngine

Add `unload()`: cancel time observer, set `AVPlayer.replaceCurrentItem(with: nil)`, clear `currentTime` / `duration` / `isPlaying`. Active-item switch calls `unload()` then `load(asset:)`.

## Testing

TDD red→green per CLAUDE.md.

**Unit tests (`OnlyCueTests/`)**

- `ProjectModelMigrationTests`
  - v1 with media → one-item v2 (media and cues preserved, fresh item UUID, set active)
  - v1 without media → empty items v2, `activeItemID == nil`
  - v2 round-trips unchanged
  - Unknown future `schemaVersion` rejected
- `CueCommandsItemTests`
  - `addItem` appends and activates first item
  - `addItems` batches into one undo group
  - `removeItem` advances active to next; to previous when removing last; clears when removing only item
  - `renameItem` edits display name; undoable
  - `reorderItems` moves within array; undoable; preserves active identity
  - Undo/redo for each
- `CueCommandsActiveScopingTests`
  - `addCue` / `retime` / `delete` mutate only the active item's cues
  - All cue commands no-op when `activeItemID == nil`
- `MediaImporterBatchTests`
  - N valid URLs → N items appended in order
  - Mixed valid + unsupported → valid imported, aggregate `batch` error reported
  - Import into empty doc sets active to first new item
  - Import into non-empty doc preserves prior active

**UI tests (`OnlyCueUITests/`, Gherkin)**

```
Given a document with no media
When the user drops 3 audio files on the sidebar
Then 3 rows appear in drop order
And the first item is active

Given 2 imported items each with their own cues
When the user clicks the second item in the sidebar
Then the preview pane shows the second item's media
And the cue list shows only the second item's cues
And the transport time is 00:00:00

Given 2 items in the sidebar
When the user drags item 2 above item 1
And saves and reopens the document
Then the order is preserved
```

## Files

- New: `OnlyCue/UI/ItemListPane.swift`, `OnlyCue/UI/ItemRowView.swift`
- New: `OnlyCueTests/ProjectModelMigrationTests.swift`
- New: `OnlyCueTests/CueCommandsItemTests.swift`
- New: `OnlyCueTests/CueCommandsActiveScopingTests.swift`
- New: `OnlyCueTests/MediaImporterBatchTests.swift`
- New: `OnlyCueUITests/MultiItemImportUITests.swift`
- Modified: `OnlyCue/Model/ProjectModel.swift` (schema v2, `MediaItem`, migration)
- Modified: `OnlyCue/Commands/CueCommands.swift` (active-item scoping + new item commands)
- Modified: `OnlyCue/Commands/MediaImporter.swift` (batch + factored `loadActive`)
- Modified: `OnlyCue/Media/PlayerEngine.swift` (`unload()`)
- Modified: `OnlyCue/UI/DocumentView.swift` (three-pane `NavigationSplitView`)
- Modified: `OnlyCue/UI/PreviewPane.swift`, `OnlyCue/UI/CueListPane.swift` (bind to active item)
- Modified: `docs/data-model.md`, `docs/architecture.md`, `docs/verification.md`, `docs/decisions.md` (new ADR), `docs/build-sequence.md`, `README.md`

## Out of scope (deferred)

- Per-item playhead memory (active switch always resets to 0).
- Cross-item cue copy/move.
- Cue reordering across items.
- Auto-advance playback between items.
- Per-item color or label styling for the sidebar.

## Acceptance criteria (Gherkin)

```
Given an existing v0.1.0 .cuelist file with media and cues
When the user opens it in the new version
Then the file loads as a single-item v2 document
And the media and cues are preserved
And subsequent saves write schema v2

Given a project document
When the user picks 5 media files in the import dialog (3 valid, 2 unsupported)
Then 3 items are appended to the sidebar in selection order
And an alert lists the 2 unsupported filenames
And the first newly-imported item becomes active if no item was active before

Given a document with multiple items
When the user adds cues to item A, switches to item B, adds different cues to B
Then item A's cue list contains only A's cues
And item B's cue list contains only B's cues
And switching back to A shows A's cues unchanged

Given a document with 3 items
When the user drags item 3 to position 1
And saves and reopens the document
Then the order is 3, 1, 2
And the previously-active item is still active
```
