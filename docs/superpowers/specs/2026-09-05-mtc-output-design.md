# MIDI Timecode (MTC) output — design

**Date:** 2026-09-05
**Issue:** (epic TBD)
**Status:** Approved (grilling)

## Goal

OnlyCue emits **MIDI Timecode** to a CoreMIDI destination while the transport
runs, alongside — and fully independent of — the existing LTC audio output. The
immediate driver is feeding a **DoReMIDI** USB-MIDI box, but nothing in the
design is vendor-specific: DoReMIDI is simply one entry in a destination picker,
exactly as a MOTU interface, the IAC bus or a network MIDI session would be.

This **reverses in part ADR-019**, which recorded that "MIDI Timecode is
delegated to an external app (as CuePoints does with Lockstep)". A new
**ADR-032** supersedes that clause; the rest of ADR-019 (the pure timecode model,
the supported framerate set, the `fps30drop`-as-30-fps simplification) stands and
is in fact load-bearing for this feature.

## Decisions (locked with the user)

| Branch | Decision |
| --- | --- |
| Transport | Generic CoreMIDI destination. No virtual source in v1. |
| `fps30drop` | MTC rate bits `10` (29.97 DF), clocked at **30 fps physical** — the same simplification LTC already ships. |
| Clock | Free-run from a `mach_absolute_time` anchor; a ~100 ms timer batches quarter-frames with exact **future** `MIDITimeStamp`s. |
| Locate | Full Frame SysEx on play-start, on any seek while playing, **and on seeks while paused** (throttled). Quarter-frames only while playing. |
| Settings | New `MTCOutputSettings` + `MTCOutputStore` (`UserDefaults`, key `mtcOutput.v1`), in the **MIDI** pane. Master switch independent of LTC. |
| Feedback | Status row in Settings + an `[MTC]` pill beside the playhead clock (lit / red). |
| Scope | Single destination; a **Send test timecode** button; no per-clip mute; no MMC / MIDI Clock. |
| Multi-window | Per-document host mirroring `LTCOutputHost`. Concurrent-window conflict documented, not solved. |
| Rate interlock | `PlaybackRateController`'s `ltcEnabled` gate becomes `ltcEnabled \|\| mtcEnabled`. |

### The `fps30drop` mapping, and why

MTC's rate field is **two bits**, encoding exactly `24 / 25 / 29.97-drop / 30`.
There is no 30-fps-drop-frame code. OnlyCue's `fps30drop` is deliberately a
**30 fps timeline wearing drop-frame labels** (ADR-019), and `LTCEncoder` already
emits it at 30 fps physical with the drop-frame bit set.

MTC therefore inherits exactly the same simplification:

| `SMPTEFramerate` | MTC rate bits | Physical rate |
| --- | --- | --- |
| `.fps24` | `00` | 24 fps |
| `.fps25` | `01` | 25 fps |
| `.fps30drop` | `10` (29.97 DF) | **30 fps** |
| `.fps30` | `11` (30 ND) | 30 fps |

The governing invariant: **whatever the LTC output says at a given instant, the
MTC output says too.** Both free-run from the same `Timecode`, so they cannot
disagree. Honesty about 29.97 is deferred to a future true-fractional-framerate
epic, unchanged from ADR-019.

## Architecture

Three pure, unit-tested types plus one hardware edge plus one host modifier —
the same split the MIDI input and OSC subsystems already use (`MIDIMessage` /
`MIDISignal` pure, `MIDIInput` the untested edge).

```
ProjectTimecodeSettings.timecode(atPlaybackSeconds:forItem:)
            │  (identical source to LTC — invariant holds)
            ▼
      MTCFrame            pure — quarter-frame bytes, Full Frame SysEx, rate bits
            ▼
      MTCSchedule         pure — anchor + window → [(byte, MIDITimeStamp)]
            ▼
      MTCOutput           hardware edge — CoreMIDI client, output port, send
            ▲
      MTCOutputHost       SwiftUI modifier — transport wiring (mirrors LTCOutputHost)
            ▲
      MTCOutputStore      UserDefaults — MTCOutputSettings
```

### `OnlyCue/MIDI/MTCFrame.swift` — pure

Wire-format encoding. No CoreMIDI import; `[UInt8]` in, `[UInt8]` out.

- `static func rateBits(for rate: SMPTEFramerate) -> UInt8` — the table above.
- `static func quarterFrameByte(piece: Int, timecode: Timecode) -> UInt8`
  Data byte is `0nnn dddd` where `nnn` is the piece index 0–7:

  | Piece | Payload | Piece | Payload |
  | --- | --- | --- | --- |
  | 0 | frame LSN | 1 | frame MSN |
  | 2 | second LSN | 3 | second MSN |
  | 4 | minute LSN | 5 | minute MSN |
  | 6 | hour LSN | 7 | `(rateBits << 1) \| (hours >> 4)` |

  Emitted on the wire as the two bytes `F1 <data>`.
- `static func fullFrameBytes(_ timecode: Timecode) -> [UInt8]`
  `F0 7F 7F 01 01 hh mm ss ff F7`, where `hh = (rateBits << 5) | hours`.

**Golden vectors.** `TimecodeGoldenVectorTests` is the existing precedent; MTC
gets its own set covering each framerate, hour rollover, the drop-frame label
rule, and `23:59:59:29`.

#### The 2-frame latency convention — resolved at leaf 2, on hardware

Eight quarter-frames span two frames, so a receiver assembles a complete value
two frames after the sequence begins. Masters differ on whether to pre-compensate
(transmit `N+2`) or transmit `N` and let the receiver apply the offset.

v1 transmits **uncompensated `N`** — the common reading of the spec, and what
most software masters do. This is explicitly **verified against the DoReMIDI box
at leaf 2** by reading LTC and MTC side by side; if the box reads two frames
early, the compensation is a one-line change in `MTCSchedule` and a golden-vector
update, not a redesign. This is the single most likely source of an "MTC is two
frames off LTC" report, so it is the primary hardware acceptance check.

### `OnlyCue/MIDI/MTCSchedule.swift` — pure

The MTC analogue of `LTCSchedule`: all the timing arithmetic, no I/O.

```swift
struct MTCSchedule {
    let startTimecode: Timecode
    let anchorHostTime: UInt64        // mach_absolute_time at startTimecode
    let ticksPerSecond: Double        // from mach_timebase_info, injected for tests

    /// Quarter-frames whose scheduled host time falls in [from, until).
    func batch(from: UInt64, until: UInt64) -> [(byte: UInt8, timestamp: UInt64)]
}
```

- Quarter-frame period is `1 / (4 × rate.framesPerSecond)` seconds — 8.33 ms at
  30 fps, 10 ms at 25 fps.
- Piece index `i` of quarter-frame sequence number `q` carries the timecode of
  frame `startFrame + (q / 8) * 2` — the value advances every **two** frames.
- The whole type is deterministic and injectable: tests pass a fixed
  `anchorHostTime` and `ticksPerSecond` and assert exact byte/timestamp pairs.
  No sleeping, no real clock.

### `OnlyCue/MIDI/MTCOutput.swift` — the hardware edge

Mirrors `MIDIInput` in shape, ownership and documentation tone. Send-only.

- Owns one `MIDIClientRef` + one `MIDIPortRef` (output port), created lazily and
  retryably by an `ensureClientAndPort()` twin, disposed in a `nonisolated deinit`.
  Its own client — not shared with `MIDIInput`, which is receive-only and whose
  client is private to it.
- `start(destinationUID:at:rate:)` resolves the destination by
  `kMIDIPropertyUniqueID` (same lookup shape as `MIDIInput.source(withUID:)`, over
  `MIDIGetNumberOfDestinations` / `MIDIGetDestination`), anchors an `MTCSchedule`,
  sends a Full Frame, and starts the refill timer.
- Refill timer: a `DispatchSourceTimer` on a dedicated queue at ~50 ms, scheduling
  the next ~200 ms window of quarter-frames via `MIDISendEventList` with future
  timestamps. Look-ahead exceeds the timer period, so one missed wake-up cannot
  gap the stream — the same reasoning as `LTCAudioOutput.primeCount`.
- `update(at:)` re-anchors on seek: send Full Frame, reset the schedule.
- `sendFullFrame(_:)` for the paused-seek and test-button paths, throttled to
  ~10/s by the caller.
- `stop()` cancels the timer and clears state. It does **not** dispose the client,
  so re-arming is cheap; `deinit` disposes.
- Hot-plug: `MIDIClientCreateWithBlock`'s notify block re-resolves the chosen UID,
  matching `MIDIInput.handleHotPlug`.
- `@Published` / observable: `isRunning`, `currentTimecode`, `lastError`.

**Not headless-testable** — the CoreMIDI wiring needs real hardware, exactly as
`LTCAudioOutput` and `MIDIInput` are. The pure parts above carry the test weight.

> **Assumption to verify at leaf 2:** that `MIDISendEventList` honours future
> timestamps on the DoReMIDI driver rather than sending immediately. If it does
> not, the fallback is a shorter timer with smaller batches — a change confined to
> `MTCOutput`, since `MTCSchedule` already yields per-message timestamps.

### `OnlyCue/MIDI/MTCOutputSettings.swift` + `MTCOutputStore.swift`

Mirrors `LTCRoutingSettings` / `LTCRoutingStore` exactly, including the
`decodeIfPresent` tolerance and the `#if DEBUG` UI-test ephemeral hook.

```swift
struct MTCOutputSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool          // defaults false — fresh install emits nothing
    var destinationUID: String?  // nil ⇒ not configured
    var isComplete: Bool { isEnabled && destinationUID != nil }
    static let `default` = Self(isEnabled: false, destinationUID: nil)
}
```

`MTCOutputStore.shared`, `UserDefaults` key `mtcOutput.v1`, corrupt/absent →
`.default`.

### `OnlyCue/UI/MTCOutputHost.swift`

A `ViewModifier` attached as `.mtcOutput(engine:document:)`, structurally parallel
to `LTCOutputHost` but far simpler — no taps, no program audio, no channel roles.

- `.onChange(of: engine.isPlaying)` → start / stop.
- `.onChange(of: engine.currentTime)` → **any**-size jump beyond a small epsilon
  is a seek (not LTC's 1.0 s threshold): re-anchor while playing, Full Frame only
  while paused. Throttled to ~10 sends/s so waveform scrubbing cannot flood the
  port.
- `.onChange(of: mtcStore.settings)` and `.onChange(of: timecodeSettings)` → refresh.
- `.onDisappear` → teardown.
- Timecode source is `document.model.timecodeSettings.timecode(atPlaybackSeconds:forItem:)`
  — byte-identical to what `LTCOutputHost` feeds the LTC engine, which is what
  makes the LTC≡MTC invariant structural rather than aspirational.
- Requires `settings.isComplete` **and** an active media item, mirroring LTC.

### `OnlyCue/UI/MIDISettingsView.swift`

A new **MTC output** section above the existing input-device section:

```
┌─ MTC output ──────────────────────────────┐
│ [✓] Send MIDI Timecode                     │
│ Destination:  [ DoReMIDI ▾ ]               │
│ [Rescan devices]   [Send test timecode]    │
│ ● Sending — 00:01:32:18                    │
│ Rate follows the project framerate.        │
└────────────────────────────────────────────┘
```

- Destination picker built from a new `MTCOutput.availableDestinations()`, the
  exact twin of `MIDIInput.availableSources()`.
- **Send test timecode**: sends a Full Frame plus ~2 s of quarter-frames at
  `01:00:00:00`, with no media loaded and no transport running, so the rig can be
  proven at setup rather than at showtime. It doubles as the documented manual
  verification step for leaf 2.
- Status row reads `isRunning` / `currentTimecode` / `lastError`. The pane grows
  past its current `height: 440`; re-measure rather than letting the list scroll.
- All `DS.*` tokens (ADR-024/029), matching the surrounding sections.

### Transport indicator

An `[MTC]` pill beside the playhead clock (`PlayheadClockHeader`), shown only when
`MTCOutputStore.shared.settings.isEnabled`. Lit while sending, `DS` error tint on
`lastError`. Pure label formatting goes in a small `MTCBadgeLabel`-style type with
its own unit tests, following `LTCBadgeLabel`.

This also closes a real gap by example: `LTCAudioOutput.lastError` is published
"for UI to surface" but **no consumer reads it**, so LTC output failures are
silently swallowed today. Fixing that is deliberately **out of scope here** and
filed as a separate follow-up issue so this epic does not perturb the LTC path.

### Playback-rate interlock

`PlaybackRateController.apply(_:engine:ltcEnabled:)` blocks off-speed playback
while LTC is armed, and `PlaybackRateBindings` resets rate to 1.0 when LTC is
enabled. MTC free-runs at nominal rate for the same reason LTC does, so the gate
becomes a single `timecodeOutputEnabled = ltcEnabled || mtcEnabled` parameter.
The call site in `DocumentView` passes both stores.

## Compatibility

- **No `ProjectModel` schema change.** Framerate comes from
  `ProjectTimecodeSettings`, start TC from `MediaItem.startTimecodeFrames`, and
  all MTC config is machine-level `UserDefaults`. `currentSchemaVersion` stays at
  **v22**; no migration.
- No change to any existing LTC type. MTC is purely additive.
- Fresh install: `isEnabled == false` — nothing is emitted until opted in,
  matching `LTCRoutingSettings.default`.

## Testing

**Unit (pure, TDD — failing test committed first where practical):**

- `MTCFrameTests` — rate-bit table for all four framerates; all 8 quarter-frame
  piece bytes for representative timecodes; piece 7 packing of rate bits + hour
  MSB; Full Frame byte sequence including the `hh` rate packing.
- `MTCFrameGoldenVectorTests` — full 8-message sequences at 24 / 25 / 30 / 30DF,
  hour rollover, drop-frame label boundaries (`00:01:00:02`), `23:59:59:29`.
- `MTCScheduleTests` — a fixed anchor and timebase yield exact
  `(byte, timestamp)` pairs; window boundaries are half-open (no duplicate or
  dropped message across consecutive batches); the transmitted value advances
  every 2 frames; re-anchoring on seek restarts the piece sequence at 0.
- `MTCOutputSettingsTests` / `MTCOutputStoreTests` — defaults, `isComplete`,
  JSON round-trip, corrupt-data fallback, missing-key tolerance.
- `MTCBadgeLabelTests` — status string formatting.
- `PlaybackRateControllerTests` — the interlock blocks with MTC alone enabled,
  with LTC alone, and with both.

**UI (`OnlyCueUITests`, BDD-mirrored):** the MTC section renders in Settings ▸
MIDI; the transport pill appears when enabled and is absent when not. Uses the
existing ephemeral-store UI-test hook pattern so the user's real prefs are never
written.

**Not automated — manual hardware verification (leaf 2, and re-run before merge):**

1. DoReMIDI box selected as destination; **Send test timecode** → box locks at
   `01:00:00:00`.
2. Play a clip with both LTC and MTC armed; confirm a reader on each shows the
   **same** value — this is the LTC≡MTC invariant and the 2-frame-convention check.
3. Seek while playing → both re-cue together. Seek while paused → the MTC display
   follows, LTC stays silent (by design).
4. Unplug the box mid-playback → status row and pill both report the failure
   rather than pretending to send.
5. Repeat 2 at 24, 25, 30 and 30 DF.

## Hard-rules check

- No App Sandbox entitlement (ADR-007) — CoreMIDI output needs none, as ADR'd for
  MIDI input.
- No `ProjectModel` schema change, so no `schemaVersion` bump (`docs/data-model.md`).
- No embedded media (ADR-006) — untouched.
- macOS 14.0 floor untouched (ADR-001).
- New main-window UI (the pill) is dark-only and consumes `DS.*` tokens
  (ADR-024/029), enforced by `TokenConformanceTests`.

## Delivery — ~8 leaves under one epic

Hardware validation is pulled forward to **leaf 2**, before any UI exists, so a
wrong wire-format assumption is caught while it is still a one-file change.

| # | Leaf | Kind |
| --- | --- | --- |
| 1 | Spec + **ADR-032** + `MTCFrame` (pure, golden vectors) | feat |
| 2 | `MTCOutput` minimal edge + hardcoded free-run send — **hardware check** | feat |
| 3 | `MTCSchedule` batching (pure, TDD) | feat |
| 4 | `MTCOutputSettings` + `MTCOutputStore` (pure, TDD) | feat |
| 5 | `MTCOutputHost` — transport wiring, Full Frame on seek / paused, throttle | feat |
| 6 | MIDI settings section + status row + **Send test timecode** | feat |
| 7 | Transport `[MTC]` pill + `MTCBadgeLabel` + UI test | feat |
| 8 | Rate interlock extension + `docs/architecture.md` + `progress.md` | chore |

## Out of scope (filed as follow-ups, not built here)

- **Multiple MTC destinations** — the analogue of LTC's #655 fan-out. v1 is one
  destination; add if DoReMIDI plus a second device is ever needed at once.
- **Virtual CoreMIDI source** so other Mac apps chase OnlyCue without hardware.
- **MTC chase / slave** (reading incoming MTC) — the mirror of LTC chase, itself
  already out of scope per ADR-019.
- **MMC and MIDI Clock** — transport verbs and tempo respectively, neither is
  timecode; a separate epic.
- **Per-clip MTC mute** — `ltcMuted` exists because LTC shares a physical cable
  with program audio; MTC has no such collision, and adding it would force a
  schema bump onto an otherwise schema-free feature.
- **Surfacing `LTCAudioOutput.lastError`** — a real existing gap found during
  design, kept out so this epic does not perturb the LTC path.
- **Concurrent-document arbitration** — two windows playing both send, exactly as
  they both fight over the audio device for LTC today. Documented, not solved.
- **True 29.97 / 23.976 framerates** — unchanged from ADR-019.
