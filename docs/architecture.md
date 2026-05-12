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

## Export pipeline

Console export (#34) is modelled as a pipeline of two orthogonal pure functions over `ProjectModel` data, plus an AppKit-side action that wires user input to a save panel. The split keeps the algorithmic core testable in isolation and lets future formats (grandMA2/3) compose without touching the filter or the menu wiring.

| Stage | API | Where it lives |
|---|---|---|
| Filter (which cues) | `CueExportFilter.cues(_:onlyTypeIDs:) -> [Cue]` | `OnlyCue/Document/CueExportFilter.swift` |
| Format (string output) | `CueCSVExporter.csv(cues:typeNamesByID:) -> String` and `.tsv(...)` | `OnlyCue/Document/CueCSVExporter.swift` |
| Action (NSSavePanel + disk) | `CueCSVExportAction.run(model:) throws` | `OnlyCue/Document/CueCSVExportAction.swift` |
| Menu (user entry) | "File > Export Cues to CSV…" `⇧⌘E` | `OnlyCue/App/AppCommands.swift` |
| Receiver (notification → action) | `.onReceive(.exportCuesToCSVRequested)` | `OnlyCue/UI/DocumentView.swift` |

Schema (one row per cue, plus a header):

```text
id,name,time,fadeIn,fadeOut,type,notes
```

`time` / `fadeIn` / `fadeOut` are decimal seconds matching in-memory storage. `type` is the human-readable name from the project's `CuePointType` lookup; the column is empty when the type ID isn't in the lookup.

**Format-aware escape.** CSV and TSV share a private `format(cues:typeNamesByID:delimiter:)` that threads the active delimiter into the escape check. A value containing the active delimiter, a quote, or a newline is wrapped in `"`s with internal quotes doubled (RFC 4180-style). TSV values with commas pass through unescaped because commas aren't column separators in TSV. Plain values pass through untouched in either format.

**Filter contract.** Empty `onlyTypeIDs` means "no filter" — the input list passes through. This matches the natural UI default ("export all cues") and keeps callers from special-casing it. The filter preserves input order so downstream exporters don't observe a re-sort they didn't request.

**Notification-bridge wiring.** The File menu posts `.exportCuesToCSVRequested`; `DocumentView` receives it and calls `CueCSVExportAction.run(model:)`. Same pattern as `.importMediaRequested`. Adding a future toolbar button or AppleScript hook means adding another poster — no new exporter code.

**Targets.** `ExportTarget` is a Swift `enum` with cases `csv`, `tsv`, `ma3`, `ma2`. Each case carries `displayName`, `fileExtension`, `contentType`, and a `format(cues:typeNamesByID:)` method that delegates to the right `CueCSVExporter` static. Adding a new target is a single-row enum addition + a switch branch. MA3 and MA2 share a `maCSV` formatter that renames the header row to grandMA conventions (`Cue,Name,Trig Time,Fade In,Fade Out,Type,Note`); see ADR-014 for the best-effort caveat.

**Golden-file regression tests.** `CueExportGoldenFileTests` pins byte-equivalent output for every target against a curated 3-cue fixture inlined as a Swift multi-line string. Schema or escape-rule drift fails loudly with a readable diff.

## Templates

CuePointType sets are reusable across projects via templates (epic #39). A template is a small JSON file under `~/Documents/OnlyCue/Templates/<name>.cuelist-template` carrying just a `schemaVersion`, a `name`, and a `[CuePointType]`. Templates intentionally do NOT carry media or cues — they're a Type bundle, not a project bundle.

| Stage | API | Where it lives |
|---|---|---|
| Format | `CueListTemplate { schemaVersion, name, cuePointTypes }` | `OnlyCue/Document/CueListTemplate.swift` |
| Store | `TemplateStore.save / .load / .list / .appendMerge` | `OnlyCue/Document/TemplateStore.swift` |
| Action (NSSavePanel/NSOpenPanel + disk) | `TemplateAction.save / .load / .newDocument` | `OnlyCue/Document/TemplateAction.swift` |
| Menu (user entry) | "File > New from Template…" / "File > Save Template As…" / "File > Load Template…" | `OnlyCue/App/AppCommands.swift` |
| Receiver (notification → action) | `.templateMenuReceiver(...)` view modifier (save / load) | `OnlyCue/UI/TemplateMenuReceiver.swift` |

**Append-merge load semantics.** Loading a template into an existing project assigns FRESH UUIDs to each loaded type and appends them to `ProjectModel.cuePointTypes`. Existing types keep their IDs, so existing cues' `typeID` references are never broken. Loading the same template twice produces two distinct copies (two fresh UUID sets) — predictable, non-destructive. ADR-015.

**New-document-from-template.** `File → New from Template…` opens an `NSOpenPanel` at the templates folder; on pick, `TemplateAction.newDocument` loads (and so validates) the template into `TemplateStore.pendingNewDocumentTemplate`, then calls `NSDocumentController.shared.newDocument(nil)`. `CueListDocument.init()` reads-and-clears that slot — when a template is pending the new project starts with its CuePointTypes (fresh UUIDs); otherwise the single built-in default, exactly as a plain ⌘N. The consume-and-clear means a stale slot can never bleed into a later ⌘N. (A splash-screen template picker is a possible later addition; `⇧⌘N` is unavailable — it's the Show Notes Overlay toggle.) `New from Template…` is handled directly in `AppCommands` rather than via the notification-bridge the save/load commands use, because it must work with no document window open.

**Why no name-collision detection.** The append-and-let-user-rename strategy keeps the load action conflict-free. Users can rename through the existing Manage Types sheet.

## OSC remote control

A receive-only OSC server (epic #35) lets external controllers — Bitfocus Companion, StreamDeck, grandMA3 macros — drive transport and cue navigation over UDP.

| Stage | API | Where it lives |
|---|---|---|
| Wire format | `OSCMessage { addressPattern, [OSCArgument] }`; `OSCParser.parse(_:)` (pure) | `OnlyCue/OSC/OSCMessage.swift`, `OSCParser.swift` |
| Command mapping | `OSCCommand.from(_ message:) -> OSCCommand?` (pure) | `OnlyCue/OSC/OSCCommand.swift` |
| Server | `OSCServer` — `@Observable @MainActor` wrapper over `NWListener` (UDP) | `OnlyCue/OSC/OSCServer.swift` |
| Host (per document) | `.oscServerHost(...)` view modifier — owns the server, dispatches commands to `PlayerEngine` / `CueCommands`, presents the monitor sheet | `OnlyCue/UI/OSCServerHost.swift` |
| Settings | `Settings → OSC` — enable toggle + listen port + copyable address list | `OnlyCue/UI/OSCSettingsView.swift` |
| Monitor | `Tools → OSC Monitor…` — sheet: listening status + port, live newest-first message tail (`Clear` to reset), copyable address list | `OnlyCue/UI/OSCMonitorView.swift`, `OSCSupportedAddressList.swift` |

`OSCParser` handles the OSC 1.0 subset OnlyCue needs: 4-byte-aligned OSC-strings, big-endian `int32` / `float32`, the zero-byte type tags (`T`/`F`/`N`/`I`), and `#bundle` flattening. A malformed datagram returns nil and is dropped — never crashes. `OSCServer` keeps a capped newest-first `recentMessages` ring buffer (including unrecognised addresses); `OSCServer.formatLine(for:)` renders each entry as `"<address> <arg…>"` and the monitor sheet live-tails it. The monitor is a sheet presented from `OSCServerHost` rather than a standalone window: the server is per-document, so a free-floating window would have to pick which document to mirror — the sheet just mirrors the one it's attached to. It re-uses `OSCSupportedAddressList` (the same copyable rows the Settings pane shows).

**Threading.** `NWListener` / `NWConnection` callbacks run on the server's private `DispatchQueue`. The connection-accept and receive-loop methods are `nonisolated` (they touch only the `Sendable` `NWConnection` and the immutable queue); everything that mutates observable state or invokes the command handler hops to the main actor in `ingest(_:)`.

**Supported addresses.** `/onlycue/play`, `/pause`, `/stop`, `/skip <seconds>` (signed int/float), `/locate <seconds>`, `/cue/add`, `/cue/next`, `/cue/prev`. See `docs/osc-companion-ma3.md` for Companion and grandMA3 macro syntax per address.

**Scope.** Receive-only (no state broadcast — that's Phase 3). Manual IP configuration (no Bonjour). Per-document ownership: each open window has its own `OSCServer` binding the same port with `allowLocalEndpointReuse`. On Darwin a unicast datagram is delivered to exactly one of the bound sockets (kernel-chosen), so with two document windows open one unpredictable document responds — fine for the single-document workflow OSC control implies. macOS shows a one-time firewall prompt on first bind; no App Sandbox entitlement is needed (the app isn't sandboxed — ADR-007). See ADR-016.

## Timeline breakdown view

A toggleable alternative to the waveform timeline (epic #37) that splits the cues into one lane per visible `CuePointType`, so a programmer can read "lighting only" or "sound only" at a glance.

| Stage | API | Where it lives |
|---|---|---|
| Layout (pure) | `TimelineBreakdownLayout.lanes(cues:types:)` / `.hiddenCount(types:)` | `OnlyCue/UI/TimelineBreakdownLayout.swift` |
| View | `TimelineBreakdownView` (+ private `BreakdownPlayheadLine`) | `OnlyCue/UI/TimelineBreakdownView.swift` |
| Visibility mutation | `CueCommands.setCuePointTypeVisibility(...)` / `.showAllCuePointTypes(...)` | `OnlyCue/Commands/CueCommands+Types.swift` |
| Toggle | `View → Show Timeline Breakdown` (`⇧⌘B`) → `@AppStorage("showTimelineBreakdown")` | `OnlyCue/App/AppCommands.swift`, read in `PreviewPane` |

`TimelineBreakdownLayout` is pure: it filters Types by `isVisible`, keeps model order (no reordering in v1), and partitions cues into a `Lane` per Type (Types with no cues still get an empty lane; stray-typed cues are dropped). `TimelineBreakdownView` renders each lane as `[colour swatch + name + hide button] | [track with that Type's markers]`, markers positioned by `CueMarkersGeometry.position` (the same time→x mapping the waveform overlay uses, so a cue sits at the same horizontal spot in either view). A single playhead line spans all lanes — drawn by `BreakdownPlayheadLine`, its own view so only it re-renders on each `engine.currentTime` tick, not the lanes. Lanes scroll vertically if they overflow; hidden Types collapse into a "+N hidden lanes" button (`showAllCuePointTypes` — one undo step). There's no horizontal zoom in the breakdown view in v1.

**Persistence.** Lane visibility is `CuePointType.isVisible`, already a `ProjectModel` field (migrations preserve it), so the layout persists in `.cuelist` with no schema change. Toggling goes through `CueCommands`, so it's undoable and triggers a document edit. **Scope (v1):** markers in the breakdown view select + seek; retiming a cue by drag stays on the waveform view. Per-lane vertical/horizontal zoom and free-form lane reordering are out. See ADR-017.

## Custom keyboard shortcuts

User-rebindable shortcuts (epic #40 — complete). The keymap JSON is the source of truth; **every** `.keyboardShortcut(...)` in `AppCommands` (the menu commands) and in `DocumentView` (the `m` "Add Cue", `0`–`9` cue-type hotkeys, Space play/pause, ←→ jump ±1 s, ↑↓ prev/next cue), plus the `DocumentShortcutHints` cheat-sheet text, read it; the Settings → Keyboard editor writes it. Defaults are exactly the old hardcoded literals.

| Piece | API | Where it lives |
|---|---|---|
| Action enum | `KeymapAction` (`.importMedia`, `.exportCues`, the waveform-zoom / overlay-toggle / cue-edit actions, `.addCueOfType1…9`) — `rawValue` is the stable JSON key; `displayName` via a static dict | `OnlyCue/App/KeymapAction.swift` |
| Chord value | `KeyChord(key:modifiers:)` — `Codable`; `key` is one printable char or a special-key name (`"leftArrow"`, …); `keyboardShortcut` → SwiftUI `KeyboardShortcut`, `displayString` → `⇧⌘E`; `KeyChord.from(keyEquivalent:modifiers:)` builds one from a captured key event (lower-cases letters, maps special keys, rejects unbindable function keys), `specialKeyName(for:)` is the reverse lookup | `OnlyCue/App/KeyChord.swift` |
| Keymap | `Keymap` — total map `action → chord`; `chord(for:)`, `conflicts()`, `actionsConflicting(with:excluding:)`, `rebind`, `resetToDefault`, `resetAll`; `Keymap.default` mirrors today's hardcoded shortcuts; `Keymap.decode(_:)` is lenient (nil/corrupt → default, partial → backfilled, unknown keys dropped) | `OnlyCue/App/Keymap.swift` |
| Store | `KeymapStore` (`@MainActor`, `ObservableObject`) — persistence under `keymap.v1`, injectable `UserDefaults` for tests; `KeymapStore.shared` is the app-wide instance `AppCommands` and the editor both observe | `OnlyCue/App/KeymapStore.swift` |
| Editor | `KeyboardSettingsView` — Settings → Keyboard tab; a row per `KeymapAction` (`displayName` · current chord button · per-row reset-to-default · conflict ⚠︎); clicking the chord enters a `.onKeyPress` capture (Esc cancels), the captured `KeyChord` is `rebind`-ed and persisted immediately; a "Reset All…" footer button + a conflict summary | `OnlyCue/UI/KeyboardSettingsView.swift`, mounted in `OnlyCueApp.swift`'s `Settings { TabView { … } }` |
| Consumers | `shortcut(_ action:)` → `KeymapStore.shared.keymap.chord(for:).keyboardShortcut` (falls back to `Keymap.default`'s) — every `.keyboardShortcut(…)` in `AppCommands` *and* `DocumentView` goes through it; `DocumentView`'s `ForEach(0...9)` digit row uses `KeymapAction.addCueOfType(digit)`; `DocumentShortcutHints` shows `keymap.chord(for:).displayString` | `OnlyCue/App/AppCommands.swift`, `OnlyCue/UI/DocumentView.swift`, `OnlyCue/UI/DocumentShortcutHints.swift` |

**Schema.** On disk a keymap is a plain JSON object `{ actionRawValue: { key, modifiers } }` — sparse (only overrides need be present; missing actions resolve to the default), forward-tolerant (unknown action keys are ignored, so a newer build's keymap doesn't break an older one and vice versa). The `KeymapAction` raw value is the stable wire key — renaming a case requires a migration. **Conflict rule (v1):** two actions may hold the same chord; `conflicts()` / the editor's ⚠︎ surface the clash but nothing is auto-resolved or blocked (macOS itself tolerates duplicate shortcuts — last responder wins). See ADR-018.

## LTC and routing

SMPTE Linear Timecode generation synced to playback (epic #33), routable to a configurable Core Audio output. **Built so far:** the timecode value model + the 80-bit LTC frame + the biphase-mark modulation primitive + the sample synthesis (rows 1–5 below); the project's persisted timecode settings (`ProjectModel.timecodeSettings` — `ProjectTimecodeSettings`, schema v7); the **Timecode Settings sheet** (`Tools → Timecode Settings…`) that edits them (`CueCommands.setProjectTimecodeSettings`, undoable; text parsed by `Timecode.parse(_:rate:)`); and the **routing settings data layer** — `LTCRoutingSettings` (device UID + per-channel roles) persisted in `UserDefaults` via `LTCRoutingStore`, plus Core Audio device enumeration (`AudioOutputDeviceList`). **Not yet:** the `AVAudioEngine` playback path fed by `PlayerEngine.currentTime` that actually renders LTC onto the assigned channel, striped-LTC playback (read existing LTC off imported media), and the Audio side of the preferences UI (output device + routing pickers).

| Piece | API | Where it lives |
|---|---|---|
| Framerate | `SMPTEFramerate` (`fps24` / `fps25` / `fps30` / `fps30drop`; `framesPerSecond`, `isDropFrame`, `displayName`) — `Codable`, raw values `"24"` / `"25"` / `"30"` / `"30df"` are the stable `.cuelist` tokens | `OnlyCue/LTC/SMPTEFramerate.swift` |
| Timecode | `Timecode` (`HH:MM:SS:FF` for a rate; `init?(hours:minutes:seconds:frames:rate:)` validating ranges + drop-frame-skipped numbers, `init(frameCount:rate:)` / `frameCount`, `init(totalSeconds:rate:)` / `totalSeconds`, `displayString` with `;` for drop-frame) — pure value type | `OnlyCue/LTC/Timecode.swift` |
| LTC frame | `LTCFrame(timecode:)` — the 80-bit SMPTE 12M word in transmission order: frame/sec/min/hour BCD in the standard bit positions, drop-frame flag (bit 10), zero user-bit/colour/BGF bits, the bit-polarity-correction (parity) bit at bit 27 so the word has even parity, the `0011 1111 1111 1101` sync word at bits 64–79; plus decoded-field accessors (`hours`/`minutes`/`seconds`/`frames`/`isDropFrame`/`hasEvenParity`/`syncWordIsValid`). v1 parks the parity bit at bit 27 for *all* rates — the 25 fps standard puts it at bit 59 (follow-up). | `OnlyCue/LTC/LTCFrame.swift` |
| Biphase modulation | `LTCBiphaseEncoder.levels(for:samplesPerHalfBit:startLevel:)` — biphase-mark (FM): a transition at every bit boundary plus a mid-bit transition for each `1`; returns one signal level per audio sample + the trailing level so frames chain seamlessly. The integer `samplesPerHalfBit` is supplied by the caller. | `OnlyCue/LTC/LTCBiphaseEncoder.swift` |
| Sample synthesis | `LTCEncoder.samples(for timecode:sampleRate:amplitude:startLevel:)` → `([Float], endLevel: Bool)`, and `.makeBuffer(for:sampleRate:amplitude:)` → mono `AVAudioPCMBuffer`. The 80-bit frame is 160 half-bit slots; slot `k` spans samples `[round(k·R)…round((k+1)·R))` with `R = sampleRate / (160·fps)` — exact at any rate (integer at 48 kHz for 24/25/30; the rounding handles fractional cases like 44.1 kHz or 24 fps's 12.5-samples-per-half-bit). `endLevel` chains consecutive frames. | `OnlyCue/LTC/LTCEncoder.swift` |
| Timecode settings | `ProjectModel.timecodeSettings: ProjectTimecodeSettings` (framerate + `startOffsetFrames`; derived `startTimecode`, `timecode(atPlaybackSeconds:)`) — persisted (schema v7); edited via `TimecodeSettingsSheet` (`Tools → Timecode Settings…`, hosted by the `.timecodeSettingsSheet(document:)` modifier on `DocumentView`) through `CueCommands.setProjectTimecodeSettings`; `Timecode.parse(_:rate:)` parses the `HH:MM:SS:FF` field | `OnlyCue/Document/ProjectTimecodeSettings.swift`, `OnlyCue/UI/TimecodeSettingsSheet.swift`, `OnlyCue/Commands/CueCommands+Timecode.swift` |
| Routing settings | `LTCRoutingSettings` (selected device UID — `nil` follows the system default — + a `[ChannelRole]` per output channel: `silent` / `ltc` / `trackLeft` / `trackRight`; `assigning(_:toChannel:)` keeps unique roles unique, `resized(toChannelCount:)` / `withDefaultRoles(forChannelCount:)`, `isComplete` once an LTC channel is assigned). Persisted as JSON in `UserDefaults` (`ltcRouting.v1`) by `LTCRoutingStore` (`@MainActor ObservableObject`, mirrors `KeymapStore`) — a machine/session preference, *not* in the `.cuelist`. Available devices via `AudioOutputDeviceList.current()` / `.defaultOutput()` (Core Audio HAL → `AudioOutputDevice`: id/uid/name/output-channel count). | `OnlyCue/LTC/LTCRoutingSettings.swift`, `OnlyCue/LTC/LTCRoutingStore.swift`, `OnlyCue/LTC/AudioOutputDevice.swift` |
| Routing playback | *(leaf 3, not built)* the `AVAudioEngine` / `AVAudioSourceNode` path that renders the generated LTC onto the assigned channel of the chosen device, fed by `PlayerEngine.currentTime` | `OnlyCue/LTC/` |

**Drop-frame.** `Timecode` implements the standard counting rule for `fps30drop`: frame numbers `00` and `01` are skipped at the top of every minute except every tenth minute, so `frameCount` is the *actual* number of frames elapsed since `00:00:00:00` (what an LTC signal carries and what `PlayerEngine.currentTime` maps to), while the `HH:MM:SS:FF` components are labels. v1 treats `fps30drop` as a 30 fps timeline with drop-frame *labels* (`totalSeconds` divides by 30.0, not 29.97) — true 29.97 / 23.976 / 59.94 and pulldown are out of scope (the epic), as is LTC chase / slave-to-incoming (we generate, we don't slave). See ADR-019.

## Phase-2 seams

These are explicit extension points so future features don't require rewrites. See [`roadmap.md`](roadmap.md) for what plugs in here.

| Seam | Future use |
|---|---|
| `PlayerEngine.currentTime` publisher | LTC encoder subscribes and feeds Core Audio |
| `ProjectModel` is plain JSON | Templates are just `.cuelist` files with no media |
| `AppCommands` reads keymap | Realized (epic #40 complete) — see [Custom keyboard shortcuts](#custom-keyboard-shortcuts) |
| `ProjectModel.cues` is a flat array | Export to CSV / EDL / Timecode XML is a pure transform |
| `CueCommands` is the only mutator | AI-suggested cues call the same API to insert |
