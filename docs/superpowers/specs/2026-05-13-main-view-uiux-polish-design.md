# Main View UI/UX Polish — Design

Date: 2026-05-13
Status: Approved (pending written-spec review)

## Summary

Six independent improvements to the main document view (`DocumentView` + the waveform stack). They share no state, so this is filed as an **epic with one leaf issue per item**, consistent with how the repo handles epics. Each lands as its own PR.

1. Rename user-facing "OnlyCue" → "Only Cue" (display strings only).
2. Declutter the main pane (remove redundant labels/hints from the loaded state).
3. High-resolution waveform peaks + render-time bucketing, drawn as a filled mirrored envelope (DAW-style) instead of rounded bars.
4. Smooth playhead motion: faster time observer **and** display-link interpolation.
5. Keep the floating time label above the playhead; keep the transport's elapsed/total readout.
6. Click-to-seek anywhere on the waveform; drag still scrubs; hand cursor over the playhead line.

## Non-goals

- No true min/max waveform envelope (single magnitude per column is enough for now; the rendering layer should not preclude adding it later, but no work toward it this round).
- No on-demand per-zoom regeneration of peaks (Reaper-style); high-res-once + bucketing is the chosen model.
- No rename of code identifiers: Xcode target, scheme, module name, bundle identifier, `.cuelist` UTI, and `OnlyCue.*` notification-name prefixes all stay `OnlyCue`.
- No change to the `.cuelist` schema or `ProjectModel`.

---

## 1. Rename "OnlyCue" → "Only Cue" (display only)

**Change:** user-facing strings only.
- `Info.plist`: set `CFBundleDisplayName` to `Only Cue` (add it if absent).
- `FirstLaunchSheet`: "Welcome to Only Cue".
- Any other visible literal "OnlyCue" in views/alerts/menus → "Only Cue".

**Keep as `OnlyCue`:** target, scheme, module, bundle identifier, UTI, notification name prefixes, source folders, repo name. Renaming those is churn with no user benefit and risks breaking saved security-scoped bookmarks and document type association.

**Verify:** app menu, About box, and window title show "Only Cue"; existing `.cuelist` documents still open.

---

## 2. Declutter the main pane (minimal)

In `DocumentView.mainPane`, **loaded state**:
- Remove `Text("OnlyCue")` title.
- Remove the `mediaSummary` line ("name — duration"); the media name is already shown via `.navigationSubtitle`. If duration is wanted there, extend the subtitle string — optional, not required.
- Remove the `cueCount` line entirely (not relocated — it isn't useful enough to keep).
- Remove `DocumentShortcutHints` from the loaded state.
- "Import Media…" button: shown only in the **empty / no-media state** (File menu and drag-drop already cover the loaded case). "Add Cue" button stays in the loaded state.
- `DocumentShortcutHints`: rendered only when no media is loaded (empty-state onboarding).

**Keep:** the hidden keyboard-shortcut `Button`s (transport / digit / step) — invisible plumbing, not clutter.

**Result (loaded):** preview → waveform → transport bar → "Add Cue". **Empty state:** "Import Media…" + shortcut hints (onboarding).

---

## 3. High-resolution waveform + render-time bucketing + filled mirrored envelope

### Peak generation
- `WaveformGenerator` produces a **high-resolution** peak array sized so that at maximum zoom (16×) there is roughly ≤ 1 peak per on-screen pixel. Express this as a fixed large column count (order 8k–16k) or "one peak per N audio frames", whichever the generator expresses more naturally. One `Float` magnitude per column.
- The `resolution` parameter threaded through `WaveformContainer` is bumped accordingly.

### Cache
- Same on-disk format (`[Float]`), just longer arrays (~tens to low-hundreds of KB per track).
- `WaveformCache` keys already include `resolution`, so old 512-entry caches are simply not matched and regenerate on next open — **no migration**.

### Rendering (`WaveformView`)
- Replace per-peak rounded bars with:
  1. Bucket the source peaks down to the current pixel width (`size.width`), taking the **max** within each bucket. If pixel width ≥ peak count, fall back to direct (or interpolated) sampling.
  2. Build a single closed `Path`: top contour left→right at `midY - peak·midY·verticalZoom`, then bottom contour right→left mirrored, close.
  3. Fill it with the accent color. No inter-column gap; clamp minimum visible height to ~0.5pt so silence still draws a hairline.
- `verticalZoom` is applied to the half-height exactly as today.

This makes zoom genuinely reveal detail: more source resolution + per-pixel bucketing replaces "stretch 512 columns across whatever width".

---

## 4. Smooth playhead motion (faster observer + display-link interpolation)

- `PlayerEngine`: change the `addPeriodicTimeObserver` interval from `0.1s` to ~`1/60s`. `currentTime` remains the authoritative value updated from this callback.
- Add a display-link-driven rendered position:
  - While playing, the on-screen playhead advances from the last observed `currentTime` by `elapsedWallClock × playbackRate`, clamped to `[0, duration]`, and snaps to the true `currentTime` on each observer tick.
  - While paused or scrubbing, it shows the exact value (scrub state already wins via `scrub.state?.scrubTime`).
  - Implementation: `CADisplayLink` (or SwiftUI `TimelineView(.animation)`) feeding the playhead `x` computation in `WaveformPlayheadLayer` / `PlayheadOverlay`.
- Auto-follow scroll keys off the same rendered position, so it tracks smoothly too.

---

## 5. Time label above the playhead; keep transport readout

- `PlayheadOverlay` already renders an `hms` label above the playhead and clamps it to the viewport edges. Keep it; verify legibility in the decluttered layout (it sits where the removed labels used to be).
- The transport bar keeps its `elapsed / total` readout — different purpose (scrubber context vs. position on the waveform).
- No structural change; this item is mostly verification + minor polish of the existing overlay label.

---

## 6. Click-to-seek on the waveform body

- Add a tap gesture covering the waveform content area. The playhead layer already lives in the `contentWidth` coordinate space, so: `time = localX / contentWidth × duration`; horizontal scroll/zoom is handled for free. On tap → `engine.seek(to: time)` immediately.
- **Drag still scrubs:** the existing press-and-drag scrub-preview (pause → follow finger → seek on release → resume if it was playing) stays. Its hit target becomes the **playhead line itself** rather than a separate 12pt grabber.
- **Cursor:** hovering the playhead line shows `NSCursor.openHand` (→ `closedHand` while dragging) to signal scrub mode. Elsewhere on the waveform, the default arrow (a click there seeks).
- **Tap vs. drag disambiguation:** a press that becomes a drag must not also fire a seek. Use a drag gesture with a small `minimumDistance` for scrub; a zero-distance press on the waveform body is the seek tap. (The current scrub gesture uses `minimumDistance: 0` on the grabber; split into tap-to-seek on the body + drag-to-scrub on the playhead line.)

---

## Testing

**Unit**
- Peak bucketing: N source peaks + pixel width → correct max-per-bucket array; edge cases: width > peak count, width == 1, empty peaks.
- `x ↔ time` mapping for click-to-seek (including at zoom > 1 with a scroll offset).
- Interpolation math: `currentTime + rate·dt` clamped to `[0, duration]`; snap-back on observer tick.

**UI tests** (`OnlyCueUITests/`)
- Clicking the waveform moves the playhead to that position.
- Dragging the playhead line still scrubs and resumes playback on release.
- Loaded main pane no longer shows the app title, media-summary line, cue-count line, or shortcut hints.
- Empty state still shows the "Import Media…" button and the shortcut hints.

**Manual / BDD acceptance**
- Given media is playing, the playhead glides smoothly (no 0.1s stepping).
- Given the pointer is over the playhead line, the cursor is a hand; elsewhere on the waveform it is an arrow.
- Given a zoomed-in waveform, more amplitude detail is visible than at 1× (not just magnified blocks).
- Given the app is running, the menu bar, About box, and window title read "Only Cue".

---

## Suggested leaf issues

1. `chore`/`refactor`: rename display strings to "Only Cue".
2. `refactor`/`feat(ui)`: declutter main pane (minimal); move Import button + hints to empty state.
3. `feat(media)`: high-resolution waveform peak generation + cache bump.
4. `feat(ui)`: filled mirrored-envelope rendering with render-time bucketing.
5. `feat(media)`/`fix`: smooth playhead — faster time observer + display-link interpolation.
6. `feat(ui)`: click-to-seek on the waveform body + playhead-line drag + hand cursor.

(Items 3 and 4 can be one issue if the generator and renderer changes are small enough to review together; otherwise split as above.)
