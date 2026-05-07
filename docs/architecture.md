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
                │  │   • media ref       │     │
                │  │   • [Cue]           │     │
                │  └─────────────────────┘     │
                └──────────────┬───────────────┘
                               │
                ┌──────────────▼───────────────┐
                │       DocumentView           │  NavigationSplitView
                │ ┌────────────┬─────────────┐ │
                │ │ PreviewPane│ CueListPane │ │
                │ │ ┌────────┐ │ ┌─────────┐ │ │
                │ │ │ Video  │ │ │ Cue rows│ │ │
                │ │ │ or     │ │ │         │ │ │
                │ │ │Waveform│ │ │         │ │ │
                │ │ └────────┘ │ └─────────┘ │ │
                │ ├────────────┴─────────────┤ │
                │ │       TransportBar       │ │
                │ └──────────────────────────┘ │
                └──────────────┬───────────────┘
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
│   ├── ProjectModel.swift        # Codable root
│   ├── Cue.swift                 # Codable cue
│   └── MediaReference.swift      # Codable bookmark wrapper
├── Media/
│   ├── PlayerEngine.swift        # AVPlayer wrapper, @Observable
│   ├── WaveformGenerator.swift   # Async peak extraction
│   └── WaveformCache.swift       # On-disk peak cache
├── UI/
│   ├── DocumentView.swift        # Top-level NavigationSplitView
│   ├── PreviewPane.swift         # Video stacks waveform below; audio fills with waveform
│   ├── WaveformView.swift        # Canvas waveform + markers + playhead
│   ├── TransportBar.swift        # Transport controls
│   ├── CueListPane.swift         # Cue table
│   └── CueRowView.swift          # Single cue row
├── Commands/
│   └── CueCommands.swift         # add/delete/move/rename — undoable
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

**Import media**
File importer → resolve URL → create security-scoped bookmark → `AVAsset(url:)` → set `ProjectModel.media` → `PlayerEngine.load(asset:)` → kick off `WaveformGenerator` (async, audio only) → cache peaks.

**Add cue at playhead**
`M` key → `CueCommands.add(at: player.currentTime)` → `UndoManager.registerUndo` → `ProjectModel.cues.append(...)` → SwiftUI re-renders cue list and waveform markers.

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

## Phase-2 seams

These are explicit extension points so future features don't require rewrites. See [`roadmap.md`](roadmap.md) for what plugs in here.

| Seam | Future use |
|---|---|
| `PlayerEngine.currentTime` publisher | LTC encoder subscribes and feeds Core Audio |
| `ProjectModel` is plain JSON | Templates are just `.cuelist` files with no media |
| `AppCommands` reads keymap | Custom shortcuts editor reads/writes the same JSON |
| `ProjectModel.cues` is a flat array | Export to CSV / EDL / Timecode XML is a pure transform |
| `CueCommands` is the only mutator | AI-suggested cues call the same API to insert |
