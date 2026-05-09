# Waveform Zoom Magnifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two hover-revealed zoom rails (`WaveformZoomRail` on right + bottom) with a single hover-revealed magnifier control at the bottom-right corner of the waveform that exposes BOTH horizontal and vertical zoom via a two-axis click-and-drag gesture, with Shift-held axis lock and double-click reset.

**Architecture:** Three new files (`MagnifierAxisLock` pure helper, `WaveformZoomMagnifier` overlay view, `WaveformContainer+Magnifier` wiring extension), one modification to `WaveformContainer.swift`'s `loaded(peaks:)` body, and three deletions (rail view, rail extension, rail tests). The two zoom controllers (`WaveformZoomController`, `WaveformVerticalZoomController`) and their `applyDrag(...)` methods are unchanged — the magnifier is a pure UI swap that dispatches through the existing seams.

**Tech Stack:** SwiftUI (`@State`, `DragGesture`, `.overlay`), AppKit (`NSCursor.crosshair`, `NSEvent.modifierFlags`), XCTest, xcodegen, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-05-09-waveform-zoom-magnifier-design.md`

**Branch:** This plan executes against issue **#77** on branch `issues/77` (which already carries 3 commits from the original PR #74 polish scope: `FirstLaunchHintTracker` singleton, cancellable `.task` hint timer, and a now-moot anchor-literal comment). Issue #77's scope was widened from "polish rails per PR #74 review" to "redesign zoom UX as single magnifier"; PR #81's title and body are likewise updated. The two surviving commits provide `hintShowing` and `FirstLaunchHintTracker` which Tasks 5 (and the magnifier view itself) depend on — the third commit's rail-comment becomes moot when Task 6 deletes the rail file (no conflict, the modified line is in a deleted file).

---

## File Structure

| File | Role |
|---|---|
| `OnlyCue/UI/MagnifierAxisLock.swift` (new) | Pure-function helper: state enum, `Resolution` struct, static `resolve(...)` deciding which axis "wins" with Shift held. No SwiftUI dependency. |
| `OnlyCueTests/MagnifierAxisLockTests.swift` (new) | 6 unit tests covering all branches of `resolve(...)`. |
| `OnlyCue/UI/WaveformZoomMagnifier.swift` (new) | SwiftUI overlay view. Renders glyph + badge, runs `DragGesture`, calls into `MagnifierAxisLock`, forwards `MagnifierDrag` struct to the container. Owns no zoom math. |
| `OnlyCue/UI/WaveformContainer+Magnifier.swift` (new) | Extension adding `magnifier` computed property + `applyMagnifierDrag(_:)` + `applyMagnifierReset()`. The dispatch seam to the two existing controllers. |
| `OnlyCueTests/WaveformZoomMagnifierTests.swift` (new) | 4 dispatch-through-controllers tests for the magnifier wiring. |
| `OnlyCue/UI/WaveformContainer.swift` (modify) | `loaded(peaks:)` body: replace `ZStack { waveformBody; verticalRail; horizontalRail }` with `waveformBody.overlay(alignment: .bottomTrailing) { magnifier.padding(8) }`. |
| `OnlyCue/UI/WaveformZoomRail.swift` | **Delete** |
| `OnlyCue/UI/WaveformContainer+ZoomRails.swift` | **Delete** |
| `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift` | **Delete** (coverage preserved by `WaveformZoomMagnifierTests`) |

Net: +5 files, −3 files, 1 modification.

---

## Task 0: Switch to `issues/77` and confirm baseline

**Files:** none (git only)

- [ ] **Step 1: Switch to `issues/77`**

```bash
git checkout issues/77
git log --oneline dev..HEAD
```

Expected: three commits already present —
```
1212d64 docs(ui): clarify unused 0.5 anchor literal on vertical rail
7d598b1 fix(ui): cancellable .task hint timer routed through FirstLaunchHintTracker
18c54a6 feat(ui): add session-scoped FirstLaunchHintTracker
```

- [ ] **Step 2: Confirm dependencies present on the branch**

```bash
grep -n 'hintShowing\|FirstLaunchHintTracker' OnlyCue/UI/WaveformContainer.swift
test -f OnlyCue/Utilities/FirstLaunchHintTracker.swift && echo "tracker file present"
```

Expected: both succeed. If either misses, the branch state is corrupt — stop and surface that before continuing.

- [ ] **Step 3: Confirm `loaded(peaks:)` is in the post-PR-#81 shape (still rails, but with `.task` hint timer)**

```bash
sed -n '66,86p' OnlyCue/UI/WaveformContainer.swift
```

Expected: the body renders `ZStack { waveformBody; verticalRail; horizontalRail }` (rails still present), AND the hint plumbing is the `.task { try? await Task.sleep(for: .seconds(1.5)) ... }` form (NOT the older `.onAppear { DispatchQueue.main.asyncAfter ... }` form). Task 5 swaps the `ZStack` for an `.overlay`; Task 6 deletes the rail files.

---

## Task 1: `MagnifierAxisLock` — pure helper, RED test first

**Files:**
- Create: `OnlyCueTests/MagnifierAxisLockTests.swift`
- Create: `OnlyCue/UI/MagnifierAxisLock.swift`

- [ ] **Step 1: Write the 6 failing tests**

Create `OnlyCueTests/MagnifierAxisLockTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class MagnifierAxisLockTests: XCTestCase {

    func test_noShift_returnsUnlockedPassThrough() {
        let result = MagnifierAxisLock.resolve(
            translationX: 30,
            translationY: 5,
            isShiftHeld: false,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 30)
        XCTAssertEqual(result.effectiveY, 5)
        XCTAssertEqual(result.nextState, .unlocked)
    }

    func test_shift_belowThreshold_passThroughAndStaysUnresolved() {
        let result = MagnifierAxisLock.resolve(
            translationX: 5,
            translationY: 3,
            isShiftHeld: true,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 5)
        XCTAssertEqual(result.effectiveY, 3)
        XCTAssertEqual(
            result.nextState,
            .unresolved,
            "below threshold the user has not declared intent — must stay unresolved"
        )
    }

    func test_shift_atThreshold_horizontalDominant_locksHorizontal() {
        let result = MagnifierAxisLock.resolve(
            translationX: 15,
            translationY: 4,
            isShiftHeld: true,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 15)
        XCTAssertEqual(result.effectiveY, 0, "vertical must be zeroed once horizontal is locked")
        XCTAssertEqual(result.nextState, .lockedHorizontal)
    }

    func test_shift_atThreshold_verticalDominant_locksVertical() {
        let result = MagnifierAxisLock.resolve(
            translationX: 4,
            translationY: 15,
            isShiftHeld: true,
            currentState: .unresolved
        )
        XCTAssertEqual(result.effectiveX, 0, "horizontal must be zeroed once vertical is locked")
        XCTAssertEqual(result.effectiveY, 15)
        XCTAssertEqual(result.nextState, .lockedVertical)
    }

    func test_shift_alreadyLockedHorizontal_keepsLock_evenIfShiftReleased() {
        let result = MagnifierAxisLock.resolve(
            translationX: 20,
            translationY: 30,
            isShiftHeld: false,
            currentState: .lockedHorizontal
        )
        XCTAssertEqual(result.effectiveX, 20)
        XCTAssertEqual(result.effectiveY, 0, "lock is one-shot per drag — releasing Shift mid-drag must NOT release the lock")
        XCTAssertEqual(result.nextState, .lockedHorizontal)
    }

    func test_shift_alreadyLockedVertical_keepsLock() {
        let result = MagnifierAxisLock.resolve(
            translationX: 30,
            translationY: 20,
            isShiftHeld: true,
            currentState: .lockedVertical
        )
        XCTAssertEqual(result.effectiveX, 0)
        XCTAssertEqual(result.effectiveY, 20)
        XCTAssertEqual(result.nextState, .lockedVertical)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new test file is picked up**

```bash
xcodegen generate
```

Expected: `Created project at /Users/chienchuanw/Documents/only-cue/OnlyCue.xcodeproj`. No errors.

- [ ] **Step 3: Run the failing tests, verify RED**

```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/MagnifierAxisLockTests \
  2>&1 | tail -10
```

Expected: build error containing `Cannot find 'MagnifierAxisLock' in scope` (or equivalent). **TEST FAILED**.

- [ ] **Step 4: Implement the helper**

Create `OnlyCue/UI/MagnifierAxisLock.swift`:

```swift
import CoreGraphics

/// Pure-function helper that decides which axis "wins" when Shift is held during
/// a magnifier drag. Lives outside SwiftUI so the decision branches can be
/// unit-tested without spinning up a view host.
///
/// The lock is one-shot per drag: once `.lockedHorizontal` or `.lockedVertical`
/// is decided, it sticks for the rest of the drag, even if Shift is released
/// mid-drag. This is a deliberate UX choice — flipping axes mid-drag would be
/// surprising. The view resets `state` to `.unresolved` on `DragGesture.onEnded`.
enum MagnifierAxisLock {

    enum State: Equatable {
        case unresolved
        case unlocked
        case lockedHorizontal
        case lockedVertical
    }

    struct Resolution: Equatable {
        let nextState: State
        let effectiveX: CGFloat
        let effectiveY: CGFloat
    }

    /// Below this absolute translation (in points), the user has not moved far
    /// enough to declare axis intent — both translations pass through unchanged
    /// regardless of `isShiftHeld`, and `nextState` stays `.unresolved`.
    static let decisionThreshold: CGFloat = 10

    static func resolve(
        translationX: CGFloat,
        translationY: CGFloat,
        isShiftHeld: Bool,
        currentState: State
    ) -> Resolution {
        switch currentState {
        case .lockedHorizontal:
            return Resolution(nextState: .lockedHorizontal, effectiveX: translationX, effectiveY: 0)
        case .lockedVertical:
            return Resolution(nextState: .lockedVertical, effectiveX: 0, effectiveY: translationY)
        case .unlocked:
            return Resolution(nextState: .unlocked, effectiveX: translationX, effectiveY: translationY)
        case .unresolved:
            break
        }

        let absX = abs(translationX)
        let absY = abs(translationY)

        guard isShiftHeld else {
            return Resolution(nextState: .unlocked, effectiveX: translationX, effectiveY: translationY)
        }

        if max(absX, absY) < Self.decisionThreshold {
            return Resolution(nextState: .unresolved, effectiveX: translationX, effectiveY: translationY)
        }

        if absX >= absY {
            return Resolution(nextState: .lockedHorizontal, effectiveX: translationX, effectiveY: 0)
        } else {
            return Resolution(nextState: .lockedVertical, effectiveX: 0, effectiveY: translationY)
        }
    }
}
```

- [ ] **Step 5: Regenerate (xcodegen picks up the new source file)**

```bash
xcodegen generate
```

- [ ] **Step 6: Run tests, verify GREEN**

```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/MagnifierAxisLockTests \
  2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`. All 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/UI/MagnifierAxisLock.swift OnlyCueTests/MagnifierAxisLockTests.swift
git commit -m "feat(ui): add MagnifierAxisLock pure-helper with one-shot per-drag locking"
```

---

## Task 2: `WaveformZoomMagnifier` view

**Files:**
- Create: `OnlyCue/UI/WaveformZoomMagnifier.swift`

This task is pure SwiftUI rendering and gesture plumbing — no zoom math, no automated test coverage worth the maintenance cost (the only branching logic, axis-lock, is tested in Task 1; dispatch is tested in Task 4). Manually verify by building and visually checking in Task 6.

- [ ] **Step 1: Create the view file**

Create `OnlyCue/UI/WaveformZoomMagnifier.swift`:

```swift
import AppKit
import SwiftUI

/// Hover-revealed magnifier overlay rendered at the bottom-right corner of the
/// waveform. Single affordance for both horizontal and vertical zoom — exposes
/// each axis through a single `DragGesture` (X delta → horizontal, Y delta →
/// vertical). Holding Shift locks to the dominant axis (one-shot per drag, see
/// `MagnifierAxisLock`). Double-click resets both axes.
///
/// Owns no zoom math. Captures both baselines at drag start and forwards the
/// resolved per-tick translations to `onDrag` for the container to dispatch
/// through the two zoom controllers.
struct WaveformZoomMagnifier: View {

    let horizontalZoom: CGFloat
    let verticalZoom: CGFloat
    let isVisible: Bool
    let onDrag: (MagnifierDrag) -> Void
    let onResetRequested: () -> Void

    @State private var dragBaseline: (h: CGFloat, v: CGFloat)?
    @State private var axisLockState: MagnifierAxisLock.State = .unresolved
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .imageScale(.medium)
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "H %.1f×", Double(horizontalZoom)))
                Text(String(format: "V %.1f×", Double(verticalZoom)))
            }
            .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isHovering ? .thinMaterial : .ultraThinMaterial, in: Capsule())
        .contentShape(Capsule())
        .opacity(isVisible || dragBaseline != nil ? 1 : 0)
        .animation(.easeInOut(duration: isVisible ? 0.12 : 0.20), value: isVisible)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(dragGesture)
        .onTapGesture(count: 2) { onResetRequested() }
        .accessibilityIdentifier("waveformZoomMagnifier")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragBaseline == nil {
                    dragBaseline = (h: horizontalZoom, v: verticalZoom)
                }
                guard let baseline = dragBaseline else { return }

                let resolution = MagnifierAxisLock.resolve(
                    translationX: value.translation.width,
                    translationY: value.translation.height,
                    isShiftHeld: NSEvent.modifierFlags.contains(.shift),
                    currentState: axisLockState
                )
                axisLockState = resolution.nextState

                onDrag(MagnifierDrag(
                    translationX: resolution.effectiveX,
                    translationY: resolution.effectiveY,
                    hBaseline: baseline.h,
                    vBaseline: baseline.v
                ))
            }
            .onEnded { _ in
                dragBaseline = nil
                axisLockState = .unresolved
            }
    }
}

/// Per-tick drag payload forwarded from `WaveformZoomMagnifier` to the
/// container's dispatch helper. `translationX` / `translationY` are already
/// axis-lock-resolved (zeroed on the locked-out axis when Shift dictates).
struct MagnifierDrag {
    let translationX: CGFloat
    let translationY: CGFloat
    let hBaseline: CGFloat
    let vBaseline: CGFloat
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodegen generate
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (The view is unused so far — just ensures it compiles.)

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/WaveformZoomMagnifier.swift
git commit -m "feat(ui): add WaveformZoomMagnifier view (axis-lock-aware two-axis drag)"
```

---

## Task 3: `WaveformContainer+Magnifier` extension and dispatch helpers

**Files:**
- Create: `OnlyCue/UI/WaveformContainer+Magnifier.swift`

This task wires the magnifier to the two existing controllers. The dispatch logic is what Task 4 tests — write the helper now and the test next.

- [ ] **Step 1: Create the extension file**

Create `OnlyCue/UI/WaveformContainer+Magnifier.swift`:

```swift
import SwiftUI

/// Wires `WaveformZoomMagnifier` to the two existing zoom controllers.
/// Lives in a separate file to keep the magnifier wiring out of the dense
/// `WaveformContainer` body (matches the prior `+ZoomRails.swift` pattern).
extension WaveformContainer {

    var magnifier: some View {
        WaveformZoomMagnifier(
            horizontalZoom: zoom.zoom,
            verticalZoom: verticalZoom.zoom,
            isVisible: isHoveringWaveform || hintShowing,
            onDrag: applyMagnifierDrag,
            onResetRequested: applyMagnifierReset
        )
    }

    func applyMagnifierDrag(_ drag: MagnifierDrag) {
        guard viewportWidth > 0 else { return }

        // Horizontal axis: route through the existing setZoom-via-applyDrag path
        // so scroll-anchor + clamping stay correct. The magnifier sits in a
        // fixed corner — center-anchor (0.5) is the only sensible default.
        var offset = scrollOffset
        zoom.applyDrag(
            translation: drag.translationX,
            baseline: drag.hBaseline,
            anchorFraction: 0.5,
            viewportWidth: viewportWidth,
            scrollOffset: &offset
        )
        scrollOffset = offset
        pinchBaseline = zoom.zoom

        // Vertical axis: scales rendering in place, no scroll-offset coupling.
        verticalZoom.applyDrag(
            translation: drag.translationY,
            baseline: drag.vBaseline
        )

        syncAnchorFromOffset(viewportWidth: viewportWidth)
    }

    func applyMagnifierReset() {
        applyZoomReset()    // existing helper: resets horizontal + scrollOffset + leadingAnchor + pinchBaseline
        verticalZoom.reset()
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodegen generate
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. The extension is unused so far — its members will be called from `WaveformContainer`'s body in Task 5.

Note: the helpers are `internal` (no `private`) so `WaveformZoomMagnifierTests` (Task 4) can reach `applyMagnifierDrag` / `applyMagnifierReset` through the extension. This matches the precedent set by `WaveformContainer+ZoomRails.swift` for the same reason.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/WaveformContainer+Magnifier.swift
git commit -m "feat(ui): add WaveformContainer+Magnifier dispatch extension"
```

---

## Task 4: Dispatch tests through the two real controllers

**Files:**
- Create: `OnlyCueTests/WaveformZoomMagnifierTests.swift`

These tests exercise `applyMagnifierDrag` / `applyMagnifierReset` against the real `WaveformZoomController` + `WaveformVerticalZoomController` instances inside a `WaveformContainer`. They are the regression net for "did we break the wiring through the controllers" — reproducing the coverage of the deleted `WaveformZoomRailHorizontalDragTests.swift`.

The container's mutating helpers operate on `@State` properties that are accessible from the same module thanks to `internal` accessibility. Tests construct a container, mutate state via the helpers, and assert on `zoom.zoom` / `verticalZoom.zoom` / `scrollOffset` / `pinchBaseline`.

- [ ] **Step 1: Write the 4 failing tests**

Create `OnlyCueTests/WaveformZoomMagnifierTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class WaveformZoomMagnifierTests: XCTestCase {

    /// Build a container in a state ready for drag dispatch. Sets `viewportWidth`
    /// to a stable test value (400pt) so horizontal scroll-anchor math is
    /// deterministic.
    private func makeContainer() -> WaveformContainer {
        let url = URL(fileURLWithPath: "/dev/null")
        var container = WaveformContainer(asset: AVURLAsset(url: url))
        container.viewportWidth = 400
        return container
    }

    func test_applyMagnifierDrag_pureHorizontal_zoomsHorizontalOnly_andAnchorsAtCenter() {
        var container = makeContainer()

        // dragPixelsPerStep = 60; one full step = 1.5× zoom.
        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 60,
            translationY: 0,
            hBaseline: 1.0,
            vBaseline: 1.0
        ))

        XCTAssertEqual(container.zoom.zoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(container.verticalZoom.zoom, 1.0, accuracy: 0.001, "vertical untouched")
        XCTAssertEqual(
            container.scrollOffset,
            100,
            accuracy: 0.5,
            "center-anchored: viewport 400, zoomed to 1.5× → content 600, anchor 0.5 → offset 100"
        )
    }

    func test_applyMagnifierDrag_pureVertical_zoomsVerticalOnly() {
        var container = makeContainer()

        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 0,
            translationY: -60,
            hBaseline: 1.0,
            vBaseline: 1.0
        ))

        XCTAssertEqual(container.zoom.zoom, 1.0, accuracy: 0.001, "horizontal untouched")
        XCTAssertEqual(
            container.verticalZoom.zoom,
            1.5,
            accuracy: 0.001,
            "vertical drag uses negative-up convention — drag up zooms in"
        )
        XCTAssertEqual(container.scrollOffset, 0, accuracy: 0.5)
    }

    func test_applyMagnifierDrag_diagonal_appliesBoth() {
        var container = makeContainer()

        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 60,
            translationY: -60,
            hBaseline: 1.0,
            vBaseline: 1.0
        ))

        XCTAssertEqual(container.zoom.zoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(container.verticalZoom.zoom, 1.5, accuracy: 0.001)
    }

    func test_applyMagnifierReset_resetsBothAxes() {
        var container = makeContainer()

        // Pre-zoom both axes via the drag helper (avoids touching internals).
        container.applyMagnifierDrag(MagnifierDrag(
            translationX: 120,    // 2 steps → 2.25×
            translationY: -120,   // 2 steps → 2.25×
            hBaseline: 1.0,
            vBaseline: 1.0
        ))
        XCTAssertGreaterThan(container.zoom.zoom, 1.0)
        XCTAssertGreaterThan(container.verticalZoom.zoom, 1.0)

        container.applyMagnifierReset()

        XCTAssertEqual(container.zoom.zoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(container.verticalZoom.zoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(container.scrollOffset, 0, accuracy: 0.5)
    }
}
```

A note for the implementer: if any assertion's expected value disagrees with the actual output, **the test is the source of truth** for the spec's contract. Tune the expected number to match the controller's behavior only if the new value still satisfies the spec's intent (e.g. "1.5× per 60pt step" is the rule from `WaveformZoomController.swift`'s existing `dragPixelsPerStep` constant). If the assertion has to flex by more than a couple of pixels of `scrollOffset` or 0.01× of zoom, stop and re-read `WaveformZoomController.applyDrag(...)` and `WaveformVerticalZoomController.applyDrag(...)` to understand what the controllers actually do — do NOT loosen the assertions to paper over a real wiring bug.

- [ ] **Step 2: Regenerate and run, verify RED**

```bash
xcodegen generate
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/WaveformZoomMagnifierTests \
  2>&1 | tail -15
```

Expected outcomes are one of:

- **Build error** if Task 3's `applyMagnifierDrag` / `applyMagnifierReset` aren't visible — fix accessibility (drop any `private` qualifier you may have introduced).
- **Test failure** if values disagree — see the implementer's note above.
- **Test pass** — if Task 3's wiring already happens to match the spec's expected numbers, you're done with this task; skip Step 3.

If Step 2 already passes (the wiring is correct because the controllers already match the spec), this is acceptable — the helper was written before the test in Task 3, but the test still locks behavior. The RED→GREEN ordering inside Task 1 is what proves the axis-lock helper is exercised; this task's role is regression-net coverage of the dispatch.

- [ ] **Step 3: Fix any wiring mismatches and re-run**

If a test fails, edit `OnlyCue/UI/WaveformContainer+Magnifier.swift` (NOT the test) until all 4 tests pass:

```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/WaveformZoomMagnifierTests \
  2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`. All 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add OnlyCueTests/WaveformZoomMagnifierTests.swift
git commit -m "test(ui): add 4 dispatch tests for WaveformContainer+Magnifier"
```

---

## Task 5: Swap the rails for the magnifier in `WaveformContainer.body`

**Files:**
- Modify: `OnlyCue/UI/WaveformContainer.swift` (`loaded(peaks:)` body around line 67–85)

- [ ] **Step 1: Read the current `loaded(peaks:)` shape**

```bash
sed -n '66,86p' OnlyCue/UI/WaveformContainer.swift
```

Expected output (the post-PR-#81 shape — verify the `.task { ... hintShowing ... }` block is present; if it's the older `.onAppear { DispatchQueue.main.asyncAfter ... }` shape, PR #81 has not landed and you must rebase before continuing):

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
    .task {
        guard !FirstLaunchHintTracker.shared.hasShownWaveformZoomHint else { return }
        FirstLaunchHintTracker.shared.markShown()
        hintShowing = true
        try? await Task.sleep(for: .seconds(1.5))
        hintShowing = false
    }
}
```

- [ ] **Step 2: Replace the `ZStack` with an `.overlay`**

Edit `OnlyCue/UI/WaveformContainer.swift` — replace the `loaded(peaks:)` body with:

```swift
@ViewBuilder
private func loaded(peaks: [Float]) -> some View {
    waveformBody(peaks: peaks)
        .padding(.horizontal, 8)
        .overlay(alignment: .bottomTrailing) {
            magnifier.padding(8)
        }
        .onHover { hovering in
            isHoveringWaveform = hovering
        }
        .task {
            guard !FirstLaunchHintTracker.shared.hasShownWaveformZoomHint else { return }
            FirstLaunchHintTracker.shared.markShown()
            hintShowing = true
            try? await Task.sleep(for: .seconds(1.5))
            hintShowing = false
        }
}
```

Two things changed:
- `ZStack(alignment: .bottomTrailing) { waveformBody; verticalRail; horizontalRail }` → `waveformBody(peaks:).padding(.horizontal, 8).overlay(alignment: .bottomTrailing) { magnifier.padding(8) }`.
- `.padding(.horizontal, 8)` moves up to wrap `waveformBody` directly (was outside the `ZStack`); the `magnifier` gets its own `.padding(8)` inside the overlay so it sits ~8pt off both the right and bottom edges.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Two unresolved references will appear at build time if Task 6 has not run yet — `verticalRail` and `horizontalRail` no longer have callers, but they're still defined in `WaveformContainer+ZoomRails.swift`. That's expected (they're just orphaned). Build still succeeds.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/WaveformContainer.swift
git commit -m "feat(ui): swap zoom rails for single magnifier overlay in WaveformContainer"
```

---

## Task 6: Delete the rails

**Files:**
- Delete: `OnlyCue/UI/WaveformZoomRail.swift`
- Delete: `OnlyCue/UI/WaveformContainer+ZoomRails.swift`
- Delete: `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift`

- [ ] **Step 1: Confirm the rails have no remaining callers**

```bash
grep -rn 'WaveformZoomRail\|verticalRail\|horizontalRail\|applyHorizontalRailDrag' OnlyCue OnlyCueTests
```

Expected: only the three files-to-be-deleted appear. If anything else matches, stop and trace the caller — Task 5's swap missed something.

- [ ] **Step 2: Delete the files**

```bash
rm OnlyCue/UI/WaveformZoomRail.swift
rm OnlyCue/UI/WaveformContainer+ZoomRails.swift
rm OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift
```

- [ ] **Step 3: Regenerate Xcode project so the deleted files leave the targets**

```bash
xcodegen generate
```

- [ ] **Step 4: Build to verify it still compiles**

```bash
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A OnlyCue/UI OnlyCueTests
git commit -m "refactor(ui): remove WaveformZoomRail and rail tests (superseded by magnifier)"
```

---

## Task 7: Full test suite + lint gate

**Files:** none (verification only)

- [ ] **Step 1: Run the entire unit-test suite**

```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests \
  2>&1 | tail -10
```

Expected: all unit tests pass. Test count should be `(prior count) + 6 + 4 − 6 = prior + 4` (PR #81 ended at 203; this PR ends at 207).

If anything fails, **do not** modify the failing test to make it pass. Read the assertion, re-read the relevant production code, fix the production code. The only edits to test files in this task are pure mechanics (e.g. fixing a typo in a helper); never relax an assertion to paper over a regression.

- [ ] **Step 2: Run SwiftLint --strict**

```bash
swiftlint --strict 2>&1 | tail -3
```

Expected: `Found 0 violations, 0 serious in N files.` Where N is approximately 81 (PR #81's 82, minus 3 deleted, plus 5 new — though the test files counted in lint will vary).

If SwiftLint flags `type_body_length` on `WaveformContainer.swift`: check whether the body grew past 250 lines. The expected outcome is the opposite — the body should shrink because two view properties (`verticalRail`, `horizontalRail`) and one helper (`applyHorizontalRailDrag`) moved out of the `+Magnifier` extension's predecessor. If it still trips, extract more wiring into the `+Magnifier` extension before tuning the `.swiftlint.yml` — the cap exists for a reason.

- [ ] **Step 3: Build Release with warnings-as-errors**

```bash
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -configuration Release \
  -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. No warnings.

- [ ] **Step 4: Manual smoke (Gherkin scenarios from spec)**

Open the app via:

```bash
open /Users/chienchuanw/Library/Developer/Xcode/DerivedData/OnlyCue-*/Build/Products/Debug/OnlyCue.app
```

Then verify each scenario in `docs/superpowers/specs/2026-05-09-waveform-zoom-magnifier-design.md` § Acceptance:

1. Import a media file. **Don't** hover the waveform yet → magnifier invisible, no gray rails ✓.
2. Hover the waveform → magnifier fades in at bottom-right, badge shows `H 1.0× / V 1.0×` ✓.
3. Click-and-drag the magnifier diagonally up-and-right ~60pt each → both axes zoom to ~1.5×, badge updates live ✓.
4. Hold Shift, drag horizontally past 10pt → only horizontal changes, vertical stays put even after releasing Shift ✓.
5. Release the drag, double-click the magnifier → both axes back to 1.0×, scroll back to 0 ✓.
6. Press `⌘=`, `⌘⌥=`, trackpad-pinch — all three keep working, magnifier badge reflects each change ✓.
7. Switch to a second media item → zooms reset, magnifier visibility resets to invisible-until-hover ✓.

If any scenario fails, **fix the production code, not the spec**. Add a regression test in `WaveformZoomMagnifierTests.swift` if the failure represents a behavior the dispatch tests didn't cover.

- [ ] **Step 5: No commit needed for verification**

If a SwiftLint fix was required in Step 2, commit it separately:

```bash
git add -p
git commit -m "chore(ui): lint fixes for magnifier overlay"
```

---

## Task 8: Push, open PR, and stand by

**Files:** none (git + GitHub only)

- [ ] **Step 1: Push the branch**

```bash
git push -u origin issues/77
```

- [ ] **Step 2: Confirm commit list is in scope**

```bash
git log --oneline dev..HEAD
```

Expected (one line per task that produced a commit):

```
<sha> chore(ui): lint fixes for magnifier overlay   [optional, only if Step 2 of Task 7 needed it]
<sha> refactor(ui): remove WaveformZoomRail and rail tests (superseded by magnifier)
<sha> feat(ui): swap zoom rails for single magnifier overlay in WaveformContainer
<sha> test(ui): add 4 dispatch tests for WaveformContainer+Magnifier
<sha> feat(ui): add WaveformContainer+Magnifier dispatch extension
<sha> feat(ui): add WaveformZoomMagnifier view (axis-lock-aware two-axis drag)
<sha> feat(ui): add MagnifierAxisLock pure-helper with one-shot per-drag locking
```

If unrelated commits appear, stop and surface them — do NOT push a mixed-scope PR.

- [ ] **Step 3: Open the PR via the `gh-pr` skill**

Use the forked OnlyCue PR template at `.github/PULL_REQUEST_TEMPLATE/feat.md`. PR title:

> `feat(ui): single magnifier zoom control replacing hover-revealed rails`

Body must include:

- **Summary**: one-paragraph description of the swap (rails → magnifier, two-axis drag, axis-lock, double-click reset).
- **Motivation**: less visual surface area; one affordance instead of two; rails were axis-perpendicular which was confusing.
- **Implementation**: link to the spec; call out the three load-bearing design calls (one-shot axis-lock, hard-coded `0.5` horizontal anchor, hover-revealed visibility kept verbatim from PR #81).
- **Test Plan**: 6 axis-lock pure tests + 4 dispatch tests + manual smoke covering all 5 Gherkin scenarios.
- **OnlyCue verification footer** with spec link and `Closes #<N>`.

- [ ] **Step 4: Stand by**

Bypass scope ends at PR creation. Wait for review / merge signal.

---

## Definition of Done

- Single hover-revealed magnifier visible at the bottom-right of the waveform; both axes zoom via two-axis click-and-drag; Shift locks to dominant axis; double-click resets both axes.
- Trackpad pinch and `⌘=` / `⌘-` / `⌘0` / `⌘⌥=` / `⌘⌥-` / `⌘⌥0` keyboard shortcuts continue to work.
- 6 `MagnifierAxisLockTests` + 4 `WaveformZoomMagnifierTests` pass.
- `WaveformZoomRail.swift`, `WaveformContainer+ZoomRails.swift`, `WaveformZoomRailHorizontalDragTests.swift` deleted.
- Full unit-test suite green, SwiftLint --strict clean, Release build clean (warnings-as-errors).
- All 7 Gherkin scenarios from the spec verified manually.
- PR opened against `dev`.
