# Transport Bar Declutter — Design

**Date:** 2026-05-14
**Status:** Approved (brainstorm)
**Scope:** `OnlyCue/UI/TransportBar.swift`, `OnlyCue/UI/DocumentView.swift`
**Related docs:** `docs/main-view.md` (if present), `docs/data-model.md` (LTC routing)

## Motivation

The bottom of the Main Pane has accumulated controls and readouts that duplicate keyboard shortcuts or repeat information. Specifically:

- The **Play/Pause** button duplicates the Space shortcut.
- The **Add Cue** button duplicates the `A` shortcut.
- Two clocks render side by side (`HMS current / total` and a frame-accurate `SMPTE` timecode), causing confusion about which is which.
- A `Last: …` elapsed-since-last-cue readout adds visual noise that does not drive operator decisions (the `Next:` countdown is the actionable one).
- The `Pause: each cue` indicator restates a state the operator just toggled via `⇧⌘P`; it costs horizontal space without adding actionable information.

The goal is a neater, keyboard-first transport bar that only carries information the operator cannot get from the playhead itself.

## Current state

`TransportBar` (rendered inside `DocumentView`) is an `HStack` containing, in order:

1. Play/Pause `Button` (calls `engine.toggle()`).
2. `Text(timeReadout)` — HMS, `current / total` (or just `current` when no media).
3. `Text(smpteReadout)` — SMPTE timecode, derived from striped LTC if present, otherwise from `ProjectTimecodeSettings` + the active item's `startTimecodeFrames`.
4. `Text("Last: …")` — conditional on a past cue existing.
5. `Text("Next: …")` — conditional on a future cue existing.
6. `Pause: each cue` indicator — conditional on the `pauseAtEachCue` `@AppStorage` flag.

Immediately below, `DocumentView` renders a standalone `Button("Add Cue")` with the `A` keyboard shortcut.

## Design

### Removals

1. **Play/Pause button** in `TransportBar`. Playback continues to be controlled by the Space shortcut. No replacement glyph is added — playhead motion is the play indicator. (`accessibilityIdentifier("playPauseButton")` is dropped; tests referring to it must be updated or removed.)
2. **`Add Cue` button** in `DocumentView` (the `Button("Add Cue") { addCueAtPlayhead() }` block). The `A` shortcut is preserved by wiring it into a hidden command — see [Preserving shortcuts](#preserving-shortcuts) below. (`accessibilityIdentifier("addCueButton")` is dropped.)
3. **`Last: …` readout** in `TransportBar` and the associated `lastCueElapsed` rendering. The static helper `TransportBar.lastCueElapsed(currentTime:cues:)` is also removed if no other call sites remain (grep before deletion).
4. **`Pause: each cue` indicator** in `TransportBar` (the conditional `HStack` keyed off the `pauseAtEachCue` `@AppStorage`). The `@AppStorage` property itself is removed from `TransportBar` (the toggle elsewhere — the `⇧⌘P` shortcut and any menu — continues to read/write the same key, so behavior is unchanged). `accessibilityIdentifier("pauseAtEachCueIndicator")` is dropped.

### Time readout — SMPTE gating and labeling

The HMS readout (`timeReadout`) remains as the always-on primary playhead clock.

The SMPTE readout becomes conditional and labeled:

- **Visibility:** rendered only when `LTCRoutingStore.shared.settings.isEnabled == true`. When LTC output is disabled, the SMPTE readout is hidden entirely. This matches the existing gate that already controls the per-media `LTCStrip` visibility in `DocumentView.ltcStripIfEnabled`.
- **Label:** prefixed with the literal string `SMPTE ` so the two clocks are distinguishable when both are visible. Example: `SMPTE 00:00:03:07`.
- **Source of truth:** unchanged — striped LTC if present, else `ProjectTimecodeSettings` + `activeItem.startTimecodeFrames`. The existing `.help(smpteReadoutHelp)` tooltip is preserved.

#### Accepted trade-off

A clip configured with a custom `startTimecodeFrames` will *not* surface that SMPTE value in the transport bar when LTC output is disabled. This is an accepted simplification: per-media start TC remains editable in the sidebar and visible on the `LTCStrip` (also gated on the same flag). If this proves confusing in practice, the gate can be widened later to `isEnabled || activeItem.hasCustomStartTC` without a schema change.

### Final visible composition

`HStack(spacing: 12)`:

1. `Text(timeReadout)` — `00:00:03.250 / 00:01:23.456`
2. `Text("SMPTE " + smpteReadout)` — *only when `LTCRoutingStore.shared.settings.isEnabled`*
3. `Text("Next: …")` — *conditional, unchanged*

When no media is loaded: only the bare `current` HMS shows (existing fallback path in `timeReadout`).

### Preserving shortcuts

The `A` shortcut for "Add Cue at playhead" must remain wired even after the visible button is removed. Two acceptable approaches; implementation plan picks one:

- **(a)** Move the existing `Button("Add Cue") …` into a `.hidden()`-modified zero-frame view kept in the view tree so SwiftUI still registers its `.keyboardShortcut`. Drawback: relies on hidden-button semantics that future SwiftUI versions could change.
- **(b)** Add an entry to the existing `transportShortcuts` / command-driven shortcut block in `DocumentView` (alongside the digit and step shortcuts already routed there). Preferred — this is the same pattern used by sibling shortcuts and keeps the view tree clean.

The Space shortcut for Play/Pause is already declared on the engine-level command, not on the button — removing the button is sufficient. (Implementation plan must verify this by grepping `Keymap.swift` and `transportShortcuts` for the `togglePlayPause` action.)

### Accessibility

- The view loses two `accessibilityIdentifier`s (`playPauseButton`, `addCueButton`). Any UI test referencing them must be updated.
- A non-interactive Play/Pause status glyph is intentionally **not** added; the user confirmed playhead motion is sufficient signal in this keyboard-driven workflow.
- The `SMPTE` label improves screen-reader output (no longer two adjacent unlabeled timecode strings).

## Out of scope

- No change to `ProjectModel`, `Cue`, `MediaItem`, or any schema. No migration.
- No change to `LTCStrip`, the per-media LTC editor, or the LTC routing store. Only the read side (TransportBar) consumes `settings.isEnabled` as a new gate.
- No change to `Next:` formatting.
- No change to the `pauseAtEachCue` `@AppStorage` semantics or the `⇧⌘P` toggle — only the visual indicator inside `TransportBar` is removed.
- No change to `TimeFormat` helpers.
- The `lastCueElapsed` static helper is removed only if it has no remaining call sites; do not refactor unrelated callers.

## Verification

- **Unit:** update `TransportBarTests` (if present) to:
  - assert the Play/Pause button is gone
  - assert the SMPTE readout is hidden when `LTCRoutingStore.shared.settings.isEnabled == false`
  - assert the SMPTE readout, when shown, is prefixed with `SMPTE `
  - assert `Last:` is never rendered
  - assert the `Pause: each cue` indicator is never rendered (regardless of `pauseAtEachCue` flag value)
- **Snapshot:** regenerate the cue-inspector / tempo-group baselines from c58441b if they include the transport bar; otherwise add a new TransportBar snapshot covering the two states (LTC on / LTC off).
- **UI test:** remove references to `playPauseButton` and `addCueButton` identifiers; ensure existing `A` and `Space` shortcut tests still pass.
- **Manual:** with LTC routing disabled in Settings, confirm only the HMS clock is visible at the bottom. Enable LTC routing, confirm `SMPTE …` appears alongside HMS. Press Space to toggle playback, press `A` to add a cue, both still work.

## Open questions

None — design approved during brainstorm on 2026-05-14.
