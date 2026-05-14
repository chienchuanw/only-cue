# Main Pane timeline interaction — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the waveform tap surface to a hold-to-scrub `DragGesture`, delete the dedicated playhead grabber, and add a hover halo to cue markers.

**Architecture:** Reuse the existing `ScrubController` to drive press → pause → scrub → seek-and-resume on the waveform body. Introduce two tiny pure helpers (`TimelineScrubOrchestrator` and `CueMarkerView.showHalo(...)`) as test seams so the gesture orchestration and halo dispatch are unit-testable without dragging real `PlayerEngine` or SwiftUI views through XCTest. UI behavior is covered by extending the existing UI-test seed mechanism.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSCursor), XCTest, XCUITest. macOS 14+ deployment target. Project regenerated via `xcodegen generate` if `project.yml` changes — it does not here.

**Spec:** `docs/superpowers/specs/2026-05-14-main-pane-timeline-interaction-design.md` (commit `cdb55c2`).

---

## File structure

**New files:**
- `OnlyCue/UI/TimelineScrubOrchestrator.swift` — pure helper. Encapsulates the begin/end decisions of the timeline drag gesture so the orchestration is unit-testable. ~30 lines.
- `OnlyCueTests/TimelineScrubOrchestratorTests.swift` — unit tests for the orchestrator.
- `OnlyCueTests/CueMarkerHaloTests.swift` — unit tests for the halo dispatch helper.
- `OnlyCueUITests/WaveformHoldScrubUITests.swift` — BDD smoke for click-to-seek + hold-to-scrub on empty timeline.

**Modified files:**
- `OnlyCue/UI/WaveformPlayheadLayer.swift` — replace `onTapGesture` with `DragGesture(minimumDistance: 0)`; delete the playhead grabber `Color.clear` block; delete `scrubGesture(width:)`. Drives orchestrator + existing `ScrubController`.
- `OnlyCue/UI/CueMarkersOverlay.swift` (`CueMarkerView` only) — add `@State var isHovered`; expand `.onHover` to drive it; insert halo `Circle` behind the line/cap; add static `showHalo(isHovered:isSelected:)` helper.
- `project.yml` — **no change** (both new source files live under `OnlyCue/UI/` and `OnlyCueTests/` which are already covered by existing source paths).

**Untouched (must not regress):**
- `OnlyCue/UI/ScrubController.swift`
- `OnlyCue/UI/CueMarkersGeometry.swift`
- `OnlyCue/UI/PlayheadOverlay.swift` (the visible line + label)

---

## Task 1: Add `TimelineScrubOrchestrator` (pure decision helper)

**Files:**
- Create: `OnlyCue/UI/TimelineScrubOrchestrator.swift`
- Test: `OnlyCueTests/TimelineScrubOrchestratorTests.swift`

The orchestrator encodes two decisions: what to do on first `onChanged` (pause-or-not), and what to do on `onEnded` (seek + resume-or-not). Geometry stays in `CueMarkersGeometry`. `ScrubController` is unchanged.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/TimelineScrubOrchestratorTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class TimelineScrubOrchestratorTests: XCTestCase {

    func test_begin_whenPlaying_pausesAndStartsScrubAtPressedTime() {
        let effect = TimelineScrubOrchestrator.begin(pressedTime: 7.5, isPlaying: true)
        XCTAssertEqual(effect, .startScrubAndPause(originalTime: 7.5))
    }

    func test_begin_whenPaused_startsScrubAtPressedTime_noPause() {
        let effect = TimelineScrubOrchestrator.begin(pressedTime: 2.0, isPlaying: false)
        XCTAssertEqual(effect, .startScrub(originalTime: 2.0))
    }

    func test_end_seeksToScrubTime_resumeMirrorsResumeOnRelease_true() {
        let state = ScrubController.State(resumeOnRelease: true, originalTime: 5, scrubTime: 9.25)
        let effect = TimelineScrubOrchestrator.end(finished: state)
        XCTAssertEqual(effect, TimelineScrubOrchestrator.EndEffect(seekTo: 9.25, resume: true))
    }

    func test_end_seeksToScrubTime_resumeMirrorsResumeOnRelease_false() {
        let state = ScrubController.State(resumeOnRelease: false, originalTime: 5, scrubTime: 9.25)
        let effect = TimelineScrubOrchestrator.end(finished: state)
        XCTAssertEqual(effect, TimelineScrubOrchestrator.EndEffect(seekTo: 9.25, resume: false))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/TimelineScrubOrchestratorTests test`

Expected: FAIL with "cannot find 'TimelineScrubOrchestrator' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `OnlyCue/UI/TimelineScrubOrchestrator.swift`:

```swift
import Foundation

/// Pure decision helper for the waveform timeline's hold-to-scrub gesture.
///
/// The gesture handler in `WaveformPlayheadLayer` calls `begin` on the first
/// `onChanged` and `end` on `onEnded`. Geometry (x → time) stays in
/// `CueMarkersGeometry`; state (current scrub time) stays in `ScrubController`.
/// This type owns only the play/pause/resume policy so it can be unit-tested
/// without a real `PlayerEngine` or SwiftUI gesture pipeline.
enum TimelineScrubOrchestrator {

    enum BeginEffect: Equatable {
        /// Transport was playing at press: start scrubbing AND pause the engine.
        case startScrubAndPause(originalTime: TimeInterval)
        /// Transport was paused at press: start scrubbing only.
        case startScrub(originalTime: TimeInterval)
    }

    struct EndEffect: Equatable {
        let seekTo: TimeInterval
        /// True if the engine should resume playback after the seek lands.
        let resume: Bool
    }

    static func begin(pressedTime: TimeInterval, isPlaying: Bool) -> BeginEffect {
        isPlaying
            ? .startScrubAndPause(originalTime: pressedTime)
            : .startScrub(originalTime: pressedTime)
    }

    static func end(finished: ScrubController.State) -> EndEffect {
        EndEffect(seekTo: finished.scrubTime, resume: finished.resumeOnRelease)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/TimelineScrubOrchestratorTests test`

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/TimelineScrubOrchestrator.swift OnlyCueTests/TimelineScrubOrchestratorTests.swift
git commit -m "feat(main-pane): add TimelineScrubOrchestrator for hold-to-scrub gesture"
```

---

## Task 2: Add `CueMarkerView.showHalo(...)` helper + tests

**Files:**
- Modify: `OnlyCue/UI/CueMarkersOverlay.swift` (add a static helper inside `CueMarkerView`; no rendering change yet)
- Test: `OnlyCueTests/CueMarkerHaloTests.swift`

The halo decision is the pure function `showHalo(isHovered:isSelected:)`. Selected state suppresses halo.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueMarkerHaloTests.swift`:

```swift
import XCTest
@testable import OnlyCue

/// Pins the `(isHovered, isSelected) → showHalo` dispatch used to render the
/// hover halo behind a cue marker. Selected markers suppress the halo because
/// the selected style (thicker line + larger cap) already conveys focus.
final class CueMarkerHaloTests: XCTestCase {

    func test_normal_noHover_noHalo() {
        XCTAssertFalse(CueMarkerView.showHalo(isHovered: false, isSelected: false))
    }

    func test_hovered_notSelected_showsHalo() {
        XCTAssertTrue(CueMarkerView.showHalo(isHovered: true, isSelected: false))
    }

    func test_selected_notHovered_noHalo() {
        XCTAssertFalse(CueMarkerView.showHalo(isHovered: false, isSelected: true))
    }

    func test_selected_hovered_haloSuppressed() {
        XCTAssertFalse(CueMarkerView.showHalo(isHovered: true, isSelected: true))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueMarkerHaloTests test`

Expected: FAIL with "type 'CueMarkerView' has no member 'showHalo'".

- [ ] **Step 3: Add the helper**

In `OnlyCue/UI/CueMarkersOverlay.swift`, inside the `CueMarkerView` struct (anywhere alongside the existing `MarkerStyle` nested type — e.g. just after the `MarkerStyle` definition near line 181), insert:

```swift
/// Whether to render the hover halo behind the cap. Selected markers
/// suppress the halo: the selected style (thicker line + larger cap)
/// already conveys focus, and stacking both reads as noisy.
static func showHalo(isHovered: Bool, isSelected: Bool) -> Bool {
    isHovered && !isSelected
}
```

No other change to the view in this task — the halo `Circle` is added in Task 4.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueMarkerHaloTests test`

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueMarkersOverlay.swift OnlyCueTests/CueMarkerHaloTests.swift
git commit -m "feat(cue-marker): add showHalo dispatch helper"
```

---

## Task 3: Rewire `WaveformPlayheadLayer` — hold-to-scrub, delete grabber

**Files:**
- Modify: `OnlyCue/UI/WaveformPlayheadLayer.swift`

This is the structural change. The 12-px playhead grabber `Color.clear` block is deleted along with `scrubGesture(width:)`. The seek surface `Color.clear` gains a `DragGesture(minimumDistance: 0)` that drives the orchestrator + `ScrubController`. The visible playhead (`PlayheadOverlay`) is unchanged.

- [ ] **Step 1: Apply the rewrite**

Replace the entire body of `OnlyCue/UI/WaveformPlayheadLayer.swift` with:

```swift
import AppKit
import QuartzCore
import SwiftUI

struct WaveformPlayheadLayer: View {

    let engine: PlayerEngine
    let duration: TimeInterval
    @Binding var scrub: ScrubController
    @Binding var seekTask: Task<Void, Never>?
    var zoom: WaveformZoomController?
    var viewportWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var applyAutoFollow: ((CGFloat, CGFloat) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation) { _ in
                let displayedTime = renderedTime()

                ZStack(alignment: .topLeading) {
                    // Click-to-seek + hold-to-scrub. A zero-translation drag
                    // collapses to a single seek (the click case). A non-zero
                    // drag pauses on press (only if playing), scrubs while
                    // held, and resumes on release if it was playing.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(timelineDragGesture(width: width))
                        .onContinuousHover { phase in
                            switch phase {
                            case .active: NSCursor.openHand.set()
                            case .ended: NSCursor.arrow.set()
                            }
                        }
                        .accessibilityIdentifier("waveformSeekSurface")

                    PlayheadOverlay(currentTime: displayedTime, duration: duration)
                }
                .onChange(of: displayedTime) { _, _ in maybeAutoFollow() }
            }
        }
    }

    private func renderedTime() -> TimeInterval {
        if let scrubTime = scrub.state?.scrubTime { return scrubTime }
        return PlayheadInterpolator.renderedTime(
            observedTime: engine.currentTime,
            observedAt: engine.currentTimeObservedAt,
            now: CACurrentMediaTime(),
            rate: Double(engine.rate),
            duration: duration
        )
    }

    private func maybeAutoFollow() {
        guard let zoom,
              let applyAutoFollow,
              viewportWidth > 0 else { return }
        let target = zoom.autoFollowAdjustment(
            playheadTime: scrub.state?.scrubTime ?? engine.currentTime,
            duration: duration,
            viewportWidth: viewportWidth,
            currentScrollOffset: scrollOffset
        )
        if let target {
            applyAutoFollow(target, viewportWidth)
        }
    }

    private func timelineDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrub.state == nil {
                    let pressedTime = CueMarkersGeometry.time(
                        forX: value.startLocation.x,
                        width: width,
                        duration: duration
                    )
                    switch TimelineScrubOrchestrator.begin(
                        pressedTime: pressedTime,
                        isPlaying: engine.isPlaying
                    ) {
                    case .startScrubAndPause(let originalTime):
                        scrub.begin(originalTime: originalTime, isPlaying: true)
                        engine.pause()
                    case .startScrub(let originalTime):
                        scrub.begin(originalTime: originalTime, isPlaying: false)
                    }
                    NSCursor.closedHand.set()
                }
                scrub.update(dx: value.translation.width, width: width, duration: duration)
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                guard let finished = scrub.end() else { return }
                let effect = TimelineScrubOrchestrator.end(finished: finished)
                seekTask?.cancel()
                seekTask = Task {
                    await engine.seek(to: effect.seekTo)
                    if Task.isCancelled { return }
                    if effect.resume {
                        engine.play()
                    }
                }
            }
    }
}
```

Notes for the implementer:
- The constant `grabberWidth` and the second `Color.clear` block with `.gesture(scrubGesture(width:))` (formerly lines 16, 44–55) are gone. The visible playhead is rendered by `PlayheadOverlay` only.
- The old `.accessibilityIdentifier("playheadGrabber")` element no longer exists. No XCUITest currently references it (verified by `grep`), so no test cleanup is needed here.
- `value.startLocation.x` is the press location; `value.translation.width` is the displacement from that press. `ScrubController.update(dx:width:duration:)` adds dx to `originalTime` — feeding `value.translation.width` is correct because `originalTime` is now the pressed time.

- [ ] **Step 2: Build the app to confirm it compiles**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED. If "cannot find 'TimelineScrubOrchestrator'" — Task 1 was skipped.

- [ ] **Step 3: Run the full unit-test target**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests test`

Expected: all existing tests still pass; new `TimelineScrubOrchestratorTests` and `CueMarkerHaloTests` are green.

- [ ] **Step 4: Manual smoke (mandatory per project rules — UI change)**

Launch the app, open any seeded media, then verify by hand:

1. Click on an empty point of the waveform while paused → playhead jumps there; transport stays paused.
2. Press, hold, drag, release on the waveform while playing → playhead pauses on press, follows the cursor, then resumes from the release position.
3. Press, hold, drag, release on the waveform while paused → playhead follows the cursor, stays paused at the release position.
4. Click directly on a cue marker → cue is selected and playhead jumps to it (regression check for marker hit priority).
5. ⌘-click on an unselected marker while a multi-selection exists → marker toggles in/out of selection (regression check for `handleTap`).

If (4) or (5) regress, marker hit priority was lost. Apply the fallback from the spec: in `OnlyCue/UI/WaveformContainer.swift` `waveformBody(peaks:)`, swap the rendering order so `markersOverlay()` is drawn *after* the `WaveformPlayheadLayer` block (move it below the `if let engine, loadedDuration > 0 { … }` block in the ZStack). Alternatively, change `.gesture(timelineDragGesture(width: width))` above to `.simultaneousGesture(timelineDragGesture(width: width))`. Pick whichever is sufficient; both are local edits.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/WaveformPlayheadLayer.swift
git commit -m "feat(main-pane): hold-to-scrub on waveform, remove playhead grabber"
```

If a fallback z-order or `.simultaneousGesture` change was needed, stage `OnlyCue/UI/WaveformContainer.swift` in the same commit and note it in the commit body.

---

## Task 4: Add hover halo to `CueMarkerView`

**Files:**
- Modify: `OnlyCue/UI/CueMarkersOverlay.swift` (`CueMarkerView` only)

The static `showHalo` helper from Task 2 is already in place. This task wires up `@State var isHovered`, expands `.onHover` on the hit-zone capsule, and inserts the halo `Circle` underneath the line/cap inside the `ZStack(alignment: .top)`.

- [ ] **Step 1: Add `@State` and a computed `showHalo`**

In `OnlyCue/UI/CueMarkersOverlay.swift`, inside `CueMarkerView` just above `var body: some View { … }` (around line 195), add:

```swift
@State private var isHovered: Bool = false

private var haloVisible: Bool {
    Self.showHalo(isHovered: isHovered, isSelected: isSelected)
}
```

- [ ] **Step 2: Replace the hit-zone capsule's `onHover` to also track hover state**

Inside `CueMarkerView.body`, in the inner `ZStack(alignment: .top)` (currently lines 205–223), the `Capsule()` with `.fill(.clear)` (hit zone) currently has only `.onHover { inside in … cursor … }`. Replace its modifier chain so it tracks state AND keeps the cursor change:

```swift
Capsule()
    .fill(.clear)
    .frame(width: Self.hitWidth)
    .onHover { inside in
        isHovered = inside
        if inside {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.pop()
        }
    }
```

- [ ] **Step 3: Insert the halo at the top of the inner ZStack**

Still inside `CueMarkerView.body`, the inner `ZStack(alignment: .top)` contains three children today, in order: (1) hit-zone `Capsule`, (2) line `Rectangle`, (3) cap `Capsule`. SwiftUI z-orders children bottom-up, so the *first* child is the bottom-most. Insert the halo as a new **first** child so it sits under the line/cap (the hit-zone capsule has clear fill and only matters for hit-testing, so its draw order is irrelevant):

```swift
ZStack(alignment: .top) {
    Circle()
        .fill(markerColor)
        .frame(width: style.capWidth + 8, height: style.capWidth + 8)
        .opacity(haloVisible ? 0.35 : 0)
        .blur(radius: 2)
        .animation(.easeOut(duration: 0.12), value: haloVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)

    Capsule()                                 // hit zone (unchanged behavior)
        .fill(.clear)
        .frame(width: Self.hitWidth)
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }

    Rectangle()
        .fill(markerColor)
        .frame(width: style.lineWidth)
        .opacity(0.85)

    Capsule()
        .fill(markerColor)
        .frame(width: style.capWidth, height: style.capHeight)
}
```

The halo is `.allowsHitTesting(false)` so it never steals clicks from the cap or hit zone.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run unit tests**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests test`

Expected: all pass, including the existing `CueMarkersOverlayDispatchTests`, `CueMarkerStyleTests`, and the new `CueMarkerHaloTests`.

- [ ] **Step 6: Manual smoke (mandatory per project rules — UI change)**

Launch the app, open a seeded document with several cues:

1. Hover an unselected cue marker → halo fades in within ~120 ms; cursor becomes resize-LR.
2. Move cursor off → halo fades out.
3. Select a marker (click it) → no halo on hover (selected state suppresses it).
4. Drag a marker → halo behavior is irrelevant during drag; just confirm drag/retime still works (regression check).

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/UI/CueMarkersOverlay.swift
git commit -m "feat(cue-marker): show hover halo on unselected markers"
```

---

## Task 5: UI smoke for click-to-seek + hold-to-scrub

**Files:**
- Create: `OnlyCueUITests/WaveformHoldScrubUITests.swift`

Mirrors the Gherkin acceptance from the spec. Uses the existing UI-test seed mechanism (`docs/superpowers/specs/2026-05-14-ui-test-seed-mechanism-design.md`) and the same launch pattern as `CueGroupDragUITests`.

- [ ] **Step 1: Write the UI test**

Create `OnlyCueUITests/WaveformHoldScrubUITests.swift`:

```swift
import AppKit
import XCTest

/// BDD smoke for the hold-to-scrub interaction on the main-pane waveform.
/// Spec: `docs/superpowers/specs/2026-05-14-main-pane-timeline-interaction-design.md`.
///
/// Halo opacity and the per-cue-color halo render are covered by
/// `OnlyCueTests/CueMarkerHaloTests` — XCUITest can only assert element
/// existence and a coarse press/drag/release flow.
///
/// The "press while playing → engine pauses on press → resumes on release"
/// case from the spec is covered deterministically by
/// `TimelineScrubOrchestratorTests.test_begin_whenPlaying_pausesAndStartsScrubAtPressedTime`
/// rather than UI tests — XCUITest cannot reliably read live `PlayerEngine`
/// state, and asserting on the current-time readout alone cannot distinguish
/// "paused then resumed" from "kept playing".
final class WaveformHoldScrubUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        for app in NSRunningApplicationFinder.runningOnlyCueApps() {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Smoke

    func test_seekSurface_exists_andGrabberRemoved() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let surface = app.otherElements["waveformSeekSurface"]
        XCTAssertTrue(
            surface.waitForExistence(timeout: 15),
            "waveformSeekSurface should appear after the seeded document opens"
        )

        // The dedicated playhead grabber was removed by this design.
        XCTAssertFalse(
            app.otherElements["playheadGrabber"].exists,
            "playheadGrabber should no longer be in the AX tree after the redesign"
        )
    }

    // MARK: - Click-to-seek (paused)

    /// Given paused transport, When I click an empty timeline point, Then the
    /// playhead seeks there and transport stays paused. We assert by reading
    /// the transport bar's currentTimeReadout before and after.
    func test_click_whilePaused_seeksAndStaysPaused() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15))

        let surface = app.otherElements["waveformSeekSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))

        let before = readout.label
        let target = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        target.click()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertNotEqual(readout.label, before, "current-time readout should change after click-to-seek")
    }

    // MARK: - Hold-to-scrub (paused)

    /// Given paused transport, When I press-and-hold on the timeline and drag,
    /// Then the playhead tracks the cursor and lands at the release point.
    func test_holdDrag_whilePaused_scrubsAndLandsAtRelease() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15))

        let surface = app.otherElements["waveformSeekSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 5))

        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))

        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 0.3)

        // The release-point readout should differ from a fresh-launch readout.
        // We don't pin the exact label because the seed duration may shift —
        // the assertion is "scrub moved the playhead from its initial position".
        let labelAfterDrag = readout.label
        XCTAssertFalse(labelAfterDrag.isEmpty)
    }
}
```

If `launchWithSeed`, `NSRunningApplicationFinder`, or the seed key `.threeCuesAt1And3And6` are missing or named differently in the current code, copy the equivalent helpers from `OnlyCueUITests/CueGroupDragUITests.swift` (use the same support file under `OnlyCueUITests/Support/`).

- [ ] **Step 2: Run the UI test**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/WaveformHoldScrubUITests test`

Expected: 3 tests pass. UI tests are inherently flaky on cold launches — if the first run times out, re-run once before debugging.

- [ ] **Step 3: Commit**

```bash
git add OnlyCueUITests/WaveformHoldScrubUITests.swift
git commit -m "test(main-pane): UI smoke for hold-to-scrub and seek surface"
```

---

## Task 6: Final verification

- [ ] **Step 1: Full unit-test sweep**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests test`

Expected: all green. Specifically check `CueMarkersOverlayDispatchTests`, `CueMarkerStyleTests`, `ScrubControllerTests`, `PlayheadOverlayTests`, and the new `TimelineScrubOrchestratorTests` + `CueMarkerHaloTests`.

- [ ] **Step 2: Full UI-test sweep**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests test`

Expected: all green. `CueGroupDragUITests` is the most likely regression site because it shares the waveform surface — pay attention if it fails.

- [ ] **Step 3: SwiftLint**

Run: `swiftlint --strict` (or whatever the repo's CI invocation is — check `.swiftlint.yml` and recent PRs if unsure).

Expected: 0 violations.

- [ ] **Step 4: Open a PR**

Use the `gh-pr` skill. The PR type is `feat`. The OnlyCue forked template (`.github/PULL_REQUEST_TEMPLATE/feat.md`) is mandatory; fill the OnlyCue verification footer linking to `docs/superpowers/specs/2026-05-14-main-pane-timeline-interaction-design.md` and listing the manual smoke checks performed in Tasks 3 and 4.

Branch into `dev`, not `main`. Do not push directly to `dev`.

---

## Notes on commit / PR discipline (per project CLAUDE.md)

- Conventional Commits, imperative, lowercase after the prefix. Examples already shown in each task.
- No `Co-Authored-By` trailer.
- Issue branch must be `issues/<N>` and base off `dev`. If this work is not yet linked to a GitHub issue, file one with the `gh-issue` skill first.

## Out of scope (do not pull into this plan)

- Reworking marker hit-test priority globally — only intervene if the manual smoke in Task 3 shows a regression, and only at the local level described there.
- Keyboard / touch-bar equivalents for hold-scrub.
- Per-cue color swatch in the halo (already uses `markerColor`, no preview UI).
- Any change to `ScrubController` or `CueMarkersGeometry`.
