# Handoff — #734 dual-envelope renderer (last of the #729 waveform-perf epic)

**Date:** 2026-08-09
**Branch to resume on:** `issues/734` (already created off `dev`, pushed).
**Spec:** `docs/superpowers/specs/2026-08-09-waveform-perf-large-file-design.md` (§4 render side, §5 render side)
**Plan:** `docs/superpowers/plans/2026-08-09-waveform-perf-large-file-plan.md`
**Parent epic:** #729

## Where the epic stands

The #729 waveform large-file perf work was sliced into 4 issues. Three are **merged to `dev`**:

- **#731 (A)** — constant-time head+tail `WaveformCache.fastFingerprint` (size + SHA256 of first/last 1 MB, no mtime). Waveform + `VideoPosterCache` share it. PR #735.
- **#732 (B)** — 8 kHz time-based **peak+RMS bucket engine** (`WaveformBucketGenerator.swift`: `WaveformBucket{peak,rms}`, `buckets(...)`, `bucketStream(...)`, `AsyncThrowingStream`, un-normalized) + **v4 bucket cache** (`WaveformCache.readBuckets/writeBuckets/bucketEntryURL`, `bucketFormatVersion = 4`, key `-<ms>ms[-xc<N>|-ch<N>]-bv4.buckets`). The legacy `RMSAccumulator` was extracted to `WaveformRMSAccumulator.swift`. PR #736.
- **#733 (C)** — `WaveformBucketCoordinator` (broadcast/coalescing actor: same key → one production, late-joiner replay, `cacheKey(...)` shared) + prewarmer rewrite (bucket cache, bounded concurrency 3, warm all on import, via coordinator) + `WaveformContainer.load()` progressive wiring (reads v4 cache; on miss `streamBuckets` with **16 ms throttle**) + **normalize-on-read adapter** `WaveformBucket.normalizedRMS(_:)`. Only the **downmix** path migrated; **split-channel lanes stay on the old `[Float]` path**. PR #737. Verified by `WaveformFollowUITests` end-to-end.

## What is already done ON THIS BRANCH (`issues/734`)

One commit ahead of `dev`:

- `c83948e perf(waveform): add RMS energy-average collapse for the dual envelope`
  - `WaveformPeakBucketer.bucketRMS(_ values:into:)` — downsamples by **RMS (√mean of squares)** per bucket (the loudness-faithful body), alongside the existing `bucket(peaks:into:)` (max, the transient outline). Fully unit-tested in `WaveformPeakBucketerTests.swift`.

This is the first foundational primitive for the dual envelope. Nothing else on D is done.

## Remaining D work (do these, TDD, in order)

### 1. Dual-envelope `WaveformView` + render-time normalization
- `OnlyCue/UI/WaveformView.swift` currently takes `let peaks: [Float]` and draws ONE mirrored envelope via `WaveformPeakBucketer.bucket` (max) + `halfHeight`.
- Change it to take **buckets** (peak + rms) — e.g. `let buckets: [WaveformBucket]` — and draw **two** layers:
  - **RMS body** (filled): collapse the rms channel with `bucketRMS`, normalize by the max of the loaded rms values **at render time**, draw as the solid fill (keeps #632 dynamics).
  - **Peak outline** (lighter/stroked): collapse the peak channel with `bucket` (max), normalize by the loaded peak max, draw on top so transients are visible at deep zoom.
- **Render-time normalization** replaces the normalize-on-read adapter: divide by the max of the currently-loaded buckets each draw (spec §5). When fully loaded this equals today's per-file normalization — assert byte-equivalence in a test.
- Keep `verticalFillRatio` (#628), `columnX` center-of-bucket mapping (#540), `bucketCount` cap (#681), achromatic color (ADR-024), `.accessibilityIdentifier("waveform")`.
- **HIGH RISK ZONE:** this is the #675 continuous-offset render + gesture / click-to-seek / accessibility area. CLAUDE.md warns explicitly. Verify after: click-to-seek, context-menu, `.sheet(item:)`, accessibility hit-tests, multi-channel lanes (#720), LTC strip alignment (#663), playhead follow (#677), zoom.

### 2. Container feeds buckets (drop the adapter)
- `WaveformContainer` `@State var peaks: [Float]?` → hold buckets instead (e.g. `@State var buckets: [WaveformBucket]?`), pass to `WaveformView`.
- `WaveformContainer+Buckets.swift streamBuckets` currently sets `peaks = WaveformBucket.normalizedRMS(snapshot)` on a 16 ms throttle → set the raw `buckets` snapshot instead (normalization moves into the view).
- `load()` cache-hit path: `peaks = normalizedRMS(cached)` → `buckets = cached`.
- Remove `WaveformBucket.normalizedRMS` once nothing calls it (it was the transitional #733 seam) — or keep if the view reuses the math.

### 3. Migrate split-channel lanes to buckets
- `WaveformContainer+Lanes.swift loadLanes` + `WaveformLanesView` still use `WaveformGenerator.channelPeaks` + `cache.read/write(...channel:)` (old v3 `[Float]`).
- Add a per-channel **bucket** generation path (channelBuckets) + v4 per-channel bucket cache (the `bucketEntryURL(...channel:)` key already exists) + coordinator keys per channel, and render each lane with the dual envelope.
- `keptChannelIndices` logic and true-index keying (#720) carry over.

### 4. Remove the old `[Float]` path
Once the container + lanes no longer use it:
- `WaveformGenerator.peaks(...)`, `channelPeaks(...)`, `keptChannelIndices(...)` (the `[Float]` API), `normalized(...)`, `silenceFloor`, `estimatedSampleCount`, `RMSAccumulator` machinery.
- `WaveformRMSAccumulator.swift` (whole file).
- `WaveformCache.read/write/entryURL` `[Float]` overloads + `formatVersion = 3`.
- `MediaPreviewStrip.swift` (2 sites) still calls `WaveformGenerator.peaks` — migrate to `buckets` + `normalizedRMS`/dual, or a simplified single-envelope for the small preview.
- Update/delete the old tests (`WaveformGeneratorTests` peak-based cases, `WaveformCacheTests` `[Float]` cases) — but keep the click-alignment / RMS-vs-peak intent as bucket-based tests.
- After this, spec §8's "formatVersion 3→4" is effectively realized (v3 gone; only `bucketFormatVersion` remains — consider renaming it to `formatVersion`).

## Design decisions already locked (from the 2026-08-09 grilling — do not relitigate)

- Analysis rate **8 kHz**, bucket width **10 ms**; store **peak (max-abs) + RMS**, **un-normalized**; normalize **at render time**.
- **Dual envelope** (option A): RMS body (overview, #632) + peak outline (deep-zoom transients). User places cues by eyeballing the sharpest transient, NOT beat-grid snap — the peak outline is load-bearing for them.
- Partial fingerprint has **no mtime** and **no "regenerate" escape hatch** (user signed off).
- `bucketFormatVersion` kept **separate** from legacy `formatVersion` during the rollout so existing caches weren't needlessly invalidated; collapse to one version when the old path is removed (step 4).

## Gotchas (learned this session)

- `OnlyCue.xcodeproj` is **gitignored** and generated by xcodegen. **Run `xcodegen generate` after adding/removing any source or test file**, or the new file won't compile in CI.
- **SwiftLint strict in CI** bit twice: `file_length` ≤ 400 (extract to a new file — that's why `WaveformRMSAccumulator.swift` and `WaveformContainer+Buckets.swift` exist), and `identifier_name` (no 1-char names, even in tests). **Lint the tests too**: `swiftlint lint --strict --quiet $(git diff dev...HEAD --name-only -- '*.swift')` before pushing.
- Unit tests: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/<Class>`. Run `killall -9 testmanagerd` first (env wedge). Ignore the `com.apple.linkd.autoShortcut` connection log noise.
- UITests: add `CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO`, `killall -9 testmanagerd` first. `WaveformFollowUITests` is the key end-to-end waveform check (~28 s). See memory notes on UITest wedges if it hangs.
- SourceKit "Cannot find type WaveformBucket / WaveformGenerator" diagnostics across files are **index noise** — the real `xcodebuild` compiles fine.
- Full unit suite was ~1450 tests, ~6 s, all green — run it before the PR (`-only-testing:OnlyCueTests`).

## Process for D (per CLAUDE.md / project loop)

TDD (red→green, commit failing test separately) → run full unit suite → **run the waveform UITests** (this is the mandated UI verification for the #675 zone) → `simplify` pass → open PR with `.github/PULL_REQUEST_TEMPLATE/perf.md` (OnlyCue verification block) → two-axis code review → CI green → rebase-merge into `dev`, `--delete-branch`. Then `dev` can be fast-forwarded toward `main` for release, and the #729 epic is complete.
