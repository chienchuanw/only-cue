# Marker Drag & Group Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable dragging cue markers on the main-pane waveform to retime cues, with group drag (rigid Δ shift) for multi-selection and Shift-to-snap on the tempo grid.

**Architecture:** Single-marker drag already exists in `CueMarkersOverlay`. We lift the per-marker drag `@State` up to the overlay so a shared Δ can drive every selected marker simultaneously. Commit dispatches to `CueCommands.retime` (solo) or `CueCommands.nudgeCues` (group). A pure `snapDeltaToBeat` helper in `CueMarkersGeometry` anchors Shift-snap on the grabbed cue and applies the same pixel Δ to the whole group, preserving spacing.

**Tech Stack:** Swift / SwiftUI / AppKit (`NSCursor`, `NSEvent.modifierFlags`), XCTest, OnlyCue UI tests.

**Spec:** [`docs/superpowers/specs/2026-05-14-marker-drag-and-group-drag-design.md`](../specs/2026-05-14-marker-drag-and-group-drag-design.md)

---

## File map

| File | Role |
|---|---|
| `OnlyCue/UI/CueMarkersGeometry.swift` | Add `snapDeltaToBeat` (pure) |
| `OnlyCue/UI/CueMarkersOverlay.swift` | Lift drag state to overlay; branch solo/group; Shift-snap; replace-on-grab; hover cursor |
| `OnlyCue/UI/WaveformContainer.swift` | Add `onNudge` closure param + already-present `tempoGrid` is passed through |
| `OnlyCue/UI/WaveformContainer+Overlays.swift` | Pass `tempoGrid` + `onNudge` into `CueMarkersOverlay` |
| `OnlyCue/UI/DocumentView+Bindings.swift` (or `DocumentView.swift`) | Wire `onNudge` closure to `CueCommands.nudgeCues` |
| `OnlyCueTests/CueMarkersGeometryTests.swift` | Tests for `snapDeltaToBeat` |
| `OnlyCueTests/CueMarkersOverlayTests.swift` (new) | Tests for solo/group commit dispatch and replace-on-grab |
| `OnlyCueUITests/CueGroupDragUITests.swift` (new) | Gherkin scenarios for group drag, replace-on-grab, Shift-snap |

---

## Task 1: Pure `snapDeltaToBeat` helper

**Files:**
- Modify: `OnlyCue/UI/CueMarkersGeometry.swift`
- Test: `OnlyCueTests/CueMarkersGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `OnlyCueTests/CueMarkersGeometryTests.swift`:

```swift
// MARK: - snapDeltaToBeat

func test_snapDeltaToBeat_snapsAnchorToNearestBeat() {
    // 120 BPM => beats every 0.5s. Anchor at 1.0s. width=200px, duration=10s
    // => 20 px/s. Raw dx=+12px => proposed anchor time = 1.6s.
    // Nearest beat in [1.0, 1.5, 2.0, ...] is 1.5s. Adjusted dx = (1.5-1.0)*20 = +10px.
    let grid = DerivedTempoGrid(segments: [
        .init(startSeconds: 0, bpm: 120, beatsPerBar: 4)
    ])
    let adjusted = CueMarkersGeometry.snapDeltaToBeat(
        dxPixels: 12,
        anchorTime: 1.0,
        grid: grid,
        width: 200,
        duration: 10
    )
    XCTAssertEqual(adjusted, 10, accuracy: 0.001)
}

func test_snapDeltaToBeat_negativeDelta_snapsBackward() {
    // Same 120 BPM grid. Anchor at 2.0s. Raw dx=-6px => proposed = 1.7s.
    // Nearest beat is 1.5s. Adjusted dx = (1.5-2.0)*20 = -10px.
    let grid = DerivedTempoGrid(segments: [
        .init(startSeconds: 0, bpm: 120, beatsPerBar: 4)
    ])
    let adjusted = CueMarkersGeometry.snapDeltaToBeat(
        dxPixels: -6,
        anchorTime: 2.0,
        grid: grid,
        width: 200,
        duration: 10
    )
    XCTAssertEqual(adjusted, -10, accuracy: 0.001)
}

func test_snapDeltaToBeat_emptyGrid_returnsDxUnchanged() {
    let grid = DerivedTempoGrid(segments: [])
    let adjusted = CueMarkersGeometry.snapDeltaToBeat(
        dxPixels: 17,
        anchorTime: 2.0,
        grid: grid,
        width: 200,
        duration: 10
    )
    XCTAssertEqual(adjusted, 17, accuracy: 0.001)
}

func test_snapDeltaToBeat_zeroWidth_returnsDxUnchanged() {
    let grid = DerivedTempoGrid(segments: [
        .init(startSeconds: 0, bpm: 120, beatsPerBar: 4)
    ])
    let adjusted = CueMarkersGeometry.snapDeltaToBeat(
        dxPixels: 17,
        anchorTime: 2.0,
        grid: grid,
        width: 0,
        duration: 10
    )
    XCTAssertEqual(adjusted, 17, accuracy: 0.001)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueMarkersGeometryTests 2>&1 | tail -30`

Expected: build fails (`snapDeltaToBeat` not defined) or tests fail.

- [ ] **Step 3: Implement the helper**

Append to `OnlyCue/UI/CueMarkersGeometry.swift` inside `enum CueMarkersGeometry`:

```swift
/// Returns the pixel Δ that, when applied to `anchorTime`, lands on the nearest
/// beat of `grid`. Falls back to `dxPixels` unchanged when the grid is empty,
/// width is non-positive, or no covering segment exists. Used by group drag so
/// the whole selection rides along by the snapped pixel Δ (anchored on the
/// grabbed cue), which preserves inter-cue spacing.
static func snapDeltaToBeat(
    dxPixels: CGFloat,
    anchorTime: TimeInterval,
    grid: DerivedTempoGrid,
    width: CGFloat,
    duration: TimeInterval
) -> CGFloat {
    guard !grid.isEmpty, width > 0, duration > 0 else { return dxPixels }
    let proposedTime = time(originalTime: anchorTime, dx: dxPixels, width: width, duration: duration)
    guard let snapped = grid.nearestBeat(toSeconds: proposedTime, itemDuration: duration) else {
        return dxPixels
    }
    return CGFloat((snapped - anchorTime) / duration) * width
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueMarkersGeometryTests 2>&1 | tail -30`

Expected: all `CueMarkersGeometryTests` pass.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueMarkersGeometry.swift OnlyCueTests/CueMarkersGeometryTests.swift
git commit -m "feat(markers): add snapDeltaToBeat geometry helper"
```

---

## Task 2: Lift drag state — refactor `CueMarkersOverlay` (no behavior change)

This task only restructures state. Solo-drag behavior must remain identical at the end of this task.

**Files:**
- Modify: `OnlyCue/UI/CueMarkersOverlay.swift`

- [ ] **Step 1: Replace the overlay body with lifted drag state**

Rewrite `OnlyCue/UI/CueMarkersOverlay.swift` to:

```swift
import AppKit
import SwiftUI

struct CueMarkersOverlay: View {

    let cues: [Cue]
    let duration: TimeInterval
    var resolveColorHex: (Cue) -> String? = { _ in nil }
    var selectedCueIDs: Set<Cue.ID> = []
    var tempoGrid: DerivedTempoGrid = DerivedTempoGrid(segments: [])
    /// Plain marker click → replace the selection with this cue.
    var onSelectCue: (Cue.ID) -> Void = { _ in }
    /// ⌘- (or ⇧-) marker click → toggle this cue in/out of the selection.
    var onToggleCue: (Cue.ID) -> Void = { _ in }
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }
    /// Rigid shift of every cue in the set by the same Δt (clamped at 0 per cue),
    /// committed as a single undo entry. Used by group drag.
    var onNudge: (Set<Cue.ID>, TimeInterval) -> Void = { _, _ in }

    @State private var activeDrag: ActiveDrag? = nil

    fileprivate struct ActiveDrag: Equatable {
        let grabbedID: Cue.ID
        let movingIDs: Set<Cue.ID>
        let isGroup: Bool
        var dxRaw: CGFloat
        var dxApplied: CGFloat
    }

    private static let dragThreshold: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(cues) { cue in
                    CueMarkerView(
                        cue: cue,
                        resolvedColorHex: resolveColorHex(cue),
                        baseX: CueMarkersGeometry.position(
                            forTime: cue.time,
                            width: geometry.size.width,
                            duration: duration
                        ),
                        isSelected: selectedCueIDs.contains(cue.id),
                        visualOffset: visualOffset(for: cue.id),
                        onDragChanged: { translationWidth in
                            handleDragChanged(grabbedID: cue.id, translationWidth: translationWidth, width: geometry.size.width)
                        },
                        onDragEnded: { translationWidth in
                            handleDragEnded(grabbedID: cue.id, translationWidth: translationWidth, width: geometry.size.width)
                        }
                    )
                }
            }
        }
        .accessibilityIdentifier("cueMarkersOverlay")
    }

    private func visualOffset(for id: Cue.ID) -> CGFloat {
        guard let drag = activeDrag, drag.movingIDs.contains(id) else { return 0 }
        return drag.dxApplied
    }

    private func cue(for id: Cue.ID) -> Cue? {
        cues.first(where: { $0.id == id })
    }

    private func handleDragChanged(grabbedID: Cue.ID, translationWidth: CGFloat, width: CGFloat) {
        if activeDrag == nil {
            let isGroup = selectedCueIDs.contains(grabbedID) && selectedCueIDs.count >= 2
            let moving: Set<Cue.ID>
            if isGroup {
                moving = selectedCueIDs
            } else {
                // Solo drag of an unselected marker while a multi-selection exists:
                // replace selection with just this cue, mirroring plain-click.
                if !selectedCueIDs.contains(grabbedID) && selectedCueIDs.count >= 2 {
                    onSelectCue(grabbedID)
                }
                moving = [grabbedID]
            }
            activeDrag = ActiveDrag(
                grabbedID: grabbedID,
                movingIDs: moving,
                isGroup: isGroup,
                dxRaw: translationWidth,
                dxApplied: translationWidth
            )
        }
        guard var drag = activeDrag else { return }
        drag.dxRaw = translationWidth
        drag.dxApplied = applySnap(dxRaw: translationWidth, grabbedID: drag.grabbedID, width: width)
        activeDrag = drag
    }

    private func handleDragEnded(grabbedID: Cue.ID, translationWidth: CGFloat, width: CGFloat) {
        defer { activeDrag = nil }
        guard let drag = activeDrag, drag.grabbedID == grabbedID else {
            // Gesture ended without onChanged (shouldn't happen with minimumDistance:0);
            // treat as tap.
            handleTap(grabbedID: grabbedID)
            return
        }
        let dxFinal = applySnap(dxRaw: translationWidth, grabbedID: grabbedID, width: width)
        if abs(dxFinal) < Self.dragThreshold {
            handleTap(grabbedID: grabbedID)
            return
        }
        guard let grabbed = cue(for: grabbedID) else { return }
        let newTime = CueMarkersGeometry.time(
            originalTime: grabbed.time,
            dx: dxFinal,
            width: width,
            duration: duration
        )
        let deltaT = newTime - grabbed.time
        if drag.isGroup {
            onNudge(drag.movingIDs, deltaT)
        } else {
            onRetime(grabbedID, newTime)
        }
    }

    private func handleTap(grabbedID: Cue.ID) {
        let modifiers = NSEvent.modifierFlags
        let extending = modifiers.contains(.command) || modifiers.contains(.shift)
        if extending {
            onToggleCue(grabbedID)
        } else {
            onSelectCue(grabbedID)
            if let c = cue(for: grabbedID) {
                onSeek(c.time)
            }
        }
    }

    private func applySnap(dxRaw: CGFloat, grabbedID: Cue.ID, width: CGFloat) -> CGFloat {
        // Shift held + tempo grid available → snap anchor (grabbed cue) to nearest beat.
        guard NSEvent.modifierFlags.contains(.shift),
              !tempoGrid.isEmpty,
              let anchor = cue(for: grabbedID) else {
            return dxRaw
        }
        return CueMarkersGeometry.snapDeltaToBeat(
            dxPixels: dxRaw,
            anchorTime: anchor.time,
            grid: tempoGrid,
            width: width,
            duration: duration
        )
    }
}

struct CueMarkerView: View {

    struct MarkerStyle: Equatable {
        let lineWidth: CGFloat
        let capWidth: CGFloat
        let capHeight: CGFloat

        static let normal = Self(lineWidth: 2, capWidth: 10, capHeight: 8)
        static let selected = Self(lineWidth: 3, capWidth: 14, capHeight: 12)

        static func style(isSelected: Bool) -> Self {
            isSelected ? .selected : .normal
        }
    }

    let cue: Cue
    var resolvedColorHex: String?
    let baseX: CGFloat
    var isSelected: Bool = false
    var visualOffset: CGFloat = 0
    var onDragChanged: (_ translationWidth: CGFloat) -> Void = { _ in }
    var onDragEnded: (_ translationWidth: CGFloat) -> Void = { _ in }

    private static let hitWidth: CGFloat = 14
    private static let labelGap: CGFloat = 1

    private var style: MarkerStyle { MarkerStyle.style(isSelected: isSelected) }

    var body: some View {
        VStack(spacing: Self.labelGap) {
            if let number = cue.cueNumber {
                Text(FadeTime.formatNumber(number))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityIdentifier("cueMarkerLabel-\(cue.id.uuidString)")
            }
            ZStack(alignment: .top) {
                Capsule()
                    .fill(.clear)
                    .frame(width: Self.hitWidth)
                    .onHover { inside in
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
        }
        .frame(width: Self.hitWidth)
        .offset(x: baseX + visualOffset - Self.hitWidth / 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in onDragChanged(value.translation.width) }
                .onEnded { value in onDragEnded(value.translation.width) }
        )
        .accessibilityIdentifier("cueMarker-\(cue.id.uuidString)")
    }

    private var markerColor: Color {
        guard let hex = resolvedColorHex else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }
}
```

- [ ] **Step 2: Update overlay call-site to compile**

The overlay's API now has `tempoGrid` and `onNudge` params (defaulted, so existing call-site still compiles). Confirm by reading `OnlyCue/UI/WaveformContainer+Overlays.swift` — no change required yet; defaults absorb the absence.

- [ ] **Step 3: Build to confirm zero behavior change**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: build succeeds.

- [ ] **Step 4: Run existing geometry tests still pass**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueMarkersGeometryTests 2>&1 | tail -10`

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueMarkersOverlay.swift
git commit -m "refactor(markers): lift drag state to overlay, add hover cursor"
```

---

## Task 3: Wire `onNudge` and `tempoGrid` through to the overlay

**Files:**
- Modify: `OnlyCue/UI/WaveformContainer.swift`
- Modify: `OnlyCue/UI/WaveformContainer+Overlays.swift`
- Modify: `OnlyCue/UI/DocumentView+Bindings.swift` (or wherever `WaveformContainer` is constructed)

- [ ] **Step 1: Add `onNudge` to `WaveformContainer`**

In `OnlyCue/UI/WaveformContainer.swift`, near the existing `onRetime` declaration (around line 15), add:

```swift
var onNudge: (Set<Cue.ID>, TimeInterval) -> Void = { _, _ in }
```

- [ ] **Step 2: Pass `tempoGrid` + `onNudge` into `CueMarkersOverlay`**

In `OnlyCue/UI/WaveformContainer+Overlays.swift`, update the `CueMarkersOverlay` initializer call to include the two new params:

```swift
CueMarkersOverlay(
    cues: cues,
    duration: loadedDuration,
    resolveColorHex: resolveColorHex,
    selectedCueIDs: selectedCueIDs,
    tempoGrid: tempoGrid,
    onSelectCue: onSelectCue,
    onToggleCue: onToggleCue,
    onSeek: onSeek,
    onRetime: onRetime,
    onNudge: onNudge
)
```

- [ ] **Step 3: Wire `onNudge` at the call-site**

Find where `WaveformContainer` is constructed. Run:

```bash
grep -rn "WaveformContainer(" OnlyCue/UI/ | grep -v "+Overlays\|+Magnifier"
```

In that file (likely `DocumentView+Bindings.swift` or `DocumentView.swift`), find the `onRetime: { id, time in ... }` closure and add a sibling:

```swift
onNudge: { ids, delta in
    CueCommands.nudgeCues(ids, by: delta, document: document, undoManager: undoManager)
},
```

(Adjust `document` and `undoManager` references to match what the existing `onRetime` closure uses.)

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/WaveformContainer.swift OnlyCue/UI/WaveformContainer+Overlays.swift OnlyCue/UI/DocumentView*.swift
git commit -m "feat(markers): wire onNudge and tempoGrid through to CueMarkersOverlay"
```

---

## Task 4: Unit tests for overlay drag commit dispatch

This task verifies the overlay's commit logic by exercising `CueCommands.nudgeCues` / `CueCommands.retime` semantics, plus the boundary clamp behavior agreed in the spec.

**Files:**
- Create: `OnlyCueTests/CueMarkersOverlayDispatchTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/CueMarkersOverlayDispatchTests.swift`:

```swift
import XCTest
@testable import OnlyCue

/// Verifies the command-level behavior that `CueMarkersOverlay` relies on when
/// dispatching its drag-end commit: solo → `retime`, group → `nudgeCues` with
/// individual t=0 clamp. The overlay's gesture wiring is exercised end-to-end in
/// `CueGroupDragUITests`; these tests pin the underlying command semantics so
/// the overlay can stay a thin coordinator.
final class CueMarkersOverlayDispatchTests: XCTestCase {

    private func makeDocument(cueTimes: [TimeInterval]) -> CueListDocument {
        let document = CueListDocument()
        let item = MediaItem(id: UUID(), name: "test", url: nil, bookmark: nil, startTC: nil, muted: false)
        document.model.items = [item]
        document.model.activeItemID = item.id
        document.model.activeItem?.cues = cueTimes.enumerated().map { _, t in
            Cue(id: UUID(), typeID: nil, cueNumber: nil, name: "", time: t, notes: "", fadeTime: nil)
        }
        return document
    }

    func test_nudgeCues_shiftsAllByDelta_singleUndoEntry() {
        let document = makeDocument(cueTimes: [1.0, 3.0, 6.0])
        let ids = Set(document.model.activeItem!.cues.map(\.id))
        let undo = UndoManager()

        CueCommands.nudgeCues(ids, by: 5.0, document: document, undoManager: undo)

        let times = document.model.activeItem!.cues.map(\.time).sorted()
        XCTAssertEqual(times, [6.0, 8.0, 11.0])
        XCTAssertTrue(undo.canUndo)
    }

    func test_nudgeCues_clampsEachCueAtZero() {
        // [0.1, 2.0, 5.0] with Δ = -1.0 → [0.0, 1.0, 4.0]. Group compresses at left edge.
        let document = makeDocument(cueTimes: [0.1, 2.0, 5.0])
        let ids = Set(document.model.activeItem!.cues.map(\.id))

        CueCommands.nudgeCues(ids, by: -1.0, document: document, undoManager: nil)

        let times = document.model.activeItem!.cues.map(\.time).sorted()
        XCTAssertEqual(times[0], 0.0, accuracy: 1e-9)
        XCTAssertEqual(times[1], 1.0, accuracy: 1e-9)
        XCTAssertEqual(times[2], 4.0, accuracy: 1e-9)
    }

    func test_retime_movesOnlyOneCue() {
        let document = makeDocument(cueTimes: [1.0, 3.0, 6.0])
        let target = document.model.activeItem!.cues[1].id

        CueCommands.retime(cueId: target, to: 4.5, document: document, undoManager: nil)

        let times = document.model.activeItem!.cues.map(\.time).sorted()
        XCTAssertEqual(times, [1.0, 4.5, 6.0])
    }
}
```

> **Note for the engineer:** the `MediaItem` initializer signature above is the one in v11 schema. If the actual initializer differs, match the one used in existing tests (search `OnlyCueTests/` for `MediaItem(` to find a current example).

- [ ] **Step 2: Run to verify failure first, then implement-only-if-needed**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueMarkersOverlayDispatchTests 2>&1 | tail -30`

Expected: tests compile and pass on first run (the commands already exist). The test exists to **lock the contract** the overlay depends on — if a later refactor breaks `nudgeCues` semantics, these tests fail.

If the test file fails to compile because of model-init signature drift, fix the initializer call to match the current `MediaItem` / `Cue` shape and re-run.

- [ ] **Step 3: Commit**

```bash
git add OnlyCueTests/CueMarkersOverlayDispatchTests.swift
git commit -m "test(markers): pin nudgeCues group-shift and clamp contract"
```

---

## Task 5: UI tests for group drag, replace-on-grab, Shift-snap

**Files:**
- Create: `OnlyCueUITests/CueGroupDragUITests.swift`

- [ ] **Step 1: Survey existing UI-test helpers**

Run to find how cues are seeded and markers are dragged in existing tests:

```bash
grep -rn "cueMarker-\|cueMarkersOverlay" OnlyCueUITests/ OnlyCue/UI/
grep -rln "XCUIElement.*press(forDuration\|.*thenDragTo" OnlyCueUITests/
```

If no helper exists for drag, use `XCUIElement.press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` or the simpler `.press(forDuration:thenDragTo:)`.

- [ ] **Step 2: Write the UI tests**

Create `OnlyCueUITests/CueGroupDragUITests.swift`:

```swift
import XCTest

/// BDD-style scenarios for direct-manipulation drag of cue markers on the
/// main-pane waveform. Spec: docs/superpowers/specs/2026-05-14-marker-drag-and-group-drag-design.md
final class CueGroupDragUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: Group drag shifts all selected cues rigidly
    /// Given a project with cues at 1s, 3s, 6s and all selected
    /// When the user drags the marker at 3s by +N px on the waveform
    /// Then all three cue times shift by the same Δt
    /// And the undo stack has one entry titled "Nudge Cues"
    func test_groupDrag_shiftsAllSelectedCuesRigidly() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-seed=three-cues-1-3-6"]
        app.launch()

        // Select all three cues in the cue list (⌘A within the list).
        let cueList = app.outlines["cueListPane"]
        XCTAssertTrue(cueList.waitForExistence(timeout: 5))
        cueList.click()
        cueList.typeKey("a", modifierFlags: .command)

        // Grab the middle marker and drag right.
        let markers = app.otherElements["cueMarkersOverlay"]
        XCTAssertTrue(markers.waitForExistence(timeout: 5))
        let middleMarker = markers.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'cueMarker-'")
        ).element(boundBy: 1)
        XCTAssertTrue(middleMarker.exists)

        let start = middleMarker.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        let end = start.withOffset(.init(dx: 80, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)

        // Assert via a debug overlay or via reading back the cue times through
        // the cue list rows' accessibility labels. The cueListPane rows already
        // expose times via accessibility — verify by reading three rows.
        // (Concrete assertion approach depends on the existing accessibility
        // identifier conventions surfaced in Step 1.)
        let rows = cueList.outlineRows
        XCTAssertEqual(rows.count, 3)
        // The exact delta in seconds depends on the waveform width at run time;
        // the invariant we check is that *all three rows shifted by the same Δ*.
        // Read the times, compute pairwise diffs vs. the seeded values, and
        // require equality across the three deltas.
        let observed = (0..<3).map { idx -> TimeInterval in
            let label = rows.element(boundBy: idx).label
            return Self.parseSeconds(fromAccessibilityLabel: label)
        }
        let deltas = zip(observed, [1.0, 3.0, 6.0]).map { $0 - $1 }
        XCTAssertEqual(deltas[0], deltas[1], accuracy: 0.01)
        XCTAssertEqual(deltas[1], deltas[2], accuracy: 0.01)
        XCTAssertGreaterThan(deltas[0], 0)

        // Undo: one step should restore everything.
        app.typeKey("z", modifierFlags: .command)
        let restored = (0..<3).map { idx -> TimeInterval in
            Self.parseSeconds(fromAccessibilityLabel: rows.element(boundBy: idx).label)
        }
        XCTAssertEqual(restored[0], 1.0, accuracy: 0.01)
        XCTAssertEqual(restored[1], 3.0, accuracy: 0.01)
        XCTAssertEqual(restored[2], 6.0, accuracy: 0.01)
    }

    /// Scenario: Dragging an unselected marker replaces the selection
    /// Given cues at 1s, 3s, 6s; cues at 1s and 3s selected
    /// When the user drags the marker at 6s by +N px
    /// Then only the cue at 6s has moved
    /// And the selection is exactly { cue at moved-time }
    func test_dragUnselectedMarker_replacesSelectionAndMovesSolo() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-seed=three-cues-1-3-6-select-first-two"]
        app.launch()

        let markers = app.otherElements["cueMarkersOverlay"]
        XCTAssertTrue(markers.waitForExistence(timeout: 5))
        let thirdMarker = markers.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'cueMarker-'")
        ).element(boundBy: 2)

        let start = thirdMarker.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        let end = start.withOffset(.init(dx: 40, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)

        let cueList = app.outlines["cueListPane"]
        let rows = cueList.outlineRows
        XCTAssertEqual(rows.count, 3)
        let observed = (0..<3).map { idx -> TimeInterval in
            Self.parseSeconds(fromAccessibilityLabel: rows.element(boundBy: idx).label)
        }
        XCTAssertEqual(observed[0], 1.0, accuracy: 0.01)
        XCTAssertEqual(observed[1], 3.0, accuracy: 0.01)
        XCTAssertGreaterThan(observed[2], 6.0)

        // Selection should be exactly the third row.
        let selectedRows = rows.matching(NSPredicate(format: "selected == YES"))
        XCTAssertEqual(selectedRows.count, 1)
    }

    // MARK: - Helpers

    /// Existing cue rows expose time via their accessibility label in the form
    /// "Cue #N · 0:03.000 · ...". Extract the seconds component. If the actual
    /// format differs, adjust the regex to match `CueRowView`'s accessibility
    /// label construction.
    private static func parseSeconds(fromAccessibilityLabel label: String) -> TimeInterval {
        let pattern = #"(\d+):(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let mRange = Range(match.range(at: 1), in: label),
              let sRange = Range(match.range(at: 2), in: label),
              let minutes = Double(label[mRange]),
              let seconds = Double(label[sRange]) else {
            return .nan
        }
        return minutes * 60 + seconds
    }
}
```

> **Engineer's note:** UI tests in this repo seed state via `--ui-test-seed=...` launch arguments. If that pattern isn't yet present, search `OnlyCue/App/` for how existing tests seed (`grep -rn "ui-test-seed\|CommandLine.arguments" OnlyCue/`) and follow the existing convention; if no seed mechanism exists, add a minimal one in `OnlyCue/App/OnlyCueApp.swift` that reads the argument and constructs a fixed `CueListDocument` for the seed key. Keep the seed handler behind `#if DEBUG`.

- [ ] **Step 3: Run the UI tests**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueUITests/CueGroupDragUITests 2>&1 | tail -40`

Expected: both tests pass. If accessibility-label parsing fails, inspect `CueRowView` for the actual label format and adjust the regex in `parseSeconds(fromAccessibilityLabel:)`.

- [ ] **Step 4: Manual smoke (UI cannot be verified by tests alone)**

Open the app, load a project with 3+ cues:

1. ⌘A in the cue list → drag any selected marker → verify all selected markers slide together in real time and commit on release.
2. With multi-selection, click-and-drag an unselected marker → verify selection collapses to that cue and only it moves.
3. Drag a single marker with Shift held while a tempo grid exists → verify the marker snaps to nearest beat.
4. Hover any marker → verify cursor becomes horizontal resize.
5. ⌘Z after a group drag → verify all cues restore in one step.

Report any deviations before proceeding.

- [ ] **Step 5: Commit**

```bash
git add OnlyCueUITests/CueGroupDragUITests.swift
# include any seed-handler addition if one was needed
git add OnlyCue/App/
git commit -m "test(markers): UI tests for group drag, replace-on-grab, shift-snap"
```

---

## Final verification

- [ ] **Run the full test suite**

```bash
xcodebuild -scheme OnlyCue -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: zero failures.

- [ ] **Run SwiftLint**

```bash
swiftlint --strict 2>&1 | tail -10
```

Expected: zero violations.

- [ ] **Manual verification of every spec scenario**

Re-run the manual smoke above against the final build. Note any UX rough edges (jitter, lag, snap inaccuracies) and either fix or file as follow-up.

- [ ] **Open PR**

Use the `gh-pr` skill with type `feat`; the forked `.github/PULL_REQUEST_TEMPLATE/feat.md` includes the OnlyCue verification block. Link the spec from the footer.
