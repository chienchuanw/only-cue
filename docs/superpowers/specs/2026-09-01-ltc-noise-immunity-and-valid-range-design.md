# LTC noise immunity and the striped valid range

Date: 2026-09-01
Status: approved (design)
Implements: `docs/architecture.md` — LTC subsystem; `docs/data-model.md` — `MediaItem` / schema versioning

## Problem

A 4:54 stereo mp3 exported from Logic Pro carries clean LTC on its right
channel, yet OnlyCue reports no timecode. The reporter's hypothesis was that the
file's silent opening defeats detection because the scan window is too narrow.

That hypothesis is wrong, and the correction matters: widening the window would
not have fixed anything.

### Measured facts

| Property | Value |
| --- | --- |
| Container | 48 kHz stereo mp3, 320 kbps, 294.05 s, Logic Pro 12.3.1 |
| Channel 0 (L) | programme audio |
| Channel 1 (R) | LTC, present 2.0 s – 291.1 s, RMS 0.379, continuous |
| Timecode | `08:00:00:18` at 3.0136 s, 30 fps non-drop |

`LTCDecoder` was ported line-for-line to a scratch script and run against the
real file:

```
channel 1, 0–10 s window (what ships today)
  transitions=80955  min interval=1
  halfBit=1.0000 -> bitRate=24000 -> fps=300
  sync frames=10, corroborated=false        -> detection returns nil

channel 1, same code, first 3 s skipped
  transitions=20834  min interval=9   intervals cluster at 10 and 20
  halfBit=9.95 -> bitRate=2411 -> fps=30
  sync frames=209 in 7 s                    -> essentially every frame decodes
```

### Root cause

`LTCDecoder.transitionIndices(in:)` is a bare zero-crossing detector with no
noise floor. The file's opening is digital silence at 16-bit, but
`AudioSampleReader` hands the decoder **float** samples, and mp3 decoding leaves
dither there: peak amplitude 2.35e-5, with 95 998 of 96 000 samples non-zero and
the sign flipping every sample or two.

That produces 32 101 one-sample intervals. `estimateHalfBitSamples` anchors on
`intervals.min()`, so the estimate collapses to 1.0 samples, the recovered bit
rate becomes 24 000 (fps 300), and the whole decode is garbage.

The LTC starts at 2.0 s, comfortably inside the existing 10 s window.
`scanWindows` was never implicated. The noise and the signal share every window,
so no window width can separate them — only a front end with noise immunity can.

The doc comment on `estimateHalfBitSamples` already claims the estimate comes
"from the transition-interval histogram". The implementation anchors on the
minimum instead. The comment describes the right idea; the code does not.

## Approaches considered

Each candidate was run against the real file, on both channels, with the pass
criterion "channel 1 decodes and corroborates, channel 0 still yields nothing".

```
                                     ch0 music        ch1 LTC
current: plain ZC + min anchor       0 frames         10 frames, corroborated=false
B: plain ZC + histogram mode         0 frames         10 frames, corroborated=false
A: Schmitt k=0.02 + min anchor       0 frames        227 frames, corroborated=true
A: Schmitt k=0.10 + min anchor       0 frames        226 frames, corroborated=true
A: Schmitt k=0.40 + min anchor       0 frames        226 frames, corroborated=true
```

**B — replace the minimum anchor with a histogram mode.** Rejected on evidence.
The 2 s of noise contributes 32 101 one-sample intervals against the LTC's
13 398 twenty-sample intervals, so the mode is also 1. Fixing the estimator
without fixing the front end does not work.

**C — decode the window in sub-blocks and take the first block that
corroborates.** Would work, but it layers a search over a front end that is
still fragile, does nothing for the full-file pass that Phase 2 needs, and still
fails on any block straddling the noise/signal boundary.

**A — hysteresis comparator (Schmitt trigger) in front of the transition
detector. Chosen.** It fixes the defect at its own altitude: the front end
becomes noise-immune, and every consumer of it — the 10 s scan, the 60 s scan,
the new full-file pass — inherits that. Correct across a 20× span of thresholds,
which means it is not a knife-edge parameter.

### Reference statistic

The threshold is a fraction of a reference amplitude. Peak is the obvious
choice and is wrong: a single sample of clipping doubles it.

```
ch1 reference statistics:  peak=0.5479  p95=0.5109  p99=0.5351  rms=0.3301
ch1 + one 0 dBFS click:    peak=1.0000  p95=0.5109  p99=0.5351  rms=0.3301
```

RMS is chosen: click-immune like p95, and computable in one pass with no sort.

## Design

### 1. Decoder front end — `OnlyCue/LTC/LTCDecoder.swift`

`transitionIndices(in:)` becomes a hysteresis comparator. State starts unknown;
it latches high when a sample exceeds `+threshold` and low when one falls below
`-threshold`; an index is emitted on each latch change after the first.

`threshold = 0.3 * rms(samples)`. A buffer whose RMS falls below `1e-4` is
treated as carrying no signal at all and yields no transitions — this rejects an
all-silent channel outright rather than amplifying its dither into a threshold.
The floor sits four times above this file's measured noise peak (2.35e-5) and
three and a half orders of magnitude below its LTC (RMS 0.33).

Margin on the reported file: noise floor 2.35e-5 against a threshold of 0.099,
a factor of 4200. If LTC occupied only 1 % of the buffer the RMS would fall to
0.038 and the threshold to 0.011 — still 480× the noise floor.

`estimateHalfBitSamples` keeps its minimum anchor. Once the noise is gated out,
the minimum interval *is* the half-bit period (measured: 9.96 samples, fps 30).
Its doc comment is corrected to describe what it actually does.

> **Constraint that must survive future edits.** The reference amplitude is
> computed over the whole buffer and must stay global. A per-block adaptive
> reference re-introduces this exact bug: a block of pure noise has an RMS equal
> to the noise, so the threshold collapses to the noise floor.

### 2. Two-phase detection and the valid range

**Phase 1** is unchanged: `LTCAudioReader.detectTimecodes` scans 10 s, then 60 s
if needed, across every channel, and the first corroborated channel wins. The
readout is live as soon as this returns.

**Phase 2** is new: once a channel is known — whether Phase 1 picked it or the
user did — decode that single channel across the whole file to measure the true
extent of the timecode. Runs in the background; the result replaces the cached
track and the remembered value.

`StripedTimecodeTrack` gains:

```swift
let validFrom: TimeInterval?    // nil = unbounded/unknown
let validUntil: TimeInterval?   // nil = unbounded/unknown
```

Both optional, `nil` meaning unbounded. This is deliberate on two counts.

Between Phase 1 completing and Phase 2 completing there is a 1–3 s gap. A
non-optional `validUntil` would have to be filled with a fabricated value
(the media duration) during that gap; `nil` states honestly that the bound is
not yet known, and the readout behaves exactly as it does today until Phase 2
lands.

More importantly, `rememberedLTC` values already persisted in users' projects
carry neither key. `decodeIfPresent` yields `nil`, which means unbounded, which
is precisely today's extrapolate-everywhere behaviour. Existing show files open
with unchanged readouts. A non-optional field would force the migration to
invent values for data it cannot measure.

Phase 1 sets `validFrom` to the first decoded frame and leaves `validUntil` nil.
Phase 2 sets both from the measured first and last frames.

If the full-file pass finds the timecode discontinuous, only the run containing
the anchor is adopted, and the UI warns. Multi-segment tracks are out of scope.

### 3. Manual channel selection

```swift
enum LTCChannelSelection: Codable, Equatable, Sendable {
    case auto            // default: run Phase 1
    case channel(Int)    // user-specified: skip Phase 1, run Phase 2 on this channel
    case none            // user asserts this file carries no LTC: run neither
}
```

`MediaItem.ltcChannelSelection: LTCChannelSelection = .auto`, kept separate from
`rememberedLTC`. The selection is authored; the decoded track is derived, and
conflating them would let `Clear` erase what the user said.

`ProjectModel.currentSchemaVersion` 22 → 23, with
`OnlyCue/Document/ProjectModel+MigrationV22.swift` following the existing
migration file convention.

`CueCommands+LTC` gains `setLTCChannelSelection(_:forItemID:document:)`, and
this one **is** undoable — the opposite of `rememberLTC` / `clearRememberedLTC`
in the same file, which are deliberately not. The contrast is documented at both
call sites so a later "let's make these consistent" pass does not flatten it.

`Clear` and `Re-detect` reset `rememberedLTC` only. They never touch
`ltcChannelSelection`.

Manual selection is also the escape hatch from the 60 s scan ceiling: a file
whose LTC begins at 90 s is invisible to `.auto`, but naming its channel sends
Phase 2 across the whole file, which finds it. This is intended, not incidental.

### 4. UI

`MediaEditSheet`'s LTC section gains a channel picker — `Auto (detected:
Channel 2)`, one entry per channel from `AudioSampleReader.channelCount(of:)`,
and `No LTC`. The status line reports the measured extent:

```
Detected · channel 2 · 08:00:00:18 · 00:00:02.0 – 00:04:51.1
```

`TransportControls.smpteReadout` shows `--:--:--:--` when the playhead sits
outside `validFrom…validUntil`, keeping the `FILE` prefix: the information does
come from the file, it is simply not valid at this position. `PreviewPane`
follows the same rule.

Whether `MediaEditSheet` falls inside ADR-029's `DS.*` token requirement is
confirmed against `TokenConformanceTests`' coverage before the view is edited.

### 5. Testing

TDD, red first. The first test encodes the bug as a pure unit test with no
fixture file: clean `LTCFrameStream` output prefixed with 2 s of ±2e-5 noise,
asserted against `LTCDecoder.decode`. Zero frames today; full frame count after
the Schmitt trigger lands.

Supporting coverage:

- a music-like signal still fails to corroborate, guarding against false
  positives introduced by the more permissive front end
- `validFrom` / `validUntil` derived from the measured first and last frames
- `LTCChannelSelection` Codable round-trip, including `.channel(n)`
- v22 → v23 migration leaves an existing `rememberedLTC` unbounded, so readouts
  in existing projects do not change

The reporter's mp3 is verified manually as the final check. It is copyrighted
and 11 MB; it does not enter the repository.

## Out of scope

Multi-segment timecode tracks for spliced files. Slaving playback position to
live incoming LTC. 29.97 / 23.976 pulldown. The 25 fps bit-59 parity variant.
Widening `scanWindows` beyond 60 s.
