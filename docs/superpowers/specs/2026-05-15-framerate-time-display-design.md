# Framerate-Based Time Display — Design

**Date:** 2026-05-15
**Status:** Approved (brainstorm)
**Spec section:** Presentation layer; consumes `docs/data-model.md` `ProjectTimecodeSettings.framerate`.

## Problem

All time readouts in OnlyCue render as `HH:MM:SS.mmm` regardless of the project's configured framerate. Lighting designers think in SMPTE frames, not milliseconds. When a project's framerate is set (24 / 25 / 30 / 30 drop-frame), every time display in the UI — the Inspector clock, transport readout, cue row times, media duration, playhead overlay, timeline tooltips, and countdowns — should render as `HH:MM:SS:FF` (`;FF` for drop-frame) at the project framerate, with frames as the smallest unit instead of milliseconds.

## Decisions

1. **Scope:** all time displays switch. Inspector clock, transport readout, cue rows, media duration, playhead overlay, timeline tooltips, beat countdown, transport countdown.
2. **Origin:** project-relative. `00:00:00:00` corresponds to playback start. Per-media `startTimecodeFrames` is *not* used in the general clocks — that remains the concern of the existing SMPTE field in `TransportBar` (line 133), which is unchanged.
3. **Opt-out:** none. `ProjectTimecodeSettings.framerate` always has a value (default 30 fps), so there is no "framerate-less" state. A `.mmm` toggle is YAGNI; if demand surfaces later, adding it is a small follow-up.
4. **Countdowns:** also frame-formatted. The deliberate decisecond precision of the current `compactCountdown` is dropped in favor of consistency with the rest of the UI.

## Non-goals

- No display-preference toggle (`.mmm` vs `:FF`).
- No media-relative re-anchoring of the general clocks.
- No `.cuelist` schema changes — display format is presentation-only.
- No changes to `Timecode`, `ProjectTimecodeSettings`, or the LTC pipeline.

## Architecture

```
ProjectModel.timecodeSettings.framerate
        │
        ▼ (read at DocumentView body)
.environment(\.projectFramerate, …)
        │
        ▼
@Environment(\.projectFramerate) in each leaf view
        │
        ▼
TimeFormat.smpte(seconds, rate:) → Timecode(totalSeconds:rate:).displayString
        │
        ▼
SwiftUI Text("HH:MM:SS:FF")
```

Reactivity is automatic: `ProjectModel.timecodeSettings` is Observation-tracked, so flipping the framerate in **Tools → Timecode Settings…** rebuilds `DocumentView`'s body, re-seeds the environment value, and invalidates every reader.

## Components

### New: `TimeFormat.smpte` and `TimeFormat.smpteCountdown`

In `OnlyCue/Utilities/Time+Format.swift`:

- `static func smpte(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String`
  Wraps `Timecode(totalSeconds: max(0, seconds), rate: rate).displayString`. Output: `HH:MM:SS:FF` (`HH:MM:SS;FF` for `.fps30drop`).
- `static func smpteCountdown(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String`
  Compact countdown. Sub-minute: `SS:FF`. Sub-hour: `M:SS:FF`. Hour-plus: `H:MM:SS:FF`. Drop-frame uses `;` between SS and FF. Negative clamps to zero.

The existing `TimeFormat.hms(_:)` and `TimeFormat.compactCountdown(_:)` functions are **deleted**.

### New: `EnvironmentValues.projectFramerate`

New file `OnlyCue/UI/Environment+Framerate.swift`:

```swift
private struct ProjectFramerateKey: EnvironmentKey {
    static let defaultValue: SMPTEFramerate = .fps30
}

extension EnvironmentValues {
    var projectFramerate: SMPTEFramerate {
        get { self[ProjectFramerateKey.self] }
        set { self[ProjectFramerateKey.self] = newValue }
    }
}
```

`DocumentView.body` seeds it once: `.environment(\.projectFramerate, document.model.timecodeSettings.framerate)`.

### Touched views (mechanical)

- `InspectorClockHeader` — reads `@Environment(\.projectFramerate)`, calls `TimeFormat.smpte`.
- `ItemRowView`, `CueRowView`, `PlayheadOverlay`, `TimelineBreakdownView` — same pattern.
- `TransportBar` — current/duration readout (lines 34–36) switches from `hms` to `smpte` (using the `timecodeSettings.framerate` it already receives). Countdown body (line 102) switches to `smpteCountdown`. The per-media SMPTE field at line 133 is unchanged.
- Beat-countdown view — switches its `compactCountdown` call to `smpteCountdown`. It reads the rate from `@Environment(\.projectFramerate)` (new dependency for this view; previously the countdown was framerate-agnostic).

## Data flow

One direction only. No view writes back. The framerate setting itself is mutated only via `TimecodeSettingsSheet` → command layer (existing path; out of this spec's scope).

## Edge cases

- **Negative time:** `Timecode(totalSeconds:rate:)` clamps to zero; `smpte` inherits. `smpteCountdown` clamps explicitly.
- **Sub-frame precision:** `Timecode(totalSeconds:)` rounds half-away-from-zero to the nearest frame. Matches LTC math.
- **Drop-frame minute boundary:** `Timecode`'s existing rule handles the `;00`/`;01` skip.
- **Duration > 24h:** `Timecode` wraps modulo one day. Same as the LTC path. No UI guard needed.
- **Missing environment value** (previews, isolated tests): default `.fps30`. Tests that depend on the rate inject explicitly.
- **Very short countdown intervals:** 1.5 s at 30 fps becomes `01:15`. Glanceability comparable to today's `1.5`.

## Testing

### Unit (`OnlyCueTests/TimeFormatTests.swift`, extended)

- `smpte(0, rate: .fps30)` == `"00:00:00:00"`.
- `smpte(1.0/30.0, rate: .fps30)` == `"00:00:00:01"`.
- `smpte(3661.5, rate: .fps24)` == `"01:01:01:12"`.
- `smpte(-5, rate: .fps30)` == `"00:00:00:00"`.
- `smpte(_, rate: .fps30drop)` uses `;` between SS and FF.
- `smpte` agrees with `Timecode(totalSeconds:rate:).displayString` over representative samples (the wrapper invariant).
- `smpteCountdown` compact forms: sub-minute, sub-hour, hour-plus.
- `smpteCountdown(0, rate:)` clamps and renders the minimal form.

### UI (extending existing UI test suites)

- `InspectorClockHeaderUITests` — assert clock matches `^\d{2}:\d{2}:\d{2}[:;]\d{2}$` under each framerate seeded via `UITestSeedHandler`.
- `CueListPaneUITests` — assert a cue row's time cell uses `:FF`.
- Regression test: flipping framerate in `TimecodeSettingsSheet` updates the Inspector clock format live.

### Removed assertions

Any existing test that pins a `HH:MM:SS.mmm` literal is converted to its `:FF` equivalent. The decisecond countdown assertions (`5.2`, `1:23.5`) are replaced with the `SS:FF` / `M:SS:FF` shapes.

## OnlyCue verification

- **Spec link:** this document.
- **Schema:** unchanged — presentation-only.
- **ADRs:** none affected.
- **Tests:** unit and UI as above; lint must stay green.
