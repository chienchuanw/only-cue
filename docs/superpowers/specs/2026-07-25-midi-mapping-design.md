# MIDI mapping — control OnlyCue from a MIDI controller — design

**Date:** 2026-07-25
**Issue:** TBD
**Status:** Approved (grilling)

## Goal

Let a user drive OnlyCue from a MIDI control surface (first target: KORG
nanoKONTROL2), via **generic MIDI-learn** — bind any control to an OnlyCue
action by moving it. Input-only for v1. Mirrors the existing external-control
(`OSC`) and user-rebinding (`Keymap`) subsystems and adds no third-party
dependency.

## Decisions (locked with the user)

- **Generic MIDI-learn**, not a device-specific preset. Pick action → Learn →
  move control → bound. A bundled nanoKONTROL preset is an explicit later add.
- **Input-only.** No LED / motor-fader feedback in v1.
- **CoreMIDI directly** (no dependency), wrapped in a thin host over a **pure,
  unit-tested** parse→match→dispatch core — the shape of `OSCServerHost` +
  `OSCCommand.from`.
- **Discrete triggers** (Note-on, or CC crossing `<64 → ≥64`) bind to the whole
  `KeymapAction` registry, **extended with two new shared cases: Show `GO` and
  `Stop`** — so keyboard and MIDI share one vocabulary and one dispatcher.
- **Continuous** (CC value 0–127, **absolute**) binds to three targets:
  **scrub/seek playhead**, **playback rate**, **LTC output level**. (Not zoom.)
- **Map keyed by physical control** `(channel 1–16, kind Note/CC, number 0–127)`
  → one action. Re-learning a control reassigns it; two controls may share an
  action. (Control-as-key.)
- **Absolute snap** on faders — no soft-takeover in v1.
- **Global machine preference** in `UserDefaults` (`midiMap.v1`), mirroring
  `KeymapStore` / `LTCRoutingStore`. No `.cuelist` schema change.
- **One selected input device** by UID, hot-plug aware — mirrors LTC device
  selection.
- **Settings → MIDI** pane: device picker + binding table + per-row **Learn** +
  a **live MIDI monitor** (ch/kind/#/value), mirroring the OSC pane + monitor.

### Inferred defaults (confirmed — "LGTM")

1. Default map is **empty** — no bindings until the user learns them.
2. Discrete fires on the **press edge only** (Note vel>0; CC `<64→≥64`); release
   does nothing (no double-fire).
3. **Active in both Edit and Show modes**, applied to the key document window —
   same scope as keyboard shortcuts.
4. A rate-fader while LTC is enabled is still overridden by the existing
   LTC-on-resets-rate interlock — **documented, not special-cased**.
5. Rapid fader CC is **throttled/coalesced** to ~frame cadence so scrubbing
   doesn't overwhelm the seek path.

## Architecture

Mirror the OSC stack. New `OnlyCue/MIDI/` group; a `MIDIInputHost` (SwiftUI) as
the thin CoreMIDI edge; everything below it pure and testable.

```
CoreMIDI source (selected by UID)
   ↓  raw packets                         ← MIDIInputHost (thin, untested edge)
MIDIMessage.parse(bytes) -> MIDIMessage?  ← pure, tested (Note/CC only)
   ↓
MIDIBinding key = (channel, kind, number) ← identity
   ↓  MIDIMap.action(for:) / .continuousTarget(for:)
AppAction / ContinuousTarget              ← reuses shared dispatcher
   ↓
KeymapAction dispatch  |  seek / rate / LTC-level setters
```

### `MIDI/MIDIMessage.swift` (pure)

- `enum MIDIMessage { case note(channel:UInt8, number:UInt8, velocity:UInt8); case controlChange(channel:UInt8, number:UInt8, value:UInt8) }`
- `static func parse(_ bytes: [UInt8]) -> MIDIMessage?` — Note-on/off + CC only;
  everything else → `nil`.
- Helpers: `isPressEdge(previousValue:)` for CC `<64→≥64`; Note-on vel>0.

### `MIDI/MIDIBinding.swift` (pure, `Codable`)

- `struct MIDIControlID: Hashable, Codable { channel: UInt8; kind: Kind; number: UInt8 }`
  where `Kind: String, Codable { case note, cc }` — **stable JSON keys**.
- `enum MIDIAction: Codable` — either a discrete `KeymapAction` (incl. new `GO`,
  `stop`) or a `ContinuousTarget { case scrub, playbackRate, ltcLevel }`.

### `MIDI/MIDIMap.swift` (pure, `Codable`)

- `[MIDIControlID: MIDIAction]`. `action(for:)` lookup. `learn(control:action:)`
  reassigns (control-as-key). Corrupt/absent → empty map.

### `App/MIDIMapStore.swift`

- `@MainActor final class MIDIMapStore: ObservableObject` — `shared`, injected
  `UserDefaults` for tests, `midiMap.v1` key, `update` / `reload` /
  `resetToDefault`. **Direct copy of the `LTCRoutingStore` shape** (and its
  `#if DEBUG` UI-test-hermetic hook, per the #697 per-instance-suppression fix).

### `MIDI/MIDIInputHost.swift` (thin edge)

- CoreMIDI client + input port; connect to the source whose UID matches the
  stored selection; hot-plug via `MIDIObjectAddRemoveNotification`.
- Emits parsed `MIDIMessage` to: (a) the dispatcher, (b) the monitor buffer,
  (c) the active Learn session.
- Continuous coalescing: keep only the latest value per control per run-loop tick.

### Dispatch (document layer)

- Reuse the existing OSC/keyboard dispatch seam. Discrete → `KeymapAction`
  handler (extended with `GO` = existing Show-GO path in `DocumentView+ShowGo`,
  and `stop`). Continuous → seek (`locate`), rate setter (respecting the LTC
  interlock in `PlaybackRateShortcuts`), and `LTCRoutingStore` amplitude.

### `KeymapAction` extension

- Add `case go` and `case stop` (new **stable rawValues** — never rename).
  Display names added. Keyboard defaults may leave them unbound; MIDI and any
  future keyboard binding share them. Verify no keymap migration needed (new
  cases fall back to unbound, which `Keymap` already tolerates).

### UI — `Settings → MIDI`

- `MIDISettingsView` mirroring `KeyboardSettingsView` + `OSCSettingsView`:
  device picker (sources by UID), a table of `MIDIAction` rows each showing its
  bound control (or "—") + **Learn** button, and a Clear.
- Learn session: highlight row, next qualifying message binds; Esc cancels.
- `MIDIMonitorView` mirroring `OSCMonitorView` — recent messages ring buffer.

## Testing (TDD)

Pure, hardware-free (mirrors `OSCCommandTests`):

- `MIDIMessage.parse` — Note-on/off, CC, junk, running status edge, non-Note/CC → nil.
- CC press-edge detection (`<64→≥64` fires once; `≥64→≥64` does not).
- `MIDIMap` learn/reassign (control-as-key), two controls → one action, lookup.
- `MIDIMapStore` persist→reload round-trip (injected `UserDefaults`), corrupt →
  empty, per-instance UI-test suppression does not leak (guard the #697 class of
  bug from the start).
- Continuous scaling: 0–127 → seconds / rate range / 0–1 LTC level, endpoints.
- Codable stability: fixture JSON for `MIDIControlID` / `MIDIAction` keys.

Thin `MIDIInputHost` CoreMIDI glue is the only untested edge.

## Out of scope for v1

LED / fader feedback · bundled nanoKONTROL preset · named profiles ·
soft-takeover · per-document maps · Program Change / Pitch Bend · MIDI clock /
sync.

## Hard-rule / ADR checks

- No App Sandbox entitlement added (ADR-007) — CoreMIDI needs none outside the
  sandbox. ✓
- No `.cuelist` schema change (global pref, not document data). ✓
- macOS 14+ CoreMIDI APIs only (ADR-001). ✓
- `ProjectModel` mutations still route through `Commands/` where a MIDI action
  edits the document (e.g. add-cue). ✓
