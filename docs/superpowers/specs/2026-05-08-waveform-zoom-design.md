# Waveform horizontal zoom + playhead line thinning — design

**Date:** 2026-05-08
**Status:** Approved
**Spec sections:** `docs/architecture.md` (waveform layer), `docs/verification.md` (new manual step)

## Problem

The waveform always fills its container width with 512 peak bars, regardless of clip duration. For a 10-minute song, each bar represents ~1.2 seconds — too coarse to place cues on transients with confidence. There's no way to zoom in for detail. Separately, the `PlayheadOverlay` line is `2pt` wide, which obscures the exact frame the playhead sits on; the user wants it thinner.

## Goal

The user can zoom the waveform horizontally for detailed cue placement, while playback still keeps the playhead in view. The playhead line is thinner so it reads as a precise pointer rather than a stripe. Behavior is identical for the audio-pane waveform and the video-strip waveform — both use the same `WaveformContainer`.

## Decisions

Captured during brainstorming, all user-confirmed:

1. **Trigger:** Trackpad pinch (`MagnifyGesture`) plus `⌘=` / `⌘-` / `⌘0` keyboard shortcuts wired through the `View` menu.
2. **Semantics:** Stretch + scroll. The 512-peak array is unchanged; the content frame grows to `viewport × zoom` and `WaveformView`'s `Canvas` re-scales bars accordingly. No re-sampling, no extra `AVAssetReader` work, no new cache entries.
3. **Range:** `1×` to `16×`. Zoom is ephemeral — not persisted to `.cuelist`, no schema bump. Resets when the active item changes (free via the existing `.id(url)` on `WaveformContainer` in `PreviewPane`).
4. **Auto-follow during playback:** When zoomed in (`zoom > 1`) and the playhead crosses ~80% of the visible viewport, scroll programmatically so the playhead lands at ~20%. User-initiated scroll disengages follow until the next `seek` or `play-from-stopped` event.
5. **Scope:** Both audio-pane and video-strip waveforms. Same `WaveformContainer` powers both — fix once.
6. **Bundled cleanup:** `PlayheadOverlay.lineWidth: 2 → 1`. Single line. Same PR.

## Design

### New: `WaveformZoomController`

Pure view-state holder. No SwiftUI imports — fully unit-testable.

```swift
@Observable
final class WaveformZoomController {
    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 16
    static let zoomStep: CGFloat = 1.5

    private(set) var zoom: CGFloat = 1
    var followsPlayhead: Bool = true

    /// Sets zoom, clamped to [min, max], and adjusts `scrollOffset` so the time
    /// currently under `anchorFraction` (0...1 across viewport) stays under it.
    func setZoom(
        _ next: CGFloat,
        anchorFraction: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    )

    func zoomIn(anchorFraction: CGFloat = 0.5,
                viewportWidth: CGFloat,
                scrollOffset: inout CGFloat)   // multiplies by zoomStep
    func zoomOut(anchorFraction: CGFloat = 0.5,
                 viewportWidth: CGFloat,
                 scrollOffset: inout CGFloat)  // divides by zoomStep
    func reset(scrollOffset: inout CGFloat)    // zoom=1, follow=true, offset=0
}
```

Anchored zoom math (so the point under the cursor / pinch stays put):

```
contentWidth(z) = viewportWidth × z
timeFractionUnderAnchor = (scrollOffset + anchorFraction × viewportWidth) / contentWidth(currentZoom)
new contentWidth         = viewportWidth × newZoom
new scrollOffset         = timeFractionUnderAnchor × newContentWidth − anchorFraction × viewportWidth
```

Then clamp `scrollOffset` to `[0, contentWidth − viewportWidth]`.

### Modified: `WaveformContainer`

Wrap the existing `ZStack` (waveform + cue markers + playhead layer) in a horizontal `ScrollView`, sized to `viewport × zoom`:

```swift
GeometryReader { proxy in
    ScrollView(.horizontal, showsIndicators: zoom.zoom > 1) {
        ZStack(alignment: .topLeading) {
            WaveformView(peaks: peaks)
            CueMarkersOverlay(cues: cues, duration: loadedDuration, ...)
            if let engine { WaveformPlayheadLayer(engine: engine, ...) }
        }
        .frame(width: proxy.size.width * zoom.zoom,
               height: proxy.size.height)
    }
    .scrollPosition($scrollOffsetID)   // for programmatic scroll
    .gesture(MagnifyGesture()
        .onChanged { value in /* call zoom.setZoom around gesture location */ })
}
```

`CueMarkersOverlay` and `WaveformPlayheadLayer` stay untouched at the geometry level — they already compute `x` from `width × time / duration`. Feeding them the **content** width (not viewport width) keeps every marker aligned automatically. **This is the load-bearing insight.**

### Modified: `WaveformPlayheadLayer`

Existing job: draw the playhead at `x(currentTime)`. Adds a side-effect: when `zoom.followsPlayhead && zoom.zoom > 1` and the playhead's viewport-relative x exceeds 80% of viewport width, programmatically scroll so the playhead lands at 20%. Implementation via the parent `ScrollViewReader` / `.scrollPosition` binding passed in.

User-scroll detection: `.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { old, new in … }`. If a scroll change arrives that did not originate from the auto-follow side-effect (track via a small `isAutoScrolling` flag with a single-runloop reset), set `followsPlayhead = false`. `engine.seek` and `play-from-stopped` re-engage by setting `followsPlayhead = true`.

### Modified: `OnlyCueApp` (View menu commands)

Mirror the Space / ← / → wiring from PR #24:

```swift
CommandMenu("View") {
    Button("Zoom In") { /* dispatch to focused waveform */ }
        .keyboardShortcut("=", modifiers: .command)
    Button("Zoom Out") { … }
        .keyboardShortcut("-", modifiers: .command)
    Button("Actual Size") { … }
        .keyboardShortcut("0", modifiers: .command)
}
```

Dispatch path: a notification (e.g., `NotificationCenter` `Notification.Name(".waveformZoom")` with a `ZoomIntent` payload) that the focused `WaveformContainer` listens for via `.onReceive`. This avoids threading a controller reference through the document-group hierarchy. Same pattern PR #24 used for transport shortcuts.

### Modified: `PlayheadOverlay`

```swift
private static let lineWidth: CGFloat = 1   // was 2
```

No other changes.

## Tests

### `WaveformZoomControllerTests` (new)

- `setZoom_clampsToMinAndMax`
- `setZoom_anchoredAtCenter_keepsCenterTimeUnderCenter`
- `setZoom_anchoredAtFraction_keepsAnchorTimeUnderAnchor`
- `setZoom_atMin_clampsScrollOffsetToZero`
- `zoomIn_thenZoomOut_returnsToOriginalZoom` (within ε)
- `reset_restoresZoom1_followsPlayheadTrue_andZeroOffset`

### `WaveformAutoFollowTests` (new)

- `playheadAtSeventyPercent_doesNotScroll`
- `playheadAtNinetyPercent_scrollsToTwentyPercent`
- `userScrollWhileFollowing_disengagesFollow`
- `seekWhileNotFollowing_reEngagesFollow`
- `playFromStoppedWhileNotFollowing_reEngagesFollow`

### Existing tests remain green

- `CueMarkersGeometryTests` — math unchanged; tests already use parameterized width.
- `CueMarkersOverlayTests` — drag math unchanged.
- All snapshot/fixture tests — no model schema change.

### Manual verification (new step in `docs/verification.md`)

> **Step 15 — Waveform zoom.** Open a project with at least one ≥ 60s media item. Pinch outward on the waveform → bars grow, scroll bar appears, cue markers and playhead remain time-aligned. Press `⌘0` → returns to fit-width. Press `⌘=` three times, then play → playhead moves to ~80% then auto-scrolls forward. Scroll manually with two fingers → auto-follow disengages; playhead continues off-screen. Click a cue in the cue list → seek re-engages auto-follow. Switch to a different item via the sidebar → zoom resets to 1×. Confirm the playhead line is visibly thinner than before (1pt vs 2pt).

## Out of scope (deliberately)

- **Persisting zoom in `.cuelist`** — view state, not project state. No schema v3.
- **Re-sampling peaks at higher resolution** — stretch is sufficient at 1×–16×; re-sampling adds AVAssetReader work, cache entries, and async reload state.
- **Vertical (amplitude) zoom** — not requested.
- **Zoom-to-selection / zoom-to-cue** — useful future addition; not in this slice.
- **Touch Bar zoom controls.**
- **Pinch on the video preview itself** — the gesture is attached to the waveform strip; the `AVPlayerLayerView` above it is unaffected.

## Files touched

| File | Change |
|---|---|
| `OnlyCue/UI/WaveformZoomController.swift` | NEW |
| `OnlyCueTests/WaveformZoomControllerTests.swift` | NEW |
| `OnlyCueTests/WaveformAutoFollowTests.swift` | NEW |
| `OnlyCue/UI/WaveformContainer.swift` | wrap in `ScrollView`, add zoom controller + magnify gesture, frame to `viewport × zoom` |
| `OnlyCue/UI/WaveformPlayheadLayer.swift` | auto-follow side-effect, user-scroll detection |
| `OnlyCue/UI/PlayheadOverlay.swift` | `lineWidth: 2 → 1` |
| `OnlyCue/OnlyCueApp.swift` (or wherever existing `CommandMenu` lives) | View menu zoom commands + shortcuts |
| `docs/architecture.md` | one paragraph noting `WaveformZoomController` and that `WaveformContainer` is now scroll-hosting |
| `docs/verification.md` | new step 15 |

## Issue / PR labelling

`enhancement`, like #27 / #29 / #31. Post-MVP slice, not part of a phase 2 epic.
