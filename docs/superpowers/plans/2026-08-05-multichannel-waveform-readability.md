# Multichannel Waveform Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure a detected LTC channel never leaks into the drawn waveform, and add an opt-in "Split Channels" mode that draws one waveform lane per music channel (LTC channel excluded, surfaced via an enhanced badge).

**Architecture:** Two pieces. ① A bug pass that confirms/repairs the existing music-only exclusion at the generation + wiring level. ② A feature that adds an app-global `@AppStorage("splitWaveformChannels")` toggle (default off → today's single combined waveform, byte-identical); when on, `WaveformGenerator.channelPeaks` produces one normalized peak array per non-LTC channel, cached per-channel, and `WaveformLanesView` stacks them vertically over a shared time axis while the existing overlays (playhead, markers, tempo grid, ruler, seek, lyrics) span the full height. The LTC channel is never a lane — the existing `PreviewPane` badge is strengthened to name it and mark it muted.

**Tech Stack:** SwiftUI, AVFoundation (`AVAssetReader`), XCTest, xcodegen-generated `.xcodeproj`.

Spec: `docs/superpowers/specs/2026-08-05-multichannel-waveform-readability.md`. Branch: `issues/720` (off `dev`). Issue: #720.

## Global Constraints

- **Default OFF = zero regression.** `splitWaveformChannels` defaults `false`; the single-`[Float]` render path (and mono/no-LTC files) must stay **byte-identical** to today. Guard the new path behind the toggle.
- **The LTC channel is NEVER drawn as a waveform lane** (spec decision 1; #715 rejected the two-track split). It is surfaced only via the enhanced badge.
- **No playback change; no per-channel mute/solo UI.** The toggle is display-only; muting stays driven by LTC detection + `MediaItem.playsOriginalSourceAudio`.
- **Toggle is an app-global preference** (`@AppStorage`, like `showTempoGrid` / `autoScrollWaveform` in `AppCommands.swift`), surfaced in the **View** menu.
- **Keep the LTC-output strip alignment (#663/#669)** and `PreviewLayout.trackContentInset` sharing intact — the multi-lane region must occupy the same horizontal content box as today.
- **Preserve the #681 render-once/translate optimization** — during follow playback the lanes are rendered once and only translated per frame; do not re-rasterize N Canvases at 60fps.
- **Cache compatibility:** per-channel peaks use a NEW key axis (a channel index); existing `excludingChannel` (`-xc<N>`) and combined (`-<res>-v<fmt>`) entries stay valid. Only bump `WaveformCache.formatVersion` if an existing entry's bytes change (they do not here).
- **Design tokens:** if a file you touch is in `OnlyCueTests/DesignSystem/TokenConformanceTests.swift`'s scanned list, raw `Color` / `.font(.system(size:))` / numeric `.padding(<n>)` fail the build unless marked `// semantic:` / `// off-grid:`. Use `DS.*`.
- **macOS 14 deployment target; no App Sandbox entitlements.**
- **Conventional Commits, lowercase after prefix, imperative; NO `Co-Authored-By`/attribution.** Never bundle the spec/plan into an implementation commit.
- **Verification is adapted:** the XCUITest automation runner is wedged in this environment. Run `xcodegen generate` + build + the full `OnlyCueTests` unit suite + `swiftlint lint --strict`. DEFER UI suites (`OnlyCueUITests/*`) and manual walks to a batched reboot pass; never fabricate a UI/manual pass.

---

### Task 1: Confirm or repair the LTC-exclusion (bug ①)

The music-only waveform *should* already exclude the LTC channel (#715). The user reports it still looks like LTC. Establish the truth with a strong regression test at the generation + cache API, and audit the runtime wiring. If a logic bug exists, fix it; if not, document the conclusion and the runtime lead for the manual pass.

**Files:**
- Test: `OnlyCueTests/WaveformGeneratorTests.swift` (extend), `OnlyCueTests/WaveformCacheTests.swift` (extend)
- Audit (read, maybe modify): `OnlyCue/UI/WaveformContainer.swift`, `OnlyCue/UI/PreviewPane.swift`, `OnlyCue/Media/WaveformPrewarmer.swift`, `OnlyCue/Media/WaveformCache.swift`
- Fixtures: reuse the existing multi-channel fixture helper used by `WaveformGeneratorTests` (the #715 "music vs a loud/known channel" 2-ch fixture); if none is reusable, extend `SilentAudioFixture` to synthesize a 2-ch WAV (a sine on ch0, a full-scale square ~1 kHz on ch1 as an LTC stand-in).

**Interfaces:**
- Consumes: `WaveformGenerator.peaks(for:resolution:excludingChannel:)`, `WaveformCache.read/write(...excludingChannel:)`.
- Produces: no new production symbol (this task is a guard + audit); a documented finding in the task report.

- [ ] **Step 1: Write a strong exclusion regression test**

In `WaveformGeneratorTests.swift`, with a 2-ch fixture (music on ch0, loud square on ch1):
```swift
func test_peaks_excludingLTCChannel_matchesMusicChannelAndDropsLTC() async throws {
    let asset = try Self.twoChannelFixture(music: 0, ltcLike: 1) // reuse/extend existing helper
    let all = try await WaveformGenerator.peaks(for: asset, resolution: 200, excludingChannel: nil)
    let musicOnly = try await WaveformGenerator.peaks(for: asset, resolution: 200, excludingChannel: 1)
    // The LTC-like square dominates the all-channel downmix, so excluding it must change the shape.
    XCTAssertNotEqual(musicOnly, all)
    // And music-only must equal excluding the *other* order is NOT the same as keeping ch1:
    let excludingMusic = try await WaveformGenerator.peaks(for: asset, resolution: 200, excludingChannel: 0)
    XCTAssertNotEqual(musicOnly, excludingMusic)
    // Music-only's loudest bucket is the music's, not the square's full-scale block.
    XCTAssertLessThan(musicOnly.max() ?? 0, (excludingMusic.max() ?? 0) + 0.001)
}
```

- [ ] **Step 2: Run it — expect PASS (the generator is already correct per #715)**

Run: `xcodegen generate && xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue -configuration Debug -destination 'platform=macOS' && xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/WaveformGeneratorTests -parallel-testing-enabled NO 2>&1 | tail -20`
Expected: PASS. If it FAILS, you found the bug in the generator — fix `musicOnlyPeaks` so exclusion is correct, then re-run to green.

- [ ] **Step 3: Audit the runtime wiring and the prewarmer (documented, code-read)**

Confirm and note in the report: (a) `.stripedTimecodeReader` at `DocumentView.swift:129` wraps the subtree containing `WaveformContainer` (env reaches it); (b) `WaveformContainer.load()` captures `excludingChannel = stripedTimecode?.ltcChannel` and passes it to all three of `cache.read` / `WaveformGenerator.peaks` / `cache.write`; (c) `WaveformLoadKey` includes `excludingChannel` so the task re-fires when detection resolves. THEN inspect `WaveformPrewarmer` (`grep -rn excludingChannel OnlyCue/Media/WaveformPrewarmer.swift`): does the import-time prewarm generate/cache the **all-channel** peaks under a key that could be displayed before the music-only regen runs? If the prewarmer caches an all-channel entry that the container then shows without re-deriving music-only, that is the runtime bug — fix by having the display path always key on the detected `excludingChannel` (it already does) and, if needed, teaching the prewarmer to skip caching a would-be-stale all-channel entry for files that will be scanned for LTC. Only change code if the audit finds a concrete defect; otherwise record the conclusion.

- [ ] **Step 4: Add a cache-distinctness regression test**

In `WaveformCacheTests.swift`, assert `entryURL(...excludingChannel: 1)` differs from `entryURL(...excludingChannel: nil)` and a write under one key is not readable under the other (guards against a key collision that would show all-channel data on the music-only read). Run the focused suite to green.

- [ ] **Step 5: Commit**

```bash
git add OnlyCueTests/WaveformGeneratorTests.swift OnlyCueTests/WaveformCacheTests.swift
# plus any fixture/production fix the audit produced
git commit -m "test(waveform): pin LTC-channel exclusion at the generator and cache"
```
(If the audit produced a production fix, use `fix(waveform): <what>` and stage those files too.)

---

### Task 2: Per-channel peak generation

Add a generation path that returns one normalized peak array per **non-excluded** channel, so the split view can draw each music channel.

**Files:**
- Modify: `OnlyCue/Media/WaveformGenerator.swift`
- Test: `OnlyCueTests/WaveformGeneratorTests.swift`

**Interfaces:**
- Consumes: the existing `makeReader`, `RMSAccumulator`, `estimatedSampleCount`, `sourceChannelCount`, `normalized` in `WaveformGenerator`.
- Produces: `static func channelPeaks(for asset: AVAsset, resolution: Int, excludingChannel: Int?) async throws -> [[Float]]` — an array of per-channel normalized peak arrays, in ascending channel order, **omitting** `excludingChannel`. Mono or index-out-of-range → a single-element array equal to `monoDownmixPeaks` (so callers can treat it uniformly). Each inner array has length `resolution`.

- [ ] **Step 1: Write the failing test**
```swift
func test_channelPeaks_returnsOnePerMusicChannel_excludingLTC() async throws {
    let asset = try Self.twoChannelFixture(music: 0, ltcLike: 1)
    let lanes = try await WaveformGenerator.channelPeaks(for: asset, resolution: 200, excludingChannel: 1)
    XCTAssertEqual(lanes.count, 1)                 // only the music channel remains
    XCTAssertEqual(lanes[0].count, 200)
    // With no exclusion on a 2-ch file, both channels come back:
    let both = try await WaveformGenerator.channelPeaks(for: asset, resolution: 200, excludingChannel: nil)
    XCTAssertEqual(both.count, 2)
    XCTAssertNotEqual(both[0], both[1])            // distinct L/R content
    // Mono fallback: a mono asset yields exactly one lane == the downmix.
    let mono = try await Self.monoFixture()
    let monoLanes = try await WaveformGenerator.channelPeaks(for: mono, resolution: 200, excludingChannel: nil)
    XCTAssertEqual(monoLanes.count, 1)
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'channelPeaks'`. (Focused: `-only-testing:OnlyCueTests/WaveformGeneratorTests`.)

- [ ] **Step 3: Implement `channelPeaks`**

Read N channels interleaved (as `musicOnlyPeaks` does), but accumulate a **separate** `RMSAccumulator` per non-excluded channel (each with `musicChannelsPerFrame: 1`, contributing only that channel's sample), then `normalized(...)` each. Reuse `makeReader(channels: channelCount)`, `estimatedSampleCount`, `sourceChannelCount`. Mono / out-of-range → `[try await monoDownmixPeaks(...)]`. Keep `musicOnlyPeaks` (the combined path) unchanged.

- [ ] **Step 4: Run to green.**

- [ ] **Step 5: Commit** — `feat(waveform): generate per-channel peaks excluding the LTC channel`.

---

### Task 3: Per-channel cache

Cache each channel's peaks so the split view is as fast as the combined view.

**Files:**
- Modify: `OnlyCue/Media/WaveformCache.swift`
- Test: `OnlyCueTests/WaveformCacheTests.swift`

**Interfaces:**
- Consumes: existing `entryURL`, `fileHash`, `formatVersion`.
- Produces: `func read(assetHash:resolution:channel: Int) -> [Float]?` and `func write(_:assetHash:resolution:channel: Int) throws`, keyed with a NEW `-ch<N>` suffix in `entryURL` (distinct from `-xc<N>`). Existing methods/keys unchanged.

- [ ] **Step 1: Write the failing test** — write channel 0 and channel 1 peaks, read each back, assert distinct and that a `channel:` entry does not collide with the combined or `excludingChannel:` entries.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Implement** — add an optional `channel: Int?` axis to `entryURL` producing a `-ch<N>` suffix; add the channel-keyed `read`/`write`. Do NOT bump `formatVersion` (existing byte formats unchanged).

- [ ] **Step 4: Run to green.**

- [ ] **Step 5: Commit** — `feat(waveform): cache per-channel peaks under a channel-indexed key`.

---

### Task 4: "Split Channels" preference + View menu

**Files:**
- Modify: `OnlyCue/App/AppCommands.swift` (+ its `+Workspace`/overlay-toggle style)
- Modify: `OnlyCue/UI/AppNotifications.swift` (if the menu toggles via notification like the others) — otherwise a plain `@AppStorage` bound `Toggle` in the menu
- Test: `OnlyCueTests/` — a small test only if a pure helper is introduced; otherwise this task is build-verified (a menu `Toggle` bound to `@AppStorage` has no unit-testable logic — do NOT invent a vacuous test)

**Interfaces:**
- Produces: `@AppStorage("splitWaveformChannels")` (default `false`), read by `WaveformContainer` in Task 6; a **View** menu item "Split Channels" (a bound `Toggle`, mirroring how `showTempoGrid` is exposed).

- [ ] **Step 1: Add the preference + menu item**

In `AppCommands.swift` add `@AppStorage("splitWaveformChannels") private var splitWaveformChannels = false` and a `Toggle("Split Channels", isOn: $splitWaveformChannels)` in the View menu next to the tempo-grid/overlay toggles. Match the existing toggle idiom exactly (bound `Toggle`, or the notification pattern the file already uses — follow whichever the neighboring toggles use).

- [ ] **Step 2: Build + full unit suite + lint** (no new test; the toggle is pure `@AppStorage`).

Run: `xcodegen generate && xcodebuild build-for-testing ... && xcodebuild test-without-building ... -only-testing:OnlyCueTests ... && swiftlint lint --strict`.

- [ ] **Step 3: Commit** — `feat(waveform): add the Split Channels view preference and menu toggle`.

---

### Task 5: `WaveformLanesView` — stack N lanes over a shared time axis

**Files:**
- Create: `OnlyCue/UI/WaveformLanesView.swift`
- Test: `OnlyCueTests/WaveformLanesLayoutTests.swift`

**Interfaces:**
- Consumes: existing `WaveformView(peaks:)`.
- Produces:
  - `enum WaveformLaneLayout { static func laneHeight(totalHeight: CGFloat, laneCount: Int, gap: CGFloat) -> CGFloat }` — pure, testable: `(totalHeight - gap*(laneCount-1)) / laneCount`, floored at a hairline minimum; `laneCount <= 1` → `totalHeight`.
  - `struct WaveformLanesView: View { let lanes: [[Float]]; let height: CGFloat; init(...) }` — a `VStack(spacing: gap)` of `WaveformView(peaks:)`, each framed to `laneHeight`. One lane → visually identical to a bare `WaveformView` (same height, no gap).

- [ ] **Step 1: Write the failing layout test**
```swift
func test_laneHeight_dividesHeightAcrossLanesWithGaps() {
    XCTAssertEqual(WaveformLaneLayout.laneHeight(totalHeight: 200, laneCount: 2, gap: 4), 98, accuracy: 0.001)
    XCTAssertEqual(WaveformLaneLayout.laneHeight(totalHeight: 200, laneCount: 1, gap: 4), 200, accuracy: 0.001)
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'WaveformLaneLayout'`.

- [ ] **Step 3: Implement `WaveformLaneLayout` + `WaveformLanesView`.** Use `DS.*` for the gap; give the view an `.accessibilityIdentifier("waveformLanes")` and each lane `"waveformLane.\(index)"`.

- [ ] **Step 4: Run to green.**

- [ ] **Step 5: Commit** — `feat(waveform): add WaveformLanesView stacking one lane per channel`.

---

### Task 6: Render lanes in `WaveformContainer` (wire the toggle + per-channel path)

**Files:**
- Modify: `OnlyCue/UI/WaveformContainer.swift`, `OnlyCue/UI/WaveformContainer+Follow.swift`
- Test: build-verified (SwiftUI render); a pure test only if a decision helper is extracted.

**Interfaces:**
- Consumes: `@AppStorage("splitWaveformChannels")` (Task 4), `WaveformGenerator.channelPeaks` (Task 2), `WaveformCache.read/write(channel:)` (Task 3), `WaveformLanesView` (Task 5), `stripedTimecode` env.
- Produces: no new external symbol.

- [ ] **Step 1: Add per-channel state + load path**

Add `@AppStorage("splitWaveformChannels") private var splitChannels = false` and `@State private var lanePeaks: [[Float]]?`. Extend `WaveformLoadKey` with `split: Bool` so toggling re-fires the task. In `load()`, when `splitChannels` is true, populate `lanePeaks` via the channel cache (read each channel; on miss, `channelPeaks(...)` then cache each) using `excludingChannel = stripedTimecode?.ltcChannel`; when false, leave `lanePeaks = nil` and keep the existing single-`peaks` path untouched (byte-identical guarantee).

- [ ] **Step 2: Render lanes when on**

In `staticScrollContent`, replace `WaveformView(peaks: peaks)` with: `if splitChannels, let lanePeaks { WaveformLanesView(lanes: lanePeaks, height: height) } else { WaveformView(peaks: peaks) }`. Everything else in the ZStack (tempo grid, ruler, seek surface, markers, lyrics lane, and the playhead in the follow layer) is UNCHANGED — they already span the full `height`, so they correctly overlay across all lanes. Keep the `.opacity(editorMode == .show ? 0.45 : 1)` on the peaks region.

- [ ] **Step 3: Build + full unit suite + lint.** Confirm the OFF path is untouched (diff shows the single-`peaks` branch identical). Report the #681 follow-render note: lanes live in the same once-rendered static content, so the translate-per-frame optimization still applies.

- [ ] **Step 4: Commit** — `feat(waveform): render per-channel lanes when Split Channels is on`.

---

### Task 7: Enhanced LTC badge (name the channel + muted)

**Files:**
- Modify: `OnlyCue/UI/PreviewPane.swift`
- Test: `OnlyCueTests/` — a pure label-format helper test.

**Interfaces:**
- Consumes: `stripedTimecode` (`StripedTimecodeTrack` with `ltcChannel`, `anchorTimecode`).
- Produces: a small pure formatter, e.g. `enum LTCBadgeLabel { static func text(channel: Int, channelCount: Int, startTimecode: String) -> String }` returning e.g. `"R = LTC (muted) · 01:00:00:00"` (map channel index → L/R for 2-ch, else `"Ch \(index+1)"`).

- [ ] **Step 1: Write the failing test** — assert `text(channel: 1, channelCount: 2, startTimecode: "01:00:00:00")` contains `"R"`, `"LTC"`, `"muted"`, and the timecode; `channel: 0, channelCount: 2` → `"L"`; `channel: 2, channelCount: 4` → `"Ch 3"`.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Implement `LTCBadgeLabel` and use it in the badge** (`PreviewPane.swift`), passing the channel count from the asset/track (fallback to the index label if the count is unknown). Keep the existing `ltcDetectedBadge` accessibility id.

- [ ] **Step 4: Run to green + build + lint.**

- [ ] **Step 5: Commit** — `feat(waveform): name the LTC channel and its muted state in the badge`.

---

### Task 8: Wire-through + acceptance

**Files:**
- Test: `OnlyCueUITests/WaveformSplitChannelsUITests.swift` (added if a fixture makes it feasible; else documented manual steps)

- [ ] **Step 1: End-to-end trace (report).** Walk each spec Gherkin scenario to the code: OFF → single combined music-only waveform (Task 1 + untouched path); ON + stereo music → 2 lanes (Tasks 2/3/5/6); ON + LTC file → music lanes only, badge names the LTC channel (Tasks 6/7); OFF → byte-identical (Task 6 Step 3).

- [ ] **Step 2: UI acceptance.** If a striped/stereo fixture can be imported and the UI target builds (`xcodebuild build-for-testing`), add `WaveformSplitChannelsUITests` mirroring the Gherkin (toggle View ▸ Split Channels, assert `waveformLanes` appears with the right lane count, assert `ltcDetectedBadge` text). DEFER running (runner wedged) — note it, do not fabricate. If a fixture isn't feasible headlessly, document the concrete manual steps instead.

- [ ] **Step 3: Full unit suite + build + lint green; commit any test/doc.** `test(waveform): acceptance coverage for split-channel display` (or docs).

## Acceptance criteria → task map

| Spec criterion | Task |
|---|---|
| LTC file, toggle OFF → clean music-only waveform | 1, 6 |
| Toggle ON → stereo music shows 2 lanes; LTC file shows music lanes only | 2, 3, 5, 6 |
| Playhead / markers / seek / tempo / lyrics span full height across lanes | 6 |
| Badge names the LTC channel + muted state | 7 |
| Toggle default OFF → zero regression (byte-identical) | 4, 6 |
| No playback change; no per-channel mute UI | Global Constraints |

## Self-review notes
- OFF-path byte-identity is guaranteed by leaving the single-`peaks` branch untouched and gating every new path on `splitWaveformChannels` (Tasks 4/6).
- Cache axes are orthogonal: combined (`-<res>`), music-only-combined (`-xc<N>`), per-channel (`-ch<N>`) — no collision (Task 3 test).
- The LTC channel is excluded in BOTH the combined path (`excludingChannel`) and the per-channel path (`channelPeaks` omits it) and never becomes a lane (Task 6); it is surfaced only by the badge (Task 7).
