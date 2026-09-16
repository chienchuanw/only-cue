# Spec — pin the LTC decoder as a cross-platform contract (#728 M3 slice 3)

**Status:** approved
**Date:** 2026-09-16
**Epic:** #728 (Windows port)
**Milestone:** M3 — hardware (the issue title may say "M2"; see the note in slice 1's spec — the epic's M2 is *media*)
**Depends on:** #854 (wire contract), #859 (schedule contract)

## Goal

Pin `LTCDecoder` — the inverse of `LTCEncoder` / `LTCFrameStream` — as `golden/ltc-decode-v1.json`, and mirror it as `OnlyCue.Core.Ltc.LtcDecoder`. With this, the whole LTC path is pinned in both directions on both platforms: a Windows build can stripe a file *and* read one back and be provably byte-compatible with macOS.

Slices 1 and 2 pinned what OnlyCue **emits**. This slice pins what it **believes** when it reads — which is the harder half, because a decoder that is subtly wrong still returns plausible timecode on a clean signal and only diverges at the edges.

## Non-goals

- PLL jitter tracking, half-speed, or reverse playback. `LTCDecoder` explicitly does not do these (v1 is tuned for clean signals); pinning behaviour the type does not have would pin fiction.
- Analogue-style noise cases (added white noise, DC drift, amplitude ramps). Decided against: reproducing them cross-platform needs a seeded PRNG whose output is itself part of the contract, which pins the PRNG rather than the decoder. **Structural** corruption is deterministic, expressible in the vector, and is where ports actually break. (If a real-world misread is ever reported, add the offending buffer as a case — captured, not synthesised.)
- `LTCAudioReader` (the `AVAssetReader` front end). Hardware/AVFoundation-facing; Windows will have its own reader feeding the same `float[]`.
- `LTCBiphaseEncoder` — still outside the contract for the reason recorded in slice 1: no production caller, and `LTCEncoder` inlines its own modulation against fractional slot boundaries the primitive's `Int` half-bit cannot express.

## The hazards this contract exists to catch

Each of these is a place where a reasonable C# port silently differs. Every one gets at least one case whose expectation would change if the port got it wrong.

### 1. `rms` accumulates in `Double`, returns `Float`

```swift
var total = 0.0
for sample in samples { total += Double(sample) * Double(sample) }
return Float((total / Double(samples.count)).squareRoot())
```

The accumulation is `double`, the **narrowing happens once at the end**. A port that accumulates in `float` drifts on long buffers; one that keeps the result `double` computes a different threshold. Both change which transitions are found, and therefore every downstream result.

### 2. The threshold is computed in `Float`

`thresholdFraction: Float = 0.3` is not exactly 0.3, and `threshold = thresholdFraction * reference` is a **`Float` multiply**. `sample > threshold` then compares `float` to `float`. A port promoting to `double` compares against a different number. This matters only for samples landing within an ulp of the threshold — which is exactly what a case with amplitude tuned to sit on the boundary will produce.

### 3. The first latch is not a transition

```swift
if state <= 0, sample > threshold {
    if state != 0 { indices.append(index) }
    state = 1
}
```

The comparator starts at `state == 0`; the first latch sets the state **without** recording an index. A port that records it shifts every `startSample` and adds one leading interval to the histogram. Pinned by every case's `startSample`, and directly by a `transitions` op.

### 4. `silenceRMSFloor` rejects the whole buffer, not a block

`reference` is the RMS of the **entire** buffer and the floor is checked against it once. A port that windows the RMS re-introduces #793 (a block of pure noise has an RMS equal to the noise, so its threshold collapses to the noise floor). Pinned by a case with a loud LTC region and a long silent lead-in: the global reference must still clear the floor and the silence must still produce no transitions.

### 5. `estimateHalfBitSamples` — strict `<`, mean not median

`intervals.filter { Double($0) < 1.5 * Double(smallest) }`, then the arithmetic **mean** of that cluster. Strict `<`, so an interval at exactly `1.5 × smallest` is excluded. At 48 kHz / 24 fps the half-bit is exactly 12.5 samples, so intervals alternate 12 and 13 and the cluster boundary is 18.0 — no tie there — but at 44.1 kHz the intervals spread and the boundary is reachable. A port using `<=`, or a median, or integer division for the mean, differs.

### 6. `framesPerSecond` rounds half away from zero

```swift
let framesPerSecond = Int((bitRate / 80.0).rounded())
```

Same Swift-vs-.NET rounding hazard as slices 1 and 2, now deciding the **rate**, so getting it wrong does not shift a sample — it returns the wrong framerate or `nil`.

### 7. `demodulate` — the trailing-`1` guard

```swift
} else if halfBits >= 0.5, halfBits < 1.5, index + 1 < transitions.count {
```

A `1` consumes **two** intervals, so the final `1` in the stream is only emitted if a transition follows it. A port that drops `index + 1 < transitions.count` emits one extra bit at the end, which shifts the last 80-bit window and can manufacture or destroy a final frame. Pinned by a case truncated immediately after a frame.

The interval classification bounds are also exact and exclusive-on-the-right: `[1.5, 2.5)` → `0`, `[0.5, 1.5)` → `1`, anything else → dropped and re-synced by advancing one.

### 8. `extractFrames` advances 80 on a **sync match**, not on a **valid frame**

```swift
if Array(window[64..<80]) == LTCFrame.syncWord {
    let frame = LTCFrame(bits: window)
    if frame.isWellFormed, let timecode = ... { frames.append(...) }
    end += 80        // <- outside the isWellFormed check
} else {
    end += 1
}
```

A frame with a good sync word but **bad parity** is not merely dropped: it consumes its 80 bits and the search resumes after it. A port that puts `end += 80` inside the validity check keeps searching bit-by-bit through a corrupted frame and can lock onto a spurious window. This is the single most likely place to get the port "nearly right", and it is invisible on clean signals — so it needs a dedicated case: a run of good frames with one parity bit flipped in the middle, asserting that the frames **after** the bad one are still recovered at their correct sample offsets.

### 9. Guard arithmetic at the entry

`transitions.count >= 3`, `bits.count >= 80`, `smallest > 0`, `sampleRate > 0` (a `precondition` on macOS → `ArgumentOutOfRangeException` in C#, per the convention slices 1 and 2 established).

## Contract format — `golden/ltc-decode-v1.json`

```
{
  "contract": "ltc-decode",
  "version": 1,
  "note": "...",
  "cases": [ { "label", "op", "input", "expect" } ]
}
```

**Input signals are described, never listed sample-by-sample.** A case names a *recipe* — the same run-length spelling slice 1 used for PCM, plus the generator parameters — and both sides build the identical `float[]` from it. This keeps the file readable and keeps the signal itself pinned:

```
"input": {
  "rate": "24", "sampleRate": 48000, "amplitude": 0.8,
  "timecode": [1, 2, 3, 4], "frameCount": 4,
  "leadSilenceSamples": 0, "trailSilenceSamples": 0,
  "truncateToSamples": null,
  "flipBitInFrame": null, "flipBitIndex": null,
  "scaleAmplitudeBy": null, "offsetBy": null
}
```

The builder is `LTCFrameStream(...).samples(frameCount:)` with the listed mutations applied in a fixed order (documented in the generator and mirrored verbatim). `flipBitInFrame` / `flipBitIndex` re-encode one frame from a mutated `LTCFrame` rather than editing samples, so "bad parity" means a genuinely mis-parity word, not a smeared waveform.

### Ops

| `op` | Asserts | Why it exists |
|---|---|---|
| `decode` | the full `[{timecode, startSample}]` list | the headline behaviour; every case has one |
| `transitions` | `count`, plus the first and last 8 indices, plus the full index list when short | isolates hazards 1–4 from everything downstream — if this op fails, the comparator is wrong and the `decode` failures are consequences, not separate bugs |
| `halfBit` | the estimate as a `GoldenDouble` bit pattern | isolates hazard 5; a bit-exact double, because the mean is where an ordering difference shows up first |
| `framesPerSecond` | the recovered integer rate | isolates hazard 6 |
| `bits` | the demodulated bit count and the bit string's first/last 96 bits | isolates hazard 7 |

Splitting the pipeline into ops is deliberate: a single `decode` op would make every hazard fail the same way, and the mutation step could not tell them apart.

### Case matrix

**Clean round-trip** — the positive core:
- every rate (24 / 25 / 30 / 30df) × sample rates 48000 and 44100, `frameCount = 4`, starting `01:00:00:00` and `00:00:59:28` (so a second/minute boundary is crossed).
- one long case: 30 fps @ 48 kHz, `frameCount = 30` — a full second, to catch drift that a 4-frame case hides.
- amplitude 0.8 (the default) and 0.25 (proves the threshold is relative, not absolute).

**Structural corruption** — the negative core, each asserting exactly what survives:
- `parity-flipped-middle-frame` — 4 frames, one data bit flipped in frame 2 so parity goes odd. Expect frames 1, 3, 4 at their correct `startSample`s. (Hazard 8.)
- `sync-word-broken` — one sync bit flipped. Expect the window never matches there; the decoder re-searches bit-by-bit.
- `bcd-out-of-range` — a frames field forced to 31 with parity re-corrected, so the word is *well-formed* but `timecode(framesPerSecond:)` returns `nil`. Proves validity and range are two separate gates.
- `truncated-mid-frame` — cut at 2.5 frames.
- `truncated-immediately-after-a-frame` — cut on the last transition. (Hazard 7.)
- `silence-only` — all zeros; expect `[]` and zero transitions.
- `silence-lead-in` — 24 000 zero samples then 4 frames; the global RMS must still clear the floor and the frames must decode with `startSample` offset by the lead. (Hazard 4.)
- `below-silence-floor` — a real LTC signal scaled to amplitude `5e-5`, under `silenceRMSFloor`. Expect `[]`. The neighbouring case at `2e-4` must decode, so the floor's *position* is pinned, not just its existence.
- `dc-offset` — the whole buffer shifted by +0.5. The comparator is symmetric about zero and has no DC blocker, so this is expected to **fail to decode**; pinning it stops a port from "helpfully" adding a DC blocker and silently diverging.
- `too-few-transitions` — a 3-sample buffer.

Estimated ~110–130 cases across the five ops.

## C# surface

New in `OnlyCue.Core`:

- `Ltc/LtcDecoder.cs` — `public static DecodedFrame[] Decode(float[] samples, double sampleRate)`, `readonly record struct DecodedFrame(Timecode Timecode, int StartSample)`, plus seams for the four intermediate ops.
  - The Swift helpers are `private`, so the mirrors should be `internal` rather than `public` — pinning an intermediate is not a reason to widen the shipping surface. **`InternalsVisibleTo` is not configured today** (checked: `windows/OnlyCue.Core/OnlyCue.Core.csproj` has only `TargetFramework` / `ImplicitUsings` / `Nullable`, and nothing in the tree references the attribute). Adding it is therefore part of this slice — a single `<ItemGroup><InternalsVisibleTo Include="OnlyCue.Core.Tests" /></ItemGroup>`, which the .NET SDK turns into the assembly attribute. No other mirror needs it, so this is the first use and should be called out in the PR rather than slipped in.
- `Ltc/LtcFrame.cs` — **extended**, not rewritten: `FromBits`, `IsWellFormed`, `Frames` / `Seconds` / `Minutes` / `Hours` / `IsDropFrame`, and `ToTimecode(int framesPerSecond)`. The existing remark says the decode-side accessors "have no caller here yet"; that stops being true, and the remark must be updated in the same commit.
- `SmpteFramerateExtensions.Matching(int framesPerSecond, bool isDropFrame)` → `SmpteFramerate?`.

## Verification

Same protocol as slices 1 and 2, and the same standard of proof.

1. Swift generator first, red (no golden file), then bootstrap and commit the file as its own commit.
2. `test_committedVectors_matchCurrentSwiftOutput` guards the file thereafter.
3. Independent fixed pins on both sides, hand-computed from the pipeline rather than read off the golden file — at minimum: the 12.5-sample half-bit at 24 fps / 48 kHz, the first-latch-is-not-a-transition rule, and the advance-80-on-sync rule.
4. C# mirror + verifier suite; `dotnet test windows/` green.
5. **Mutation testing is mandatory.** A green first run proves nothing. For each mutant: apply, `grep -n MUTANT` to prove it landed, run, confirm red **and record which tests went red by grepping the failure lines, not the started lines**, revert, `grep -c MUTANT` = 0.
6. Predictions below are **hypotheses, not requirements**. Slice 2 falsified two of its own. If a mutant survives, the rule is: **prove equivalence over the reachable domain empirically, or fix the contract** — never assume the survivor is harmless, and never delete the finding. Record the outcome either way, in the PR body and in the code comment that made the claim.
7. Full `OnlyCueTests` green; `swiftlint lint --strict` exit 0.
8. Confirm the Windows CI log **executed** the new suite by name with the expected case count — counted from the log, not inferred from a green tick.

### Mutants

| # | Mutant | Prediction |
|---|---|---|
| 1 | `rms` accumulates in `float` | red on the long (30-frame) case at minimum |
| 2 | `threshold` computed in `double` | red on the boundary-amplitude case |
| 3 | record the first latch as a transition | red on every `transitions` and every `decode` case (`startSample` shifts) |
| 4 | RMS windowed per 1024 samples instead of global | red on `silence-lead-in`; **must not** be green-by-luck on `silence-only` |
| 5 | `<=` instead of `<` in the half-bit cluster filter | red on a 44.1 kHz case; the 48 kHz cases are the control |
| 6 | banker's rounding for `framesPerSecond` | red wherever `bitRate / 80` is a tie; if **no** case produces a tie, that is a gap in the matrix — add one or prove none is reachable |
| 7 | drop the `index + 1 < transitions.count` guard | red on `truncated-immediately-after-a-frame` |
| 8 | move `end += 80` inside the `isWellFormed` check | red on `parity-flipped-middle-frame`; the clean cases are the control |
| 9 | `end += 1` after a sync match (never skip) | red on the clean cases too — a spurious re-lock |
| 10 | drop the `silenceRMSFloor` check | red on `silence-only` and `below-silence-floor` |

Mutant 6 carries an explicit instruction because slice 2 taught the lesson: if a mutant cannot go red, the honest conclusion may be that the case matrix is incomplete rather than that the mutant is harmless. Decide which, with evidence, and say so.

## Deliverables

1. `OnlyCueTests/LTCDecodeGolden.swift` + `LTCDecodeGoldenVectorTests.swift` (generator; red first).
2. `golden/ltc-decode-v1.json` (own commit).
3. `windows/OnlyCue.Core/Ltc/LtcDecoder.cs`, the `LtcFrame` extension, `SmpteFramerateExtensions.Matching`, and the verifier suite.
4. `docs/architecture.md` — extend the Decoder row.
5. PR via `.github/PULL_REQUEST_TEMPLATE/chore.md`, disclosing every mutation outcome including survivors.
