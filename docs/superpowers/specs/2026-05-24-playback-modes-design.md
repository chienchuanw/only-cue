# Playback Modes — Play Once / Loop Current Media / Auto Play Next Media

**Status:** approved (brainstorm 2026-05-24)
**Schema impact:** `ProjectModel` v14 → v15

## 1. Overview

Add three mutually-exclusive playback modes that govern end-of-media behavior, surfaced in the **Playback** menu and reflected in the TransportBar.

- **Play Once** — playhead parks at end of media; transport pauses. (Today's behavior.)
- **Loop Current Media** — seek to 0 and continue playing, indefinitely.
- **Auto Play Next Media** — advance `activeItemID` to the next item in `items[]` and resume playback. Stop at the end of the list.

The mode is a property of the show (`.cuelist`), persisted in `ProjectModel`. Default for new and migrated documents is **Play Once** to preserve observable behavior.

## 2. Decisions (from brainstorm)

| # | Branch | Decision |
|---|---|---|
| Q1 | Composability | Mutually exclusive radio group (exactly one mode active). |
| Q2 | Storage | Per-document, persisted in `ProjectModel`. |
| Q3 | Auto-Next at end of list | Stop. Do not wrap. |
| Q4 | LTC interlock | Mode always selectable; suppress *transition* at fire time when LTC is on. Behaves as Play Once + beep/flash interlock signal. Mode persists for when LTC is disabled. |
| Q5 | Playback rate across transitions | Preserve. Rate is a transport property, not a media property. |
| Q6 | Menu presentation | Three sibling items with leading checkmark on the active row, above `Pause at Each Cue`. |
| Q7 | Default mode | Play Once, for both new and migrated documents. |
| Q8 | Keyboard shortcuts | None. Mode is configuration, not transport. |
| Q9 | Auto-Next wiring | Dedicated `CueCommands.advanceToNextMediaAndPlay(undoManager:)`. Non-undoable. |
| Q10 | Visibility outside menu | TransportBar badge (SF Symbol) for Loop and Auto Next; nothing for Play Once. Informational, no click. |

## 3. Data model

`OnlyCue/Document/ProjectModel.swift`:

```swift
enum PlaybackMode: String, Codable {
    case playOnce
    case loop
    case autoNext
}

struct ProjectModel: Codable {
    static let currentSchemaVersion = 15

    var schemaVersion: Int = currentSchemaVersion
    var items: [MediaItem]
    var activeItemID: UUID?
    // …existing fields…
    var playbackMode: PlaybackMode = .playOnce
}
```

### Migration v14 → v15

New file `OnlyCue/Document/ProjectModel+MigrationV15.swift`, mirroring the V11 pattern at `OnlyCue/Document/ProjectModel+MigrationV11.swift`:

- Decode the v14 shape via a local `LegacyV14` struct.
- Construct a v15 `ProjectModel` with `playbackMode: .playOnce` and `schemaVersion: currentSchemaVersion`.

Extend the version switch at `OnlyCue/Document/ProjectModel+Migration.swift:12` with a `case 14:` arm that calls the V15 migration.

### Mutations through commands

Per the project hard rule "No direct mutations of `ProjectModel`" (CLAUDE.md), all mode changes go through `Commands/CueCommands.swift`:

- `setPlaybackMode(_ mode: PlaybackMode, undoManager: UndoManager?)` — undoable. Cmd-Z restores the previous mode; this does not change media state, only the rule.
- `advanceToNextMediaAndPlay(undoManager: UndoManager?)` — **non-undoable**. Computes the next index at fire time, mutates `activeItemID`, and after the existing `.task(id: activeItemID)` reload pipeline finishes, calls `engine.play()`. (Undoing mid-show would silently snap back to the previous song; manual sidebar selection is the right recovery path.)

## 4. End-of-media detection

`OnlyCue/Media/PlayerEngine.swift` gains a subscription to `AVPlayerItem.didPlayToEndTimeNotification` on the currently loaded item. The notification fires only on natural playback reaching end, not on programmatic `seek`.

Engine exposes a publisher (e.g., `let mediaDidReachEnd: AnyPublisher<Void, Never>`). `DocumentView` subscribes and dispatches on `document.model.playbackMode`:

```swift
switch document.model.playbackMode {
case .playOnce:
    break // AVPlayer already paused
case .loop:
    guard !ltcRoutingStore.settings.isEnabled else { fireLTCInterlock(); break }
    Task { await engine.seek(to: 0); engine.play() }
case .autoNext:
    guard !ltcRoutingStore.settings.isEnabled else { fireLTCInterlock(); break }
    commands.advanceToNextMediaAndPlay(undoManager: undoManager)
}
```

`fireLTCInterlock()` posts the same beep/flash notification used by the speed-item shortcuts (per `OnlyCue/App/AppCommands.swift:190`).

### Edge cases

- **Last item in list under Auto Next** → no next index; transport stays paused at end of last media.
- **Single-item list under Auto Next** → same as above on first end-of-media.
- **`activeItemID` is `nil`** → engine has nothing loaded; notification cannot fire.
- **Operator deletes/rearranges `items[]` mid-playback** → next index is computed at fire time, so the new ordering is honored.
- **Mode changed mid-playback near end-of-media** → the new mode applies to *this* end-of-media event (the dispatcher reads `playbackMode` at fire time).

## 5. LTC interlock

The three new menu items are **always enabled**, unlike the speed items at `OnlyCue/App/AppCommands.swift:198,205,212` which use `.disabled(ltcOn)`. Mode is a property of the show; LTC is a property of *this performance*. A designer who plans Loop for rehearsal should not lose the setting when going live.

The interlock fires at *transition time* inside the `mediaDidReachEnd` dispatcher (above): if LTC is on, suppress the loop/advance and fire the existing interlock notification. Mode is unchanged. The moment LTC is disabled, end-of-media events resume honoring the selected mode.

## 6. UI

### Menu — `OnlyCue/App/AppCommands.swift:186`

New block at the top of the Playback menu, above the existing Speed group and above the `Pause at Each Cue` toggle:

```
Playback
  Speed Up                ⌘…
  Slow Down               ⌘…
  Reset Speed             ⌘…
  ──────────
✓ Play Once
  Loop Current Media
  Auto Play Next Media
  ──────────
  Pause at Each Cue       ⌘…
```

Each mode item shows a leading `Image(systemName: "checkmark")` only when active, matching macOS HIG for radio-style menu modes (cf. Music.app's Repeat). Clicking an inactive item calls `commands.setPlaybackMode(_:undoManager:)`.

Accessibility identifiers:

- `playbackModePlayOnceMenuItem`
- `playbackModeLoopMenuItem`
- `playbackModeAutoNextMenuItem`

### TransportBar badge — `OnlyCue/UI/TransportBar.swift`

A single SF Symbol placed next to the rate badge area, visible only when mode is non-default:

| Mode | Symbol | Notes |
|---|---|---|
| `.playOnce` | (none) | Default — no badge keeps the bar clean. |
| `.loop` | `repeat` | |
| `.autoNext` | `forward.end` | |

Informational only — **no click handler** in v1. (Click-to-cycle would re-introduce the footgun considered and rejected in Q8.)

Accessibility identifier: `playbackModeBadge` with a value reflecting the current mode.

## 7. Test surface

Per the project TDD rule, failing tests come first.

### Unit — `OnlyCueTests/`

- Migration v14 → v15 round-trip: decode a v14 fixture (no `playbackMode`), assert `playbackMode == .playOnce` and `schemaVersion == 15`. Encode → decode → identity.
- `CueCommands.setPlaybackMode` updates the model and supports undo/redo.
- `CueCommands.advanceToNextMediaAndPlay`:
  - normal case (advances to next, calls `engine.play()` after reload)
  - last item (no-op, transport paused)
  - single item (no-op)
  - `activeItemID == nil` (no-op)
  - next-index captured at fire time (mutate `items[]` between mode-set and fire; assert correct destination)
- Dispatcher behavior under each mode, with LTC on and off (use the existing `LTCRoutingStore` fake).

### UI / BDD — `OnlyCueUITests/`

Gherkin-style scenarios mirrored in the test names:

- **Loop:** Given a doc with one media and `.loop`, When playback reaches end, Then the playhead returns to 0 and playback continues at the previously-set rate.
- **Auto Next:** Given a doc with two media in `.autoNext`, When the first media reaches end, Then `activeItemID` advances to the second and playback resumes.
- **Auto Next at end of list:** Given a doc with two media in `.autoNext` with the second active, When that media reaches end, Then transport stays paused and `activeItemID` is unchanged.
- **LTC interlock for Loop:** Given LTC enabled and `.loop`, When media reaches end, Then transport stays paused, the interlock notification is posted, and `playbackMode` is still `.loop`.
- **Menu checkmark:** Selecting each mode moves the leading checkmark to the chosen row.
- **TransportBar badge:** Badge is hidden in `.playOnce`, visible in `.loop` and `.autoNext` with the correct accessibility value.

## 8. Out of scope (explicit YAGNI)

- Keyboard shortcuts for mode switching.
- Click-to-cycle on the TransportBar badge.
- Wrap-the-whole-show under Auto Next (loop the entire `items[]`).
- Per-media mode override.
- Shuffle / random next media.
- Cue-driven mid-show mode switching via OSC.

## 9. Spec section ↔ docs reference

This spec implements end-of-media transport policy. The closest existing doc section is `docs/architecture.md` (transport pipeline) and `docs/data-model.md` (schema versioning). PRs that follow this spec must cite both in the OnlyCue verification footer.
