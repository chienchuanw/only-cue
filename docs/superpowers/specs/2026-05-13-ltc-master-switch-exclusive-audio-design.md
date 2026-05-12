# LTC master switch + exclusive audio routing — design

**Date:** 2026-05-13
**Status:** approved
**Spec section implemented:** `docs/architecture.md` § "LTC and routing" (epic #33 follow-up)

## Problem

Two gaps in the current LTC output:

1. **No way to turn LTC off.** `LTCRoutingSettings` always wants an `ltc` channel; the Audio
   settings pane nags with a "no channel assigned to LTC" warning even for users who never use
   timecode. There is no master switch, and there is no sensible default — a fresh install behaves
   as if the user intends to emit LTC.
2. **LTC overlaps program audio.** `PlayerEngine` plays media via `AVPlayer` on the system default
   output; `LTCAudioOutput` runs its own `AVAudioEngine` on the routed device with LTC on the
   assigned channel and digital silence elsewhere. When the routed device *is* the system output,
   `AVPlayer`'s stereo program audio sums with the LTC signal on the shared channel — the LTC feed
   is corrupted.

## Behavior

### A. LTC master switch, default off

- `LTCRoutingSettings` gains `isEnabled: Bool`, default `false`.
- Audio settings (`Settings → Audio`) gets a top toggle **"Enable LTC output"**.
- **Off:** no LTC engine runs; no "no LTC channel assigned" warning; the channel-assignment table
  is hidden; media plays normally through `AVPlayer` exactly as today. **Everything on this path is
  byte-for-byte the current behavior.**
- **On:** today's routing behavior (device picker, per-channel roles, the warning when no `ltc`
  channel is assigned) — plus B.

### B. Exclusive audio while LTC is running

When the LTC engine is running (`isEnabled && ltcChannel != nil` and the engine started):

- The routed device carries **only** what the engine produces:
  - `ltc` channel → generated LTC (as today),
  - `trackLeft` / `trackRight` channels → the media's program audio (if those roles are assigned),
  - every other channel → digital silence (zero).
- `AVPlayer`'s own audio output is muted (`AVPlayer.volume = 0`) so nothing sums at the device.
- If no track channels are assigned, program audio is simply inaudible while LTC is on. The Audio
  settings pane shows a hint to that effect when LTC is enabled and no `trackLeft`/`trackRight` role
  exists.
- Single destination only for v1: program audio + LTC both go to the one routed device. Monitoring
  program audio locally while the interface gets LTC+tracks is a future enhancement, explicitly out
  of scope.

When `isEnabled` is false, or true but no `ltcChannel` is assigned (engine not started): `AVPlayer`
is **not** muted and no tap is installed — the media plays normally.

## Components

| Unit | Responsibility | File |
|---|---|---|
| `LTCRoutingSettings.isEnabled` | New stored `Bool`, default `false`. `isComplete` ⇒ `isEnabled && ltcChannel != nil`. `Codable`: absent JSON key decodes to `false` (custom `init(from:)` or `decodeIfPresent`). Lives in `UserDefaults` (`ltcRouting.v1`), not `.cuelist` — no `schemaVersion` bump. | `OnlyCue/LTC/LTCRoutingSettings.swift` |
| `AudioSettingsView` | New "Enable LTC output" `Toggle` bound through `LTCRoutingStore`. Channel-assignment table + "no LTC channel" warning shown only when enabled. New hint when enabled with no `trackLeft`/`trackRight` channel assigned ("Program audio will be silent on this device — assign Track L / Track R to hear it"). | `OnlyCue/UI/AudioSettingsView.swift` |
| `ProgramAudioRingBuffer` (new) | Pure float-PCM ring buffer (deinterleaved, render-format-shaped): `push(_:)`, `drain(into:frameCount:)` (zero-fills on underrun), `flush()`, capacity sized to a few `bufferTargetSeconds`. Pure value/reference type — fully unit-tested without any live audio. | `OnlyCue/LTC/ProgramAudioRingBuffer.swift` |
| `ProgramAudioTap` (new) | Wraps an `MTAudioProcessingTap` + `AVMutableAudioMix`. `attach(to item: AVPlayerItem, renderFormat:)` installs the tap (sets `item.audioMix`); the process callback converts tapped audio via an owned `AVAudioConverter` to the engine render format and `push`es into a `ProgramAudioRingBuffer`. `detach()` clears `item.audioMix` and tears down the tap. Exposes the ring buffer for the engine to drain. The realtime callback only does conversion + push (no allocation in steady state). | `OnlyCue/LTC/ProgramAudioTap.swift` |
| `LTCAudioOutput` | Gains a second `AVAudioPlayerNode` (`programNode`), attached and connected to `engine.outputNode` with the same discrete multichannel `renderFormat`. A second buffer-pump path (mirroring the LTC pump: completion handler + the existing refill `DispatchSourceTimer`) drains the `ProgramAudioRingBuffer` into PCM buffers that place the tapped stereo onto the `trackLeft`/`trackRight` channel indices via a generalized `makeBuffer`. When neither track role is assigned, the program pump is inactive (engine still emits silence there). `start(at:routing:programTap:)` / `stop()` / `update(at:)` also manage `programNode` and `flush()` the ring buffer on seek. `restartEngine()` re-creates `programNode`'s connection on config change. | `OnlyCue/LTC/LTCAudioOutput.swift` |
| `LTCAudioOutput.makeBuffer` (generalized) | From the current mono-on-one-channel form to `makeBuffer(channels: [(samples: [Float], channel: Int)], format:) -> AVAudioPCMBuffer?` — fills the named channels, silence elsewhere, clamps out-of-range channel indices, requires all source arrays equal length. The LTC path passes one entry; the program path passes up to two. Pure — unit-tested. | `OnlyCue/LTC/LTCAudioOutput.swift` |
| `LTCOutputHost` | Gates on `settings.isEnabled`. When starting the engine: also set `PlayerEngine`'s `AVPlayer.volume = 0` and create + `attach` a `ProgramAudioTap` to `player.currentItem` (if any); pass the tap to `LTCAudioOutput.start`. On stop: `detach` the tap and restore `AVPlayer.volume = 1`. Observe `AVPlayer.currentItem` changes and re-attach the tap to the new item while the engine runs. | `OnlyCue/UI/LTCOutputHost.swift` |
| `PlayerEngine` | Small `setAudioMuted(_ muted: Bool)` helper (sets `player.volume`) for clarity; `currentItem` reachable via the already-public `player`. No behavior change otherwise. | `OnlyCue/Media/PlayerEngine.swift` |

## Data flow

```
AVPlayer (video clock; drives currentTime + SMPTE readout)
   │  audio render
   ▼
MTAudioProcessingTap  ──►  AVAudioConverter ──► ProgramAudioRingBuffer (render format)
   (ProgramAudioTap)                                      │
AVPlayer.volume = 0                                       │
                                                          ▼
                                              LTCAudioOutput (one AVAudioEngine, routed device)
                                                ├─ ltcNode      ◄─ LTCSchedule.nextBuffer()  → channel ltcChannel
                                                └─ programNode  ◄─ ring buffer drain          → channels trackLeft/trackRight
                                                        (engine sums both onto the routed device)
```

- **Seek:** `LTCAudioOutput.update(at:)` re-cues the LTC node (as today) and `flush()`es the program
  ring buffer; the tap refills from the new position. Program audio carries a small constant
  latency vs. video (tap → schedule); acceptable for v1.
- **Master clock stays `AVPlayer`** — no new A/V sync logic; we only siphon its audio.

## Edge cases & errors

- **Engine config change / device disconnect** — `restartEngine()` rebuilds; it must re-create
  `programNode`'s connection and re-prime from the (still-attached) tap. The tap survives because it
  lives on the `AVPlayerItem`, not the engine.
- **No current media item when LTC starts** — engine runs LTC only; `LTCOutputHost` attaches the tap
  lazily when an item appears.
- **Tap underruns / can't keep up** — `drain` zero-fills; `programNode` gets a brief silence. The LTC
  stream is a separate node with its own pump and is unaffected.
- **`isEnabled` true but no `ltcChannel`** — engine doesn't start, warning shown, `AVPlayer` not
  muted, no tap — media plays normally.
- **App built without App Sandbox (ADR-007)** — unaffected; no new entitlements.
- **Schema** — `LTCRoutingSettings` is a `UserDefaults` preference, not part of `.cuelist`; tolerate
  the missing `isEnabled` key on decode (→ `false`). No migration.
- **macOS deployment target** — `MTAudioProcessingTap` and `AVMutableAudioMix` predate 14.0; no
  target change (ADR-001).

## Testing

**Pure / unit (headless):**
- `LTCRoutingSettings` — `isEnabled` default `false`; `isComplete` ⇔ enabled ∧ has `ltc` channel;
  JSON round-trip with and without the `isEnabled` key; `assigning` / `resized` / `withDefaultRoles`
  unchanged.
- `LTCAudioOutput.makeBuffer` (generalized) — single mono entry on one channel (LTC parity with
  today); two entries on track channels with silence elsewhere; out-of-range channel clamps;
  mismatched-length sources rejected.
- `ProgramAudioRingBuffer` — `push`/`drain` ordering, wrap-around, underrun zero-fill, `flush`,
  capacity bounds.

**Not headless-testable (manual; document in `docs/verification.md`):** the `MTAudioProcessingTap`
install + format conversion, the live two-node `AVAudioEngine`, `AVPlayer` muting on engine
start/stop, A/V sync feel — verified by running the app against a multichannel interface, same as the
existing `LTCAudioOutput` live path.

**UITests (`OnlyCueUITests/`):** toggling "Enable LTC output" in `Settings → Audio` shows/hides the
channel-assignment table and the "no LTC channel" warning.

## Out of scope

- Monitoring program audio locally while the interface gets LTC + tracks (separate engine output).
- Per-channel gain / pan for program audio.
- Routing program audio to a *different* device than LTC.
- Anything touching LTC chase / slave-to-incoming (we generate; we don't slave) — unchanged.
