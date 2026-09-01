# LTC Noise Immunity and the Striped Valid Range — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `LTCDecoder` immune to the dither in an mp3's silent lead-in, then measure and honour the timecode's true extent so the readout blanks outside it, with a user-authored channel override.

**Architecture:** A hysteresis comparator (Schmitt trigger) replaces the bare zero-crossing detector at the front of `LTCDecoder`, gated on a global RMS reference. Detection becomes two-phase: the existing 10 s / 60 s scan (Phase 1) publishes a readout immediately, then a background full-file pass on the known channel (Phase 2) measures `validFrom` / `validUntil` and replaces the cached track. A new `MediaItem.ltcChannelSelection` (schema v23) lets the user name the LTC channel, which skips Phase 1 and sends Phase 2 straight at that channel.

**Tech Stack:** Swift 5.9, SwiftUI, AVFoundation (`AVAssetReader` via `AudioSampleReader`), XCTest / XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-01-ltc-noise-immunity-and-valid-range-design.md`

**Issue:** https://github.com/chienchuanw/only-cue/issues/793 — branch `issues/793`.

## Global Constraints

- **Threshold formula, verbatim from spec §1:** `threshold = 0.3 * rms(samples)`.
- **Silence floor:** a buffer whose RMS is below `1e-4` yields *no* transitions at all.
- **The reference amplitude is computed over the whole buffer and must stay global.** A per-block adaptive reference re-introduces this exact bug: a block of pure noise has an RMS equal to the noise, so the threshold collapses to the noise floor. Task 1 pins this with a test — do not "optimise" it into a sliding window.
- **`estimateHalfBitSamples` keeps its minimum anchor.** The histogram-mode alternative was tested against the real file and rejected (spec "Approaches considered", candidate B). Do not re-attempt it.
- Schema change: `ProjectModel.currentSchemaVersion` 22 → 23, with a migration file. No schema change without both (project rule, `docs/data-model.md`).
- macOS deployment target stays at 14.0 (ADR-001). No App Sandbox entitlements (ADR-007). No media embedded in `.cuelist` (ADR-006).
- `TransportControls.swift`, `PreviewPane.swift` and `ItemListPane.swift` are inside `TokenConformanceTests.mainWindowFiles` — edits there must use `DS.*` tokens, never raw `Color.` / `.font(.system(size:` / magic-number `.padding`. **`MediaEditSheet.swift` is NOT in that list** (verified: `OnlyCueTests/DesignSystem/TokenConformanceTests.swift`), so the new picker carries no token obligation. This resolves the open check in spec §4.
- All new mutation of `ProjectModel` goes through `CueCommands` (project rule). No direct `document.model` writes from views.
- After creating any new source file, run `xcodegen generate` — `OnlyCue.xcodeproj/` is not committed and new files are picked up by folder rule only on regeneration.
- Commits: Conventional Commits, lowercase after the prefix, imperative. **No `Co-Authored-By`, signatures, or attribution of any kind.** Stage files by explicit path — never `git add .` / `-A` / `--all`.
- **The reporter's mp3 is copyrighted and 11 MB. It must never enter the repository.** Every test in this plan is synthetic. The real file is used only for the final manual check.
- There is no `make check` target in this repo (the Makefile has only `generate`, `open`, `xcode`). Verification uses the CI's own invocations:

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueTests -parallel-testing-enabled NO
```

To run a single test while iterating, append the identifier:
`-only-testing:OnlyCueTests/LTCDecoderTests/test_decode_ltcPrecededBySilentLeadIn_stillDecodes`.

## Deviations from the spec, flagged for review

Two statements in spec §4 do not survive contact with the code. Both are called out here rather than silently resolved — a reviewer can reject either.

1. **"`PreviewPane` follows the same rule" has nothing to apply to.** `PreviewPane`'s only LTC surface is `ltcDetectedBadge(track:)` at `OnlyCue/UI/PreviewPane.swift:340-369`, which renders `track.anchorTimecode` — the *detected start*, a static value, not a playhead-following readout. There is no position-dependent readout there to blank. Task 7 therefore changes `TransportControls` only.
2. **Spec §2's "the UI warns" on a discontinuous track** is satisfied by the extent range in the `MediaEditSheet` status line (Task 6): a range visibly shorter than the media on a long file *is* the warning. No separate persisted "truncated" flag is introduced. If a reviewer wants an explicit warning, that is a follow-up issue, not a silent omission.

## File Structure

**Create:**

| File | Responsibility |
| --- | --- |
| `OnlyCue/Document/LTCChannelSelection.swift` | The `auto` / `channel(n)` / `none` enum and its explicit `Codable` conformance. |
| `OnlyCue/Document/ProjectModel+MigrationV22.swift` | v22 → v23 re-stamp migration. |
| `OnlyCue/LTC/LTCExtentLabel.swift` | Pure formatter turning `validFrom` / `validUntil` into `00:00:02.0 – 00:04:51.1`. |
| `OnlyCueTests/LTCExtentLabelTests.swift` | Unit tests for the formatter. |
| `OnlyCueTests/ProjectModelMigrationV23Tests.swift` | v22 → v23 migration + round-trip tests. |
| `OnlyCueTests/LTCChannelSelectionTests.swift` | Codable round-trip for the enum, including `.channel(n)`. |
| `OnlyCueTests/LTCFullFileAnalysisTests.swift` | `analyzeFullFile` extent + run-trimming tests. |

**Modify:**

| File | Change |
| --- | --- |
| `OnlyCue/LTC/LTCDecoder.swift` | Schmitt-trigger front end; corrected doc comment. |
| `OnlyCue/LTC/StripedTimecodeTrack.swift` | `validFrom` / `validUntil` / `isValid(atPlaybackSeconds:)`; full-file initialiser. |
| `OnlyCue/LTC/LTCAudioReader.swift` | `analyzeFullFile(from:channel:)` and run trimming. |
| `OnlyCue/LTC/StripedTimecodeCache.swift` | `store(_:for:)` setter so Phase 2 can replace a cached track. |
| `OnlyCue/LTC/TimecodeReadout.swift` | `outOfRange` constant. |
| `OnlyCue/Document/MediaItem.swift` | `ltcChannelSelection` field, `CodingKeys`, coding. |
| `OnlyCue/Document/ProjectModel.swift` | `currentSchemaVersion` 22 → 23. |
| `OnlyCue/Document/ProjectModel+Migration.swift` | Dispatch `case 22`. |
| `OnlyCue/Commands/CueCommands+LTC.swift` | `setLTCChannelSelection` (undoable) and `refineRememberedLTC`. |
| `OnlyCue/Commands/MediaImporter.swift` | Selection-aware Phase 1/2 branch; `audioChannelCount(for:)`. |
| `OnlyCue/UI/StripedTimecodeHost.swift` | Kick off Phase 2 after Phase 1 lands. |
| `OnlyCue/UI/MediaEditSheet.swift` | Channel picker; extent in the status line. |
| `OnlyCue/UI/ItemListPane.swift` | Wire `onSelectLTCChannel`. |
| `OnlyCue/UI/TransportControls.swift` | Blank the readout outside the valid range. |
| `docs/data-model.md` | Document the v23 field and migration. |

Task order is a dependency chain: 1 (decoder) → 2 (track shape) → 3 (Phase 2) → 4 (persistence) → 5 (command) → 6 (sheet UI) → 7 (readout). Each task ends green and committable on its own.

---

### Task 1: Noise-immune decoder front end

This is the whole bug fix. Everything after it is the feature the fix makes possible.

**Files:**
- Modify: `OnlyCue/LTC/LTCDecoder.swift` — `transitionIndices(in:)` and the `estimateHalfBitSamples` doc comment
- Test: `OnlyCueTests/LTCDecoderTests.swift` (existing file, append)

**Interfaces:**
- Consumes: `LTCFrameStream(startTimecode:sampleRate:)` / `.samples(frameCount:)` and the `tc(_:_:_:_:_:)` helper, both already in `LTCDecoderTests.swift`.
- Produces: `LTCDecoder.silenceRMSFloor: Float` (`internal`, so tests can reference it) and the unchanged public entry point `LTCDecoder.decode(samples:sampleRate:) -> [DecodedFrame]`.

- [ ] **Step 1: Write the failing test**

Append to `OnlyCueTests/LTCDecoderTests.swift`. The dither helper is deterministic on purpose — alternating sign gives a one-sample transition interval, the exact worst case measured in the reporter's file, and it never flakes.

```swift
// MARK: - Silent lead-in (#793)

/// Mimics the dither mp3 decoding leaves in "digital silence": amplitude
/// 2e-5 with the sign flipping every sample. The real file measured a
/// 2.35e-5 peak with 95998 of 96000 samples non-zero; alternating signs
/// is that case at its worst, and is deterministic.
private func silenceDither(seconds: Double, sampleRate: Double) -> [Float] {
    let count = Int(seconds * sampleRate)
    return (0..<count).map { $0 % 2 == 0 ? Float(2e-5) : Float(-2e-5) }
}

func test_decode_ltcPrecededBySilentLeadIn_stillDecodes() {
    let sampleRate = 48_000.0
    let start = tc(8, 0, 0, 18, .fps30)
    let stream = LTCFrameStream(startTimecode: start, sampleRate: sampleRate)
    let samples = silenceDither(seconds: 2.0, sampleRate: sampleRate)
        + stream.samples(frameCount: 30)

    let frames = LTCDecoder.decode(samples: samples, sampleRate: sampleRate)

    XCTAssertGreaterThanOrEqual(frames.count, 28, "expected ~30 frames, got \(frames.count)")
    XCTAssertEqual(frames.first?.timecode.rate, .fps30)
    XCTAssertEqual(frames.first?.timecode, start)
    XCTAssertGreaterThanOrEqual(
        frames.first?.startSample ?? 0, 96_000 - 100,
        "the first frame must sit after the 2 s lead-in, not inside it"
    )
}

func test_decode_pureSilenceDither_findsNothing() {
    // Pins the global-reference constraint: a buffer that is *only* noise
    // must be rejected by the RMS floor, not normalised up to it.
    let samples = silenceDither(seconds: 2.0, sampleRate: 48_000.0)
    XCTAssertTrue(LTCDecoder.decode(samples: samples, sampleRate: 48_000.0).isEmpty)
}

func test_decode_loudNonLTCTone_findsNoFrames() {
    // The more permissive front end must not invent frames in music.
    let sampleRate = 48_000.0
    let samples = (0..<Int(sampleRate * 2)).map { index in
        Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
    }
    XCTAssertTrue(LTCDecoder.decode(samples: samples, sampleRate: sampleRate).isEmpty)
}
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:OnlyCueTests/LTCDecoderTests
```

Expected: `test_decode_ltcPrecededBySilentLeadIn_stillDecodes` fails with `got 0` (the min-anchor collapses the half-bit estimate to 1.0, so nothing demodulates). The other two already pass — they are regression guards, not red tests.

- [ ] **Step 3: Commit the failing test**

```bash
git add OnlyCueTests/LTCDecoderTests.swift
git commit -m "test(ltc): show a silent mp3 lead-in defeats the decoder"
```

- [ ] **Step 4: Implement the hysteresis comparator**

In `OnlyCue/LTC/LTCDecoder.swift`, add the two constants and the `rms` helper next to `transitionIndices`, and replace the body of `transitionIndices(in:)` entirely:

```swift
/// A buffer whose RMS falls below this carries no signal worth decoding.
/// Four times above the dither peak measured in a real Logic Pro mp3
/// export (2.35e-5) and three and a half orders of magnitude below that
/// file's LTC (RMS 0.33). Rejecting such a buffer outright is what stops
/// an all-silent channel from having its own noise amplified into a
/// threshold. See #793.
static let silenceRMSFloor: Float = 1e-4

/// Fraction of the reference amplitude at which the comparator latches.
/// Verified correct across a 20x span (0.02...0.40) against a real file:
/// the LTC channel decoded 226-227 frames at every setting and the music
/// channel decoded none.
private static let thresholdFraction: Float = 0.3

private static func rms(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    var total = 0.0
    for sample in samples { total += Double(sample) * Double(sample) }
    return Float((total / Double(samples.count)).squareRoot())
}

/// Indices where the signal crosses a hysteresis comparator.
///
/// A bare zero-crossing detector has no noise immunity: the dither in a
/// decoded mp3's silent lead-in flips sign every sample or two, which
/// swamps the interval statistics the demodulator depends on. Latching
/// only past +/- `thresholdFraction * rms` gates that out.
///
/// The reference amplitude is deliberately computed over the WHOLE
/// buffer and must stay global. A per-block adaptive reference
/// re-introduces the bug: a block of pure noise has an RMS equal to the
/// noise, so its threshold collapses to the noise floor.
private static func transitionIndices(in samples: [Float]) -> [Int] {
    let reference = rms(samples)
    guard reference >= silenceRMSFloor else { return [] }
    let threshold = thresholdFraction * reference

    var indices: [Int] = []
    var state = 0
    for (index, sample) in samples.enumerated() {
        if state <= 0, sample > threshold {
            if state != 0 { indices.append(index) }
            state = 1
        } else if state >= 0, sample < -threshold {
            if state != 0 { indices.append(index) }
            state = -1
        }
    }
    return indices
}
```

Then correct the lie in the `estimateHalfBitSamples` doc comment — it currently claims the estimate comes "from the transition-interval histogram". Replace that sentence with:

```swift
/// Estimates the half-bit period from the shortest transition intervals.
/// Biphase-mark encoding emits one transition per `0` bit and two per `1`,
/// so the shortest intervals are the half-bit period; the estimate is the
/// mean of every interval within 1.5x of the minimum. This is only sound
/// because `transitionIndices` gates out noise first — an ungated minimum
/// collapses to 1 sample (#793).
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:OnlyCueTests/LTCDecoderTests \
  -only-testing:OnlyCueTests/LTCAudioReaderTests
```

Expected: PASS, including every pre-existing round-trip test in both classes. `LTCAudioReaderTests` is included because it exercises the same front end through the WAV fixtures — if the comparator broke clean-signal decoding, it shows up there.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/LTC/LTCDecoder.swift
git commit -m "fix(ltc): gate the decoder front end with a hysteresis comparator"
```

---

### Task 2: `validFrom` / `validUntil` on the striped track

**Files:**
- Modify: `OnlyCue/LTC/StripedTimecodeTrack.swift`
- Test: `OnlyCueTests/StripedTimecodeTrackTests.swift` (existing file — append)

**Interfaces:**
- Consumes: `LTCDecoder.DecodedFrame` (`timecode: Timecode`, `startSample: Int`), `LTCAudioReader.DetectionResult` (`channel: Int`, `frames: [LTCDecoder.DecodedFrame]`).
- Produces:
  - `StripedTimecodeTrack.validFrom: TimeInterval?` and `.validUntil: TimeInterval?` — `nil` means unbounded.
  - `func isValid(atPlaybackSeconds: TimeInterval) -> Bool`
  - `init(anchorTimecode:anchorPlaybackSeconds:ltcChannel:validFrom:validUntil:)` — the last three all defaulted, so every existing call site compiles untouched.
  - `init?(fullFileFrames: [LTCDecoder.DecodedFrame], channel: Int, sampleRate: Double)` — used by Task 3.

Both bounds are `TimeInterval?` so Swift's synthesised `Codable` uses `decodeIfPresent` / `encodeIfPresent`. Documents saved before this change carry neither key, decode as `nil`, and therefore keep today's extrapolate-everywhere behaviour. That is why no `MediaItem` schema bump is needed for *this* task — the change is additive inside an already-optional stored value.

- [ ] **Step 1: Write the failing test**

```swift
// MARK: - Valid range (#793)

func test_isValid_withNoBounds_isAlwaysValid() {
    let track = StripedTimecodeTrack(
        anchorTimecode: Timecode(frameCount: 0, rate: .fps30),
        anchorPlaybackSeconds: 0
    )
    XCTAssertTrue(track.isValid(atPlaybackSeconds: 0))
    XCTAssertTrue(track.isValid(atPlaybackSeconds: 10_000))
}

func test_isValid_respectsBothBounds() {
    let track = StripedTimecodeTrack(
        anchorTimecode: Timecode(frameCount: 0, rate: .fps30),
        anchorPlaybackSeconds: 2.0,
        validFrom: 2.0,
        validUntil: 291.1
    )
    XCTAssertFalse(track.isValid(atPlaybackSeconds: 1.99))
    XCTAssertTrue(track.isValid(atPlaybackSeconds: 2.0))
    XCTAssertTrue(track.isValid(atPlaybackSeconds: 291.1))
    XCTAssertFalse(track.isValid(atPlaybackSeconds: 291.2))
}

func test_initFullFileFrames_derivesBothBoundsFromFirstAndLastFrame() {
    let sampleRate = 48_000.0
    let frames = [
        LTCDecoder.DecodedFrame(
            timecode: Timecode(frameCount: 30, rate: .fps30), startSample: 96_000
        ),
        LTCDecoder.DecodedFrame(
            timecode: Timecode(frameCount: 31, rate: .fps30), startSample: 97_600
        )
    ]
    let track = StripedTimecodeTrack(
        fullFileFrames: frames, channel: 1, sampleRate: sampleRate
    )
    XCTAssertEqual(track?.ltcChannel, 1)
    XCTAssertEqual(track?.validFrom ?? -1, 2.0, accuracy: 0.001)
    // last frame start (97600/48000) plus one frame of duration (1/30)
    XCTAssertEqual(track?.validUntil ?? -1, 2.0666 + 0.0333, accuracy: 0.002)
}

func test_track_roundTripsBoundsThroughCoding() throws {
    let track = StripedTimecodeTrack(
        anchorTimecode: Timecode(frameCount: 5, rate: .fps30),
        anchorPlaybackSeconds: 1.0,
        ltcChannel: 1,
        validFrom: 1.0,
        validUntil: 9.0
    )
    let data = try JSONEncoder().encode(track)
    XCTAssertEqual(try JSONDecoder().decode(StripedTimecodeTrack.self, from: data), track)
}

func test_track_savedBeforeThisChange_decodesUnbounded() throws {
    // A rememberedLTC persisted by v22 carries neither key.
    let json = """
    {"anchorTimecode":{"frameCount":5,"rate":"fps30"},\
    "anchorPlaybackSeconds":1,"ltcChannel":1}
    """.data(using: .utf8)!
    let track = try JSONDecoder().decode(StripedTimecodeTrack.self, from: json)
    XCTAssertNil(track.validFrom)
    XCTAssertNil(track.validUntil)
    XCTAssertTrue(track.isValid(atPlaybackSeconds: 12_345))
}
```

If `Timecode`'s own `Codable` representation differs from the literal above, run the encoder once and paste what it actually emits — do not adjust `Timecode` to fit the test.

- [ ] **Step 2: Run the tests and watch them fail**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
```

Expected: the build fails — `validFrom` is not a member. A compile failure is the red state for an additive-API task.

- [ ] **Step 3: Add the bounds**

In `StripedTimecodeTrack.swift`, add the two stored properties after `ltcChannel`, extend the memberwise initialiser with defaulted parameters (append them last so existing positional calls still resolve), and add the predicate:

```swift
/// First playback second at which this track's timecode is real.
/// `nil` means unbounded — either not yet measured (between Phase 1 and
/// Phase 2 completing) or loaded from a document saved before #793.
let validFrom: TimeInterval?

/// Last playback second at which this track's timecode is real.
/// `nil` means unbounded, exactly as `validFrom`.
let validUntil: TimeInterval?

init(
    anchorTimecode: Timecode,
    anchorPlaybackSeconds: TimeInterval,
    ltcChannel: Int = 0,
    validFrom: TimeInterval? = nil,
    validUntil: TimeInterval? = nil
) {
    self.anchorTimecode = anchorTimecode
    self.anchorPlaybackSeconds = anchorPlaybackSeconds
    self.ltcChannel = ltcChannel
    self.validFrom = validFrom
    self.validUntil = validUntil
}

/// Whether the timecode this track reports at `seconds` was actually
/// measured from the file, as opposed to extrapolated past the end of
/// the stripe. Unbounded on either side means "assume valid".
func isValid(atPlaybackSeconds seconds: TimeInterval) -> Bool {
    if let validFrom, seconds < validFrom { return false }
    if let validUntil, seconds > validUntil { return false }
    return true
}
```

Then set `validFrom` in the existing `init?(decodedFrames:sampleRate:)` — it knows the first frame, so it can bound the start, but a windowed scan cannot bound the end:

```swift
// Phase 1 sees only the head of the file: it can bound the start but
// not the end, so validUntil stays nil (unbounded) until the full-file
// pass in MediaImporter measures it.
self.validFrom = Double(first.startSample) / sampleRate
self.validUntil = nil
```

Finally add the full-file initialiser:

```swift
/// Builds a track from a decode of the entire file, so both bounds are
/// measured rather than assumed. `validUntil` extends one frame past the
/// last frame's start, because that frame occupies real time.
init?(fullFileFrames frames: [LTCDecoder.DecodedFrame], channel: Int, sampleRate: Double) {
    guard let first = frames.first, let last = frames.last else { return nil }
    self.anchorTimecode = first.timecode
    self.anchorPlaybackSeconds = Double(first.startSample) / sampleRate
    self.ltcChannel = channel
    self.validFrom = Double(first.startSample) / sampleRate
    self.validUntil = Double(last.startSample) / sampleRate
        + 1.0 / Double(last.timecode.rate.framesPerSecond)
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:OnlyCueTests
```

Expected: PASS. The full suite runs here rather than one class, because widening a memberwise initialiser can break call sites anywhere.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/LTC/StripedTimecodeTrack.swift OnlyCueTests/StripedTimecodeTrackTests.swift
git commit -m "feat(ltc): record the measured valid range on a striped track"
```

---

### Task 3: Phase 2 — the background full-file pass

Phase 1 (the 10 s / 60 s scan) is unchanged and still publishes a readout immediately. Phase 2 decodes the one known channel across the whole file to measure the true extent, then replaces the cached and remembered track.

**Files:**
- Modify: `OnlyCue/LTC/LTCAudioReader.swift`
- Modify: `OnlyCue/LTC/StripedTimecodeCache.swift`
- Modify: `OnlyCue/Commands/CueCommands+LTC.swift`
- Modify: `OnlyCue/UI/StripedTimecodeHost.swift`
- Create: `OnlyCueTests/LTCFullFileAnalysisTests.swift`

**Interfaces:**
- Consumes: `StripedTimecodeTrack.init?(fullFileFrames:channel:sampleRate:)` (Task 2); `AudioSampleReader.readInterleavedSamples(from:channels:range:)`, `.channelCount(of:)`, `.channel(_:of:in:)`, `.sampleRate`; the existing `LTCAudioReader.DetectionResult` and `isCorroborated(_:)`.
- Produces:
  - `LTCAudioReader.analyzeFullFile(from url: URL, channel: Int) async throws -> DetectionResult?`
  - `StripedTimecodeCache.store(_ track: StripedTimecodeTrack?, for id: MediaItem.ID)`
  - `CueCommands.refineRememberedLTC(_ track: StripedTimecodeTrack, forItemID: MediaItem.ID, document: CueListDocument)`

`refineRememberedLTC` exists because `rememberLTC` is deliberately write-once (`guard ... rememberedLTC == nil`) — Phase 1 has already filled the slot by the time Phase 2 finishes, so Phase 2 cannot use it. The refinement is guarded to the *same channel*, so it upgrades a Phase 1 result with measured bounds and never overwrites a different channel's answer.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/LTCFullFileAnalysisTests.swift`. It reuses the WAV helpers already in `LTCAudioReaderTests.swift` — copy `tc`, `writeWav(channels:sampleRate:)` and `makeFormat(channels:sampleRate:)` in if they are `private` there, rather than widening their access.

```swift
import XCTest
@testable import OnlyCue

final class LTCFullFileAnalysisTests: XCTestCase {

    private let sampleRate = 48_000.0

    /// Two channels: 0 is a tone, 1 is silence-then-LTC-then-silence. The
    /// full-file pass must find the middle run and bound it on both sides.
    func test_analyzeFullFile_measuresTheExtentOfATrailingSilentTail() async throws {
        let start = tc(8, 0, 0, 0, .fps30)
        let ltc = LTCFrameStream(startTimecode: start, sampleRate: sampleRate)
            .samples(frameCount: 60)                       // 2 s of LTC
        let silence = [Float](repeating: 0, count: Int(sampleRate))  // 1 s
        let ltcChannel = silence + ltc + silence
        let tone = (0..<ltcChannel.count).map { index in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
        }

        let url = try writeWav(channels: [tone, ltcChannel], sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await LTCAudioReader.analyzeFullFile(from: url, channel: 1)

        let unwrapped = try XCTUnwrap(result)
        XCTAssertEqual(unwrapped.channel, 1)
        XCTAssertGreaterThanOrEqual(unwrapped.frames.count, 55)
        let first = try XCTUnwrap(unwrapped.frames.first)
        let last = try XCTUnwrap(unwrapped.frames.last)
        XCTAssertEqual(Double(first.startSample) / sampleRate, 1.0, accuracy: 0.05)
        XCTAssertEqual(Double(last.startSample) / sampleRate, 3.0, accuracy: 0.1)
    }

    func test_analyzeFullFile_onAChannelWithoutLTC_returnsNil() async throws {
        let ltc = LTCFrameStream(startTimecode: tc(8, 0, 0, 0, .fps30), sampleRate: sampleRate)
            .samples(frameCount: 60)
        let tone = (0..<ltc.count).map { index in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(index) / sampleRate))
        }
        let url = try writeWav(channels: [tone, ltc], sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await LTCAudioReader.analyzeFullFile(from: url, channel: 0)
        XCTAssertNil(result)
    }

    func test_analyzeFullFile_outOfRangeChannel_returnsNil() async throws {
        let ltc = LTCFrameStream(startTimecode: tc(8, 0, 0, 0, .fps30), sampleRate: sampleRate)
            .samples(frameCount: 30)
        let url = try writeWav(ltc, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await LTCAudioReader.analyzeFullFile(from: url, channel: 7)
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
```

Expected: build failure — `analyzeFullFile` does not exist. Run `xcodegen generate` first or the new test file is not in the target at all and the suite passes vacuously.

- [ ] **Step 3: Commit the failing test**

```bash
git add OnlyCueTests/LTCFullFileAnalysisTests.swift
git commit -m "test(ltc): specify the full-file extent pass"
```

- [ ] **Step 4: Implement `analyzeFullFile` and the run trimming**

Add to `OnlyCue/LTC/LTCAudioReader.swift`:

```swift
/// Decodes one channel across the entire file to measure where its
/// timecode actually starts and stops (#793). Unlike `detectTimecodes`,
/// which scans a window across every channel to answer "is there LTC
/// here", this answers "how far does the LTC we already found extend".
///
/// Only the contiguous run containing the first frame is returned:
/// spliced files with several disjoint stripes are out of scope, and
/// adopting frames from a later stripe would place the anchor on a
/// timecode that does not follow from it.
static func analyzeFullFile(from url: URL, channel: Int) async throws -> DetectionResult? {
    let channelCount = try await AudioSampleReader.channelCount(of: url)
    guard channel >= 0, channel < channelCount else { return nil }

    let interleaved = try await AudioSampleReader.readInterleavedSamples(
        from: url, channels: channelCount, range: nil
    )
    let samples = AudioSampleReader.channel(channel, of: channelCount, in: interleaved)
    let frames = LTCDecoder.decode(samples: samples, sampleRate: sampleRate)
    let run = contiguousRunContainingFirst(frames)
    guard isCorroborated(run) else { return nil }
    return DetectionResult(channel: channel, frames: run)
}

/// The leading run of frames whose timecodes advance by one or two — the
/// same continuity rule `isCorroborated` uses. Two is tolerated because a
/// single dropped frame in the middle of a stripe is normal; anything
/// larger is a splice, and the run ends there.
private static func contiguousRunContainingFirst(
    _ frames: [LTCDecoder.DecodedFrame]
) -> [LTCDecoder.DecodedFrame] {
    guard let first = frames.first else { return [] }
    var run = [first]
    for frame in frames.dropFirst() {
        let delta = frame.timecode.frameCount - (run.last?.timecode.frameCount ?? 0)
        guard (1...2).contains(delta) else { break }
        run.append(frame)
    }
    return run
}
```

If `readInterleavedSamples(from:channels:range:)`'s `range` parameter is not optional, pass the full range explicitly instead of `nil` — check the signature at `OnlyCue/Tempo/AudioSampleReader.swift` and match it. Do not change that signature.

- [ ] **Step 5: Add the cache setter**

In `OnlyCue/LTC/StripedTimecodeCache.swift`, after `track(for:decode:)`:

```swift
/// Replaces `id`'s cached answer outright. Used by the full-file pass
/// (#793), which runs after `track(for:decode:)` has already cached the
/// windowed result and needs to upgrade it in place — `invalidate` would
/// instead cause the next ask to re-run the expensive scan.
func store(_ track: StripedTimecodeTrack?, for id: MediaItem.ID) {
    entries[id] = track
}
```

- [ ] **Step 6: Add the refinement command**

In `OnlyCue/Commands/CueCommands+LTC.swift`, after `rememberLTC`:

```swift
/// Upgrades a remembered LTC with the bounds the full-file pass measured
/// (#793). `rememberLTC` is deliberately write-once, so Phase 2 — which
/// always runs after Phase 1 has filled the slot — needs its own door.
///
/// Guarded to the same channel: refining is for adding measured bounds to
/// an answer already agreed on, never for overruling which channel the
/// LTC is on. Non-undoable, like its neighbours, because this is derived
/// data (contrast `setLTCChannelSelection`, which is authored and IS
/// undoable).
static func refineRememberedLTC(
    _ track: StripedTimecodeTrack,
    forItemID id: MediaItem.ID,
    document: CueListDocument
) {
    guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
    let existing = document.model.items[index].rememberedLTC
    guard existing == nil || existing?.ltcChannel == track.ltcChannel else { return }
    document.model.items[index].rememberedLTC = track
}
```

- [ ] **Step 7: Kick Phase 2 off from the host**

In `OnlyCue/UI/StripedTimecodeHost.swift`, extend the existing `.task(id: item?.id)` so Phase 2 follows Phase 1 in the same task — it inherits cancellation for free when the item changes:

```swift
.task(id: item?.id) {
    track = nil
    let decoded = await MediaImporter.stripedTimecode(for: item)
    guard !Task.isCancelled else { return }
    if let decoded, let item, item.rememberedLTC == nil {
        CueCommands.rememberLTC(decoded, forItemID: item.id, document: document)
    }
    track = LTCFallback.resolve(detected: decoded, remembered: item?.rememberedLTC)

    // Phase 2 (#793): the windowed scan can bound only the start. Now
    // that the channel is known, measure the real extent across the whole
    // file in the background and upgrade the readout in place. Skipped
    // when the pass has already run (validUntil is set) or when the user
    // named the channel, because MediaImporter went straight to the
    // full-file pass in that case.
    guard let item, item.ltcChannelSelection == .auto,
          let phase1 = track, phase1.validUntil == nil else { return }
    let refined = await MediaImporter.fullFileStripedTimecode(
        for: item, channel: phase1.ltcChannel
    )
    guard !Task.isCancelled, let refined else { return }
    StripedTimecodeCache.shared.store(refined, for: item.id)
    CueCommands.refineRememberedLTC(refined, forItemID: item.id, document: document)
    track = refined
}
```

`MediaImporter.fullFileStripedTimecode(for:channel:)` and `MediaItem.ltcChannelSelection` land in Task 4 — this step will not compile until then, which is the one place in this plan where a task depends forward. Write it now and let Task 4 close it; the alternative is writing the host twice.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/LTC/LTCAudioReader.swift OnlyCue/LTC/StripedTimecodeCache.swift \
        OnlyCue/Commands/CueCommands+LTC.swift OnlyCue/UI/StripedTimecodeHost.swift
git commit -m "feat(ltc): measure the timecode extent with a full-file pass"
```

---

### Task 4: `LTCChannelSelection`, the `MediaItem` field, and schema v23

The task that makes the branch persistent. It carries its own migration, its own doc update, and it closes Task 3's forward reference — split it and neither half builds.

**Files:**
- Create: `OnlyCue/Document/LTCChannelSelection.swift`
- Create: `OnlyCue/Document/ProjectModel+MigrationV22.swift`
- Modify: `OnlyCue/Document/MediaItem.swift`
- Modify: `OnlyCue/Document/ProjectModel.swift` (`currentSchemaVersion`)
- Modify: `OnlyCue/Document/ProjectModel+Migration.swift` (dispatch)
- Modify: `OnlyCue/Commands/MediaImporter.swift`
- Modify: `docs/data-model.md`
- Create: `OnlyCueTests/LTCChannelSelectionTests.swift`
- Create: `OnlyCueTests/ProjectModelMigrationV23Tests.swift`

**Interfaces:**
- Consumes: `LTCAudioReader.analyzeFullFile(from:channel:)` (Task 3), `StripedTimecodeTrack.init?(fullFileFrames:channel:sampleRate:)` (Task 2), `StripedTimecodeCache.store(_:for:)` (Task 3).
- Produces:
  - `enum LTCChannelSelection: Codable, Equatable, Sendable { case auto; case channel(Int); case none }`
  - `MediaItem.ltcChannelSelection: LTCChannelSelection` (default `.auto`), last in the memberwise initialiser.
  - `ProjectModel.currentSchemaVersion == 23`; `ProjectModel.migrateFromV22(data:)`.
  - `MediaImporter.fullFileStripedTimecode(for: MediaItem?, channel: Int) async -> StripedTimecodeTrack?`
  - `MediaImporter.audioChannelCount(for: MediaItem?) async -> Int` (Task 6 uses it).

The enum gets **explicit** `Codable`, not the synthesised form. Swift would encode `.channel(2)` as `{"channel":{"_0":2}}` — a compiler-generated key name inside a persisted document format is a trap for the next schema change.

- [ ] **Step 1: Write the failing tests**

`OnlyCueTests/LTCChannelSelectionTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class LTCChannelSelectionTests: XCTestCase {

    private func roundTrip(_ value: LTCChannelSelection) throws -> LTCChannelSelection {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(LTCChannelSelection.self, from: data)
    }

    func test_roundTrips_everyCase() throws {
        XCTAssertEqual(try roundTrip(.auto), .auto)
        XCTAssertEqual(try roundTrip(.none), LTCChannelSelection.none)
        XCTAssertEqual(try roundTrip(.channel(0)), .channel(0))
        XCTAssertEqual(try roundTrip(.channel(2)), .channel(2))
    }

    func test_encodesAsAStableStringForm() throws {
        let json = String(data: try JSONEncoder().encode(LTCChannelSelection.channel(2)),
                          encoding: .utf8)
        XCTAssertEqual(json, "\"channel:2\"")
        XCTAssertEqual(String(data: try JSONEncoder().encode(LTCChannelSelection.auto),
                              encoding: .utf8), "\"auto\"")
        XCTAssertEqual(String(data: try JSONEncoder().encode(LTCChannelSelection.none),
                              encoding: .utf8), "\"none\"")
    }

    func test_unknownStringDecodesAsAuto() throws {
        let data = "\"channel:banana\"".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(LTCChannelSelection.self, from: data), .auto)
    }
}
```

`OnlyCueTests/ProjectModelMigrationV23Tests.swift` — the `v22Doc()` fixture is `ProjectModelMigrationV22Tests`' `v21Doc()` at schema 22 with `colorHex` added:

```swift
import XCTest
@testable import OnlyCue

/// v22 -> v23 migration (#793): `MediaItem` gains `ltcChannelSelection` and
/// `StripedTimecodeTrack` gains optional `validFrom` / `validUntil`. A v22
/// document has none of those keys, so every item must load as `.auto` and
/// every remembered track as unbounded — which is exactly the behaviour
/// those documents already had.
final class ProjectModelMigrationV23Tests: XCTestCase {

    private func v22Doc() -> String {
        """
        {
          "schemaVersion": 22,
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": [{
            "id":"AAAA0001-0000-0000-0000-000000000001","name":"G","colorHex":"#FFFFFF",
            "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
            "isVisible":true,"isExportEnabled":true
          }],
          "items": [{
            "id": "22220000-2222-0000-2222-000022220000",
            "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
            "cues": [],
            "startTimecodeFrames": 0,
            "ltcMuted": true,
            "alternateName": "Overture",
            "lyrics": {"offsetSeconds": 0, "lines": []},
            "playsOriginalSourceAudio": false,
            "colorHex": "\(CuePointType.defaultPalette[3])"
          }],
          "activeItemID": "22220000-2222-0000-2222-000022220000",
          "timecodeSettings": {"framerate":"30"},
          "playbackMode": "playOnce"
        }
        """
    }

    /// The same fixture carrying a `rememberedLTC` written by v22. The JSON
    /// is produced by encoding a bounds-free track rather than hand-written,
    /// because `encodeIfPresent` omits both new keys for such a track — so
    /// this IS the v22 on-disk shape, and the assertion below proves it.
    private func v22DocWithRememberedLTC() throws -> String {
        let legacy = StripedTimecodeTrack(
            anchorTimecode: Timecode(frameCount: 900, rate: .fps30),
            anchorPlaybackSeconds: 2.0,
            ltcChannel: 1
        )
        let trackJSON = try XCTUnwrap(
            String(data: JSONEncoder().encode(legacy), encoding: .utf8)
        )
        XCTAssertFalse(trackJSON.contains("valid"), "a v22 track carries neither bound")
        return v22Doc().replacingOccurrences(
            of: "\"playsOriginalSourceAudio\": false",
            with: "\"playsOriginalSourceAudio\": false, \"rememberedLTC\": \(trackJSON)"
        )
    }

    func test_v22ToV23_bumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v22Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertGreaterThanOrEqual(ProjectModel.currentSchemaVersion, 23)
    }

    func test_v22ToV23_channelSelectionDefaultsToAuto() throws {
        let migrated = try ProjectModel.decode(from: Data(v22Doc().utf8))
        XCTAssertEqual(migrated.items[0].ltcChannelSelection, .auto)
    }

    func test_v22ToV23_leavesARememberedLTCUnbounded() throws {
        // The whole reason both bounds are optional: existing projects must
        // open with exactly the readout they had before (#793).
        let migrated = try ProjectModel.decode(
            from: Data(try v22DocWithRememberedLTC().utf8)
        )
        let remembered = try XCTUnwrap(migrated.items[0].rememberedLTC)
        XCTAssertNil(remembered.validFrom)
        XCTAssertNil(remembered.validUntil)
        XCTAssertTrue(remembered.isValid(atPlaybackSeconds: 9_999))
    }

    func test_v22ToV23_otherFieldsIntact() throws {
        let migrated = try ProjectModel.decode(from: Data(v22Doc().utf8))
        let item = migrated.items[0]
        XCTAssertEqual(item.media.displayName, "x.wav")
        XCTAssertEqual(item.alternateName, "Overture")
        XCTAssertTrue(item.ltcMuted)
        XCTAssertEqual(item.colorHex, CuePointType.defaultPalette[3])
        XCTAssertEqual(migrated.name, "doc")
        XCTAssertEqual(migrated.activeItemID, item.id)
        XCTAssertEqual(migrated.timecodeSettings.framerate, .fps30)
    }

    /// The choice has to survive a save/load cycle, not just the migration —
    /// that is the whole point of putting it in the document.
    func test_channelSelection_roundTripsThroughEncodeAndDecode() throws {
        var model = try ProjectModel.decode(from: Data(v22Doc().utf8))
        model.items[0].ltcChannelSelection = .channel(1)

        let reloaded = try ProjectModel.decode(from: JSONEncoder().encode(model))

        XCTAssertEqual(reloaded.items[0].ltcChannelSelection, .channel(1))
    }

    /// An item on `.auto` must not write the key at all — otherwise every
    /// document grows a field per item that only says "default". Mirrors
    /// `test_untaggedItem_omitsTheColorHexKey` in the v22 tests.
    func test_autoSelection_omitsTheKeyEntirely() throws {
        let model = try ProjectModel.decode(from: Data(v22Doc().utf8))

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(model), encoding: .utf8))

        XCTAssertFalse(json.contains("ltcChannelSelection"))
    }
}
```

`colorHex` interpolates `CuePointType.defaultPalette[3]` into the multi-line string rather than hard-coding a hex, so a palette change cannot silently rot the fixture.

- [ ] **Step 2: Run and watch it fail**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
```

Expected: build failure — `LTCChannelSelection` does not exist.

- [ ] **Step 3: Commit the failing tests**

```bash
git add OnlyCueTests/LTCChannelSelectionTests.swift \
        OnlyCueTests/ProjectModelMigrationV23Tests.swift
git commit -m "test(document): specify the ltc channel selection field"
```

- [ ] **Step 4: Add the enum**

Create `OnlyCue/Document/LTCChannelSelection.swift`:

```swift
import Foundation

/// Which audio channel of a media file carries LTC, as the user declared it
/// (#793). Authored data, kept separate from `MediaItem.rememberedLTC`,
/// which is derived: conflating them would let Clear erase what the user said.
///
/// Naming a channel is also the escape hatch from the 60 s scan ceiling. A
/// file whose LTC begins at 90 s is invisible to `.auto`, but a named channel
/// sends the full-file pass at it, which finds it.
enum LTCChannelSelection: Equatable, Sendable {

    /// Run the windowed scan across every channel and take the first that
    /// corroborates. The default.
    case auto

    /// The user named this channel: skip the scan, decode this one across
    /// the whole file. Zero-based, as `StripedTimecodeTrack.ltcChannel` is.
    case channel(Int)

    /// The user asserts this file carries no LTC: decode nothing.
    case none
}

/// Encoded as a flat string rather than by Swift's synthesised form for
/// enums with associated values, which would write `{"channel":{"_0":2}}`
/// — a compiler-generated key inside a persisted document format is a trap
/// for the next schema change.
extension LTCChannelSelection: Codable {

    private static let channelPrefix = "channel:"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "none":
            self = .none
        case let value where value.hasPrefix(Self.channelPrefix):
            let index = Int(value.dropFirst(Self.channelPrefix.count))
            // An unparseable or negative index falls back to auto rather
            // than failing the load: one malformed field must not make a
            // whole show file unopenable.
            self = index.map { $0 >= 0 ? .channel($0) : .auto } ?? .auto
        default:
            self = .auto
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .none: try container.encode("none")
        case .channel(let index): try container.encode("\(Self.channelPrefix)\(index)")
        }
    }
}
```

- [ ] **Step 5: Add the field to `MediaItem`**

In `OnlyCue/Document/MediaItem.swift`: add the stored property **after `colorHex`** (memberwise-init order must match the field order), add the `CodingKeys` case last, and extend both coding methods.

```swift
/// Which channel carries LTC, as the user declared it. Schema v23 (#793).
var ltcChannelSelection: LTCChannelSelection = .auto
```

`CodingKeys`: append `case ltcChannelSelection`.

In `init(from decoder:)`, alongside the other per-field version comments:

```swift
// v23: absent in older documents, where auto is the historical behaviour.
ltcChannelSelection = try container.decodeIfPresent(
    LTCChannelSelection.self, forKey: .ltcChannelSelection
) ?? .auto
```

In `encode(to:)`:

```swift
// Only written when the user has actually chosen. Encoding .auto would
// add a key saying "default" to every item in every document.
if ltcChannelSelection != .auto {
    try container.encode(ltcChannelSelection, forKey: .ltcChannelSelection)
}
```

Add the parameter to the memberwise initialiser last, defaulted to `.auto`, so no existing construction site changes.

- [ ] **Step 6: Bump the schema and add the migration**

`OnlyCue/Document/ProjectModel.swift`: `static let currentSchemaVersion = 23`.

Create `OnlyCue/Document/ProjectModel+MigrationV22.swift`, mirroring `ProjectModel+MigrationV21.swift` exactly:

```swift
import Foundation

extension ProjectModel {

    /// v22 -> v23 (#793): `MediaItem.ltcChannelSelection` arrives, and
    /// `StripedTimecodeTrack` gains optional `validFrom` / `validUntil`.
    /// Both are absent-means-default, so this is a pure re-stamp: items
    /// decode with `.auto` and remembered tracks decode unbounded, which
    /// is the behaviour those documents had.
    static func migrateFromV22(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV22.self, from: data)
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items,
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings,
            playbackMode: legacy.playbackMode
        )
    }

    private struct LegacyV22: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [MediaItem]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
        let playbackMode: PlaybackMode
    }
}
```

In `OnlyCue/Document/ProjectModel+Migration.swift`, add one line to the dispatch, immediately after `case 21`:

```swift
case 22: return try migrateFromV22(data: data)
```

- [ ] **Step 7: Route detection through the selection**

In `OnlyCue/Commands/MediaImporter.swift`, replace the body of `stripedTimecode(for:)` with a selection-aware branch and add the two new helpers. Keeping the branch here — rather than in a new resolver type — is deliberate: this function is already the single door every caller uses.

```swift
@MainActor
static func stripedTimecode(for item: MediaItem?) async -> StripedTimecodeTrack? {
    guard let item else { return nil }
    return await StripedTimecodeCache.shared.track(for: item.id) {
        switch item.ltcChannelSelection {
        case .none:
            // The user asserted there is none. Believe them and skip the scan.
            return nil
        case .channel(let channel):
            // Named channel: no windowed scan at all — go straight to the
            // full-file pass, which is also what finds LTC starting past
            // the 60 s scan ceiling.
            return await fullFileTrack(for: item, channel: channel)
        case .auto:
            return await autoDetectedTrack(for: item)
        }
    }
}

/// The historical windowed scan across every channel (Phase 1).
@MainActor
private static func autoDetectedTrack(for item: MediaItem) async -> StripedTimecodeTrack? {
    await withResolvedMedia(item) { url in
        guard let detection = try await LTCAudioReader.detectTimecodes(from: url) else {
            return nil
        }
        return StripedTimecodeTrack(detection: detection, sampleRate: LTCAudioReader.sampleRate)
    }
}

/// Decodes one channel across the whole file (Phase 2), for the measured
/// extent. Public entry point used by `StripedTimecodeHost` once Phase 1
/// has named a channel.
@MainActor
static func fullFileStripedTimecode(
    for item: MediaItem?, channel: Int
) async -> StripedTimecodeTrack? {
    guard let item else { return nil }
    return await fullFileTrack(for: item, channel: channel)
}

@MainActor
private static func fullFileTrack(
    for item: MediaItem, channel: Int
) async -> StripedTimecodeTrack? {
    await withResolvedMedia(item) { url in
        guard let result = try await LTCAudioReader.analyzeFullFile(
            from: url, channel: channel
        ) else { return nil }
        return StripedTimecodeTrack(
            fullFileFrames: result.frames,
            channel: result.channel,
            sampleRate: LTCAudioReader.sampleRate
        )
    }
}

/// How many audio channels the item's file has, for the channel picker.
/// Returns 0 when the bookmark cannot be resolved — the picker then offers
/// only Auto and No LTC, which is the honest thing to show.
@MainActor
static func audioChannelCount(for item: MediaItem?) async -> Int {
    guard let item else { return 0 }
    return await withResolvedMedia(item) { url in
        try await AudioSampleReader.channelCount(of: url)
    } ?? 0
}

/// Resolves the security-scoped bookmark, runs `body`, and always releases
/// access. Extracted because four call sites now need the same dance
/// (ADR-006: media is referenced by bookmark, never embedded).
@MainActor
private static func withResolvedMedia<T>(
    _ item: MediaItem,
    _ body: (URL) async throws -> T?
) async -> T? {
    do {
        let resolution = try Bookmarks.resolve(item.media.bookmarkData)
        let didAccess = resolution.url.startAccessingSecurityScopedResource()
        defer { if didAccess { resolution.url.stopAccessingSecurityScopedResource() } }
        return try await body(resolution.url)
    } catch {
        return nil
    }
}
```

`resolvedStripedTimecode(for:)` above it is unchanged — it still composes `stripedTimecode` with `LTCFallback.resolve`.

- [ ] **Step 8: Update `docs/data-model.md`**

Five edits, all in the sections the file already has:

1. `MediaItem` field listing (~line 120): add `ltcChannelSelection` after `colorHex`.
2. Field-semantics table (~line 213): a row after `item.colorHex` — "`item.ltcChannelSelection` — which channel the user says carries LTC (`auto` / `channel:N` / `none`). Authored, unlike `rememberedLTC`; Clear and Re-detect never touch it."
3. Line 217, "current file": `schemaVersion: 22` → `schemaVersion: 23`.
4. Migration list (~line 236): add "**v22 → current** — `ltcChannelSelection` defaults to `auto`; `rememberedLTC` gains optional `validFrom` / `validUntil`, both absent-means-unbounded, so existing readouts are unchanged."
5. Line 237: "v22 is a one-way upgrade" → "v23 is a one-way upgrade".

- [ ] **Step 9: Run the full suite and verify it passes**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueTests -parallel-testing-enabled NO
```

Expected: PASS, including every earlier `ProjectModelMigrationV*Tests` class — a schema bump that breaks an older migration shows up there and nowhere else. Task 3's `StripedTimecodeHost` change compiles from this point on.

- [ ] **Step 10: Commit**

```bash
git add OnlyCue/Document/LTCChannelSelection.swift \
        OnlyCue/Document/ProjectModel+MigrationV22.swift \
        OnlyCue/Document/MediaItem.swift \
        OnlyCue/Document/ProjectModel.swift \
        OnlyCue/Document/ProjectModel+Migration.swift \
        OnlyCue/Commands/MediaImporter.swift \
        docs/data-model.md
git commit -m "feat(document): let the user name the ltc channel (schema v23)"
```

---

### Task 5: The undoable channel-selection command

**Files:**
- Modify: `OnlyCue/Commands/CueCommands+LTC.swift`
- Test: `OnlyCueTests/CueCommandsLTCTests.swift` (existing file, append)

**Interfaces:**
- Consumes: `LTCChannelSelection` and `MediaItem.ltcChannelSelection` (Task 4); the test helpers `makeItem()`, `track(channel:)`, `seed(_:)` already in `CueCommandsLTCTests.swift`.
- Produces: `CueCommands.setLTCChannelSelection(_ selection: LTCChannelSelection, forItemID: MediaItem.ID, document: CueListDocument, undoManager: UndoManager?)`.

This one **is** undoable, unlike every other command in the file. That asymmetry is the point: `rememberedLTC` is derived from the media, `ltcChannelSelection` is something the user typed. The test below pins it so a later "let's make these consistent" pass has to argue with a red test rather than a comment.

- [ ] **Step 1: Write the failing test**

```swift
// MARK: - Channel selection (#793)

func test_setLTCChannelSelection_storesTheChoice() {
    let item = makeItem()
    let document = seed([item])
    CueCommands.setLTCChannelSelection(
        .channel(1), forItemID: item.id, document: document, undoManager: nil
    )
    XCTAssertEqual(document.model.items.first?.ltcChannelSelection, .channel(1))
}

func test_setLTCChannelSelection_isUndoable() {
    let item = makeItem()
    let document = seed([item])
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false

    CueCommands.setLTCChannelSelection(
        .channel(1), forItemID: item.id, document: document, undoManager: undoManager
    )
    XCTAssertEqual(document.model.items.first?.ltcChannelSelection, .channel(1))

    undoManager.undo()
    XCTAssertEqual(
        document.model.items.first?.ltcChannelSelection, .auto,
        "the channel the user named must be undoable, unlike derived rememberedLTC"
    )
}

func test_clearRememberedLTC_leavesTheChannelSelectionAlone() {
    // Clear and Re-detect reset derived data only. Erasing the user's
    // declaration would make Re-detect silently undo their override.
    let item = makeItem()
    let document = seed([item])
    CueCommands.setLTCChannelSelection(
        .channel(1), forItemID: item.id, document: document, undoManager: nil
    )
    CueCommands.rememberLTC(track(channel: 1), forItemID: item.id, document: document)

    CueCommands.clearRememberedLTC(forItemID: item.id, document: document)

    XCTAssertNil(document.model.items.first?.rememberedLTC)
    XCTAssertEqual(document.model.items.first?.ltcChannelSelection, .channel(1))
}

func test_setLTCChannelSelection_unchangedValue_doesNotRegisterUndo() {
    let item = makeItem()
    let document = seed([item])
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    CueCommands.setLTCChannelSelection(
        .auto, forItemID: item.id, document: document, undoManager: undoManager
    )
    XCTAssertFalse(undoManager.canUndo)
}

func test_refineRememberedLTC_onADifferentChannel_isIgnored() {
    let item = makeItem()
    let document = seed([item])
    CueCommands.rememberLTC(track(channel: 1), forItemID: item.id, document: document)

    CueCommands.refineRememberedLTC(track(channel: 0), forItemID: item.id, document: document)

    XCTAssertEqual(document.model.items.first?.rememberedLTC?.ltcChannel, 1)
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
```

Expected: build failure — `setLTCChannelSelection` does not exist.

- [ ] **Step 3: Implement the command**

Append to `OnlyCue/Commands/CueCommands+LTC.swift`, following the `setMediaColor` shape at `OnlyCue/Commands/CueCommands+Media.swift:76-96`:

```swift
/// Records which channel the user says carries LTC (#793).
///
/// Undoable, deliberately unlike `rememberLTC` / `clearRememberedLTC` /
/// `refineRememberedLTC` in this same file. Those three carry data derived
/// from the media, where Cmd-Z resurrecting a stale value would be wrong.
/// This one carries a decision the user made, and every user decision in
/// this app is undoable. Do not "make these consistent".
static func setLTCChannelSelection(
    _ selection: LTCChannelSelection,
    forItemID id: MediaItem.ID,
    document: CueListDocument,
    undoManager: UndoManager?
) {
    guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
    let previous = document.model.items[index].ltcChannelSelection
    guard previous != selection else { return }

    undoManager?.beginUndoGrouping()
    defer { undoManager?.endUndoGrouping() }

    document.model.items[index].ltcChannelSelection = selection
    undoManager?.registerUndo(withTarget: document) { doc in
        Self.setLTCChannelSelection(
            previous, forItemID: id, document: doc, undoManager: undoManager
        )
    }
    undoManager?.setActionName("Set LTC Channel")
}
```

Also add a cross-reference to the two existing commands' doc comments so the asymmetry is visible from either side — one line each, e.g. `/// Contrast \`setLTCChannelSelection\`, which is authored and undoable.`

- [ ] **Step 4: Run and verify**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:OnlyCueTests/CueCommandsLTCTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Commands/CueCommands+LTC.swift OnlyCueTests/CueCommandsLTCTests.swift
git commit -m "feat(commands): add an undoable ltc channel selection command"
```

---

### Task 6: The channel picker and the measured extent in the edit sheet

**Files:**
- Create: `OnlyCue/LTC/LTCExtentLabel.swift`
- Create: `OnlyCueTests/LTCExtentLabelTests.swift`
- Modify: `OnlyCue/UI/MediaEditSheet.swift`
- Modify: `OnlyCue/UI/ItemListPane.swift:45-73` (the `.sheet(item:)` presenter)

**Interfaces:**
- Consumes: `LTCChannelSelection` and `CueCommands.setLTCChannelSelection` (Tasks 4–5); `MediaImporter.audioChannelCount(for:)` (Task 4); `StripedTimecodeTrack.validFrom` / `.validUntil` (Task 2).
- Produces:
  - `enum LTCExtentLabel { static func text(validFrom: TimeInterval?, validUntil: TimeInterval?) -> String? }`
  - `MediaEditSheet.onSelectLTCChannel: (LTCChannelSelection) -> Void` (defaulted to `{ _ in }` so existing previews and tests keep compiling).

`MediaEditSheet.item` is a `let` snapshot held by `ItemListPane`'s `EditingTarget`, so it does **not** update when the document changes underneath. The picker's `@State channelDraft` is therefore the display source of truth after the first sync — do not try to read the selection back off `item`.

The selection applies **immediately** on change, not on Save. Save's `onSave` closure commits four fields atomically through `updateMediaItem`, and threading a fifth field of a different type through it would conflate an authored enum with that atomic edit. More practically: the status line has to re-resolve against the new channel to be worth showing, which means the change has to have landed.

**No `DS.*` token obligation here** — `MediaEditSheet.swift` is not in `TokenConformanceTests.mainWindowFiles`. Match the file's existing plain-SwiftUI style.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/LTCExtentLabelTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class LTCExtentLabelTests: XCTestCase {

    func test_bothBounds_rendersARange() {
        XCTAssertEqual(
            LTCExtentLabel.text(validFrom: 2.0, validUntil: 291.1),
            "00:00:02.0 – 00:04:51.1"
        )
    }

    func test_noBounds_rendersNothing() {
        // Phase 2 has not run, or the document predates #793. Showing
        // "unknown – unknown" would be worse than showing nothing.
        XCTAssertNil(LTCExtentLabel.text(validFrom: nil, validUntil: nil))
    }

    func test_startOnly_rendersAnOpenEndedRange() {
        // Phase 1 has landed but Phase 2 has not.
        XCTAssertEqual(LTCExtentLabel.text(validFrom: 2.0, validUntil: nil), "from 00:00:02.0")
    }

    func test_endOnly_rendersAnOpenStartedRange() {
        XCTAssertEqual(LTCExtentLabel.text(validFrom: nil, validUntil: 61.5), "to 00:01:01.5")
    }

    func test_hoursAreRendered() {
        XCTAssertEqual(LTCExtentLabel.text(validFrom: 3_661.25, validUntil: nil),
                       "from 01:01:01.2")
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
```

Expected: build failure — `LTCExtentLabel` does not exist.

- [ ] **Step 3: Commit the failing test**

```bash
git add OnlyCueTests/LTCExtentLabelTests.swift
git commit -m "test(ltc): specify the striped extent label"
```

- [ ] **Step 4: Implement the formatter**

Create `OnlyCue/LTC/LTCExtentLabel.swift`. Pure and view-free, like `TimecodeReadout` next to it, so the wording is testable without a UI test.

```swift
import Foundation

/// Renders a striped track's measured extent for the edit sheet's status
/// line (#793) — `00:00:02.0 – 00:04:51.1`. Wall-clock position in the
/// media, deliberately not SMPTE: this answers "where in this file", and
/// mixing it with the timecode value in the same line would read as two
/// timecodes.
enum LTCExtentLabel {

    /// `nil` when neither bound is known, so the caller can omit the
    /// segment entirely rather than print a placeholder.
    static func text(validFrom: TimeInterval?, validUntil: TimeInterval?) -> String? {
        switch (validFrom, validUntil) {
        case (nil, nil):
            return nil
        case (let from?, nil):
            return "from \(clock(from))"
        case (nil, let until?):
            return "to \(clock(until))"
        case (let from?, let until?):
            return "\(clock(from)) – \(clock(until))"
        }
    }

    /// HH:MM:SS.t — tenths, because the bounds are measured to within a
    /// frame and a second's resolution would hide a short stripe.
    private static func clock(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let tenths = Int((clamped - Double(whole)) * 10)
        return String(
            format: "%02d:%02d:%02d.%d",
            whole / 3600, (whole % 3600) / 60, whole % 60, tenths
        )
    }
}
```

- [ ] **Step 5: Add the picker to the sheet**

In `OnlyCue/UI/MediaEditSheet.swift`:

Add the property, after `onClearLTC`:

```swift
/// Records which channel carries LTC (#793). Applied immediately rather
/// than on Save — the status line re-resolves against the new channel,
/// so the change has to have landed to be worth showing. Supplied by the
/// presenter, which holds `document` and the undo manager.
var onSelectLTCChannel: (LTCChannelSelection) -> Void = { _ in }
```

Add the state:

```swift
/// The picker's displayed value. `item` is a snapshot the presenter took
/// when the sheet opened and never updates, so this is the source of
/// truth after the initial sync.
@State private var channelDraft: LTCChannelSelection = .auto
/// How many channels the file has, for the picker's rows. 0 until the
/// probe returns, which is why the loop below is over an empty range then.
@State private var channelCount = 0
```

Insert the picker into `Section("LTC")`, immediately above the Status row — the choice comes before its consequence:

```swift
Picker("Channel", selection: $channelDraft) {
    Text(autoChannelLabel).tag(LTCChannelSelection.auto)
    ForEach(0..<channelCount, id: \.self) { index in
        Text("Channel \(index + 1)").tag(LTCChannelSelection.channel(index))
    }
    Text("No LTC").tag(LTCChannelSelection.none)
}
.accessibilityIdentifier("mediaEditLTCChannelPicker")
.onChange(of: channelDraft) { _, new in
    onSelectLTCChannel(new)
    fetchToken = UUID()   // re-resolve the status line against the new choice
}
```

Add the two computed labels, and fold the extent into the existing status text:

```swift
/// Names what Auto actually found, so the user can accept it or override
/// it from the same list without first reading the Status row.
private var autoChannelLabel: String {
    guard let channel = resolvedTrack?.ltcChannel, channelDraft == .auto else { return "Auto" }
    return "Auto (detected: Channel \(channel + 1))"
}

private var ltcStatusText: String {
    if detecting { return "Detecting…" }
    guard let track = resolvedTrack else { return "Not found" }
    let prefix = item.rememberedLTC == nil ? "Detected" : "Remembered"
    let tc = track.timecode(atPlaybackSeconds: track.anchorPlaybackSeconds).displayString
    var line = "\(prefix) · channel \(track.ltcChannel + 1) · \(tc)"
    // Present only once the full-file pass has measured something. A range
    // visibly shorter than the media is also how a truncated/discontinuous
    // stripe announces itself (spec section 2).
    if let extent = LTCExtentLabel.text(validFrom: track.validFrom, validUntil: track.validUntil) {
        line += " · \(extent)"
    }
    return line
}
```

Seed `channelDraft` in `syncDraftsFromItem()`:

```swift
channelDraft = item.ltcChannelSelection
```

And probe the channel count in the existing `.task(id: fetchToken)`, before the resolve:

```swift
.task(id: fetchToken) {
    detecting = true
    channelCount = await MediaImporter.audioChannelCount(for: item)
    resolvedTrack = await MediaImporter.resolvedStripedTimecode(for: item)
    detecting = false
}
```

The sheet is `.frame(width: 460)`; `Auto (detected: Channel 2)` fits. If a long status line wraps, add `.lineLimit(1)` to the Status `Text` — do not widen the sheet.

- [ ] **Step 6: Wire the presenter**

In `OnlyCue/UI/ItemListPane.swift`, add a closure to the `MediaEditSheet(...)` call after `onClearLTC`:

```swift
onSelectLTCChannel: { selection in
    CueCommands.setLTCChannelSelection(
        selection,
        forItemID: editing.item.id,
        document: document,
        undoManager: undoManager
    )
    // The cached answer was computed for the old selection.
    StripedTimecodeCache.shared.invalidate(editing.item.id)
}
```

`ItemListPane.swift` **is** token-gated — but this addition is pure wiring with no colors, fonts, or padding, so no `DS.*` reference is needed and none should be invented.

- [ ] **Step 7: Run the full suite and verify**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueTests -parallel-testing-enabled NO
```

Expected: PASS, `TokenConformanceTests` included.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/LTC/LTCExtentLabel.swift OnlyCue/UI/MediaEditSheet.swift \
        OnlyCue/UI/ItemListPane.swift
git commit -m "feat(ui): let the user pick the ltc channel and show its extent"
```

---

### Task 7: Blank the readout outside the valid range

**Files:**
- Modify: `OnlyCue/LTC/TimecodeReadout.swift`
- Modify: `OnlyCue/UI/TransportControls.swift:229-239`
- Test: `OnlyCueTests/TimecodeReadoutTests.swift` (existing file — append)

**Interfaces:**
- Consumes: `StripedTimecodeTrack.isValid(atPlaybackSeconds:)` (Task 2).
- Produces: `TimecodeReadout.outOfRange: String` — the shared `--:--:--:--` literal.

Per the "Deviations" section above, `PreviewPane` is **not** touched: its `ltcDetectedBadge` shows the detected start, not a playhead-following value, so there is nothing there to blank.

- [ ] **Step 1: Write the failing test**

```swift
// MARK: - Out of range (#793)

func test_outOfRange_isTheStandardBlankTimecode() {
    XCTAssertEqual(TimecodeReadout.outOfRange, "--:--:--:--")
}

func test_prefix_staysFILEOutsideTheValidRange() {
    // The information still comes from the file — it is simply not valid
    // at this position. Flipping to SMPTE would claim the project's
    // fallback timecode is being shown, which it is not.
    XCTAssertEqual(TimecodeReadout.prefix(hasFileTimecode: true), "FILE")
}
```

Add a matching assertion that the transport readout blanks, at whatever level `TransportControls` is testable in this repo. If `smpteReadout` is `private` (it is), do **not** widen it for the test — the behaviour is covered by `StripedTimecodeTrackTests.test_isValid_respectsBothBounds` plus the UI test in Step 5, and widening a view's private surface to reach a two-line guard is a worse trade.

- [ ] **Step 2: Run and watch it fail**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
```

Expected: build failure — `outOfRange` does not exist.

- [ ] **Step 3: Implement**

In `OnlyCue/LTC/TimecodeReadout.swift`:

```swift
/// Shown in place of a timecode when the playhead sits outside the
/// stripe's measured range (#793). The prefix stays `FILE`: the
/// information does come from the file, it is simply not valid here.
static let outOfRange = "--:--:--:--"
```

In `OnlyCue/UI/TransportControls.swift`, guard the striped branch of `smpteReadout`:

```swift
private var smpteReadout: String {
    if let striped = stripedTimecode {
        // Outside the measured stripe the old code extrapolated, inventing
        // timecode for a stretch of the file that carries none (#793).
        guard striped.isValid(atPlaybackSeconds: engine.currentTime) else {
            return TimecodeReadout.outOfRange
        }
        return striped.timecode(atPlaybackSeconds: engine.currentTime).displayString
    }
    guard let activeItem else {
        return Timecode(frameCount: 0, rate: timecodeSettings.framerate).displayString
    }
    return timecodeSettings.timecode(atPlaybackSeconds: engine.currentTime, forItem: activeItem).displayString
}
```

No token change: the surrounding `Text` at `TransportControls.swift:220` is untouched, and a string constant is not a design-token concern.

- [ ] **Step 4: Run the full suite and verify**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueTests -parallel-testing-enabled NO
```

Expected: PASS.

- [ ] **Step 5: Add the BDD acceptance coverage**

The issue's Gherkin scenarios describe user-visible behaviour, so they are mirrored in `OnlyCueUITests/` per the project's BDD rule. Add one XCUITest that opens the edit sheet on a fixture clip and asserts `mediaEditLTCChannelPicker` exists and `mediaEditLTCStatus` is non-empty. Follow the existing sheet-opening helper in `OnlyCueUITests/` rather than writing a new one.

**Two standing traps, both previously bitten:**
- `openContextMenu` throws `XCTSkip`, so a real regression reads as "skipped" and the run stays green. Diff the skip count against a `dev` worktree before believing a green run.
- CI does not run UI tests on PRs — the UI steps are gated on push-to-`dev`. A green PR check does **not** cover this test. Run it locally, ad-hoc signed, and say so in the PR:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueUITests \
  CODE_SIGN_IDENTITY="-"
```

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/LTC/TimecodeReadout.swift OnlyCue/UI/TransportControls.swift \
        OnlyCueTests/TimecodeReadoutTests.swift OnlyCueUITests/
git commit -m "fix(ui): blank the readout outside the measured ltc range"
```

---

## Final verification

- [ ] **Full suite, both targets, clean**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS'
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueTests -parallel-testing-enabled NO
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueUITests CODE_SIGN_IDENTITY="-"
```

- [ ] **Release build.** Release is warnings-as-errors and CI only builds Debug, so a warning introduced here would not surface until a tag:

```bash
./scripts/build-release.sh
```

- [ ] **Manual check against the reporter's file.** The last step, and the only one using real media. Import `f0e98cb3-99.mp3` (from `~/.claude/uploads/…` — **do not copy it into the repository**) and confirm:
  - the readout shows `FILE 08:00:00:18`-and-counting once playback passes 2.0 s;
  - the readout shows `FILE --:--:--:--` before 2.0 s and after ~291.1 s;
  - the edit sheet reports `Detected · channel 2 · 08:00:00:18 · 00:00:02.0 – 00:04:51.1` (a second or two after opening, once Phase 2 lands);
  - selecting `No LTC` blanks the readout, and Cmd-Z restores the previous selection.

- [ ] **Open the PR** into `dev` using `.github/PULL_REQUEST_TEMPLATE/bug.md` (the issue carries the `bug` label). Fill the OnlyCue verification block with the commands actually run, link spec §1–§5, and state plainly that CI's PR check does not cover the XCUITest.

## Self-review notes

Checked against the spec, section by section:

- §1 decoder front end → Task 1 (threshold formula, RMS floor, global-reference constraint, corrected doc comment, min anchor retained).
- §2 two-phase detection and the valid range → Tasks 2 and 3 (`validFrom` / `validUntil` optional, Phase 1 sets start only, Phase 2 sets both, run-trimming for discontinuity). "The UI warns" → flagged as a deviation, satisfied by the extent display.
- §3 manual channel selection → Tasks 4 and 5 (enum, field, schema 22→23 + migration, undoable command, Clear/Re-detect leave it alone, escape hatch from the 60 s ceiling via the `.channel` branch going straight to `analyzeFullFile`).
- §4 UI → Tasks 6 and 7 (picker, status line with extent, `--:--:--:--` keeping the `FILE` prefix). `PreviewPane` → flagged as a deviation. The `TokenConformanceTests` coverage question → answered: `MediaEditSheet` is outside `mainWindowFiles`.
- §5 testing → the first red test is the pure `LTCDecoder` unit test in Task 1; the false-positive guard, the bounds derivation, the `LTCChannelSelection` round-trip, and the v22→v23 "leaves an existing `rememberedLTC` unbounded" test are all present; the mp3 is manual-only and stays out of the repo.

Out-of-scope items in the spec (multi-segment tracks, LTC-slaved playback, pulldown, the 25 fps parity variant, widening `scanWindows`) have no task, as intended.
