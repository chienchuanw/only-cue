# Playback speed control — design

**Status:** Approved (brainstorm 2026-05-15)
**Scope:** OnlyCue media playback only. No data-model changes.
**Related code:** `OnlyCue/Media/PlayerEngine.swift`, `OnlyCue/App/KeymapAction.swift`, `OnlyCue/App/KeymapStore.swift`, `OnlyCue/App/AppCommands.swift`, transport bar UI.

## 1. Goal

Let the user rehearse against a media file at variable playback speed — fast-skim long tracks, slow-mo through tricky sections while placing cues — via keyboard shortcuts and a new `Playback` menu, in the spirit of PotPlayer's speed control.

## 2. Non-goals

- **No timeline mutation.** Waveform, cue positions, tempo grid, beat countdown, and LTC frame timestamps are anchored to real media time. They do not scale with playback rate.
- **No persistence.** Rate is transient view-state. It is not written to `.cuelist`, so no schema bump, no migration.
- **No undo/redo integration.** Rate is not routed through `Commands/CueCommands.swift`; that seam is for `ProjectModel` mutations.
- **No varispeed / pitch-shifting.** Audio pitch is preserved at all rates.
- **No preset speed menu.** Stepping is uniform 0.1× increments; users hit shortcuts (or the menu items) repeatedly to reach a target.

## 3. Behavior

### 3.1 Range and stepping

- Allowed rates: **0.1× to 3.0×**, inclusive.
- Step: **0.1×**, linear.
- Default: **1.0×**.
- Internally stored as `Float` (matches `AVPlayer.rate`). Values are clamped to `[0.1, 3.0]` and snapped to the nearest 0.1 on every entry point.

### 3.2 Audio behavior

- `AVPlayerItem.audioTimePitchAlgorithm = .spectral` on item creation. Pitch is preserved at all rates; audio is time-stretched.
- Applies to all media types currently routed through `PlayerEngine`.

### 3.3 Rate change while playing vs. paused

- **While playing:** `player.rate` is updated live; audio continues without a pause.
- **While paused:** the new rate is stored; the next `play()` call uses it.

### 3.4 Reset triggers

Rate auto-resets to 1.0× on:

1. **App relaunch** — automatic, since rate is not persisted.
2. **Opening a different `.cuelist` project** — `PlayerEngine` is rebuilt, which yields the default.
3. **Enabling LTC output** while rate ≠ 1.0× — see §3.5.

Rate is **sticky** across:

- Stop / Play cycles (including playhead returning to 0).
- Switching the selected media within the same project.
- Seeking.

### 3.5 LTC interlock

LTC output and rate ≠ 1.0× are mutually exclusive: LTC frames are wall-clock timestamps going to physical hardware, so silent drift would be a footgun.

1. **Rate change attempt while LTC is active:**
   - If target rate == 1.0× → allowed (already-permitted state).
   - If target rate ≠ 1.0× → rejected (no-op). Emit a transient HUD: *"Disable LTC to change playback rate."*
2. **Enabling LTC while rate ≠ 1.0×:**
   - Rate is reset to 1.0× first, then LTC is enabled. Emit a transient HUD: *"Playback rate reset to 1.0× for LTC."*

The same interlock disables (grays out) the `Playback` menu's `Speed Up` / `Slow Down` / `Reset Speed` items while LTC is active and rate is 1.0×. (Rate is already at 1.0×, so the items have nothing to do; greying them is more honest than letting them click and emit a HUD.)

## 4. Architecture

### 4.1 `PlayerEngine` (single owner of rate state)

New public surface:

```swift
extension PlayerEngine {
    /// Current user-facing playback rate. Range [0.1, 3.0], snapped to 0.1.
    private(set) var playbackRate: Float = 1.0

    /// Set the playback rate. Clamps to [0.1, 3.0] and snaps to 0.1.
    /// No-op (with HUD signal) if LTC is active and `rate != 1.0`.
    func setPlaybackRate(_ rate: Float)

    /// Increment / decrement by 0.1, clamped.
    func nudgePlaybackRate(by delta: Float)

    /// Convenience: setPlaybackRate(1.0).
    func resetPlaybackRate()
}
```

Internal changes:

- `play()` sets `player.rate = playbackRate` (was `1.0`).
- The existing `player.rate` KVO path remains the source of truth for the public `rate` property (which reflects *actual* AVPlayer state, including 0 when paused). `playbackRate` is the *intended* user-facing rate when playing.
- On `setPlaybackRate(_:)` while playing, the engine updates `player.rate` immediately.

### 4.2 Keymap actions

Three new cases in `KeymapAction`:

```swift
case playbackRateUp        // default: ]
case playbackRateDown      // default: [
case playbackRateReset     // default: \
```

Registered in the same dispatcher as existing actions. Each invokes the corresponding `PlayerEngine` method. Defaults live in `KeymapStore`'s default-keymap factory; users can rebind via the existing keymap preferences.

These shortcuts were verified to be unused by other `KeymapAction` cases as of 2026-05-15.

### 4.3 `Playback` menu

A new top-level menu added in `AppCommands.swift`. Placement: between `View` and `Window`, or matching the existing convention in the file — to be confirmed during implementation. Items:

```
Playback
├── Play / Pause                    (existing action, second entry point)
├── ─────────────────────────────
├── Speed Up                        ⌨ playbackRateUp
├── Slow Down                       ⌨ playbackRateDown
└── Reset Speed                     ⌨ playbackRateReset
```

- The three speed items use the `KeymapStore`→`KeyboardShortcut` bridge so rebinds in keymap preferences are reflected automatically.
- LTC interlock disables the speed items per §3.5.
- `Play / Pause` is added here as a second entry point; the implementation must verify it does not conflict with any existing menu entry for the same action. If there is a conflict, drop it from this menu and keep the speed items only.

### 4.4 Transport bar rate badge

Small text badge in the transport bar, to the right of the play/pause cluster.

- **Hidden** when `playbackRate == 1.0` outside the flash window (no clutter in the common case).
- **Visible** otherwise, formatted e.g. `1.5×`, `0.3×` (one decimal).
- **Flash on change:** any rate change (including back to 1.0×) makes the badge visible for ~1.2s, then it fades if the new rate is 1.0×. Provides feedback that the keypress took effect.
- **Clickable:** opens a tiny popover containing a slider (0.1×–3.0×, 0.1 step) and a Reset button. Calls `setPlaybackRate(_:)`. LTC interlock applies; slider is disabled when LTC is active.

## 5. Out-of-scope confirmations

- `.cuelist` schema is unchanged. No migration.
- `Commands/CueCommands.swift` is not touched. No new command.
- Tempo grid, derived tempo, LTC encoder, OSC output, and waveform are not touched. They continue to read real media time.

## 6. Testing

### 6.1 Unit (`OnlyCueTests`)

- `setPlaybackRate(_:)` clamps to `[0.1, 3.0]` and snaps to the nearest 0.1 (test boundary inputs: -1, 0, 0.05, 0.14, 1.0, 3.05, 5).
- `nudgePlaybackRate(by: +0.1)` from 1.0 climbs to 3.0 in 20 steps and then stays at 3.0 (no overshoot).
- `nudgePlaybackRate(by: -0.1)` from 1.0 descends to 0.1 in 9 steps and then stays at 0.1.
- `resetPlaybackRate()` returns to 1.0 from any starting value.
- `play()` after `setPlaybackRate(0.5)` results in `player.rate == 0.5` (within float tolerance).
- Rate change while playing updates `player.rate` live.
- Rate change with LTC active and target ≠ 1.0× is rejected: `playbackRate` is unchanged and an `ltcConflict` signal is emitted (observable via the HUD message channel or an injected callback — to be designed in the plan).
- Enabling LTC while rate ≠ 1.0× resets `playbackRate` to 1.0 *before* LTC is enabled, and emits the corresponding signal.

### 6.2 UI smoke (`OnlyCueUITests`)

- Press `]` three times → badge reads `1.3×`. Press `\` → badge shows `1.0×` briefly then disappears.
- Open `Playback` menu → `Speed Up`, `Slow Down`, `Reset Speed` are present with the configured shortcuts displayed.
- Click the rate badge → popover appears, slider reflects current rate, Reset button returns to 1.0×.
- With LTC active, the three menu items are disabled.

## 7. Open questions for the implementation plan

- Exact placement of the `Playback` menu relative to existing menus in `AppCommands.swift`.
- Whether `Play / Pause` belongs in the `Playback` menu given the existing menu layout (see §4.3).
- HUD message channel: confirm the existing transient-HUD mechanism used by similar features (e.g., LTC errors elsewhere in the app) and reuse it.
- Whether the rate badge fade-out animation matches existing transport-bar fade conventions.
