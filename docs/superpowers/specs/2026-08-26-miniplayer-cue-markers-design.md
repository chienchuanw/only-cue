# Mini Player — cue markers on the progress bar (read-only)

**Status:** approved (grill 2026-08-26 in zh-Hant; Figma approved 2026-08-26)
**Figma:** file `NhH2957iKQ8b581x3gI3Wk`, page "Screens", section "Mini Player
(macOS)" `577:3020` — Cue Mode `581:3020` and Show Mode `583:3020` now carry the
marker layer; Empty `583:3058` deliberately has none (duration 0 → nothing
drawn, per data rule 2). Section `623:3325` "Mini Player — Cue Markers · density
rationale" keeps the density stress case `623:3420` that decided rules 4 and 7.
**Supersedes (partially):** the "waveform/scrub" out-of-scope line in
`2026-08-16-miniplay-design.md` — this adds *marker overlay only*, still no waveform.

## Problem & goal

The Mini Player's progress bar (`OnlyCue/UI/MiniPlayerView.swift:48-90`) is a
featureless indigo fill. An operator driving a show from the Mini Player can see
*where the playhead is* but not *where the cues are* — no sense of "a dense
stretch is coming up" or "nothing happens for the next minute". The main window's
waveform already answers this; the Mini Player exists precisely so the main
window can be out of the way.

**Goal:** render the active media's cues as colored ticks on the Mini Player
progress bar, purely as an overview. **Read-only — no editing, no selection, no
click-to-seek-to-cue.**

## The density constraint (drives most decisions)

The panel's minimum width is 660pt (`MiniPlayerSize.swift`), leaving roughly
600pt for the bar. A 5-minute song is therefore **~2pt per second** — two cues
one second apart are visually on top of each other. Every visual decision below
is made against that number, not against the roomy main-window waveform.

## Confirmed decisions

1. **Form:** a **2pt-wide × 9pt-tall vertical tick** per cue, centered in the
   existing 11pt progress row. The track is only 4pt tall, so ~2.5pt of each tick
   overhangs above and below onto the panel's `DS.Color.surface` background.
   Rejected: dots (unreadable at 2pt/s), a separate marker lane (needs panel
   height), segment tinting (turns into mush when cues are dense).
2. **Panel height stays 84pt.** No change to `MiniPlayerController`'s locked
   height or its config tests. The Mini Player's value is being small.
3. **Which cues:** every cue of the active `MediaItem` whose `CuePointType`
   has `isVisible == true` — the same flag that shows or hides a Type's lane in
   the timeline breakdown (`TimelineBreakdownLayout`), so hiding a Type hides it
   here too. **This deliberately does *not* match the waveform:**
   `CueMarkersOverlay` ignores `isVisible` and draws every cue. The tick strip
   is conceptually a compressed *breakdown*, not a compressed waveform — the
   breakdown is where "which Types am I looking at right now" is already
   expressed, and the Mini Player exists to replace exactly that overview when
   the main window is out of the way. (Corrected 2026-08-26: the original
   wording claimed the strip matched "what the main window shows", which is
   only true of the breakdown lanes, not the waveform markers.)
   **Identical in Cue mode and Show mode** — the `showGoTypeID` filter is
   deliberately *not* applied.
4. **Overlap:** none of it is managed. Ticks are drawn in time order and later
   ticks overdraw earlier ones, exactly like `CueMarkersOverlay`. **No bucketing,
   no merging, no "N cues here" affordance.** A dense stretch rendering as a
   solid color block is the correct message: *this section is busy*. Bucketing
   would add complexity and distort the color semantics.
5. **No hit testing.** The tick layer is `.allowsHitTesting(false)`. Clicking a
   tick behaves exactly like clicking the bar next to it — the existing
   `DragGesture(minimumDistance: 0)` seek is untouched. Snap-to-cue was rejected:
   at 2pt/s the snap radius would span several seconds, making ordinary seeking
   unpredictable. **This is the decision most likely to be revisited; the reason
   it was declined is the density, not a lack of interest.**
6. **Z-order:** track → `cueIndigo` fill → **tick layer** → knob. The whole
   song's cue distribution stays visible for the entire playback (that *is* the
   feature); the knob is never sliced by a tick.
7. **Contrast:** no outline, no stroke. The ~5pt of overhang onto the dark panel
   background carries the readability; the color is a category hint, not
   something to be read precisely. Adding a 1pt outline would make each tick 4pt
   wide and fuse cues two seconds apart into one blob.
   **Accepted trade-off, validated against the Figma stress case:** on the
   *played* (indigo-filled) portion, cool-colored ticks (`#4D96FF`, `#9D7EE0`)
   keep their **position** legible via the overhang but lose their **type
   color** — they read as slightly-lighter indigo. Judged acceptable because
   type identity matters least for cues already passed.
8. **No played/unplayed distinction and no current-cue emphasis.** The playhead
   already splits the bar into before/after, and the `cueBlock` text already
   names the current and next cue. Re-encoding either on the timeline is
   redundant and becomes noise in dense stretches.

**Out of scope:** editing, selection, tooltips/hover, cue numbers on the ticks,
lyric markers, waveform, Windows.

## Data rules (the entire unit-test surface)

Derived by a pure function on `MiniPlayerModel`:

1. Include a cue only if its `CuePointType` resolves and `isVisible == true`
   (decision 3 — the breakdown-lane flag, not the waveform's rule). Because the
   type must resolve, the emitted colour is non-optional.
2. Skip cues whose `time` is outside `[0, duration]`. When `duration <= 0`, the
   layer draws nothing. (Out-of-range cue times are real — the `set-list-act-i`
   Figma mock itself has cue times exceeding the clip length. Clamping them to
   the right edge would fabricate a fake thick tick there; relying on clipping
   would be implicit and awkward to test.)
3. Position fraction = `time / duration`; the view draws at
   `fraction * width - lineWidth / 2`, matching `CueMarkersGeometry.position`.
4. Color = `ProjectModel.colorHex(for:)` → `Color(hex:)`, falling back to
   `.accentColor` — the same resolution path as `CueMarkersOverlay`.

## Architecture

- **Derivation:** a pure, testable function on `MiniPlayerModel` producing an
  array of `(fraction, colorHex)` in time order. No new data plumbing —
  `MiniPlayerHostView` already receives `document.model.activeItem` and
  `cuePointTypes` (`MiniPlayerHostView.swift:25-33`).
- **Rendering:** `MiniPlayerCueMarkers` — an **`Equatable` view wrapping a
  `Canvas`**, depending only on
  the derived ticks and the geometry width — **never on `currentTime`**.
  This matters: `MiniPlayerHostView` re-derives its model on every render and
  `engine.currentTime` advances every frame, so the progress row repaints at
  30–60Hz while playing. A `ForEach` of `Rectangle`s would relayout hundreds of
  views per second in an always-on-top panel; the `Equatable` + `Canvas` pair
  makes the tick layer completely static during playback. Since the ticks are
  non-interactive (decision 5), `Canvas` costs nothing.
- **Token gate:** `MiniPlayerView.swift` is not in
  `TokenConformanceTests.mainWindowFiles`, so the tick geometry constants do not
  conflict with the `DS.*` gate. Colors are hex-derived, the established pattern.
- **Accessibility:** the ticks are invisible to VoiceOver by construction. The
  progress bar gains a short accessibility hint ("N cue markers on the
  timeline"), localized to zh-Hant. Individual ticks are deliberately *not*
  focusable elements — that would trap VoiceOver on the bar for dozens of stops.

## Verification strategy

- **Unit tests (TDD, red first, separate commit):** `MiniPlayerCueMarkerTests`
  — the four data rules above: `isVisible` filtering, out-of-range skipping,
  `duration <= 0`, fraction math, color resolution + fallback, time ordering.
- **Screenshot test:** `MiniPlayerViewScreenshotTests` gains a **dense-cue**
  state, producing a PNG that pairs with the dense Figma mock for the
  Figma↔app check.
- **No XCUITest:** there is no interactive behaviour to drive, and the Mini
  Player UI tests are already marked flaky on the self-hosted runner.
- No ADR. This is a view-layer presentation choice with no cross-subsystem
  constraint; decisions 4 and 5 are recorded here instead.

## Delivery

Single `feat` issue, branch `issues/<N>`, PR into `dev`. This spec is committed
separately from the implementation commits. Issue checklist order:

1. ~~Figma proposal frame approved by the maintainer~~ — **done 2026-08-26**.
2. ~~Rewrite the canonical Mini Player frames with the approved marker layer.~~
   — **done 2026-08-26** (`581:3020`, `583:3020`).
3. ~~Failing `MiniPlayerModelTests` → derivation → green.~~ — **done
   2026-08-26**, as `MiniPlayerCueMarkerTests` (its own file; folding it into
   `MiniPlayerModelTests` breached SwiftLint's `type_body_length`).
4. ~~`Canvas` tick layer + z-order + accessibility hint (+ zh-Hant string).~~
   — **done 2026-08-26** (`OnlyCue/UI/MiniPlayerCueMarkers.swift`; hint
   `"Cue markers: %lld"` → `"Cue 標記：%lld"`).
5. ~~Dense-state screenshot baseline; Figma↔app comparison.~~ — **done
   2026-08-26** (`miniplayer-dense-dark`). The comparison confirmed decision 7's
   recorded trade-off: cool ticks on the indigo fill keep position, lose colour.

**Known drift, deliberately not fixed here:** the Figma Mini Player frames are
620×118, while the shipped panel is 660–1000 wide × 84 tall. Unrelated to this
feature. The "Mini Player — Resize Range" group `607:3185` also still shows the
progress bar without markers.
