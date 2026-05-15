# Waveform Cue-Marker Hit-Test Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cue markers in the main-pane waveform reachable to pointer hit-tests (click → select cue, drag → retime, hover → resize cursor + halo) by reordering the layers so the playhead's full-bleed click-to-seek surface no longer sits on top of the markers.

**Architecture:** Split `WaveformPlayheadLayer` into two sibling views. `WaveformSeekSurface` carries the click-to-seek/hold-to-scrub `DragGesture` and the `.onContinuousHover` cursor; it renders nothing visible and is placed *below* `markersOverlay()` in the `ZStack`. `WaveformPlayheadVisual` owns the `TimelineView(.animation)` rendered-time loop, auto-follow, and `PlayheadOverlay`; it has hit-testing disabled and is placed *above* `markersOverlay()` so the playhead line/badge are never visually occluded by a selected (wider) marker cap. No new commands, gestures, or schema changes.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVPlayer`), AppKit (`NSCursor`), `UITestSeedHandler` + XCUITest seed key `threeCuesAt1And3And6`.

**Spec:** [`docs/superpowers/specs/2026-05-15-waveform-cue-marker-hit-test-fix-design.md`](../specs/2026-05-15-waveform-cue-marker-hit-test-fix-design.md) (commit `e294b6c` on local `dev`)

**Branching:** Per project CLAUDE.md, all implementation happens on `issues/<N>` off `dev`. The executor opens the issue first via the `gh-issue` skill (template: `bug`), then creates the branch via the `gh-dev` skill (`gh issue develop <N> --base dev`), then runs the tasks below. PR back into `dev` uses `.github/PULL_REQUEST_TEMPLATE/bug.md`.

---

## File Structure

**Modify:**
- `OnlyCue/UI/WaveformContainer.swift` (lines ~96–116, the inner `ZStack` in `waveformBody`) — replace single `WaveformPlayheadLayer` use with `WaveformSeekSurface` (below `markersOverlay()`) and `WaveformPlayheadVisual` (above `markersOverlay()`).

**Create:**
- `OnlyCue/UI/WaveformSeekSurface.swift` — full-bleed `Color.clear` with `contentShape(Rectangle())`, the `DragGesture(minimumDistance: 0)` that drives `ScrubController` + `seekTask` + `engine.seek`, `.onContinuousHover` cursor, `accessibilityIdentifier("waveformSeekSurface")`. ~70 lines.
- `OnlyCue/UI/WaveformPlayheadVisual.swift` — `TimelineView(.animation)` driving `renderedTime()` + `maybeAutoFollow()`, hosting `PlayheadOverlay`. `.allowsHitTesting(false)` on the root. ~55 lines.
- `OnlyCueUITests/CueMarkerHitTestUITests.swift` — UI smoke proving the bug-fix: clicking a marker selects the underlying cue and seeks the playhead to the cue's time (i.e. the click is no longer absorbed by the seek surface).

**Delete:**
- `OnlyCue/UI/WaveformPlayheadLayer.swift` — superseded by the two new files.

**Regenerate Xcode project:** `OnlyCue.xcodeproj/` is generated from `project.yml` via XcodeGen and is not committed; the existing `sources` rule for `OnlyCue/UI/` picks up the new files automatically. Run `xcodegen generate` after the create/delete to refresh the local project.

---

## Task 1: Add a failing UI test that proves the bug

**Files:**
- Create: `OnlyCueUITests/CueMarkerHitTestUITests.swift`

This test asserts the user-visible bug from the spec: clicking a marker should select that cue and seek the playhead to the cue's time. Today the click hits the seek surface instead, so the cue is never selected and the playhead seeks to the click x (which differs from the cue time by the cap's pixel width — and would only coincide by accident).

The existing skipped tests in `OnlyCueUITests/CueGroupDragUITests.swift` cover *drag* of markers but are blocked by the XCUITest/SwiftUI drag-synthesis issue (#273). A *click* on a marker is reliable in XCUITest and is the cheapest assertion that distinguishes "marker received the down event" from "seek surface received it."

- [ ] **Step 1: Write the failing test**

Create `OnlyCueUITests/CueMarkerHitTestUITests.swift`:

```swift
import AppKit
import XCTest

/// BDD smoke proving cue markers are reachable to pointer hit-tests.
/// Spec: `docs/superpowers/specs/2026-05-15-waveform-cue-marker-hit-test-fix-design.md`.
///
/// Before the fix, every click in the waveform area landed on the
/// full-bleed `waveformSeekSurface` rendered above the markers, so the
/// click was treated as a seek and no cue was ever selected. After the
/// fix the seek surface sits below `cueMarkersOverlay`, so a click on a
/// marker reaches `CueMarkerView` and dispatches `onSelectCue`.
final class CueMarkerHitTestUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        for app in NSRunningApplicationFinder.runningOnlyCueApps() {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Given a seeded document with cues at 1s, 3s, 6s,
    /// When the user clicks the marker for the cue at 3s,
    /// Then the row for that cue becomes the only selected row.
    func test_clickOnMarker_selectsTheUnderlyingCue() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        let markers = try CueGroupDragUITests.waitForMarkers(in: app, count: 3)
        let rows = CueGroupDragUITests.sortedCueRows(in: app)
        XCTAssertEqual(rows.count, 3, "Seed should produce three cue rows.")

        // Sanity: nothing selected at launch.
        XCTAssertEqual(rows.filter { $0.isSelected }.count, 0,
                       "No cue should be selected before the click.")

        // Click the middle marker (cue at 3s).
        let middle = CueGroupDragUITests.markerHitCoordinate(markers[1])
        middle.click()
        Thread.sleep(forTimeInterval: 0.4)

        let selected = rows.filter { $0.isSelected }
        XCTAssertEqual(selected.count, 1,
                       "Clicking a marker should select exactly one cue.")
        XCTAssertEqual(selected.first?.identifier,
                       rows[1].identifier,
                       "The selected cue should be the one whose marker was clicked.")
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new test file is picked up**

Run: `xcodegen generate`
Expected: `OnlyCue.xcodeproj` regenerated; no errors.

- [ ] **Step 3: Run the new test and verify it fails for the right reason**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/CueMarkerHitTestUITests/test_clickOnMarker_selectsTheUnderlyingCue \
  test
```
Expected: FAIL — `selected.count` is `0`, not `1`. (The click was absorbed by the seek surface; the marker never received it.) If it fails for any other reason — seed didn't launch, markers never appeared, identifier query empty — fix the test before proceeding; do not start the implementation against a test that's broken for the wrong reason.

- [ ] **Step 4: Commit the failing test**

```bash
git add OnlyCueUITests/CueMarkerHitTestUITests.swift
git commit -m "test(ui): assert marker click selects underlying cue (currently red)"
```

---

## Task 2: Extract `WaveformSeekSurface`

**Files:**
- Create: `OnlyCue/UI/WaveformSeekSurface.swift`
- Reference (do not modify yet): `OnlyCue/UI/WaveformPlayheadLayer.swift`

This is a pure cut from `WaveformPlayheadLayer.swift`: the `Color.clear`/`contentShape`/`DragGesture`/`onContinuousHover` block plus the `timelineDragGesture(width:)` helper. Identical behaviour, identical AX identifier — so the existing `WaveformHoldScrubUITests` keeps passing once Task 4 wires it in.

- [ ] **Step 1: Write the new file**

Create `OnlyCue/UI/WaveformSeekSurface.swift`:

```swift
import AppKit
import QuartzCore
import SwiftUI

/// Full-bleed transparent surface that bears the click-to-seek and
/// hold-to-scrub gesture for the main-pane waveform.
///
/// Renders nothing visible. Lives BELOW `CueMarkersOverlay` in
/// `WaveformContainer`'s `ZStack` so a press on a cue marker reaches the
/// marker view instead of being absorbed here. The visual playhead line +
/// time-label badge are rendered separately by `WaveformPlayheadVisual`,
/// which sits ABOVE the markers with hit-testing disabled.
///
/// A zero-translation drag collapses to a single seek (the click case).
/// A non-zero drag pauses on press (only if the engine is playing),
/// scrubs while held, and resumes on release if it was playing — see
/// `TimelineScrubOrchestrator`.
struct WaveformSeekSurface: View {

    let engine: PlayerEngine
    let duration: TimeInterval
    @Binding var scrub: ScrubController
    @Binding var seekTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
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

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: success.

- [ ] **Step 3: Build to confirm the new file compiles**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED. (The file isn't yet referenced by anything; we're just verifying it compiles in isolation. The old `WaveformPlayheadLayer` is still in place and still in use.)

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/WaveformSeekSurface.swift
git commit -m "refactor(waveform): extract WaveformSeekSurface from playhead layer"
```

---

## Task 3: Extract `WaveformPlayheadVisual`

**Files:**
- Create: `OnlyCue/UI/WaveformPlayheadVisual.swift`
- Reference: `OnlyCue/UI/WaveformPlayheadLayer.swift`, `OnlyCue/UI/PlayheadOverlay.swift`, `OnlyCue/UI/PlayheadInterpolator.swift`

This is the rendering half of `WaveformPlayheadLayer`: the `TimelineView(.animation)` that ticks each frame, `renderedTime()`, `maybeAutoFollow()`, and the `PlayheadOverlay` itself. Hit-testing is off on the root so the markers below remain reachable.

- [ ] **Step 1: Write the new file**

Create `OnlyCue/UI/WaveformPlayheadVisual.swift`:

```swift
import AppKit
import QuartzCore
import SwiftUI

/// Visual-only playhead: the vertical line + time-label badge, ticking
/// each frame off `TimelineView(.animation)`. Hit-testing is disabled
/// on the root so a press at the playhead's x-position reaches the
/// markers / seek surface below; only `WaveformSeekSurface` carries the
/// click-to-seek gesture.
///
/// Sits ABOVE `CueMarkersOverlay` in `WaveformContainer`'s `ZStack` so
/// the playhead line is never visually occluded by a selected (wider)
/// cue-marker cap.
struct WaveformPlayheadVisual: View {

    let engine: PlayerEngine
    let duration: TimeInterval
    @Binding var scrub: ScrubController
    var zoom: WaveformZoomController?
    var viewportWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var applyAutoFollow: ((CGFloat, CGFloat) -> Void)?

    var body: some View {
        GeometryReader { _ in
            TimelineView(.animation) { _ in
                let displayedTime = renderedTime()
                PlayheadOverlay(currentTime: displayedTime, duration: duration)
                    .onChange(of: displayedTime) { _, _ in maybeAutoFollow() }
            }
        }
        .allowsHitTesting(false)
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
}
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: success.

- [ ] **Step 3: Build to confirm compilation**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED. (Still not wired; `WaveformPlayheadLayer` is still the live one.)

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/WaveformPlayheadVisual.swift
git commit -m "refactor(waveform): extract WaveformPlayheadVisual from playhead layer"
```

---

## Task 4: Wire the new layers into `WaveformContainer`, delete the old layer

**Files:**
- Modify: `OnlyCue/UI/WaveformContainer.swift` (the `ZStack` inside `waveformBody`, lines ~96–116)
- Delete: `OnlyCue/UI/WaveformPlayheadLayer.swift`

This is the change that actually fixes the bug. Reorder the ZStack so the seek surface sits below the markers and the visual sits above them.

- [ ] **Step 1: Update the ZStack in `waveformBody`**

In `OnlyCue/UI/WaveformContainer.swift`, replace the `ZStack` block currently at lines ~97–116 (the one inside `ScrollView(.horizontal, showsIndicators: zoom.zoom > 1)`).

Old:

```swift
ZStack(alignment: .topLeading) {
    WaveformView(peaks: peaks, verticalZoom: verticalZoom.zoom)
    tempoGridOverlay()
    markersOverlay()
    if let engine, loadedDuration > 0 {
        WaveformPlayheadLayer(
            engine: engine,
            duration: loadedDuration,
            scrub: $scrub,
            seekTask: $seekTask,
            zoom: zoom,
            viewportWidth: width,
            scrollOffset: scrollOffset,
            applyAutoFollow: applyAutoFollow
        )
    }
    if zoom.zoom > 1 && loadedDuration > 0 {
        anchorRail(contentWidth: contentWidth)
    }
}
```

New:

```swift
ZStack(alignment: .topLeading) {
    WaveformView(peaks: peaks, verticalZoom: verticalZoom.zoom)
    tempoGridOverlay()
    if let engine, loadedDuration > 0 {
        // Seek surface BELOW the markers so a press on a cue marker
        // reaches `CueMarkerView` instead of being absorbed by the
        // full-bleed click-to-seek surface. See spec
        // `docs/superpowers/specs/2026-05-15-waveform-cue-marker-hit-test-fix-design.md`.
        WaveformSeekSurface(
            engine: engine,
            duration: loadedDuration,
            scrub: $scrub,
            seekTask: $seekTask
        )
    }
    markersOverlay()
    if let engine, loadedDuration > 0 {
        // Playhead line + time-label badge ABOVE the markers so a
        // selected (wider) cue cap never visually occludes them.
        // Hit-testing is disabled inside `WaveformPlayheadVisual`.
        WaveformPlayheadVisual(
            engine: engine,
            duration: loadedDuration,
            scrub: $scrub,
            zoom: zoom,
            viewportWidth: width,
            scrollOffset: scrollOffset,
            applyAutoFollow: applyAutoFollow
        )
    }
    if zoom.zoom > 1 && loadedDuration > 0 {
        anchorRail(contentWidth: contentWidth)
    }
}
```

- [ ] **Step 2: Delete the now-unused old layer**

```bash
git rm OnlyCue/UI/WaveformPlayheadLayer.swift
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: success.

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED. If the build fails because something else still imported `WaveformPlayheadLayer`, grep the workspace and fix the holdout — there should be exactly one user inside `WaveformContainer.swift` and zero elsewhere:

```bash
grep -rn "WaveformPlayheadLayer" OnlyCue OnlyCueTests OnlyCueUITests
```

Expected output after the fix: no matches.

- [ ] **Step 5: Run the formerly-failing UI test and verify it now passes**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/CueMarkerHitTestUITests/test_clickOnMarker_selectsTheUnderlyingCue \
  test
```
Expected: PASS. If it still fails (`selected.count == 0`), the most likely cause is that SwiftUI is still delivering the press to the seek surface because both siblings carry `DragGesture(minimumDistance: 0)` — see Task 4a.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/WaveformContainer.swift
git commit -m "fix(waveform): split playhead layer so cue markers receive clicks"
```

---

## Task 4a: Contingency — raise seek-surface drag minimum to 1px (only if Task 4 Step 5 still fails)

**Skip this task entirely if Task 4 Step 5 passed.** The spec flagged this as a possible mitigation; only apply it if hit-test ordering alone wasn't enough.

**Files:**
- Modify: `OnlyCue/UI/WaveformSeekSurface.swift`

- [ ] **Step 1: Bump `minimumDistance` from `0` to `1` in the seek surface**

In `WaveformSeekSurface.timelineDragGesture(width:)` change:

```swift
DragGesture(minimumDistance: 0)
```

to:

```swift
// minimumDistance: 1 lets the marker's `DragGesture(minimumDistance: 0)`
// win arbitration on a press that lands on a cap; click-to-seek still
// works because the seek surface's gesture collapses zero-translation
// drags to a single seek (`TimelineScrubOrchestrator.end`).
DragGesture(minimumDistance: 1)
```

- [ ] **Step 2: Re-run the marker click test**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/CueMarkerHitTestUITests/test_clickOnMarker_selectsTheUnderlyingCue \
  test
```
Expected: PASS.

- [ ] **Step 3: Re-run the click-to-seek smoke to confirm it still works**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/WaveformHoldScrubUITests/test_click_whilePaused_dispatchesWithoutCrash \
  test
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/WaveformSeekSurface.swift
git commit -m "fix(waveform): raise seek-surface drag minimum so marker gesture wins"
```

---

## Task 5: Run the full regression suite

**Files:** none — verification only.

The risk surface for this change is gesture wiring on the main-pane waveform. The tests below cover the neighbours and must all stay green.

- [ ] **Step 1: Run the full unit test target**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests \
  test
```
Expected: all tests pass. Pay attention to: `CueMarkersOverlayDispatchTests`, `CueMarkersGeometryTests`, `CueMarkerHaloTests`, `TimelineScrubOrchestratorTests`, `PlayheadInterpolator*` if present.

- [ ] **Step 2: Run the waveform-adjacent UI tests**

Run:
```bash
xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/CueMarkerHitTestUITests \
  -only-testing:OnlyCueUITests/WaveformHoldScrubUITests \
  -only-testing:OnlyCueUITests/CueGroupDragUITests/test_seedMechanism_opensDocumentAndRendersMarkers \
  -only-testing:OnlyCueUITests/InspectorClockHeaderUITests \
  test
```
Expected: all pass. The XCTSkip'd marker-drag tests in `CueGroupDragUITests` remain skipped — that's the unrelated #273 blocker, not a regression.

- [ ] **Step 3: SwiftLint**

Run: `swiftlint lint --quiet --strict`
Expected: no violations. If `type_body_length` or similar flags `WaveformContainer.swift`, the split should have *reduced* its size; if it didn't, recheck Task 4.

- [ ] **Step 4: Manual smoke (per project CLAUDE.md "UI changes")**

Open the regenerated project (`open OnlyCue.xcodeproj`), Run, open a `.cuelist` with at least two cues on a media item, and verify by hand:

1. Click on a cue marker cap → that cue becomes selected in the cue list AND the playhead seeks to the cue's stored time (not to the click x).
2. ⌘-click on a second marker → both cues are selected (toggle behaviour).
3. Hover a marker cap → cursor becomes the horizontal resize cursor; hover halo appears.
4. Hover empty timeline → cursor becomes the open-hand cursor.
5. Click empty timeline → playhead seeks to that point.
6. Press-and-drag on empty timeline → playhead scrubs; transport pauses on press if it was playing and resumes on release.
7. Press-and-drag on a marker cap past ~4 px → the cue retimes (live preview, commits on release). Single undo restores the original time.
8. With a selected (wider) marker at the same x-position as the playhead, the playhead line and time-label badge are still visually on top.

If any of 1–8 misbehave, stop — the fix is incomplete. Note specifically what failed before opening a PR.

- [ ] **Step 5: Commit nothing, mark task done**

This task is verification only. No commit.

---

## Task 6: Open the PR

**Files:** none.

- [ ] **Step 1: Push the branch**

Run: `git push -u origin issues/<N>` (replace `<N>` with the issue number created at the start).

- [ ] **Step 2: Open the PR via the `gh-pr` skill**

Use the `gh-pr` skill with PR type `bug`. Per project CLAUDE.md the template MUST be read from `.github/PULL_REQUEST_TEMPLATE/bug.md` (the OnlyCue fork), not from the skill's bundled template. Fill in the OnlyCue verification footer, link the spec at `docs/superpowers/specs/2026-05-15-waveform-cue-marker-hit-test-fix-design.md`, and link the originating issue.

- [ ] **Step 3: Confirm CI is green**

Wait for the GitHub Actions checks on the PR. If any fail, address them on the same branch before requesting review.

---

## Self-review notes (for the planner, not the executor)

- Spec coverage: §"Fix" → Tasks 2/3/4. §"Behaviour after the fix" → Task 5 Step 4 manual smoke (items 1–8 enumerate the spec's behaviour list). §"Risk: press-on-marker must not also begin a scrub" → Task 4 Step 5 + Task 4a contingency. §"Tests" #1 → Task 1. §"Tests" #2/#3/#4 are deferred to manual smoke (Task 5 Step 4) because XCUITest drag synthesis is blocked by #273; this is documented in the spec's Tests section and in Task 5 Step 2's note. §"Tests" #5 (independently constructible) is implicitly satisfied by the Task 2 and Task 3 isolated builds. §"Tests" #6 (ZStack snapshot) is intentionally not implemented — there is no precedent in the codebase for SwiftUI view-hierarchy snapshot tests, and adding one for this single fix would be over-scoping; the manual smoke item #8 covers the visual-ordering invariant the snapshot would have asserted.
- Type/method-name consistency: `WaveformSeekSurface` is referenced identically in Task 2 (definition), Task 4 Step 1 (use site), and Task 4a Step 1. Same for `WaveformPlayheadVisual`. `applyAutoFollow` signature `(CGFloat, CGFloat) -> Void` matches the existing one in `WaveformContainer.applyAutoFollow(targetOffset:viewportWidth:)`.
- No placeholders.
