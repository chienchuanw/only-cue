# M2 contract slice 1 — the LTC and MTC wire formats

**Status:** draft 2026-09-16 — awaiting approval
**Epic:** #728 (Windows port), milestone M2
**Touches:** `OnlyCue/LTC/LTCFrame.swift`, `OnlyCueTests/LTCFrameTests.swift`,
new `OnlyCueTests/LTCWireGoldenVectorTests.swift`,
new `OnlyCueTests/MTCWireGoldenVectorTests.swift`,
new `golden/ltc-wire-v1.json`, new `golden/mtc-wire-v1.json`,
new `windows/OnlyCue.Core/Ltc/`, new `windows/OnlyCue.Core/Midi/`,
new `windows/OnlyCue.Core.Tests/LtcWireGoldenVectorTests.cs`,
new `windows/OnlyCue.Core.Tests/MtcWireGoldenVectorTests.cs`
**Prior art:** `golden/timecode-v1.json` + `OnlyCueTests/TimecodeGoldenVectorTests.swift`
+ `windows/OnlyCue.Core.Tests/TimecodeGoldenVectorTests.cs` (M0) — this slice
copies that three-file shape verbatim. `windows/OnlyCue.Core/Timecode.cs` and
`SmpteFramerate.cs` already exist and are the inputs to everything below.

## Goal

Pin the two timecode **output wire formats** — the 80-bit SMPTE LTC frame and
its PCM modulation, and the MTC quarter-frame / Full Frame byte encodings — as
golden vectors with `OnlyCue.Core` mirrors, so that when a Windows audio/MIDI
backend is eventually written it cannot silently disagree with macOS about what
goes on the wire.

Everything here is pure value-type logic and needs no WinUI, so the whole slice
is doable on the Mac.

## Why these two, and why now

Both are already implemented, already unit-tested on the Swift side, and both
consume `Timecode`/`SMPTEFramerate`, which M0 already mirrored. So the marginal
work is the contract, not the logic.

More concretely, **there is a specific silent-divergence hazard that only a
golden vector catches.** `LTCEncoder.samples` lays each half-bit slot down at

```swift
let start = Int((Double(slot) * halfBitSamples).rounded())   // LTCEncoder.swift:44
let end   = Int((Double(slot + 1) * halfBitSamples).rounded())
```

Swift's `.rounded()` is **half-away-from-zero**. C#'s `Math.Round(double)` is
**banker's rounding** — `Math.Round(0.5)` is `0` where Swift's `(0.5).rounded()`
is `1`. At 24 fps / 48 kHz, `halfBitSamples` is exactly `12.5`, so every other
slot boundary lands on a `.5` and the two implementations disagree on which
sample each transition falls in. A C# port written by eye would compile, pass
any hand-written test, and emit a subtly different waveform forever.

The same `.rounded()` appears in `LTCFrameStream.samplesPerFrame`,
`LTCSchedule.samplesPerBuffer` and `MTCSchedule.timestamp` — out of scope here
(slice 2), but the rule this slice establishes covers them.

## Non-goals

- **`LTCDecoder`.** Signal-dependent RMS / zero-crossing thresholds; the vectors
  would have to embed synthesised waveforms. Separate slice, if ever.
- **`LTCFrameStream`, `LTCSchedule`, `MTCSchedule`.** Cross-frame polarity
  threading, buffer planning and host-clock window tiling. Slice 2 — they have
  their own set of boundary conditions (half-open windows, the `1e-6` snap
  before `ceil` in `MTCSchedule.quarterFrameIndex(atOrAfter:)`) and folding them
  in would make this PR unreviewable. `LTCEncoder`'s `startLevel`/`endLevel`
  contract is pinned here, which is the primitive those three are built on.
- **`MTCLocateGate`, `MIDIUniversalPacket`, `WaveformPeakBucketer`.** Also pure
  and also unpinned; separate slices.
- **`LTCEncoder.makeBuffer`.** `AVAudioPCMBuffer` is Apple-only; the Windows
  backend will build its own buffer type around the same `samples(...)` output.
- **`LTCBiphaseEncoder`.** See "Finding 1" below — it has no production caller.
- Any Windows audio or MIDI I/O. This slice ships no device code on either side.

## Findings from the source audit

Three things turned up while verifying the candidate list. Two change the slice.

### Finding 1 — `LTCBiphaseEncoder` is test-only

`grep` over `OnlyCue/` finds no production caller. `LTCEncoder.samples`
(`LTCEncoder.swift:50-55`) does not use it: it inlines the same toggle rule but
against *fractional* slot boundaries, which is the whole point — the
`samplesPerHalfBit: Int` primitive cannot express 12.5.

So `LTCBiphaseEncoder` is a superseded stepping stone kept alive by
`LTCFrameTests`. **It is excluded from the mirror** — porting it would put dead
code in `OnlyCue.Core` and pin a contract nothing consumes. Whether to delete it
from the Swift side is a separate question and is *not* part of this slice.

### Finding 2 — `LTCFrame` puts the parity bit in the wrong place at 25 fps 🐛

`LTCFrame.parityBitIndex` is `27` for every rate (`LTCFrame.swift:20`, and the
doc comment admits it: *"the 25 fps standard moves it to bit 59, which a
follow-up can add"*). SMPTE 12M assigns:

| | 24 / 30 fps | 25 fps |
| - | ----------- | ------ |
| Bi-phase mark phase correction (parity) | **bit 27** | **bit 59** |
| BGF0 | bit 43 | bit 27 |
| BGF2 | bit 59 | bit 43 |

Corroborated independently by `libltc` (`ltc.h`) and the Wikipedia *Linear
timecode* article; both state 25 fps (`LTC_TV_625_50`) uses bit 59.

Consequence today: at 25 fps OnlyCue sets **bit 27**, which a conforming reader
interprets as BGF0 being raised, while the real parity position (bit 59) stays
`0` — so the 80-bit word can go out with odd parity. A strict 25 fps reader may
reject it. 25 fps is the PAL-region norm, so this is a live defect, not a
theoretical one.

**Decision (approved): fix Swift first, then pin the corrected behaviour.**
Consistent with the #841 call — do not fossilise a known-wrong behaviour into a
cross-platform contract, because unpicking it later means a coordinated
two-sided change plus a vector version bump.

### Finding 3 — the existing tests are structurally unable to catch Finding 2

Not a separate bug, but it explains why this shipped, and it dictates the shape
of the failing test:

- `test_frame_parityBit27_isTheOnlyBitUsedForCorrection`
  (`LTCFrameTests.swift:80-88`) only ever builds `.fps30` timecodes.
- `test_frame_hasEvenParity_always` *does* cover 25 fps (`:77`) but only asserts
  the word has an even number of ones — true whichever bit carries the
  correction. It passes before and after the fix.
- `test_frame_userAndFlagBits_areZero` (`:56-66`) lists the eighth user-bit
  group as `59..<63`. SMPTE puts user bits 8 at **60..63**; bit 59 is a flag.
  The off-by-one is invisible today because every one of those bits is always
  zero — it passes vacuously — but it means the suite currently *asserts bit 59
  is a user bit*, which directly contradicts the fix. It has to be corrected in
  the same change. Line `:65` (`bits[63]` described as a BGF) is the other half
  of the same off-by-one.

This is the reason the fix needs a genuinely new, genuinely red test rather
than an adjustment to an existing one.

## Decisions

| # | Question | Decision |
| - | -------- | -------- |
| 1 | Slice size | **LTC + MTC wire formats together.** They share the already-mirrored `Timecode`; MTC is all-integer and nearly free once the harness exists. |
| 2 | How is the PCM output represented in the vector? | **Run-length encoding** of the sample array — `[[levelSign, count], …]`. See below. |
| 3 | 25 fps parity | **Fix Swift to SMPTE 12M (bit 59), then pin the fixed behaviour.** |
| 4 | One contract file or two? | **Two** — `golden/ltc-wire-v1.json`, `golden/mtc-wire-v1.json`. One contract per file is the existing convention and keeps the DTOs honest. |
| 5 | `LTCBiphaseEncoder` | **Excluded** (Finding 1). |
| 6 | Where do the C# types live? | `windows/OnlyCue.Core/Ltc/LtcFrame.cs`, `Ltc/LtcEncoder.cs`, `Midi/MtcFrame.cs` — mirroring the Swift folder split, as `Osc/` and `Tempo/` already do. |

### Decision 2 in detail

`LTCEncoder.samples` returns `[Float]` whose elements take exactly two values,
`+amplitude` and `-amplitude`. So run-length encoding is **lossless** and
equivalent to the real return value, while shrinking one 48 kHz / 24 fps frame
from 2000 floats to ~160–240 pairs.

It is also the most diagnostic form: a rounding divergence shows up as one run
being one sample long or short, at a run index that maps straight back to a slot
number. A hash would only say "different"; a per-slot sample-count array would
pin `emitSlot()`'s internals rather than the public return value, and would
false-alarm on any future algorithm rewrite that produced an identical waveform.

No float ever goes in the `runs` array — the sign is `1` / `-1`. The amplitude
itself is pinned once per case as a JSON number, read back through the existing
`GoldenDouble` helper and compared as `float`.

## Contract: `golden/ltc-wire-v1.json`

```jsonc
{
  "contract": "ltc-wire",
  "version": 1,
  "note": "…source-of-truth banner, same wording as timecode-v1…",
  "cases": [
    {
      "label": "frame/25/01:02:03:04",
      "op": "frame",
      "rate": "25",
      "input": { "hours": 1, "minutes": 2, "seconds": 3, "frames": 4 },
      "expect": {
        "bits": "0010…",          // 80 chars, transmission order, '0'/'1'
        "parityBitIndex": 59,      // 27 for 24/30/30df
        "parityBit": true,
        "hasEvenParity": true,
        "syncWordIsValid": true
      }
    },
    {
      "label": "encode/24@48000/00:00:00:00/startLow",
      "op": "encode",
      "rate": "24",
      "input": {
        "hours": 0, "minutes": 0, "seconds": 0, "frames": 0,
        "sampleRate": 48000, "amplitude": 0.8, "startLevel": false
      },
      "expect": {
        "totalSamples": 2000,
        "endLevel": true,
        "runs": [[1, 13], [-1, 12], [1, 25], …]
      }
    }
  ]
}
```

`op: "frame"` case matrix — all four rates × `00:00:00:00`, `12:34:56:0f`,
`23:59:59:max`, plus `00:01:00:02` and `00:10:00:00` at `30df` (the drop-frame
counting boundaries), plus at least two 25 fps values chosen so one *needs* the
correction bit and one does not. Every case additionally asserts bits 27 and 59
explicitly, so the rate-dependent placement is covered in both directions.

`op: "encode"` case matrix — the `(rate, sampleRate)` pairs are chosen for their
`halfBitSamples = sampleRate / (160 · fps)` remainder:

| rate | sampleRate | halfBitSamples | why |
| ---- | ---------- | -------------- | --- |
| 24 | 48000 | **12.5** | the banker's-rounding trap; every odd boundary is a `.5` |
| 25 | 48000 | 12.0 | exact — the control |
| 30 | 48000 | 10.0 | exact |
| 30df | 48000 | 10.0 | proves DF rides the 30 fps clock (ADR-019) |
| 24 | 44100 | 11.484375 | dyadic remainder, no `.5` ties |
| 25 | 44100 | 11.025 | non-dyadic — pins the accumulated `Double` error |
| 30 | 44100 | 9.1875 | dyadic |
| 24 | 96000 | 25.0 | exact at a second sample rate |

× `startLevel` ∈ {false, true} for the 24/48000 pair (proves the
`startLevel`/`endLevel` threading that `LTCFrameStream` and `LTCSchedule` are
built on), × one case at a non-default `amplitude` (0.9, the product default
from `LTCRoutingSettings`) to prove amplitude does not leak into run lengths.

## Contract: `golden/mtc-wire-v1.json`

```jsonc
{
  "contract": "mtc-wire",
  "version": 1,
  "cases": [
    { "label": "rateBits/30df", "op": "rateBits", "rate": "30df",
      "input": {}, "expect": { "byte": 2 } },
    { "label": "quarterFrame/24/23:59:59:23/piece7", "op": "quarterFrame",
      "rate": "24", "input": { "hours": 23, "minutes": 59, "seconds": 59,
      "frames": 23, "piece": 7 }, "expect": { "byte": 113 } },
    { "label": "quarterFrameSequence/25/01:02:03:04", "op": "quarterFrameSequence",
      "rate": "25", "input": { … }, "expect": { "bytes": [0,17,…] } },
    { "label": "fullFrame/30/17:00:00:00", "op": "fullFrame",
      "rate": "30", "input": { … },
      "expect": { "bytes": [240,127,127,1,1,241,0,0,0,247] } }
  ]
}
```

Case matrix — all four rates × `00:00:00:00`, `01:02:03:04`, `17:30:45:12`
(hours ≥ 16, so the hour's high bit rides in piece 7 next to the rate bits),
`23:59:59:max`. `quarterFrame` additionally covers `piece: -1` and `piece: 8` to
pin the clamp at `MTCFrame.swift:61`, which is behaviour a C# port would
plausibly write as an exception instead.

The C# translation hazards this catches: in C#, `byte << 1` and `byte >> 4`
promote to `int`, so every shift needs an explicit `(byte)` cast and an
unintended sign/width change is easy; `fullFrameBytes`' `(rateBits << 5) | (hours & 0x1F)`
is the worst of them.

## Work plan

Two issues (#853, #854), two PRs, the second rebased on the first. The bug fix is
independently shippable and should not wait behind a contract PR.

### #853 — `bug(ltc): the 25 fps parity bit is written at 27 instead of 59`

1. **Red.** New `test_frame_at25fps_writesCorrectionAtBit59_notBit27`: pick a
   25 fps timecode whose word-minus-correction has odd parity, assert
   `bits[59] == true && bits[27] == false`. Commit red separately.
2. **Green.** `LTCFrame.parityBitIndex(for rate:)` returns 59 for `.fps25`,
   27 otherwise; `init(timecode:)` uses it. Keep the existing
   `static let parityBitIndex = 27` only if something still needs it — otherwise
   remove it, since CI runs SwiftLint `--strict`.
3. Correct `test_frame_userAndFlagBits_areZero` per Finding 3 (`60..<64`, and
   the flag-bit assertions become rate-aware).
4. Parameterise `test_frame_parityBit27_…` over all four rates and rename it.

`LTCDecoder` needs **no** change: `hasEvenParity` counts ones across the whole
word and `isWellFormed` is position-agnostic, so decoding is unaffected in both
directions. Verify this claim with a decoder round-trip test at 25 fps before
claiming it.

### #854 — `chore(windows): pin the LTC and MTC wire formats as golden vectors`

1. Swift generator/guard suites (`LTCWireGoldenVectorTests.swift`,
   `MTCWireGoldenVectorTests.swift`), modelled line-for-line on
   `TimecodeGoldenVectorTests.swift` — they both *emit* the JSON from the Swift
   implementation and *guard* the committed file against drift.
2. `xcodegen generate` (new files; the `.xcodeproj` is not committed).
3. C# mirrors: `Ltc/LtcFrame.cs`, `Ltc/LtcEncoder.cs`, `Midi/MtcFrame.cs`.
4. C# verifier suites + DTOs (`LtcWireVector.cs`, `MtcWireVector.cs`), reusing
   `GoldenFiles` and `GoldenDouble`.

## Implementation traps

- **`Math.Round` is not `.rounded()`.** C# needs
  `Math.Round(x, MidpointRounding.AwayFromZero)`. This is the single most likely
  place the mirror goes wrong, and the reason the 24/48000 case exists.
- **`Int(x)` is not `(int)x` for negatives** — Swift's `Int(Double)` truncates
  toward zero and so does C#'s cast, so these agree; but `.rounded(.up)` is
  `Math.Ceiling`, not `Math.Round`. Only relevant in slice 2; noted so it is not
  re-derived later.
- **`Float` vs `float`.** `amplitude` is single-precision on both sides. Do the
  comparison at `float`, never at `double`.
- **Byte promotion in C#** (see the MTC section).
- **`precondition` vs exceptions.** Swift traps on `sampleRate <= 0`; the
  vectors must not contain such a case, and the C# mirror should throw rather
  than silently return empty, so a future bad caller fails the same way on both
  sides.
- **Vector regeneration must be a deliberate act.** The Swift suite writes the
  file only under the same opt-in the M0 suites use; a plain `xcodebuild test`
  must *fail* on drift, not quietly rewrite the contract. Confirm which
  mechanism `TimecodeGoldenVectorTests` uses and copy it exactly.

## Verification

- **Swift unit** — the two new golden suites + the corrected `LTCFrameTests`;
  run the full `OnlyCueTests` via `scripts/dev/test.sh` (runner-collision guard,
  `testmanagerd` reset, ad-hoc signing).
- **C# unit** — `dotnet test windows/` (currently 566 tests) must stay green and
  grow by the new case count.
- **SwiftLint `--strict`** — exit 0.
- **Mutation testing is mandatory, per the standing rule.** A green first run
  proves nothing. For each of the following, apply the mutant, `grep -n MUTANT`
  to prove it landed, run, confirm red, revert, `grep -c MUTANT` = 0:
  1. C# `LtcEncoder`: `Math.Round(x, AwayFromZero)` → plain `Math.Round(x)`.
     **Must** fail the 24 fps / 48 kHz case. If it does not, the vector is
     vacuous and the case matrix is wrong.
  2. C# `LtcFrame`: parity index hardcoded to 27 for all rates. Must fail the
     25 fps cases.
  3. C# `MtcFrame`: drop the `(byte)` cast on the piece-7 shift. Must fail.
  4. Swift `LTCFrame`: revert #853. Must fail the new Swift test *and* the
     Swift golden guard.
- **No UI tests involved**, so the usual "CI does not run UI tests on PRs"
  caveat does not apply to this slice.
- Both required checks — "Build & test (macOS, self-hosted)" and "Golden vectors
  (Windows, C# core)" — must be green, and the Windows job must be confirmed to
  have *executed* the new suites by name in its log, not merely to have passed.

## Open question for approval

#853 changes shipped LTC output at 25 fps. Nobody has reported a 25 fps
reader rejecting OnlyCue's LTC, so this is a spec-conformance fix rather than a
field-reported bug — worth stating plainly in the PR rather than implying a
user-visible symptom was observed.
