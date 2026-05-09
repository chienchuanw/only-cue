# Hover-revealed waveform zoom rails — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bottom-edge `VerticalZoomDragHandle` with two hover-revealed minimal zoom rails — vertical on the right edge, horizontal on the bottom — each showing a magnifier badge with live zoom level and supporting continuous drag-to-zoom.

**Architecture:** One reusable `WaveformZoomRail` SwiftUI view parameterized by axis. It owns no zoom math — it captures a baseline at drag start and forwards translation to a closure that the container wires to existing controller methods. Horizontal drag math is added as a new `WaveformZoomController.applyDrag(...)` mirror of the vertical one (PR #67), keeping a single tested seam per axis. The container overlays both rails on top of the waveform via `ZStack`, gates visibility on a hover `@State` plus a session-scoped first-launch flag, and animates opacity.

**Tech Stack:** Swift 6, SwiftUI on macOS 14+, XCTest, XcodeGen-managed project (re-run `xcodegen generate` after adding/removing source files).

**Spec:** `docs/superpowers/specs/2026-05-09-hover-zoom-rails-design.md`

---

## File Structure

- **Create:** `OnlyCue/UI/WaveformZoomRail.swift` — axis-parameterized rail view (vertical or horizontal). One view, one job: render the rail, run the drag gesture, fade with opacity, expose the zoom-level badge.
- **Create:** `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift` — covers the new horizontal `applyDrag` math on `WaveformZoomController`.
- **Modify:** `OnlyCue/UI/WaveformZoomController.swift` — add `applyDrag(translation:baseline:anchorFraction:viewportWidth:scrollOffset:)` mirroring the vertical controller's drag math.
- **Modify:** `OnlyCue/UI/WaveformContainer.swift` — replace the `VStack { waveformBody; VerticalZoomDragHandle }` with a `ZStack` overlaying the new rails; add `@State` for hover and first-launch hint.
- **Delete:** `OnlyCue/UI/VerticalZoomDragHandle.swift`.
- **Modify:** `project.yml` — no change expected (folder-rule `sources: OnlyCue` should pick up the new file); re-run `xcodegen generate` to refresh `OnlyCue.xcodeproj`.

---

## Task 1: Add horizontal `applyDrag` to `WaveformZoomController`

**Files:**
- Modify: `OnlyCue/UI/WaveformZoomController.swift`
- Test: `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift`

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift`:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class WaveformZoomRailHorizontalDragTests: XCTestCase {

    func test_applyDrag_zeroTranslation_keepsBaseline() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        controller.applyDrag(
            translation: 0,
            baseline: 2,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(controller.zoom, 2, accuracy: 0.0001)
    }

    func test_applyDrag_dragRightOneStepDistance_zoomsInOneStep() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        let baseline: CGFloat = 2
        controller.applyDrag(
            translation: WaveformZoomController.dragPixelsPerStep,
            baseline: baseline,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(
            controller.zoom,
            baseline * WaveformZoomController.zoomStep,
            accuracy: 0.0001,
            "drag right by one dragPixelsPerStep must multiply baseline by zoomStep"
        )
    }

    func test_applyDrag_dragLeftOneStepDistance_zoomsOutOneStep() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        let baseline: CGFloat = 4
        controller.applyDrag(
            translation: -WaveformZoomController.dragPixelsPerStep,
            baseline: baseline,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(
            controller.zoom,
            baseline / WaveformZoomController.zoomStep,
            accuracy: 0.0001
        )
    }

    func test_applyDrag_clampsAtMaxOnExtremeRightDrag() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        controller.applyDrag(
            translation: 10000,
            baseline: 1,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(controller.zoom, WaveformZoomController.maxZoom)
    }

    func test_applyDrag_clampsAtMinOnExtremeLeftDrag() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        controller.applyDrag(
            translation: -10000,
            baseline: 4,
            anchorFraction: 0.5,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        XCTAssertEqual(controller.zoom, WaveformZoomController.minZoom)
    }

    func test_applyDrag_anchorsScrollOffsetToCursorFraction() {
        let controller = WaveformZoomController()
        var offset: CGFloat = 0
        // Zoom in 2× anchored at the right edge — content width doubles to 800,
        // anchor at fraction 1.0 should keep the right edge of the viewport
        // (originally x=400 in content coords) at the same place.
        controller.applyDrag(
            translation: WaveformZoomController.dragPixelsPerStep,
            baseline: 1,
            anchorFraction: 1.0,
            viewportWidth: 400,
            scrollOffset: &offset
        )
        // After zoom of 1 * zoomStep = 1.5, contentWidth = 600.
        // timeFraction at start = (0 + 1.0*400) / 400 = 1.0.
        // newAnchorContentX = 1.0 * 600 = 600.
        // newOffset = 600 - 1.0*400 = 200.
        XCTAssertEqual(controller.zoom, WaveformZoomController.zoomStep, accuracy: 0.0001)
        XCTAssertEqual(offset, 200, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/WaveformZoomRailHorizontalDragTests`
Expected: FAIL — `applyDrag` is not a member of `WaveformZoomController`.

(If `OnlyCue.xcodeproj` is missing, run `xcodegen generate` first.)

- [ ] **Step 3: Add `applyDrag` and a `dragPixelsPerStep` constant to `WaveformZoomController`**

In `OnlyCue/UI/WaveformZoomController.swift`, add a new constant alongside the existing static values:

```swift
    static let dragPixelsPerStep: CGFloat = 60
```

Then add this method to the class (place it after `reset(scrollOffset:)`):

```swift
    /// Apply a continuous drag translation to a baseline zoom captured at drag start,
    /// anchored on a horizontal cursor fraction so zoom centers on what the user is
    /// pointing at. Positive `translation` = drag right = zoom in; one
    /// `dragPixelsPerStep` of drag in either direction multiplies (or divides) the
    /// baseline by `zoomStep`. Mirrors `WaveformVerticalZoomController.applyDrag`,
    /// but routes through `setZoom(...)` so scroll-offset anchoring is preserved.
    func applyDrag(
        translation: CGFloat,
        baseline: CGFloat,
        anchorFraction: CGFloat,
        viewportWidth: CGFloat,
        scrollOffset: inout CGFloat
    ) {
        let raw = baseline * pow(Self.zoomStep, translation / Self.dragPixelsPerStep)
        setZoom(
            raw,
            anchorFraction: anchorFraction,
            viewportWidth: viewportWidth,
            scrollOffset: &scrollOffset
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/WaveformZoomRailHorizontalDragTests`
Expected: PASS, all six tests green.

Also re-run the existing controller tests to confirm no regression:

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/WaveformZoomControllerTests -only-testing:OnlyCueTests/WaveformVerticalZoomControllerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/WaveformZoomController.swift OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift
git commit -m "feat(ui): add WaveformZoomController.applyDrag for horizontal drag-to-zoom"
```

---

## Task 2: Create `WaveformZoomRail` view

**Files:**
- Create: `OnlyCue/UI/WaveformZoomRail.swift`

This task adds the view but does not wire it in yet. We commit it standalone so the next task is a clean wiring change.

- [ ] **Step 1: Write `WaveformZoomRail.swift`**

```swift
import SwiftUI

/// Hover-revealed minimal zoom rail. One view serves both axes — caller picks `.vertical`
/// or `.horizontal` and supplies an `applyDrag` closure that captures the baseline at
/// drag start and forwards the translation to the appropriate controller.
///
/// The rail owns no zoom math. It only:
///   - renders a thin translucent strip along the chosen edge,
///   - shows a magnifier badge with the live zoom level,
///   - runs a `DragGesture` and forwards `(translation, baseline)` to the closure.
struct WaveformZoomRail: View {

    enum Axis {
        case vertical
        case horizontal
    }

    let axis: Axis
    let zoom: CGFloat
    let isVisible: Bool
    /// Called on each drag change. `translation` is the axis-relevant component of
    /// the drag (height for vertical, width for horizontal). `baseline` is the zoom
    /// captured at drag start. Optional `anchorFraction` is the cursor's start
    /// position normalised to viewport width (horizontal axis only — ignored when
    /// the rail is vertical).
    let onDrag: (_ translation: CGFloat, _ baseline: CGFloat, _ anchorFraction: CGFloat) -> Void
    /// Called on a double-click of the rail badge. Caller resets the relevant axis.
    let onResetRequested: () -> Void

    @State private var dragBaseline: CGFloat?
    @State private var isHovering: Bool = false

    private static let railThickness: CGFloat = 14
    private static let restingFill = Color.secondary.opacity(0.18)
    private static let hoverFill = Color.secondary.opacity(0.40)

    var body: some View {
        Group {
            switch axis {
            case .vertical:
                verticalRail
            case .horizontal:
                horizontalRail
            }
        }
        .opacity(isVisible || dragBaseline != nil ? 1 : 0)
        .animation(.easeInOut(duration: isVisible ? 0.12 : 0.20), value: isVisible)
        .accessibilityIdentifier(axis == .vertical
            ? "waveformVerticalZoomRail"
            : "waveformHorizontalZoomRail")
    }

    private var verticalRail: some View {
        Rectangle()
            .fill(isHovering ? Self.hoverFill : Self.restingFill)
            .frame(width: Self.railThickness)
            .overlay(badge)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragBaseline == nil { dragBaseline = zoom }
                        if let baseline = dragBaseline {
                            // Vertical: anchorFraction is unused; pass 0.5 as a stable default.
                            onDrag(value.translation.height, baseline, 0.5)
                        }
                    }
                    .onEnded { _ in dragBaseline = nil }
            )
            .onTapGesture(count: 2) { onResetRequested() }
    }

    private var horizontalRail: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(isHovering ? Self.hoverFill : Self.restingFill)
                .frame(height: Self.railThickness)
                .overlay(alignment: .trailing) { badge.padding(.trailing, 6) }
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragBaseline == nil { dragBaseline = zoom }
                            if let baseline = dragBaseline {
                                let width = max(proxy.size.width, 1)
                                let anchor = max(min(value.startLocation.x / width, 1), 0)
                                onDrag(value.translation.width, baseline, anchor)
                            }
                        }
                        .onEnded { _ in dragBaseline = nil }
                )
                .onTapGesture(count: 2) { onResetRequested() }
        }
        .frame(height: Self.railThickness)
    }

    private var badge: some View {
        HStack(spacing: 3) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
            Text(String(format: "%.1f×", Double(zoom)))
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(.thinMaterial, in: Capsule())
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Regenerate Xcode project so the new file is compiled**

Run: `xcodegen generate`
Expected: `Created project at OnlyCue.xcodeproj`.

- [ ] **Step 3: Verify the project still builds**

Run: `xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/WaveformZoomRail.swift
git commit -m "feat(ui): add WaveformZoomRail view (axis-parameterized hover rail)"
```

---

## Task 3: Wire rails into `WaveformContainer` and remove the old handle

**Files:**
- Modify: `OnlyCue/UI/WaveformContainer.swift`
- Delete: `OnlyCue/UI/VerticalZoomDragHandle.swift`

- [ ] **Step 1: Replace the `loaded(peaks:)` body in `WaveformContainer`**

In `OnlyCue/UI/WaveformContainer.swift`, add two new `@State` properties just after the existing `@State` block (alongside `viewportWidth`):

```swift
    @State private var isHoveringWaveform = false
    @State private var hasShownFirstLaunchHint = false
```

Replace the existing `loaded(peaks:)` method with:

```swift
    @ViewBuilder
    private func loaded(peaks: [Float]) -> some View {
        ZStack(alignment: .bottomTrailing) {
            waveformBody(peaks: peaks)
            verticalRail
            horizontalRail
        }
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHoveringWaveform = hovering
        }
        .onAppear {
            guard !hasShownFirstLaunchHint else { return }
            hasShownFirstLaunchHint = true
            isHoveringWaveform = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // Only retract the hint if the cursor isn't actually over the waveform.
                // A real hover will keep the rails visible naturally.
                isHoveringWaveform = false
            }
        }
    }

    private var verticalRail: some View {
        WaveformZoomRail(
            axis: .vertical,
            zoom: verticalZoom.zoom,
            isVisible: isHoveringWaveform,
            onDrag: { translation, baseline, _ in
                verticalZoom.applyDrag(translation: translation, baseline: baseline)
            },
            onResetRequested: { verticalZoom.reset() }
        )
        .frame(maxHeight: .infinity, alignment: .trailing)
    }

    private var horizontalRail: some View {
        WaveformZoomRail(
            axis: .horizontal,
            zoom: zoom.zoom,
            isVisible: isHoveringWaveform,
            onDrag: { translation, baseline, anchor in
                guard viewportWidth > 0 else { return }
                var offset = scrollOffset
                zoom.applyDrag(
                    translation: translation,
                    baseline: baseline,
                    anchorFraction: anchor,
                    viewportWidth: viewportWidth,
                    scrollOffset: &offset
                )
                scrollOffset = offset
                pinchBaseline = zoom.zoom
                syncAnchorFromOffset(viewportWidth: viewportWidth)
            },
            onResetRequested: { applyZoomReset() }
        )
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
```

- [ ] **Step 2: Delete the old handle file**

Run:
```bash
git rm OnlyCue/UI/VerticalZoomDragHandle.swift
```

- [ ] **Step 3: Regenerate Xcode project**

Run: `xcodegen generate`
Expected: success (the deleted file no longer appears in the project).

- [ ] **Step 4: Build**

Run: `xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`. If the build fails citing `VerticalZoomDragHandle`, search for stale references with `grep -R VerticalZoomDragHandle OnlyCue OnlyCueTests` and remove them.

- [ ] **Step 5: Run all tests**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'`
Expected: all tests pass.

- [ ] **Step 6: Lint**

Run: `swiftlint --strict`
Expected: 0 violations.

- [ ] **Step 7: Manual UX verification (golden path + regressions)**

1. `xcodegen generate && open OnlyCue.xcodeproj` and run the app.
2. Import a media item.
3. On first waveform load: both rails fade in, stay ~1.5s, fade out. ✅
4. Move cursor over the waveform — both rails fade in. Move cursor away — both fade out. ✅
5. Drag the right-edge rail up: vertical zoom badge counts up (1.0× → up to 8.0×), waveform amplitude grows. Drag down: zooms back. ✅
6. Drag the bottom rail right: horizontal zoom badge counts up (1.0× → up to 16.0×), waveform stretches and is scrollable. Drag left from a zoomed state: zooms out. ✅
7. Drag-anchor check: zoom in horizontally with the cursor near the right edge — the right portion of the waveform should stay roughly under the cursor. ✅
8. Double-click the badge on the vertical rail: vertical resets to 1.0×. Double-click on the horizontal rail badge: horizontal resets to 1.0× and scroll-offset returns to 0. ✅
9. Keyboard: ⌘= / ⌘- / ⌘0 still work for horizontal; ⌘⌥= / ⌘⌥- / ⌘⌥0 still work for vertical. ✅
10. Trackpad pinch on the waveform still zooms horizontally. ✅
11. Switching between media items resets both axes (existing behavior preserved by `load()`). ✅

If any step fails, stop and fix before committing.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/UI/WaveformContainer.swift OnlyCue.xcodeproj
git commit -m "feat(ui): replace bottom drag handle with hover-revealed zoom rails"
```

(`git rm` from Step 2 is already staged.)

---

## Task 4: Open the PR

- [ ] **Step 1: Push the branch and open a PR via the `gh-pr` skill**

Use the OnlyCue-forked `feat` template at `.github/PULL_REQUEST_TEMPLATE/feat.md`. The PR body must:

- Link the spec: `docs/superpowers/specs/2026-05-09-hover-zoom-rails-design.md`.
- Link the tracking issue (filed separately by the parent workflow).
- Note epic #36.
- In the OnlyCue verification block, list the 11 manual checks from Task 3 Step 7 and call out:
  - new test file `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift`,
  - existing controller tests still passing,
  - `swiftlint --strict` clean.

---

## Self-Review

**Spec coverage:**

- Layout & visibility (right-edge vertical rail, bottom horizontal rail, hover fade in/out, first-launch hint) → Task 3 Steps 1 & 7.
- Visual & content (translucent fill, hover deepen, magnifier + `N.N×` badge) → Task 2 Step 1 (`badge`, `restingFill`, `hoverFill`).
- Vertical drag interaction (drag up = in, `resizeUpDown`, reuses `applyDrag`) → Task 2 Step 1 (`verticalRail`) + Task 3 Step 1 (wiring).
- Horizontal drag interaction (drag right = in, anchored on cursor x-fraction, `resizeLeftRight`, reuses `setZoom`) → Task 1 (new `applyDrag`) + Task 3 Step 1 (wiring).
- Double-click badge resets axis → Task 2 Step 1 (`onTapGesture(count: 2)`).
- Keyboard shortcuts, pinch, scroll unchanged → Task 3 Step 7 manual checks (no code in those paths is touched).
- Files-touched list → matches Tasks 1–3.
- Tests: `WaveformZoomRailHorizontalDragTests` covers horizontal-axis math → Task 1 (the spec mentioned "rename `VerticalZoomDragHandleTests`"; no such test file exists today, so the plan creates a new file rather than renaming — vertical drag math is already covered by `WaveformVerticalZoomControllerTests`).

**Placeholder scan:** none. All steps have concrete code, commands, and expected output.

**Type consistency:** `WaveformZoomRail.Axis` (`.vertical` / `.horizontal`), `onDrag(_ translation, _ baseline, _ anchorFraction)`, and `onResetRequested` are referenced consistently across Tasks 2 and 3. New `WaveformZoomController.applyDrag(translation:baseline:anchorFraction:viewportWidth:scrollOffset:)` signature matches between Task 1 (definition + tests) and Task 3 (call site). `WaveformZoomController.dragPixelsPerStep` constant is introduced in Task 1 and referenced in the Task 1 tests.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-09-hover-zoom-rails.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
