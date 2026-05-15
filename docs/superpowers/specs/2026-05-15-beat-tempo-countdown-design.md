# Beat-tempo countdown — design

**Status:** approved
**Date:** 2026-05-15
**Touches:** `OnlyCue/UI/TransportBar.swift`, `OnlyCue/Utilities/Time+Format.swift` (or sibling file), `OnlyCueTests/`, `OnlyCueUITests/`

## Problem

The transport bar's `Next: 4.2` readout (in `TransportBar.swift:77-82`) shows time-to-next-cue as seconds. Lighting designers cueing to music think in **bars and beats**, not seconds — they want to anticipate the next cue musically. The data model already carries optional per-cue `bpm` / `beatsPerBar` (added in v9→v10), so a beat-based countdown is derivable without new persisted state.

## Behavior

The `Next: …` readout becomes click-to-cycle between two modes.

### Time mode (current default)

`Next: 4.2` — unchanged; uses `TimeFormat.compactCountdown`.

### Beat mode

Driven by the **active BPM**: the most recent cue at or before the playhead whose `bpm` is set. Two display zones:

- **>1 bar away:** `Next: ~3 bars` — `floor(beatsLeft / beatsPerBar)` rounded down to integer bars, with a leading `~` to signal it's coarse.
- **≤1 bar away:** `Next: 4 · 3 · 2 · 1` — a per-beat pulse. Each beat boundary the displayed integer ticks down. The current beat's number is rendered with slightly heavier weight / accented foreground so the readout reads as a visual pulse, not a static label.

### BPM-missing fallback

When no cue at or before the playhead has `bpm` set, beat mode silently renders the time-mode string with a trailing `ⓘ` glyph and a help tooltip:

> *"Set a tempo on a cue to enable beat countdown."*

The user's mode preference is **not** reset — it just degrades. As soon as the playhead crosses a tempo'd cue, the beat readout returns.

## State & persistence

```swift
enum CountdownMode: String { case time, beats }
@AppStorage("transport.countdownMode") private var mode: CountdownMode = .time
```

App-wide preference (not per-document). A per-document preference would require a `ProjectModel` schema bump, and a display toggle does not warrant that cost.

## Computation

Pure helpers, colocated with `TransportBar.nextCueInterval` (or extracted to a sibling file if `TransportBar.swift` grows):

```swift
/// Returns the bpm/beatsPerBar of the latest cue with `time ≤ currentTime`
/// AND a non-nil `bpm`. Nil when no such cue exists.
static func activeBPM(currentTime: TimeInterval, cues: [Cue])
    -> (bpm: Double, beatsPerBar: Int)?

enum BeatCountdown: Equatable {
    case bars(Int)              // >1 bar zone
    case pulse(remaining: Int)  // ≤1 bar zone, remaining ∈ 1...beatsPerBar
}

/// Computes the beat-mode display value from a time interval and tempo.
/// `beatsLeft = ceil(interval * bpm / 60)`.
/// If `beatsLeft > beatsPerBar` → `.bars(beatsLeft / beatsPerBar)`.
/// Else → `.pulse(remaining: max(1, beatsLeft))`.
static func beatCountdown(interval: TimeInterval,
                          bpm: Double,
                          beatsPerBar: Int) -> BeatCountdown
```

`activeBPM` does not consult `DerivedTempoGrid` — only authored cue tempo counts. This keeps the feature deterministic and avoids surprising behavior where the countdown switches to beats mid-section because the analyzer guessed.

## UI wiring

`TransportBar.swift` — replace the existing `Text("Next: ...")` block with a plain-styled button so the click target is the readout itself:

```swift
Button(action: cycleMode) {
    Text(countdownLabel)               // "Next: 4.2" or "Next: 4 · 3 · 2 · 1" or fallback
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
}
.buttonStyle(.plain)
.help("Click to switch between time and beat countdown.")
.accessibilityIdentifier("nextCueCountdown")     // unchanged for existing tests
```

The button gets a sibling identifier `nextCueCountdownToggle` for new UI tests that need to assert the toggle action distinct from the label.

Pulse-beat emphasis: render the active integer with `.fontWeight(.semibold)` and `.foregroundStyle(.primary)`; the trailing dots/numbers stay `.secondary`.

## Tests (TDD — failing first)

Unit (`OnlyCueTests/`):

- `activeBPM_returnsLatestCueAtOrBeforePlayhead_withBPM`
- `activeBPM_skipsCuesWithoutBPM` — picks the most recent *tempo'd* cue, not the most recent cue
- `activeBPM_returnsNil_whenNoPriorCueHasBPM`
- `beatCountdown_overOneBar_returnsBarsRoundedDown` — e.g. `interval=4.5s, bpm=120, bpb=4` → `.bars(2)` (9 beats → 2 full bars + 1)
- `beatCountdown_exactlyOneBar_returnsPulseFull` — boundary
- `beatCountdown_underOneBar_returnsPulseWithRemainingBeats`
- `beatCountdown_atZero_returnsPulseOne` — non-zero floor
- `countdownLabel_beatsMode_withNoActiveBPM_fallsBackToTimeFormatPlusHintGlyph`

UI (`OnlyCueUITests/`):

- Click `nextCueCountdownToggle` → readout text format flips from `Next: 4.2` style to `Next: 4 · 3 · 2 · 1` (or `~N bars`) style.
- Mode persists across relaunch (write the AppStorage key, relaunch app, assert beat-mode label).
- Beat mode with a tempo-less project shows the `ⓘ` glyph (assert label contains the glyph or its help text).

## Out of scope (explicit YAGNI)

- No project-default BPM setting.
- No bars+beats decomposition (e.g. `2 | 3`) — the >1-bar zone shows bars only.
- No audio click / metronome — visual pulse only.
- No per-document persistence of the mode.
- No use of `DerivedTempoGrid` (analyzer-guessed tempo) for the active BPM.
- No animation framework / Timeline-driven pulse — the readout already updates on `engine.currentTime` ticks; that drives the per-beat re-render naturally.

## Verification

- All unit tests above green.
- All listed UI tests green.
- Existing `NextCueCountdownTests` and any UI test asserting the `nextCueCountdown` identifier still pass (identifier preserved on the label, time-mode default unchanged).
