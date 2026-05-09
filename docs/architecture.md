# Architecture

OnlyCue is a **document-based SwiftUI app** following MVVM. Each open `.cuelist` file is one document with its own model, player engine, and undo stack.

## High-level diagram

```
┌─────────────────────────────────────────────────────────────┐
│                       OnlyCueApp (@main)                    │
│                       DocumentGroup                         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                ┌──────────────▼───────────────┐
                │     CueListDocument          │  ReferenceFileDocument
                │  ┌─────────────────────┐     │  - load / save JSON
                │  │   ProjectModel      │     │  - vended UndoManager
                │  │   • [MediaItem]     │     │
                │  │   • activeItemID    │     │
                │  └─────────────────────┘     │
                └──────────────┬───────────────┘
                               │
                ┌──────────────▼───────────────────────────────┐
                │            DocumentView                      │  NavigationSplitView (3-pane)
                │ ┌────────────┬────────────┬───────────────┐  │
                │ │ItemListPane│ PreviewPane│ CueListPane   │  │
                │ │ ┌────────┐ │ ┌────────┐ │ ┌───────────┐ │  │
                │ │ │ Items  │ │ │ Video  │ │ │ Cue rows  │ │  │
                │ │ │ sidebar│ │ │ or     │ │ │ (active   │ │  │
                │ │ │        │ │ │Waveform│ │ │  item)    │ │  │
                │ │ └────────┘ │ └────────┘ │ └───────────┘ │  │
                │ │            ├────────────┴───────────────┤  │
                │ │            │       TransportBar         │  │
                │ └────────────┴────────────────────────────┘  │
                └──────────────┬───────────────────────────────┘
                               │ binds to
                ┌──────────────▼───────────────┐
                │       PlayerEngine           │  @Observable
                │ • AVPlayer                   │
                │ • currentTime publisher      │
                │ • play / pause / seek        │
                └──────────────┬───────────────┘
                               │
                ┌──────────────▼───────────────┐
                │   AVFoundation (system)      │
                │ AVAsset / AVPlayer /         │
                │ AVAssetReader / AVPlayerLayer│
                └──────────────────────────────┘
```

## Folder layout

```
OnlyCue.xcodeproj
OnlyCue/
├── App/
│   ├── OnlyCueApp.swift          # @main, DocumentGroup
│   └── AppCommands.swift         # Menu commands (Add Cue, Import Media…)
├── Document/
│   ├── CueListDocument.swift     # ReferenceFileDocument, .cuelist UTType
│   ├── ProjectModel.swift        # Codable root, schema-versioned decoder + v1→v2 migration
│   ├── MediaItem.swift           # Codable per-media wrapper (media + own cues)
│   ├── Cue.swift                 # Codable cue
│   └── MediaReference.swift      # Codable bookmark wrapper
├── Media/
│   ├── PlayerEngine.swift        # AVPlayer wrapper, @Observable
│   ├── WaveformGenerator.swift   # Async peak extraction
│   └── WaveformCache.swift       # On-disk peak cache
├── UI/
│   ├── DocumentView.swift        # Three-pane NavigationSplitView (items | preview | cues)
│   ├── ItemListPane.swift        # Sidebar list of MediaItems; drag-reorder, multi-URL drop
│   ├── ItemRowView.swift         # Single sidebar row (kind icon + name + duration)
│   ├── PreviewPane.swift         # Video stacks waveform below; audio fills with waveform (active item)
│   ├── WaveformContainer.swift   # ScrollView host: pinch + ⌘=/⌘-/⌘0 zoom (1×–16×), auto-follow
│   ├── WaveformZoomController.swift # Anchored-zoom + auto-follow math (pure, unit-tested)
│   ├── WaveformView.swift        # Canvas waveform + markers + playhead
│   ├── TransportBar.swift        # Transport controls
│   ├── CueListPane.swift         # Cue table (active item)
│   └── CueRowView.swift          # Single cue row
├── Commands/
│   └── CueCommands.swift         # cue + item commands — undoable (selection is not)
└── Utilities/
    ├── Time+Format.swift         # HH:MM:SS.mmm formatter
    └── Bookmarks.swift           # Security-scoped bookmark helpers

OnlyCueTests/                     # Unit: model round-trip, commands, time math
OnlyCueUITests/                   # Smoke: new doc → import → cue → save → reopen
```

## Layer responsibilities

| Layer | Owns | Does NOT own |
|---|---|---|
| **App** | App lifecycle, menu wiring | Document state |
| **Document** | `ProjectModel`, persistence, undo | Playback, UI |
| **Media** | Playback state, waveform peaks | Cue data, UI layout |
| **UI** | Views and bindings | Mutating model directly (goes through Commands) |
| **Commands** | Undoable mutations to `ProjectModel` | I/O, playback |
| **Utilities** | Pure helpers | Anything stateful |

The strict rule: **UI never mutates `ProjectModel` directly.** All mutations route through `CueCommands`, which registers undo and updates the document. This keeps undo correct and gives us one place to add validation, telemetry, or future hooks (e.g. push to console).

## Key system APIs (no need to reinvent)

| Need | API |
|---|---|
| New / open / save / autosave / recents | `DocumentGroup` + `ReferenceFileDocument` |
| Audio + video playback | `AVPlayer` + `AVPlayerLayer` (in `NSViewRepresentable`) |
| Waveform sample extraction | `AVAssetReader` + `AVAssetReaderTrackOutput` |
| Persistent file access across launches | `URL.bookmarkData(options: .withSecurityScope)` |
| Undo / redo | `UndoManager` (provided by `ReferenceFileDocument`) |
| Waveform + marker drawing | SwiftUI `Canvas` |

## Data flows

**Import media (one or many)**
File importer (`allowsMultipleSelection: true`) or sidebar drop → for each URL: resolve, create security-scoped bookmark, build `MediaItem` → `CueCommands.addItems(...)` appends in selection order → if document was empty, `setActiveItem` to the first new id and `MediaImporter.loadActive` → `PlayerEngine.load(asset:)` → kick off `WaveformGenerator` (audio only) → cache peaks. Per-file failures surface as `MediaImportError.batch(unsupported:)` after the successful imports complete.

**Switch active item**
Sidebar selection → `CueCommands.setActiveItem(id:)` (not undoable) → `DocumentView.task(id: activeItemID)` invalidates → `engine.unload()` → resolve next item's bookmark → `engine.load(asset:)`. Transport resets to 0; cue list and preview rebind to the new item.

**Add cue at playhead**
`M` key → `CueCommands.addCueAtPlayhead(...)` → finds the active item index → mutates `items[i].cues` → registers undo → SwiftUI re-renders the cue list and waveform markers for the active item.

**Seek from cue click**
`CueListPane` row tap → `PlayerEngine.seek(to: cue.time)` → `currentTime` publisher updates → waveform playhead follows.

**Save**
`ReferenceFileDocument.snapshot` → `JSONEncoder` (pretty, sortedKeys) → `.cuelist` file. Bookmark stored as base64 inside JSON.

**Reopen**
`init(configuration:)` decodes JSON → resolves bookmark → if still valid, loads asset; if stale, surfaces a "relink media" alert.

## Concurrency

- Player time updates run on the main actor (UI binding).
- Waveform peak extraction runs on a background task; result is published once and cached.
- Document save runs on the main actor (cheap, JSON only).

## Notes overlay

Toggleable HUD layer rendering the active cue's notes on top of `PreviewPane` so a show caller can read them during a run-through. UI surface, no schema impact.

| Aspect | Rule |
|---|---|
| Active-cue resolution | `MediaItem.activeCue(at: TimeInterval) -> Cue?` — the cue with the largest `time <= playhead`. Inclusive on `currentTime` (boundary cue IS active). Returns `nil` when the playhead is before the first cue or `cues` is empty; returns the last cue when the playhead is past it (notes persist until show end). |
| Toggle | `View > Show Notes Overlay`, persisted via `@AppStorage("showNotesOverlay")`. Default OFF. Both `AppCommands` and `PreviewPane` bind to the same UserDefaults key — SwiftUI keeps them in sync. |
| Render contract | When the toggle is ON and the active cue has non-empty notes, the overlay renders a centered `Text(cue.notes)` card on `.ultraThinMaterial` background. When the active cue is `nil` or its notes are empty, the layer renders nothing — the toggle stays on but the card disappears (no placeholder text). |
| Default visual | Bottom-center alignment, `.title` font, `.primary` foreground on `.ultraThinMaterial` rounded card, max-width 600pt, multi-line wrap, 12pt bottom padding inside the preview clip rect. |
| Customisation | Deferred. The customisation sheet (font scaling, position, color, optional cue-ID prefix) and restore-defaults button are separate leaves of [#38](https://github.com/chienchuanw/only-cue/issues/38). When that leaf lands, an ADR will lock the persistence shape (per-app vs per-document tuning). |

## Phase-2 seams

These are explicit extension points so future features don't require rewrites. See [`roadmap.md`](roadmap.md) for what plugs in here.

| Seam | Future use |
|---|---|
| `PlayerEngine.currentTime` publisher | LTC encoder subscribes and feeds Core Audio |
| `ProjectModel` is plain JSON | Templates are just `.cuelist` files with no media |
| `AppCommands` reads keymap | Custom shortcuts editor reads/writes the same JSON |
| `ProjectModel.cues` is a flat array | Export to CSV / EDL / Timecode XML is a pure transform |
| `CueCommands` is the only mutator | AI-suggested cues call the same API to insert |
