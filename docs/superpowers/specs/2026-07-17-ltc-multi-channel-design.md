# LTC channel assignment — same role on multiple channels — design

**Date:** 2026-07-17
**Issue:** #655
**Status:** Approved (grilling)

Part 3 of 3 in the LTC-output improvements (② gain → ① strip → ③ multi-channel).

## Goal

Let the **same role** (LTC / Track L / Track R) be assigned to **multiple output
channels**, so one LTC signal can feed several devices at once (Doremidi + a
lighting desk + a recorder) and program audio can go to multiple outputs. Today
each of these roles is unique — one channel maximum.

## Decisions (locked with the user — option C)

- Both LTC **and** program (Track L / Track R) can go to multiple channels.
- Assigning a role to a channel no longer clears the role off other channels.
- `Silent` stays repeatable (unchanged); now every role is repeatable.

## Architecture

The audio buffer writer (`makeBuffer(channels:)`) **already** writes any
`[(samples, channel)]` list — including the same samples to several channels.
The change is: the routing model exposes channel **lists**, and the output builds
entries from those lists. Single-channel and stereo cases stay identical.

### `LTCRoutingSettings.swift`

- `channels(for role:) -> [Int]` — all channels holding `role` (new). Keep the
  existing single `channel(for:)` only if still used, else remove.
- `ltcChannels: [Int]`, `trackLeftChannels: [Int]`, `trackRightChannels: [Int]`
  replace the `…Channel: Int?` computeds.
- `hasTrackChannels = !trackLeftChannels.isEmpty || !trackRightChannels.isEmpty`.
- `isComplete = isEnabled && !ltcChannels.isEmpty`.
- `assigning(_:toChannel:)` drops the unique-role clearing — it just sets the role.
- `ChannelRole.uniqueRoles` / `isUnique` removed (no longer meaningful).

### `LTCAudioOutput.swift`

- Stored `ltcChannel: Int = 0` → `ltcChannels: [Int] = []`; `trackLeftChannel?`/
  `trackRightChannel?` → `[Int]`. Reset to `[]` on `stop()`.
- `restartEngine` reads `pending.routing.ltcChannels` / `…trackLeftChannels` /
  `…trackRightChannels`.
- `start` guard: `!routing.ltcChannels.isEmpty` (was `ltcChannel != nil`).
- `scheduleOneBuffer`: build `ltcChannels.map { (samples, $0) }` and call
  `makeBuffer(channels:)` (was single `makeBuffer(monoSamples:channel:)`).
- `scheduleOneProgramBuffer`: iterate `trackLeftChannels` / `trackRightChannels`,
  appending `(left, ch)` / `(right, ch)` per channel.
- `hasProgramOutput`: `!trackLeftChannels.isEmpty || !trackRightChannels.isEmpty`.

### `AudioSettingsView.swift`

- `routingStatusCard`: `settings.ltcChannels.isEmpty` (was `ltcChannel == nil`);
  the Track warning already uses `hasTrackChannels`.
- The per-channel `Picker` needs no change — removing the `assigning` clearing is
  enough to let the same role sit on several channels.

### Compatibility

`channelRoles: [ChannelRole]` is unchanged, so stored UserDefaults settings
decode as-is — **no migration**. Only the *interpretation* (single→list) changes.

## Testing

- **Unit (`LTCRoutingSettingsTests`):**
  - `assigning` the same role to a second channel keeps both (no clearing) — the
    inverse of the old `test_assigning_uniqueRole_clearsPreviousHolder`.
  - `ltcChannels` / `trackLeftChannels` / `trackRightChannels` return all matching
    channels, in order.
  - `isComplete` true with ≥1 LTC channel; `hasTrackChannels` with ≥1 track channel.
  - Update/remove the old unique-clearing + `isUnique` tests.
- **Unit (buffer):** `makeBuffer(channels: [(ltc,0),(ltc,2)])` writes the LTC
  samples to both channels (extend `LTCAudioOutput` buffer tests). Single/stereo
  entries produce the same buffers as before (regression guard).
- **Not unit-tested:** the live `AVAudioEngine` scheduling — run-verified with a
  multi-output interface + Doremidi.

## Regression safety

- Single LTC → `ltcChannels = [0]` → entries `[(samples,0)]` — identical to today.
- LTC + stereo → `trackLeftChannels=[1]`, `trackRightChannels=[2]` — identical.
- Multi is purely additive entries; the buffer writer already handles it.

## Hard-rules check

No `ProjectModel` schema change (LTC settings in UserDefaults, structure
unchanged). No App Sandbox. No embedded media. macOS 14.0 floor untouched.

## Out of scope

A richer status display ("LTC on channels 1 & 3") — a nice-to-have, not required.
</content>
