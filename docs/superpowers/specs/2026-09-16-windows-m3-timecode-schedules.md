# Contract slice 2 — the LTC and MTC schedulers

**Status:** draft 2026-09-16 — awaiting approval
**Epic:** #728 (Windows port), milestone **M3 — hardware**
**Touches:** `OnlyCue/LTC/LTCSchedule.swift` (doc comment only),
new `OnlyCueTests/LTCScheduleGolden.swift`,
new `OnlyCueTests/LTCScheduleGoldenVectorTests.swift`,
new `OnlyCueTests/MTCScheduleGolden.swift`,
new `OnlyCueTests/MTCScheduleGoldenVectorTests.swift`,
new `golden/ltc-schedule-v1.json`, new `golden/mtc-schedule-v1.json`,
new `windows/OnlyCue.Core/Ltc/LtcFrameStream.cs`,
new `windows/OnlyCue.Core/Ltc/LtcSchedule.cs`,
new `windows/OnlyCue.Core/Midi/MtcSchedule.cs`,
new `windows/OnlyCue.Core.Tests/LtcScheduleVector.cs` + `LtcScheduleGoldenVectorTests.cs`,
new `windows/OnlyCue.Core.Tests/MtcScheduleVector.cs` + `MtcScheduleGoldenVectorTests.cs`
**Prior art:** slice 1 (#854) — `golden/ltc-wire-v1.json`, `golden/mtc-wire-v1.json`,
`windows/OnlyCue.Core/Ltc/{LtcFrame,LtcEncoder}.cs`, `Midi/MtcFrame.cs`. This
slice reuses that shape verbatim, including the run-length PCM encoding and the
`GoldenDouble` helper.

## Milestone label

Slice 1's spec and issue titles say "M2 slice 1". **That label is wrong** —
epic #728's M2 is *media*; timecode I/O is **M3 — hardware**. The epic body has
been corrected and this spec uses the right milestone. The file name keeps the
`m3` prefix so the two specs do not look like the same milestone.

## Goal

Pin the three **scheduling** value types that sit on top of the slice-1 wire
primitives:

| Swift | Role | C# mirror |
| ----- | ---- | --------- |
| `LTCFrameStream` | concatenates N frames into one seamless waveform | `LtcFrameStream` |
| `LTCSchedule` | slices that stream into fixed-size playback buffers | `LtcSchedule` |
| `MTCSchedule` | maps host-clock windows to the quarter-frames due in them | `MtcSchedule` |

Slice 1 pinned *what one frame looks like*. This slice pins *how frames are
composed into a stream, how that stream is cut into buffers, and how a host-clock
window selects messages* — the three places a Windows backend has to agree with
macOS about scheduling, not just about bytes.

All three are pure value types. No WinUI, no audio device, no MIDI device — the
whole slice is doable on the Mac.

## Non-goals

- **`MTCSchedule.hostTicksPerSecond()`.** It reads `mach_timebase_info`. Windows
  will use `QueryPerformanceFrequency`. The *value* is injected on both sides
  (`ticksPerSecond`), which is exactly why the rest of the type is pinnable —
  so the platform call itself stays out of the contract.
- **`LTCAudioOutput`, `MTCOutput`.** Device plumbing; they consume these types.
- **`LTCDecoder`**, **`MTCLocateGate`**, **`WaveformPeakBucketer`.** Still
  unpinned, still separate slices.
- **Behaviour changes.** Everything here is pinned as it currently is. The one
  exception is a doc comment (see Finding 3) — no executable line changes.

## Findings from the source audit

### Finding 1 — the `endLevel == startLevel` invariant, and why buffer joins are seamless

`LTCFrameStream.samples(frameCount:)` threads biphase polarity across frames, but
`LTCSchedule.samples(forBufferIndex:)` builds each buffer with a *fresh*
`LTCFrameStream`, which always starts at `level = false`. So polarity is
explicitly **not** threaded across buffer joins.

`LTCSchedule`'s doc comment calls that "harmless, since an LTC reader keys on
transitions, not absolute polarity". **That reasoning is wrong.** A reset that
actually flipped the level would mean a *missing* transition at the join, and a
missing transition is a misread bit — not a harmless polarity inversion.

The conclusion happens to be right, for a stronger reason. Per frame the encoder
emits 80 bit-boundary flips plus one mid-bit flip per `1` bit. The parity bit
forces the number of ones to be **even**, so the total flip count is even and
`endLevel` always equals `startLevel`. All ten `op: "encode"` cases in
`golden/ltc-wire-v1.json` confirm it: every one has `endLevel == startLevel`.

So: **the parity bit is what makes the buffer joins seamless.** A port that got
parity wrong would not merely fail a conformance check — it would emit an audible
glitch at every buffer boundary. That is the single most valuable thing this
slice can pin, and it is invisible in slice 1, which only ever looks at one frame
at a time.

### Finding 2 — three separate rounding hazards, all confirmed numerically

Slice 1 established the rule (`Math.Round(x, MidpointRounding.AwayFromZero)`).
This slice has three fresh instances, each verified to actually diverge:

| Site | Expression | Divergent case | Swift | C# `Math.Round` |
| ---- | ---------- | -------------- | ----- | --------------- |
| `LTCSchedule.framesPerBuffer(forTargetSeconds:rate:)` | `(secs · fps).rounded()` | `0.1 s @ 25 fps → 2.5` | **3** | 2 |
| " | " | `0.5 s @ 25 fps → 12.5` | **13** | 12 |
| `MTCSchedule.timestamp(forQuarterFrame:)` | `(index · ticksPerQuarterFrame).rounded()` | `ticksPerSecond = 50`, 25 fps, index 1 → `0.5` | **1** | 0 |

A fourth is an *ordering* hazard rather than a rounding-mode one.
`LTCSchedule.samplesPerBuffer` rounds **per frame and then multiplies**:

```swift
framesPerBuffer * Int((sampleRate / Double(framesPerSecond)).rounded())
```

At 44 100 Hz / 24 fps that is `4 × round(1837.5) = 4 × 1838 = 7352`. A port that
wrote the arithmetically-equivalent-looking `round(4 × 44100 / 24)` gets
**7350** — two samples short per buffer, i.e. a drift of one sample per two
frames, forever. Pinning `samplesPerBuffer` at a non-integer `sampleRate / fps`
catches it; pinning it only at 48 kHz (where the division is exact) does not.

`LTCFrameStream.samplesPerFrame` has the same `.rounded()` but no *realistic*
sample rate produces a mode-divergent tie (a divergence needs `floor(sr/fps)` to
be even; 44100/24 = 1837.5 has an odd floor, so both modes give 1838). It is
pinned anyway, and the 44 100/24 case does double duty as the ordering pin above.

### Finding 3 — `MTCSchedule.quarterFrameIndex`'s 1 µs quantise is load-bearing

```swift
let exact = offset / ticksPerQuarterFrame
let rounded = (exact * 1_000_000).rounded() / 1_000_000
return Int(rounded.rounded(.up))
```

Simulated over the first 200 quarter-frames at `ticksPerSecond = 1e9`:

| clock | fps | messages dropped at a tiled seam **without** the quantise |
| ----- | --- | --- |
| 1 e9 (nanoseconds) | 24 | **74 / 200** |
| 1 e9 | 30 | **66 / 200** |
| 1 e9 | 25 | 0 (the period is exactly 10 000 000 ticks) |
| 24 e6 (Apple Silicon) | 24 / 25 / 30 | 0 (all exact) |

So the quantise is not defensive padding — at nanosecond resolution, which is
what a Windows `QueryPerformanceFrequency` of 10 MHz is a coarser cousin of, a
port that dropped it would lose **more than a third of all MTC messages**. The
vectors must include a `ticksPerSecond = 1e9` case at 24 fps or the hazard is
untested.

**The C# spelling is `Math.Ceiling`, not `Math.Round`** — and the inner
`.rounded()` still needs `MidpointRounding.AwayFromZero`. Banker's rounding there
would drop a message at the seams where `exact · 1e6` lands on a `.5`.

### Finding 4 — the quantise makes the window asymmetric, on purpose

A consequence worth recording rather than discovering later: because
`quarterFrameIndex` snaps to the nearest microsecond-of-a-quarter-frame, a window
whose `from` sits a tick or two *after* a message's timestamp can still include
that message. The half-open `[from, until)` guarantee in the doc comment is
therefore exact only at the tolerance, not absolutely.

This never bites the real caller: `MTCOutput` tiles windows, so every `from` is a
previous `until`, and the invariant that actually matters — **each message
exactly once across a tiled chain** — holds. The looser reading is the price of
Finding 3, and Finding 3 is worth paying for.

**Decision (approved): pin it as-is, including the seam cases.** Not fossilising
a bug — this is deliberate, documented behaviour whose alternative is 37 % message
loss. If we ever want strict half-open semantics, `quarterFrameIndex` is one line
and the vector version bumps to 2.

## Decisions

| # | Question | Decision |
| - | -------- | -------- |
| 1 | How deep is the PCM pinned? | **Structure + seam windows.** Slice 1 already pins every sample of a single frame. What is new here is *composition*, so: pin `samplesPerFrame` / `samplesPerBuffer` / `totalSamples` / `timecode` / `endLevel`, and pin actual PCM **only as run-lengths in a ±16-sample window around each join**. |
| 2 | `MTCSchedule`'s 1 µs quantise | **Pin as observed, with explicit tiling cases** — a chain where each window's `until` is the next window's `from`, so both a dropped and a duplicated seam message fail. |
| 3 | One golden file or two? | **Two** — `golden/ltc-schedule-v1.json`, `golden/mtc-schedule-v1.json`. One contract per file, as in slice 1. |
| 4 | `hostTicksPerSecond()` | **Excluded** (Mach-specific). |
| 5 | The wrong doc comment (Finding 1) | **Corrected in this slice.** It documents the exact invariant the vectors now pin, so leaving it wrong while pinning the truth next to it would be worse than either. Comment only — no executable change. |

### Decision 1 in detail — why ±16 samples

The failure this window has to catch is a **missing transition** at a join, which
shows up as one run being roughly twice as long as its neighbours. At 48 kHz /
24 fps a half-bit is 12.5 samples, so ±16 samples spans more than a full bit
either side of the boundary — enough to see the run that straddles the join *and*
its neighbours for comparison, and small enough that the whole `joins` array for
an 8-frame stream is a few dozen pairs rather than 16 000 floats.

Pinning every sample of a multi-frame stream would be ~40× the file size of
slice 1's for information slice 1 already has. Pinning nothing but
`totalSamples` would pass a port that concatenated frames with a glitch at every
seam. The window is the only part that carries new information.

## Contract: `golden/ltc-schedule-v1.json`

```jsonc
{
  "contract": "ltc-schedule",
  "version": 1,
  "note": "…source-of-truth banner, same wording as ltc-wire-v1…",
  "cases": [
    {
      "label": "stream/24@48000/00:00:00:00/x4",
      "op": "stream",
      "rate": "24",
      "input": { "hours": 0, "minutes": 0, "seconds": 0, "frames": 0,
                 "sampleRate": 48000, "amplitude": 0.8, "frameCount": 4 },
      "expect": {
        "samplesPerFrame": 2000,
        "totalSamples": 8000,
        "endLevel": false,
        "joins": [ { "at": 2000, "runs": [[1,12],[-1,13],[1,25],…] }, … ]
      }
    },
    {
      "label": "streamTimecode/30df/00:00:59:29/offset-1",
      "op": "streamTimecode",
      "rate": "30df",
      "input": { …, "frameOffset": -1 },
      "expect": { "timecode": "00:00:59;29" }
    },
    {
      "label": "schedule/24@44100/01:00:00:00/fpb4",
      "op": "schedule",
      "rate": "24",
      "input": { …, "sampleRate": 44100, "framesPerBuffer": 4 },
      "expect": { "samplesPerBuffer": 7352, "bufferDuration": 0.16666666666666666 }
    },
    {
      "label": "buffer/24@48000/01:00:00:00/fpb2/index3",
      "op": "buffer",
      "input": { …, "bufferIndex": 3 },
      "expect": { "timecode": "01:00:00:06", "sampleCount": 4000,
                  "endLevel": false,
                  "joins": [ { "at": 2000, "runs": […] } ] }
    },
    {
      "label": "bufferSeam/24@48000/01:00:00:00/fpb2/index3-4",
      "op": "bufferSeam",
      "input": { …, "bufferIndex": 3 },
      "expect": { "previousEndLevel": false, "nextStartLevel": false,
                  "runs": [[1,7],[-1,13],[1,12],…] }
    },
    {
      "label": "targetBufferCount/25/fpb4/elapsed0.48/lead2",
      "op": "targetBufferCount",
      "input": { …, "elapsedSeconds": 0.48, "leadBuffers": 2 },
      "expect": { "count": 5 }
    },
    {
      "label": "framesPerBuffer/25/0.1s",
      "op": "framesPerBuffer",
      "rate": "25",
      "input": { "targetSeconds": 0.1 },
      "expect": { "frames": 3 }
    }
  ]
}
```

### Case matrices

**`op: "stream"`** — `(rate, sampleRate)` pairs reused from slice 1's encode
matrix so the per-frame PCM is already independently pinned, × `frameCount ∈
{1, 2, 8}`. `frameCount = 1` proves `joins` is empty and `totalSamples ==
samplesPerFrame`; `2` is the minimal join; `8` proves the join is identical at
every boundary, i.e. that polarity really is threaded and not merely correct once.
Plus a `frameCount = 0` and a `frameCount = -3` case, both expecting
`totalSamples: 0` (the `guard count > 0` early return).

Every `stream` case asserts `endLevel == false`, which given `startLevel == false`
*is* Finding 1's invariant. The test states it as a named assertion, not as an
incidental field, so the reason is visible at the failure site.

**`op: "streamTimecode"`** — offsets `{-5, -1, 0, 1, 23, 24, 25}` at all four
rates from `00:00:59:xx`, so the offsets cross a second boundary and, at `30df`,
the drop-frame minute boundary. Pins the `max(0, offset)` clamp, which a port
would plausibly write as a precondition or as a negative index.

**`op: "schedule"`** — must include **24 fps @ 44 100 Hz** (Finding 2's ordering
hazard, `samplesPerBuffer == 7352`), plus 48 kHz at every rate, ×
`framesPerBuffer ∈ {1, 2, 4, 25}`. `bufferDuration` is a `GoldenDouble` — it is
`framesPerBuffer / fps` and at 24 fps is non-terminating in binary, so a port that
computed it as `samplesPerBuffer / sampleRate` instead would differ in the last
bits and fail. That is the intended catch.

**`op: "buffer"`** — indices `{-2, 0, 1, 3}` (negative pins the `max(0, index)`
clamp), at 30df with a start timecode chosen so buffer 1 crosses the drop-frame
minute, proving the buffer's timecode goes through `Timecode(frameCount:)` rather
than naive field arithmetic.

**`op: "bufferSeam"`** — the new information. `runs` is the run-length encoding of
`last16(samples(i)) ++ first16(samples(i+1))`, so a port whose buffers do not abut
cleanly produces a doubled run at index ~8 of the array. Indices `{0, 1, 3}` × the
24/48000 and 25/48000 pairs. `previousEndLevel` and `nextStartLevel` are pinned
separately so a failure says *which* half is wrong.

**`op: "targetBufferCount"`** — `elapsedSeconds ∈ {-1, 0, 0.001, one exact
bufferDuration, exactly n·bufferDuration, just under, just over}` ×
`leadBuffers ∈ {-1, 0, 1, 2}`. The negatives pin both `max(0, …)` clamps.

Honest note: I searched for an exact-multiple case where the float division makes
`ceil` overshoot by one, and at realistic `(fps, framesPerBuffer)` pairs there is
none — `n · bd / bd` comes back exactly `n`. The exact-multiple cases are still
included, because what they actually pin is `ceil` vs `round`: at
`elapsed = 0.2 · bufferDuration`, `ceil` gives 1 and `round` gives 0, which is the
difference between the engine staying ahead of the playhead and starving it.

**`op: "framesPerBuffer"`** — `targetSeconds ∈ {-1, 0, 0.02, 0.1, 0.3, 0.5, 1.0}`
× all four rates. `0.1` and `0.5` at 25 fps are Finding 2's confirmed banker's
divergences (2.5 → 3, 12.5 → 13); `0.3 @ 25` is 7.5, where the two modes *agree*,
and is included as the control that proves a failure is about the tie and not
about ties in general. `-1` and `0.02` pin the `max(1, …)` floor.

## Contract: `golden/mtc-schedule-v1.json`

```jsonc
{
  "contract": "mtc-schedule",
  "version": 1,
  "cases": [
    { "label": "cadence/24/1e9", "op": "cadence", "rate": "24",
      "input": { "ticksPerSecond": 1000000000 },
      "expect": { "ticksPerQuarterFrame": 10416666.666666666 } },

    { "label": "sequenceTimecode/30df/00:00:59:28/seq-2", "op": "sequenceTimecode",
      "rate": "30df", "input": { …, "sequenceIndex": -2 },
      "expect": { "timecode": "00:00:59;28" } },

    { "label": "quarterFrame/24/1e9/index9", "op": "quarterFrame",
      "input": { …, "anchorHostTime": 1000, "ticksPerSecond": 1000000000,
                 "quarterFrameIndex": 9 },
      "expect": { "byte": 17, "timestamp": 93750001 } },

    { "label": "batch/24/1e9/tiled", "op": "batchChain",
      "input": { …, "boundaries": [1000, 93750001, 187500001, 280000000] },
      "expect": {
        "windows": [ [[0,1000],[16,10417667],…], […], […] ],
        "combined": [[0,1000],[16,10417667],…]
      } }
  ]
}
```

### Case matrices

**`op: "cadence"`** — all four rates × `ticksPerSecond ∈ {1e9, 24e6, 50}`.
`ticksPerQuarterFrame` is a `GoldenDouble`; at 1e9/24 fps it is non-terminating,
which pins the divide order (`tps / (fps · 4)`, not `(tps / fps) / 4` — those are
not bit-identical in binary floating point).

**`op: "sequenceTimecode"`** — indices `{-2, 0, 1, 7, 100}` at all four rates,
starting at `00:00:59:28` so index 1 crosses a second and, at 30df, a drop-frame
minute. Pins the two-frames-per-sequence advance *and* the `max(0, index)` clamp.

**`op: "quarterFrame"`** — indices `{-1, 0, 1, 7, 8, 9, 15, 16, 200}` ×
`(rate, ticksPerSecond)` = `{(24, 1e9), (25, 1e9), (30, 24e6), (25, 50)}`, each
with a non-zero `anchorHostTime` so a port that forgot the anchor fails. Index 8
is the first message of sequence 1, i.e. the first one carrying a *different*
timecode — the single most likely off-by-one in a port. `(25, 50)` is a
deliberately coarse clock chosen so every odd index lands on a `.5` tick
(Finding 2, row 3); it is synthetic, but `ticksPerSecond` is an injected
parameter precisely so tests can be exact, so this is in-contract.

**`op: "batchChain"`** — the tiling pin, and the reason this op exists instead of
a plain `batch`. `input.boundaries` is a list `[a₀, a₁, …, aₙ]`; `expect.windows`
is the messages for each `[aᵢ, aᵢ₊₁)` and `expect.combined` is the messages for
`[a₀, aₙ)`. Both sides assert **`concat(windows) == combined`** as a named
property in addition to matching the vector field-by-field, so a dropped seam
message and a duplicated one both fail, and fail with different diffs.

Chains to include:

1. **`ticksPerSecond = 1e9`, 24 fps, boundaries on exact emitted timestamps.**
   Finding 3's case — without the microsecond quantise this chain loses 37 % of
   its messages. Non-negotiable; if this chain is absent the slice is vacuous.
2. Same at 30 fps (33 % loss without the quantise).
3. 25 fps @ 1e9, where the period is exact — the control that proves failures in
   (1) and (2) are about the quantise and not about tiling generally.
4. `ticksPerSecond = 24e6` (Apple Silicon), all exact.
5. Boundaries that are *not* message timestamps: mid-gap splits, so the chain
   exercises the ordinary `ceil` path rather than only the tolerance path.

Plus standalone degenerate `batch` cases: `from == until` (empty),
`from > until` (inverted), a window entirely before the anchor (clamps to
quarter-frame 0), and a window entirely inside one gap (empty).

Each message serialises as `[byte, timestamp]` — the byte is already pinned by
`golden/mtc-wire-v1.json`, so a mismatch here localises to the schedule rather
than to the encoding.

## Work plan

One issue, one PR — `chore(windows): pin the LTC and MTC schedules as golden
vectors`. Order inside the PR, mirroring #854:

1. Swift golden models + emit/guard suites (`LTCScheduleGolden.swift`,
   `LTCScheduleGoldenVectorTests.swift`, and the MTC pair), modelled on slice 1's
   files line for line. Commit red (bootstrap failures) first.
2. Commit the generated `golden/*.json` — green.
3. `xcodegen generate` (new files; the `.xcodeproj` is not committed).
4. C# mirrors: `Ltc/LtcFrameStream.cs`, `Ltc/LtcSchedule.cs`,
   `Midi/MtcSchedule.cs`.
5. C# DTOs + verifier suites, reusing `GoldenFiles` and `GoldenDouble`.
6. The `LTCSchedule` doc-comment correction (Decision 5), as its own commit so it
   is trivially reviewable and trivially revertible.
7. `docs/architecture.md` — extend the rows slice 1 added rather than adding new
   ones.

`docs/progress.md` is updated **after** the merge, as repo metadata, per the
house rule.

## Implementation traps

- **`Math.Round` is not `.rounded()`** — three new sites (Finding 2). Every one
  needs `MidpointRounding.AwayFromZero`.
- **`.rounded(.up)` is `Math.Ceiling`**, not `Math.Round`. Two sites:
  `targetBufferCount` and `quarterFrameIndex`. Slice 1's spec flagged this in
  advance for exactly this slice.
- **Round then multiply, never multiply then round** (`samplesPerBuffer`).
- **`&+` is wrapping.** `timestamp(forQuarterFrame:)` adds to `anchorHostTime`
  with Swift's wrapping `&+`. C#'s `ulong +` is unchecked by default, which
  matches — but if the csproj ever sets `CheckForOverflowUnderflow`, it would
  not. Wrap the addition in `unchecked` explicitly rather than relying on the
  project default, and keep the vectors well away from `UInt64.max` so the two
  behaviours are never distinguished by accident.
- **`Int(Double)` traps in Swift, saturates-or-worse in C#.** Swift's
  `Int(x)` traps on NaN/overflow; C#'s `(int)x` is undefined for out-of-range.
  Keep all vector values in range — this contract is not the place to pin
  crash behaviour.
- **`precondition` vs exceptions.** Swift traps on `sampleRate <= 0`,
  `framesPerBuffer < 1`, `ticksPerSecond <= 0`. No vector case may contain one;
  the C# mirrors throw `ArgumentOutOfRangeException` so a bad caller fails on
  both sides rather than silently producing empty output.
- **`Float` vs `float`** for `amplitude`, as in slice 1. Never compare at
  `double`.
- **Run arrays hold `1` / `-1`, never floats.** Same rule as slice 1.

## Verification

- **Swift unit** — the four new suites; full `OnlyCueTests` via
  `scripts/dev/test.sh` (runner-collision guard, `testmanagerd` reset, ad-hoc
  signing). Current baseline 1852 tests, 0 failures.
- **C# unit** — `dotnet test windows/` (currently 644) must stay green and grow
  by exactly the new case count; the delta is checked, not eyeballed.
- **SwiftLint `--strict`** — exit 0.
- **Mutation testing is mandatory.** A green first run proves nothing. For each
  mutant: apply, `grep -n MUTANT` to prove it landed, run, confirm red *and
  record which tests went red by grepping the failure lines, not the started
  lines*, revert, `grep -c MUTANT` = 0.
  1. C# `MtcSchedule`: delete the `× 1e6 / 1e6` quantise. **Must** fail
     `batchChain` chain 1 and 2 and **must not** fail chain 3 — if chain 3 also
     fails, the chains are not isolating what they claim to.
  2. C# `MtcSchedule`: quantise with plain `Math.Round` (banker's). Must fail.
  3. C# `LtcSchedule`: `samplesPerBuffer` as `round(fpb × sr / fps)`. Must fail
     the 44 100/24 case and **only** that one.
  4. C# `LtcSchedule`: `framesPerBuffer(forTargetSeconds:)` with plain
     `Math.Round`. Must fail `0.1 s @ 25` and `0.5 s @ 25`, not `0.3 s @ 25`.
  5. C# `LtcSchedule`: `targetBufferCount` with `Math.Round` instead of
     `Math.Ceiling`. Must fail.
  6. C# `LtcFrameStream`: reset `level = false` at the top of each frame instead
     of threading `endLevel`. **Must fail the `joins` windows** — this is the
     mutant that proves Decision 1's window is wide enough to be worth having.
     If it survives, the window is too narrow and the slice is not doing its job.
  7. C# `LtcSchedule`: drop the `max(0, index)` clamp in
     `timecode(forBufferIndex:)`. Must fail the negative-index cases.
  8. Swift: any surviving mutant must be **proven** equivalent by exhaustive
     enumeration over the reachable domain, not argued. (Slice 1 had one; the
     spec's claim about it was wrong and the enumeration is what settled it.)
- **No UI tests involved**, so the "CI does not run UI tests on PRs" caveat does
  not apply.
- Both required checks green, **and** the Windows job's log confirmed to have
  *executed* the new suites by name with the expected case counts — not merely
  to have passed.

## Open questions for approval

1. **The coarse `ticksPerSecond = 50` clock.** It is the only way found to make
   `timestamp(forQuarterFrame:)`'s `.rounded()` divergent, but it is unphysical,
   and at that resolution the half-open window guarantee visibly does not hold
   (message 1's timestamp equals a window's `until` yet is emitted in it). Pin it
   as a documented curiosity, or drop the case and accept that
   `timestamp`'s rounding mode is untested? Recommendation: **keep it**, labelled,
   since the mutant it kills is otherwise unkillable.
2. **Finding 4** is behaviour I would not have chosen from scratch. Pinning it
   makes it harder to change later. Recommendation: **pin**, per the approved
   decision, and leave this paragraph in the spec as the record of why.
