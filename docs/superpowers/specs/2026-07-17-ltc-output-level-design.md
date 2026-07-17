# LTC output level (gain) — design

**Date:** 2026-07-17
**Issue:** #651
**Status:** Approved (grilling)

Part 1 of 3 in the LTC-output improvements (② gain → ① strip → ③ multi-channel).

## Goal

Give the user an **independent LTC output level** control so the LTC signal can
be driven closer to full scale for reliable decoding (the user saw Doremidi
drop/jump frames when the level was low) — **without** touching the program
(track) audio level, unlike turning up the Mac's system volume.

## Decisions (locked with the user)

- **Independent digital amplitude, not system volume.** A single **LTC output
  level** slider controls the LTC signal's digital amplitude (0–100% → `0.0…1.0`).
  It only scales the LTC samples; program audio is untouched.
- **Known limit (documented, not a bug).** This makes LTC fuller-scale and
  independent of the *music* level, but it **cannot** escape the Mac's system
  output volume — the signal still passes through the output device. Full
  independence needs an audio interface + channel assignment (hardware). Called
  out in the settings footnote / PR.
- **Default raised.** New default `0.9` (was a hard-coded `0.8`), for more
  headroom-to-decode out of the box. Existing users with no stored amplitude
  decode to `0.9`.

## Architecture

Pure-core (settings value + clamp, unit-tested) threaded into the existing
`LTCAudioOutput` amplitude parameter (already plumbed through
`LTCSchedule`/`LTCFrameStream`).

### Settings model (`OnlyCue/LTC/LTCRoutingSettings.swift`)

- Add `var amplitude: Float` (0…1). Persisted in UserDefaults (not `.cuelist` —
  no `ProjectModel` schema change).
- `Codable`: `decodeIfPresent(.amplitude) ?? Self.defaultAmplitude`, then clamp;
  `encode` always writes it. Missing key (older stored settings) → default, so
  existing users don't break.
- `static let defaultAmplitude: Float = 0.9`.
- Value-returning transform `settingAmplitude(_:) -> Self` that clamps to
  `0...1` (matches the existing `assigning`/`settingEnabled` transform style;
  callers persist the result).
- The memberwise `init` gains `amplitude: Float = defaultAmplitude` (defaulted so
  existing call-sites and the `default` value keep compiling).

### Output threading (`OnlyCue/LTC/LTCAudioOutput.swift`)

- `start(at:routing:programRing:)` already receives `routing`. Store
  `routing.amplitude` and build both `LTCSchedule`s (the one in `start` and the
  re-cue one in `update(at:)`) with `amplitude:` from the stored value instead
  of the `LTCEncoder.defaultAmplitude` default.
- `LTCOutputHost.refresh(playing:)` is unchanged — it already passes `routing`.
- `LTCEncoder.defaultAmplitude` (0.8) stays as the pure-encoding default for
  callers that don't route (tests); the routing path now always supplies an
  explicit amplitude.

### Settings UI (`OnlyCue/UI/AudioSettingsView.swift`)

- Add an **"LTC output level"** row: a `Slider` (0…1) with a `%` readout,
  shown/enabled only when LTC is enabled. Binding writes
  `store.update(settings.settingAmplitude(newValue))`.
- Footnote: the level only affects LTC (not the music), and can't exceed the
  system output volume.

## Testing

- **Unit (`LTCRoutingSettingsTests`):**
  - `settingAmplitude` clamps below 0 → 0 and above 1 → 1; in-range passes through.
  - Codable round-trip preserves amplitude; a JSON payload without `amplitude`
    decodes to `defaultAmplitude` (existing-user compatibility); an out-of-range
    stored value clamps on decode.
- **Unit (amplitude threading):** given an amplitude, `LTCSchedule`/`LTCFrameStream`
  produce samples at that amplitude (extend `LTCScheduleTests`/`LTCEncoderTests`
  patterns — sample magnitude equals the amplitude).
- **Not unit-tested:** the `AVAudioEngine` output, the slider — verified by
  running the app + external decoder (Doremidi).

## Hard-rules check

No `ProjectModel` schema change (LTC settings live in UserDefaults; UserDefaults
compat handled via `decodeIfPresent`). No App Sandbox. No embedded media. macOS
14.0 floor untouched.

## Out of scope (later PRs)

① LTC strip moving playhead. ③ Multi-channel role assignment.
</content>
