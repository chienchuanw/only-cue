# Spec — Waveform display for video imports

**Date:** 2026-05-08
**Status:** Approved (brainstorming)
**Implements / extends:** `docs/mvp-scope.md` row 3 (Preview pane), `docs/build-sequence.md` steps 4 (video preview) and 5 (waveform), `docs/architecture.md` "PreviewPane.swift — Switches video vs waveform".

## Summary

When a video file is imported, the preview pane currently shows the picture only. After this change it shows the picture **and** a waveform strip beneath it, sourced from the video's first audio track. Cue markers, drag-to-retime, and click-to-seek work on the video's waveform identically to the audio case. Silent videos render a flat baseline so marker editing still works.

## Motivation

Cue authoring is a timeline activity. Today the marker overlay (drag-to-retime, click-to-seek) lives only on the waveform, so video imports lose the timeline UX entirely — users can only seek via the transport bar and `⌘+M` at playhead. Surfacing a waveform under video gives video imports the same authoring affordances as audio.

This also corrects a small but visible product asymmetry: the MVP doc reads "Audio shows a waveform; video shows the picture," which implicitly de-prioritizes timeline editing for video.

## Design decisions (from brainstorming)

1. **Layout** — Video on top, waveform strip below, both always visible. Vertical stack inside the existing preview pane bounds.
2. **Waveform height** — Fixed at 100pt. Video frame takes the remaining height. No user-resizable divider.
3. **Silent video** — Generator returns flat peaks (`[Float](repeating: 0, count: resolution)`) instead of throwing. Renderer naturally draws a baseline; markers remain draggable.

## Architecture

### `PreviewPane.swift`

The video case changes from a single `AVPlayerLayerView` to a `VStack` of player layer + `WaveformContainer.frame(height: 100)`. The audio case is unchanged. The waveform path reuses the existing `engine.player.currentItem?.asset as? AVURLAsset` lookup that already works for the audio branch.

Sketch:

```swift
case .video:
    if let asset = engine.player.currentItem?.asset as? AVURLAsset {
        VStack(spacing: 0) {
            AVPlayerLayerView(player: engine.player)
                .accessibilityIdentifier("videoPreview")
            WaveformContainer(
                asset: asset,
                cues: document.model.cues,
                onSeek: { time in Task { await engine.seek(to: time) } },
                onRetime: { cueId, newTime in
                    CueCommands.retime(
                        cueId: cueId,
                        to: newTime,
                        document: document,
                        undoManager: undoManager
                    )
                }
            )
            .frame(height: 100)
            .accessibilityIdentifier("videoWaveform")
        }
    } else {
        AVPlayerLayerView(player: engine.player)
            .accessibilityIdentifier("videoPreview")
    }
```

### `WaveformGenerator.swift`

Change `peaks(for:resolution:)` to early-return flat peaks when the asset has no audio track, instead of throwing `WaveformError.noAudioTrack`:

```swift
guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
    return [Float](repeating: 0, count: resolution)
}
```

`WaveformError.noAudioTrack` is removed (YAGNI; no remaining callers). `WaveformError.readerFailed` stays for genuine reader failures mid-stream.

### `WaveformCache.swift`

No change. The cache hashes the file and stores the resulting peaks — flat peaks for a silent video are valid cache entries and will hit on second open.

### `WaveformContainer.swift`, `WaveformView.swift`, `CueMarkersOverlay.swift`

No source changes. They consume `[Float]` peaks and a duration; both are well-defined for silent video.

## Edge cases

| Case | Behavior |
| --- | --- |
| Video with audio | Waveform renders peaks, markers drag/seek normally. |
| Video with no audio track | Flat baseline, markers drag/seek normally. |
| Video where `AVAssetReader` fails mid-stream | `WaveformError.readerFailed` thrown, container shows existing error state. |
| No media imported | Existing empty-state placeholder, unchanged. |
| Audio-only import | Unchanged path — waveform fills the pane (no video frame above). |
| Reopen after restart (security-scoped bookmark relink) | Asset is re-resolved before this view runs; no special handling needed. |

## Tests (TDD order)

### Unit — `OnlyCueTests/WaveformGeneratorTests.swift`

1. **Red:** Replace the existing "throws `noAudioTrack` for silent asset" test with: `peaks(for:resolution:)` on an asset with no audio track returns an array of `resolution` zeros. Test fails because the current code still throws.
2. **Green:** Apply the early-return change. Test passes.
3. **Regression:** Existing test that verifies non-flat peaks for an audio fixture must still pass unchanged.

If a silent-video fixture is awkward to add, synthesize an `AVMutableComposition` with no audio track in the test, or reuse an existing audio fixture stripped of its track. Prefer synthesis to keep `OnlyCueTests/Fixtures/` lean.

### UI — `OnlyCueUITests/`

Acceptance scenario (BDD):

```gherkin
Feature: Video preview shows a waveform
  Scenario: Importing a video reveals the waveform strip
    Given OnlyCue is open with no media
    When I import a video file with an audio track
    Then the preview pane shows the video frame
    And the preview pane shows a waveform strip below the video
    And dragging a cue marker on the strip retimes the cue

  Scenario: Importing a silent video shows a flat baseline
    Given OnlyCue is open with no media
    When I import a video file with no audio track
    Then the preview pane shows the video frame
    And the preview pane shows a flat waveform baseline below the video
    And clicking on the strip seeks the player
```

Identifiers to assert:

- `videoPreview` — present in both video sub-cases (existing).
- `videoWaveform` — new; present only in the with-asset branch.
- `cueMarkerOverlay` (existing) — must be hit-testable inside `videoWaveform`.

If full UI tests are infeasible without a real video fixture, the unit-level coverage of `WaveformGenerator` plus a manual verification entry in `docs/verification.md` is acceptable for this iteration.

## Files touched

| File | Change |
| --- | --- |
| `OnlyCue/UI/PreviewPane.swift` | Video case becomes stacked VStack with waveform strip at 100pt. |
| `OnlyCue/Media/WaveformGenerator.swift` | Flat-peaks early return for assets with no audio track; remove `WaveformError.noAudioTrack`. |
| `OnlyCueTests/WaveformGeneratorTests.swift` | Update silent-asset test to assert flat peaks; add synthesized silent-asset test if needed. |
| `OnlyCueUITests/…` | Add or extend a UI test for the stacked video+waveform composition (best-effort; see Tests section). |
| `docs/mvp-scope.md` | Row 3 updated: "Audio shows a waveform; video shows the picture **and** a waveform." |
| `docs/architecture.md` | Update PreviewPane comment from "Switches video vs waveform" to "Video stacks waveform below; audio fills with waveform". |
| `docs/build-sequence.md` | Note in step 4 that video preview composes the step-5 waveform component. |

## Hard rules check (from `CLAUDE.md`)

- No App Sandbox entitlements changed (none touched).
- No `.cuelist` schema change.
- No deployment-target change.
- No direct mutations of `ProjectModel` — UI continues to call `CueCommands.retime` for marker drag.
- No new media embedding — same security-scoped bookmark path.

## Out of scope

- Resizable divider between video and waveform.
- Multi-track audio selection (which audio track to visualize).
- Stereo waveform rendering, color-coded peaks, zoom.
- Waveform display for video thumbnails (timeline strip distinct from waveform).
- Auto-detecting and toggling the strip off for silent videos — explicitly chosen against in design decision 3.

## Risks

- **Test fixture for silent video** — Adding a real silent `.mp4` to fixtures bloats the repo; synthesis via `AVMutableComposition` is preferred but adds test complexity. Mitigation: synthesize, fall back to a tiny generated fixture if synthesis is brittle on CI.
- **Layout regressions on small windows** — Fixed 100pt strip plus video may squeeze the video frame on short windows. Mitigation: rely on `PreviewPane`'s existing `minHeight: 180`; if it proves too tight, raise `minHeight` to 220 in a follow-up rather than making the strip flexible.
