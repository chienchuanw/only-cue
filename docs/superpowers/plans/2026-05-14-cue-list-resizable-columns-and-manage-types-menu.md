# Cue List Resizable Columns & "Manage Types" Menu Move — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the cue list's Time and Number columns user-resizable via header drag handles (widths persisted globally in `@AppStorage`), and move the "Manage Types…" command out of `CueInspectorView` into the top-level **Tools** menu.

**Architecture:** Introduce a `CueListColumnWidths` namespace that holds defaults, ranges, clamp helpers, and `@AppStorage` keys. `CueListPane` reads its two widths via `@AppStorage` and passes them down to `CueRowView` so header and rows stay aligned during drag. A new `ColumnResizeHandle` view exposes the drag affordance with `NSCursor.resizeLeftRight` and writes the clamped width back through a `Binding<CGFloat>`. For the menu move, a new `.manageTypesRequested` notification connects a Tools-menu button to a `TypeManagementSheet` presented by `DocumentView`; the inspector loses its button, divider, and `@State`.

**Tech Stack:** SwiftUI, AppKit (`NSCursor`), `@AppStorage`, XCTest.

**Spec:** `docs/superpowers/specs/2026-05-14-cue-list-resizable-columns-and-manage-types-menu-design.md`

---

## File Map

**Create:**
- `OnlyCue/UI/CueListColumnWidths.swift` — defaults, ranges, clamp helpers, storage keys
- `OnlyCue/UI/ColumnResizeHandle.swift` — drag-handle view with `NSCursor.resizeLeftRight`
- `OnlyCueTests/CueListColumnWidthsTests.swift` — unit tests for clamp helpers

**Modify:**
- `OnlyCue/UI/CueListPane.swift` — drop static widths, add `@AppStorage`, pass widths to rows, embed resize handles in header
- `OnlyCue/UI/CueRowView.swift` — accept `timeWidth` / `numberWidth` parameters instead of reading static constants
- `OnlyCue/UI/CueInspectorView.swift` — delete the `Manage Types…` button, the preceding `Divider`, the `showTypesSheet` state, the trailing `.sheet`
- `OnlyCue/UI/DocumentView.swift` — add `@State showManageTypes`, observer for `.manageTypesRequested`, `.sheet` presenting `TypeManagementSheet`, and add `manageTypesRequested` to the existing `Notification.Name` extension
- `OnlyCue/App/AppCommands.swift` — add `Button("Manage Types…")` + `Divider()` at the top of the Tools `CommandMenu`
- `OnlyCueTests/CueRowLayoutTests.swift` — update sanity test now that `timeColumnWidth` / `numberColumnWidth` no longer live on `CueListLayout`
- `project.yml` — no change expected (existing `OnlyCue/UI/**` source rule should pick up the new files); re-run `xcodegen generate` after Task 1 and Task 3

---

## Task 1: `CueListColumnWidths` helpers + tests

**Files:**
- Create: `OnlyCue/UI/CueListColumnWidths.swift`
- Create: `OnlyCueTests/CueListColumnWidthsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/CueListColumnWidthsTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class CueListColumnWidthsTests: XCTestCase {

    func test_clampTime_belowMin_returnsLowerBound() {
        XCTAssertEqual(CueListColumnWidths.clampTime(0), CueListColumnWidths.timeRange.lowerBound)
        XCTAssertEqual(CueListColumnWidths.clampTime(-50), CueListColumnWidths.timeRange.lowerBound)
    }

    func test_clampTime_aboveMax_returnsUpperBound() {
        XCTAssertEqual(CueListColumnWidths.clampTime(9999), CueListColumnWidths.timeRange.upperBound)
    }

    func test_clampTime_inRange_returnsValue() {
        XCTAssertEqual(CueListColumnWidths.clampTime(120), 120)
    }

    func test_clampNumber_belowMin_returnsLowerBound() {
        XCTAssertEqual(CueListColumnWidths.clampNumber(0), CueListColumnWidths.numberRange.lowerBound)
    }

    func test_clampNumber_aboveMax_returnsUpperBound() {
        XCTAssertEqual(CueListColumnWidths.clampNumber(9999), CueListColumnWidths.numberRange.upperBound)
    }

    func test_clampNumber_inRange_returnsValue() {
        XCTAssertEqual(CueListColumnWidths.clampNumber(80), 80)
    }

    func test_defaults_areInsideRanges() {
        XCTAssertTrue(CueListColumnWidths.timeRange.contains(CueListColumnWidths.timeDefault))
        XCTAssertTrue(CueListColumnWidths.numberRange.contains(CueListColumnWidths.numberDefault))
    }

    func test_storageKeys_areNonEmpty_andDistinct() {
        XCTAssertFalse(CueListColumnWidths.timeStorageKey.isEmpty)
        XCTAssertFalse(CueListColumnWidths.numberStorageKey.isEmpty)
        XCTAssertNotEqual(CueListColumnWidths.timeStorageKey, CueListColumnWidths.numberStorageKey)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -scheme OnlyCue -only-testing:OnlyCueTests/CueListColumnWidthsTests test`
Expected: FAIL — `Cannot find 'CueListColumnWidths' in scope`.

- [ ] **Step 3: Create the helper file**

Create `OnlyCue/UI/CueListColumnWidths.swift`:

```swift
import CoreGraphics

/// Shared widths for the cue list's Time and Number columns.
///
/// Persisted globally via `@AppStorage` (keys below) and read by both the
/// header row and `CueRowView` so they stay aligned during drag-resize.
/// Name column intentionally has no entry — it absorbs the remaining width.
enum CueListColumnWidths {

    static let timeRange: ClosedRange<CGFloat> = 64...180
    static let numberRange: ClosedRange<CGFloat> = 40...120

    static let timeDefault: CGFloat = 96
    static let numberDefault: CGFloat = 56

    static let timeStorageKey = "cueList.timeColumnWidth"
    static let numberStorageKey = "cueList.numberColumnWidth"

    static func clampTime(_ width: CGFloat) -> CGFloat {
        min(max(width, timeRange.lowerBound), timeRange.upperBound)
    }

    static func clampNumber(_ width: CGFloat) -> CGFloat {
        min(max(width, numberRange.lowerBound), numberRange.upperBound)
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project so the new files are included**

Run: `xcodegen generate`
Expected: prints success line; no errors.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -scheme OnlyCue -only-testing:OnlyCueTests/CueListColumnWidthsTests test`
Expected: PASS — 8 tests succeed.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/CueListColumnWidths.swift OnlyCueTests/CueListColumnWidthsTests.swift
git commit -m "feat(cue-list): add CueListColumnWidths helpers (defaults, ranges, clamp)"
```

---

## Task 2: Thread column widths through `CueRowView` and the header

**Files:**
- Modify: `OnlyCue/UI/CueRowView.swift`
- Modify: `OnlyCue/UI/CueListPane.swift`
- Modify: `OnlyCueTests/CueRowLayoutTests.swift`

Replace every read of `CueListLayout.timeColumnWidth` and `CueListLayout.numberColumnWidth` with values passed in via parameters / `@AppStorage`. No resize UI yet — this task only re-routes the data flow. Existing behavior (default widths) must be unchanged.

- [ ] **Step 1: Update `CueRowLayoutTests` to reflect the constants being removed**

Open `OnlyCueTests/CueRowLayoutTests.swift` and replace its body with:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

final class CueRowLayoutTests: XCTestCase {

    /// Pins the new initializer surface: `CueRowView` no longer takes an
    /// `index:` parameter (the position-index column was removed). If a
    /// future refactor reintroduces a leading index, this test catches it.
    /// Also pins the addition of explicit width parameters introduced when
    /// columns became user-resizable.
    func test_cueRowView_initializer_takesCueColorAndWidths() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 12.5,
            name: "Verse",
            time: 12.345,
            notes: "",
            fadeTime: .zero
        )
        let view = CueRowView(
            cue: cue,
            resolvedColorHex: "#FF8800",
            timeColumnWidth: CueListColumnWidths.timeDefault,
            numberColumnWidth: CueListColumnWidths.numberDefault
        )
        XCTAssertNotNil(view.body)
    }

    /// Sanity check on the shared layout constants that still live on
    /// `CueListLayout`: row tint stays subtle enough to keep text legible.
    /// Time/Number widths now live on `CueListColumnWidths`.
    func test_cueListLayout_constants_areSane() {
        XCTAssertGreaterThan(CueListLayout.rowHorizontalSpacing, 0)
        XCTAssertGreaterThan(CueListLayout.rowTintOpacity, 0)
        XCTAssertLessThan(CueListLayout.rowTintOpacity, 0.5)
        XCTAssertGreaterThan(CueListColumnWidths.timeDefault, 0)
        XCTAssertGreaterThan(CueListColumnWidths.numberDefault, 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails (compile error)**

Run: `xcodebuild -scheme OnlyCue -only-testing:OnlyCueTests/CueRowLayoutTests test`
Expected: FAIL — `Extra arguments at positions 'timeColumnWidth', 'numberColumnWidth'`.

- [ ] **Step 3: Drop the two width constants from `CueListLayout`**

In `OnlyCue/UI/CueListPane.swift`, replace the existing `enum CueListLayout` block at the top of the file (lines 3–8) with:

```swift
enum CueListLayout {
    static let rowHorizontalSpacing: CGFloat = 8
    static let rowTintOpacity: Double = 0.18
}
```

- [ ] **Step 4: Add width parameters to `CueRowView`**

In `OnlyCue/UI/CueRowView.swift`, replace the property block at the top of the struct (lines 5–8) with:

```swift
    let cue: Cue
    var resolvedColorHex: String?
    var timeColumnWidth: CGFloat = CueListColumnWidths.timeDefault
    var numberColumnWidth: CGFloat = CueListColumnWidths.numberDefault
    var onRename: (String) -> Void = { _ in }
    var onCommitNumber: (Double?) -> CueNumberValidator.Result = { _ in .ok }
```

Then in the same file, replace the three `.frame(width: CueListLayout.timeColumnWidth, …)` / `.frame(width: CueListLayout.numberColumnWidth, …)` / `.padding(.leading, CueListLayout.timeColumnWidth + …)` sites (lines 25, 29, 40) with the parameter-based versions:

```swift
                    .frame(width: timeColumnWidth, alignment: .leading)
```

```swift
                    .frame(width: numberColumnWidth, alignment: .leading)
```

```swift
                    .padding(.leading, timeColumnWidth + CueListLayout.rowHorizontalSpacing)
```

- [ ] **Step 5: Add `@AppStorage` in `CueListPane` and use it in the header + row construction**

In `OnlyCue/UI/CueListPane.swift`, just below the existing `@Environment(\.undoManager) private var undoManager` (line 23), add:

```swift
    @AppStorage(CueListColumnWidths.timeStorageKey)
    private var timeColumnWidthRaw: Double = Double(CueListColumnWidths.timeDefault)

    @AppStorage(CueListColumnWidths.numberStorageKey)
    private var numberColumnWidthRaw: Double = Double(CueListColumnWidths.numberDefault)

    private var timeColumnWidth: CGFloat {
        CueListColumnWidths.clampTime(CGFloat(timeColumnWidthRaw))
    }

    private var numberColumnWidth: CGFloat {
        CueListColumnWidths.clampNumber(CGFloat(numberColumnWidthRaw))
    }
```

Then replace the `headerRow` computed property body to use the dynamic widths:

```swift
    private var headerRow: some View {
        HStack(spacing: CueListLayout.rowHorizontalSpacing) {
            Text("Time")
                .frame(width: timeColumnWidth, alignment: .leading)
            Text("Cue #")
                .frame(width: numberColumnWidth, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
    }
```

And update the `CueRowView(...)` construction inside `scrollableList` (around line 161) to pass the widths:

```swift
                    CueRowView(
                        cue: cue,
                        resolvedColorHex: document.model.colorHex(for: cue),
                        timeColumnWidth: timeColumnWidth,
                        numberColumnWidth: numberColumnWidth,
                        onRename: { newName in
                            CueCommands.rename(cueId: cue.id, to: newName, document: document, undoManager: undoManager)
                        },
                        onCommitNumber: { newNumber in
                            CueCommands.setCueNumber(
                                cueId: cue.id,
                                to: newNumber,
                                document: document,
                                undoManager: undoManager
                            )
                        }
                    )
```

- [ ] **Step 6: Build the app to surface any other stragglers**

Run: `xcodebuild -scheme OnlyCue build`
Expected: succeeds. (If any other file references `CueListLayout.timeColumnWidth` / `.numberColumnWidth` the compiler will name them; switch those sites to `CueListColumnWidths.timeDefault` / `.numberDefault` only if they need a static fallback, otherwise route through the same parameter approach as `CueRowView`.)

- [ ] **Step 7: Run the row-layout test**

Run: `xcodebuild -scheme OnlyCue -only-testing:OnlyCueTests/CueRowLayoutTests test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/UI/CueListPane.swift OnlyCue/UI/CueRowView.swift OnlyCueTests/CueRowLayoutTests.swift
git commit -m "refactor(cue-list): thread column widths through CueRowView and header"
```

---

## Task 3: `ColumnResizeHandle` view + unit test

**Files:**
- Create: `OnlyCue/UI/ColumnResizeHandle.swift`
- Create: `OnlyCueTests/ColumnResizeHandleTests.swift`

The handle is a 6pt-wide invisible region that lives at a column's trailing edge. Hovering changes the cursor to `resizeLeftRight`; dragging writes the new clamped width through a `Binding<CGFloat>`. The drag is tracked relative to the width at drag-start so we don't accumulate errors across small mouse movements.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/ColumnResizeHandleTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

final class ColumnResizeHandleTests: XCTestCase {

    /// The handle must initialize with a binding + range and be constructible
    /// from the same primitives the header uses. If a future refactor changes
    /// the surface (e.g. requires a custom cursor or label) this catches it.
    func test_columnResizeHandle_initializer_takesBindingAndRange() {
        var width: CGFloat = 100
        let binding = Binding(get: { width }, set: { width = $0 })
        let handle = ColumnResizeHandle(width: binding, range: 64...180)
        XCTAssertNotNil(handle.body)
    }

    /// The static `apply(delta:start:range:)` helper drives the drag math —
    /// pure function, exhaustively tested so the SwiftUI gesture stays a thin
    /// shell over verified logic.
    func test_apply_clampsBelowMin() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: -500, start: 100, range: 64...180),
            64
        )
    }

    func test_apply_clampsAboveMax() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: 500, start: 100, range: 64...180),
            180
        )
    }

    func test_apply_addsDeltaWithinRange() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: 20, start: 100, range: 64...180),
            120
        )
    }

    func test_apply_negativeDeltaWithinRange() {
        XCTAssertEqual(
            ColumnResizeHandle.apply(delta: -10, start: 100, range: 64...180),
            90
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -scheme OnlyCue -only-testing:OnlyCueTests/ColumnResizeHandleTests test`
Expected: FAIL — `Cannot find 'ColumnResizeHandle' in scope`.

- [ ] **Step 3: Implement the handle**

Create `OnlyCue/UI/ColumnResizeHandle.swift`:

```swift
import AppKit
import SwiftUI

/// A 6pt-wide invisible drag region for resizing a column's trailing edge.
/// Cursor flips to `resizeLeftRight` on hover; dragging writes the clamped
/// width back through the supplied binding.
struct ColumnResizeHandle: View {

    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        let start = dragStartWidth ?? width
                        width = Self.apply(delta: value.translation.width, start: start, range: range)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .accessibilityHidden(true)
    }

    /// Pure drag math — applied per drag tick to compute the new width.
    static func apply(delta: CGFloat, start: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        let proposed = start + delta
        return min(max(proposed, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: prints success line.

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild -scheme OnlyCue -only-testing:OnlyCueTests/ColumnResizeHandleTests test`
Expected: PASS — 5 tests succeed.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/ColumnResizeHandle.swift OnlyCueTests/ColumnResizeHandleTests.swift
git commit -m "feat(cue-list): add ColumnResizeHandle drag view with clamp math"
```

---

## Task 4: Wire resize handles into the cue list header

**Files:**
- Modify: `OnlyCue/UI/CueListPane.swift`

The header gets two handles: one at the right edge of the Time cell, one at the right edge of the Number cell. The handles operate on bindings that read/write the `@AppStorage` values added in Task 2.

- [ ] **Step 1: Add binding helpers in `CueListPane`**

In `OnlyCue/UI/CueListPane.swift`, just below the two `private var ...Width: CGFloat { ... }` getters added in Task 2, add:

```swift
    private var timeColumnWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CueListColumnWidths.clampTime(CGFloat(timeColumnWidthRaw)) },
            set: { timeColumnWidthRaw = Double(CueListColumnWidths.clampTime($0)) }
        )
    }

    private var numberColumnWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CueListColumnWidths.clampNumber(CGFloat(numberColumnWidthRaw)) },
            set: { numberColumnWidthRaw = Double(CueListColumnWidths.clampNumber($0)) }
        )
    }
```

- [ ] **Step 2: Embed handles in `headerRow`**

Replace the `headerRow` computed property body added in Task 2 with this version, which composes each header cell with a trailing `ColumnResizeHandle`:

```swift
    private var headerRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Time")
                    .frame(width: timeColumnWidth, alignment: .leading)
                ColumnResizeHandle(
                    width: timeColumnWidthBinding,
                    range: CueListColumnWidths.timeRange
                )
                .accessibilityIdentifier("cueListTimeColumnResizeHandle")
            }
            .padding(.trailing, CueListLayout.rowHorizontalSpacing - 6)

            HStack(spacing: 0) {
                Text("Cue #")
                    .frame(width: numberColumnWidth, alignment: .leading)
                ColumnResizeHandle(
                    width: numberColumnWidthBinding,
                    range: CueListColumnWidths.numberRange
                )
                .accessibilityIdentifier("cueListNumberColumnResizeHandle")
            }
            .padding(.trailing, CueListLayout.rowHorizontalSpacing - 6)

            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
    }
```

Notes:
- The outer `HStack` uses `spacing: 0` because spacing is now absorbed by the per-cell trailing padding (`rowHorizontalSpacing - 6`), which accounts for the 6pt handle so total visible gap matches the row's `rowHorizontalSpacing`.
- The handle sits at the trailing edge of each cell, immediately adjacent to the text frame — this is what the user grabs.

- [ ] **Step 3: Build the app and launch it manually to verify the drag works**

Run: `xcodebuild -scheme OnlyCue build` (expected: succeeds).

Manually open `OnlyCue.xcodeproj`, run the app, open or create a project with at least one cue, and:
- Hover the right edge of the Time header → cursor flips to resize.
- Drag left/right → Time column shrinks/grows, rows track the header.
- Release, quit the app, relaunch → the new width persists.
- Repeat for the Number header.
- Drag far enough that you'd exceed bounds → width stops at min (64 / 40) and max (180 / 120).

Document the manual verification result in the commit message body.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/CueListPane.swift
git commit -m "feat(cue-list): drag-resizable Time and Number column headers"
```

---

## Task 5: Add `Manage Types…` to the Tools menu

**Files:**
- Modify: `OnlyCue/UI/DocumentView.swift` (notification declaration only)
- Modify: `OnlyCue/App/AppCommands.swift`

This task only adds the menu entry and the notification name. The sheet presentation arrives in Task 6; the inspector button is removed in Task 7. After Task 5 alone the menu item exists but does nothing visible — that's intentional so each task stays small and reviewable.

- [ ] **Step 1: Declare the new notification name**

In `OnlyCue/UI/DocumentView.swift`, find the existing `extension Notification.Name` block near the bottom (currently containing `importMediaRequested`, `exportCuesToCSVRequested`, …). Add one new line at the end of the extension:

```swift
    static let manageTypesRequested = Notification.Name("OnlyCue.manageTypesRequested")
```

- [ ] **Step 2: Add the Tools menu entry**

In `OnlyCue/App/AppCommands.swift`, find the `CommandMenu("Tools")` block (around line 141). Insert the new button + divider at the very top of the menu, immediately after `CommandMenu("Tools") {`:

```swift
        CommandMenu("Tools") {
            Button("Manage Types…") {
                NotificationCenter.default.post(name: .manageTypesRequested, object: nil)
            }
            .accessibilityIdentifier("manageTypesButton")

            Divider()

            Button("Edit Note Overlay Appearance…") {
```

Leave the rest of the Tools menu (Edit Note Overlay Appearance, OSC Monitor, Timecode Settings) unchanged.

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme OnlyCue build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/App/AppCommands.swift OnlyCue/UI/DocumentView.swift
git commit -m "feat(menu): add Manage Types... to Tools menu (notification wiring only)"
```

---

## Task 6: Present `TypeManagementSheet` from `DocumentView` on notification

**Files:**
- Modify: `OnlyCue/UI/DocumentView.swift`

- [ ] **Step 1: Add the state property**

In `OnlyCue/UI/DocumentView.swift`, in the `DocumentView` struct's property block near the top (after `@State private var showOverlayAppearance = false` on line 11), add:

```swift
    @State private var showManageTypes = false
```

- [ ] **Step 2: Observe the notification**

In the same file, find the `.onReceive(NotificationCenter.default.publisher(for: .editNotesOverlayAppearance))` modifier inside `body` (around line 56). Add a sibling modifier directly below it:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .manageTypesRequested)) { _ in
            showManageTypes = true
        }
```

- [ ] **Step 3: Present the sheet**

In the same file, find the `.sheet(isPresented: $showOverlayAppearance)` modifier (around line 59). Add a sibling sheet directly below it:

```swift
        .sheet(isPresented: $showManageTypes) {
            TypeManagementSheet(document: document)
        }
```

- [ ] **Step 4: Build and manually verify**

Run: `xcodebuild -scheme OnlyCue build`
Expected: succeeds.

Then open the app and: choose **Tools → Manage Types…** → the sheet opens. Close it. Open with no cue selected → sheet still opens (this is one of the fixes: previously the button only existed when the inspector form was visible).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/DocumentView.swift
git commit -m "feat(menu): present TypeManagementSheet on .manageTypesRequested"
```

---

## Task 7: Remove `Manage Types…` from `CueInspectorView`

**Files:**
- Modify: `OnlyCue/UI/CueInspectorView.swift`

The inspector becomes purely cue-field editing: type picker + number + name + fade + notes + tempo.

- [ ] **Step 1: Delete the state property**

In `OnlyCue/UI/CueInspectorView.swift`, delete this line (currently line 19):

```swift
    @State private var showTypesSheet = false
```

- [ ] **Step 2: Delete the divider, button, and trailing `.sheet`**

In the same file's `body`, the current shape is:

```swift
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let cue {
                    fields(for: cue)
                        .id(cue.id)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            Button("Manage Types…") { showTypesSheet = true }
                .accessibilityIdentifier("manageTypesButton")
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("cueInspector")
        .sheet(isPresented: $showTypesSheet) {
            TypeManagementSheet(document: document)
        }
    }
```

Replace it with:

```swift
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let cue {
                    fields(for: cue)
                        .id(cue.id)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("cueInspector")
    }
```

- [ ] **Step 3: Build and manually verify**

Run: `xcodebuild -scheme OnlyCue build`
Expected: succeeds — no remaining references to `showTypesSheet`.

Then run the full test suite to ensure no test relied on the inspector's `manageTypesButton`:

Run: `xcodebuild -scheme OnlyCue test`
Expected: all green. If a UI test fails because it tapped the old inspector button, update it to invoke the menu item instead — example pattern (open Tools menu, click Manage Types…). Pin the fix in the test, not in the production code.

Manually: run the app, select a cue → inspector shows fields only, no "Manage Types" button at the bottom and no divider above where it used to be. Tools → Manage Types… still works.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/CueInspectorView.swift
git commit -m "refactor(inspector): remove Manage Types... button (moved to Tools menu)"
```

If a UI test required updating, include it in the same commit and amend the message body to note the test change.

---

## Wrap-up

- [ ] **Step 1: Run the entire test suite from a clean state**

Run: `xcodebuild -scheme OnlyCue clean test`
Expected: all green.

- [ ] **Step 2: Verify the spec acceptance list manually**

Walk through the **Verification** section of the spec:

- [ ] Drag Time header divider → Time column resizes live; rows aligned; width persists across relaunch.
- [ ] Drag Number header divider → same.
- [ ] Widths clamp at min and max; no visual glitches at bounds.
- [ ] Tools → Manage Types… opens the sheet with no cue selected.
- [ ] Cue inspector no longer shows the Manage Types button or its divider.

- [ ] **Step 3: Final summary commit (only if needed)**

If `xcodegen generate` regenerated `project.yml`-derived files that aren't yet committed, stage and commit them now:

```bash
git status
# if project.yml changed, or untracked Xcode-derived files appeared that should not be ignored:
git add project.yml
git commit -m "chore: regenerate project for new UI files"
```

If `git status` is clean, skip this step.
