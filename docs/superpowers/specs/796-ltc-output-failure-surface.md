# Spec — #796: surface LTC output failures in the UI

## Problem

`LTCAudioOutput.lastError` (`OnlyCue/LTC/LTCAudioOutput.swift:28`) is `@Published`
and its doc comment says it exists "for UI to surface", but no consumer reads it.
`LTCOutputHost` owns the live output as a `@StateObject` private to the modifier
(`OnlyCue/UI/LTCOutputHost.swift:30`) and never exposes it. The three showtime
failures — no LTC channel assigned, routed device unavailable, unsupported output
format — stop timecode silently: the transport keeps running and the desk simply
stops receiving LTC, with no operator-visible indication.

## Approach — mirror the #794 MTC pattern

#794 closed the identical gap for MIDI Timecode with a pure state machine plus a
pill by the playhead clock. `MTCStatusPill.swift:8-10` explicitly names this LTC
gap as filed-separately follow-up. Copy that structure.

### Goal / Input / Output

- **Goal:** an operator can see, at showtime, that LTC output has failed (or is
  armed / sending), without opening a settings pane.
- **Input:** the live `LTCAudioOutput` (`isRunning`, `lastError`) + the user's
  `LTCRoutingSettings` (`isEnabled`, `isComplete`).
- **Output:** an "LTC" pill beside the playhead clock whose colour + accessibility
  / help text report off / ready / sending / failed.

### State machine (pure, unit-tested first — TDD red)

`enum LTCStatusLabel`, mirroring `MTCStatusLabel`:

- `State { off, ready, sending, failed }` — `failed` outranks `sending`.
- `state(isComplete:isRunning:lastError:)` → `failed` if `lastError != nil`;
  else `off` if `!isComplete`; else `sending`/`ready` by `isRunning`.
- `statusText(state:timecode:lastError:)` — `failed` returns `lastError ?? "LTC
  output failed."`; `off` → "Not sending — enable LTC and assign an output
  channel."; `ready` → "Ready — sends on play."; `sending` → "Sending" (LTC has
  no published timecode; the playhead clock is adjacent).
- `pillText = "LTC"`, `isPillVisible(isEnabled:) = isEnabled`.

`isComplete` = `LTCRoutingSettings.isComplete` (`isEnabled && !ltcChannels.isEmpty`).
Pill visibility follows the master `isEnabled` switch, so an armed-but-idle rig is
visible and an unconfigured install carries no dead chrome.

### Wiring

- `Environment+LTCOutput.swift` — optional `\.ltcOutput` key, mirroring
  `Environment+MTCOutput.swift`.
- `LTCOutputHost` — add `.environment(\.ltcOutput, output)`.
- `LTCStatusPill` — reads `\.ltcOutput`, `accessibilityIdentifier("ltcPill")`.
- `PlayheadClockHeader` — place `LTCStatusPill` next to `MTCStatusPill` in an
  HStack at `.topLeading` (keeps the existing `mtcPill` UITest valid).

### Tests

- `LTCStatusLabelTests` — mirror `MTCStatusLabelTests` (state precedence + copy).
- `LTCStatusPillUITests` — hidden when disabled, visible with the existing
  `--ui-test-ltc-enabled` launch arg.
- Add `"LTCStatusPill.swift"` to `TokenConformanceTests.mainWindowFiles`
  exemptions: it uses the system red/white failure fill, exactly like the already
  exempted `MTCStatusPill.swift` (ADR-029 keeps the palette achromatic, so no
  `danger` token is added for one pill).

## Out of scope (deliberate)

- **No Settings ▸ Audio status row.** MTC's second surface exists because that
  pane owns its own `MTCOutput` for test sends; `AudioSettingsView` has no live
  `LTCAudioOutput`, so a settings row would require an LTC test-tone feature —
  separate work.
- **No new published timecode** on `LTCAudioOutput` just to print it in the pill.

## Docs / decisions

Implements the LTC output path of epic #33; respects ADR-029 (dark-only main
window, DS tokens). No schema change, no new entitlement.
