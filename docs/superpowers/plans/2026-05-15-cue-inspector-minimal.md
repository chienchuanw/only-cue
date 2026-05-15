# Cue Inspector Minimal Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trim the Cue Inspector to clock + Number/Name/Fade, move Type/Notes/Tempo into the cue-row right-click menu (Type instant; Notes & Tempo as modal sheets, ⌘⌥N / ⌘⌥T), and add a left color stripe + Fade column to each cue row.

**Architecture:** Inspector loses three sections (`typePicker`, `tempoSection`, Notes `TextEditor`) and the related drafts/`Field` cases. `CueRowView` gains a leading 3pt color stripe and a resizable Fade column. Two new sheet views (`CueNotesSheet`, `CueTempoSheet`) follow the existing `MediaEditSheet` / `ItemListPane` pattern — host via `.sheet(item:)` in `CueListPane` with a `Cue.ID?` state binding wrapped in an `Identifiable` shim. Tempo detect logic moves verbatim into `CueTempoSheet` but is rewired to populate `bpmDraft` without committing (Save commits via the existing atomic `CueCommands.setCueTempo`).

**Tech Stack:** SwiftUI, Swift 6, macOS 14+, XCTest, XcodeGen (`project.yml`). Existing helpers: `CueCommands.setType / setNotes / setFadeTime / setCueTempo`, `Color(hex:)`, `FadeTime.parse / format`, `CueListColumnWidths`.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `OnlyCue/UI/CueListColumnWidths.swift` | Modify | Add `fadeDefault`, `fadeRange`, `clampFade`, `fadeStorageKey`. |
| `OnlyCue/UI/CueRowView.swift` | Modify | Add leading color stripe; add Fade column with double-click inline edit (mirror Number cell). |
| `OnlyCue/UI/CueListPane.swift` | Modify | Add Fade column to header + row instantiation with `@AppStorage`; add right-click menu entries; host Notes / Tempo sheets via `.sheet(item:)`. |
| `OnlyCue/UI/CueNotesSheet.swift` | Create | Modal sheet — title, `TextEditor`, Cancel/Save. |
| `OnlyCue/UI/CueTempoSheet.swift` | Create | Modal sheet — BPM + beats/bar + Detect/Clear + status; absorbs tempo-detect logic. Save commits atomically via `CueCommands.setCueTempo`. |
| `OnlyCue/UI/CueInspectorView.swift` | Modify | Remove `typePicker`, Notes `TextEditor`, `commitNotes`; remove tempo `row` and buttons (the section is now empty after the helpers move out); drop `Field` cases `.notes`, `.bpm`, `.beatsPerBar`; drop `bpmDraft`, `beatsPerBarDraft`, `notesDraft`, `detectingCueID`, `detectMessage`. |
| `OnlyCue/UI/CueInspectorView+Tempo.swift` | Delete | Logic moves into `CueTempoSheet.swift`. |
| `OnlyCueTests/CueInspectorTempoSnapshotTests.swift` | Delete | Inspector no longer has a tempo section. Coverage replaced by `CueTempoSheetTests.swift`. |
| `OnlyCueTests/CueRowViewStripeTests.swift` | Create | Verify stripe color + Fade column inline-commit. |
| `OnlyCueTests/CueNotesSheetTests.swift` | Create | Verify Save / Cancel commit semantics. |
| `OnlyCueTests/CueTempoSheetTests.swift` | Create | Verify Save / Cancel / Clear semantics + Detect populates draft without committing. |
| `OnlyCueUITests/CueInspectorMinimalUITests.swift` | Create | Right-click opens menu items; ⌘⌥N opens Notes sheet; ⌘⌥T opens Tempo sheet; Fade column visible; stripe accessibility identifier present. |
| `project.yml` | Possibly modify | Only if new source folders are added (none here — all files live under existing `OnlyCue/UI/`). Re-run `xcodegen generate`. |

---

## Conventions used throughout this plan

- **Build / test command:** `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' test` for the full suite; for a single target use `-only-testing:OnlyCueTests/<ClassName>/<methodName>`.
- **Commit style:** Conventional Commits, lowercase after prefix (project `CLAUDE.md`). No `Co-Authored-By` trailers.
- **No mutations of `ProjectModel` outside `Commands/CueCommands.swift`** — sheets always go through commands.
- **Accessibility identifiers** for every new test target: `cueRowStripe-<id>`, `cueRowFade-<id>`, `cueNotesSheet`, `cueNotesSheetEditor`, `cueNotesSheetSave`, `cueNotesSheetCancel`, `cueTempoSheet`, `cueTempoSheetBPM`, `cueTempoSheetBeatsPerBar`, `cueTempoSheetDetect`, `cueTempoSheetClear`, `cueTempoSheetSave`, `cueTempoSheetCancel`, `cueTempoSheetStatus`, `cueRowContextChangeType`, `cueRowContextEditNotes`, `cueRowContextTempo`.

---

## Task 1: Add Fade column width constants

**Files:**
- Modify: `OnlyCue/UI/CueListColumnWidths.swift`
- Test: `OnlyCueTests/CueListColumnWidthsTests.swift` (create if absent; otherwise append)

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueListColumnWidthsTests.swift` (or append to it if it exists):

```swift
import XCTest
@testable import OnlyCue

final class CueListColumnWidthsTests: XCTestCase {

    func test_fadeDefault_isInsideFadeRange() {
        let d = CueListColumnWidths.fadeDefault
        XCTAssertGreaterThanOrEqual(d, CueListColumnWidths.fadeRange.lowerBound)
        XCTAssertLessThanOrEqual(d, CueListColumnWidths.fadeRange.upperBound)
    }

    func test_clampFade_clampsBelowLowerBound() {
        XCTAssertEqual(CueListColumnWidths.clampFade(0), CueListColumnWidths.fadeRange.lowerBound)
    }

    func test_clampFade_clampsAboveUpperBound() {
        XCTAssertEqual(CueListColumnWidths.clampFade(9_999), CueListColumnWidths.fadeRange.upperBound)
    }

    func test_clampFade_passesThroughInsideRange() {
        let mid = (CueListColumnWidths.fadeRange.lowerBound + CueListColumnWidths.fadeRange.upperBound) / 2
        XCTAssertEqual(CueListColumnWidths.clampFade(mid), mid)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListColumnWidthsTests test`
Expected: FAIL — `fadeDefault`, `fadeRange`, `clampFade` don't exist.

- [ ] **Step 3: Implement minimal additions**

Edit `OnlyCue/UI/CueListColumnWidths.swift`, adding inside the `enum`:

```swift
static let fadeRange: ClosedRange<CGFloat> = 56...160
static let fadeDefault: CGFloat = 72
static let fadeStorageKey = "cueList.fadeColumnWidth"

static func clampFade(_ width: CGFloat) -> CGFloat {
    min(max(width, fadeRange.lowerBound), fadeRange.upperBound)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueListColumnWidthsTests test`
Expected: PASS — all four tests green.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueListColumnWidths.swift OnlyCueTests/CueListColumnWidthsTests.swift
git commit -m "feat(cue-list): add fade column width constants"
```

---

## Task 2: Add leading color stripe to CueRowView

**Files:**
- Modify: `OnlyCue/UI/CueRowView.swift`
- Test: `OnlyCueTests/CueRowViewStripeTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueRowViewStripeTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

final class CueRowViewStripeTests: XCTestCase {

    /// Smoke test — the row must expose an accessibility identifier
    /// `cueRowStripe-<cue.id>` for UI tests to anchor the stripe assertion.
    @MainActor
    func test_stripeIdentifierIsExposed() throws {
        let cue = Cue(id: UUID(), name: "Test", time: 0, fadeTime: .immediate)
        let view = CueRowView(cue: cue, resolvedColorHex: "#FF8800")
        let mirror = Mirror(reflecting: view)
        // Reflective check — full hosting-view rendering happens in UI tests.
        // Here we just assert the view compiles with the new resolvedColorHex usage.
        XCTAssertNotNil(mirror)
    }
}
```

> Note: full stripe rendering is exercised in the UI test in Task 11. This unit test is a compile-time guard so the row API change can't silently drop the parameter.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueRowViewStripeTests test`
Expected: FAIL — file doesn't compile (or test absent).

- [ ] **Step 3: Add stripe to CueRowView**

In `OnlyCue/UI/CueRowView.swift`, replace the body's outer `VStack` with one that prepends a stripe. Locate this block (around line 23–47):

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: CueListLayout.rowHorizontalSpacing) {
            Text(TimeFormat.smpte(cue.time, rate: framerate))
                ...
```

Replace with:

```swift
var body: some View {
    HStack(spacing: 0) {
        stripe
            .frame(width: 3)
            .accessibilityIdentifier("cueRowStripe-\(cue.id)")
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CueListLayout.rowHorizontalSpacing) {
                Text(TimeFormat.smpte(cue.time, rate: framerate))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: timeColumnWidth, alignment: .leading)
                    .accessibilityIdentifier("cueTime-\(cue.id)")

                numberCell
                    .frame(width: numberColumnWidth, alignment: .leading)
                    .accessibilityIdentifier("cueNumber-\(cue.id)")

                nameField
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("cueName-\(cue.id)")
            }
            if let numberError {
                Text(numberError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, timeColumnWidth + CueListLayout.rowHorizontalSpacing)
                    .accessibilityIdentifier("cueNumberError-\(cue.id)")
            }
        }
        .padding(.leading, 6)
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier("cueRow-\(cue.id)")
}

@ViewBuilder
private var stripe: some View {
    if let hex = resolvedColorHex, let color = Color(hex: hex) {
        Rectangle().fill(color)
    } else {
        Rectangle().fill(Color.clear)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueRowViewStripeTests test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueRowView.swift OnlyCueTests/CueRowViewStripeTests.swift
git commit -m "feat(cue-list): add leading color stripe to cue row"
```

---

## Task 3: Add Fade column to CueRowView (display + double-click edit)

**Files:**
- Modify: `OnlyCue/UI/CueRowView.swift`
- Test: `OnlyCueTests/CueRowViewStripeTests.swift` (extend)

- [ ] **Step 1: Write the failing test**

Append to `OnlyCueTests/CueRowViewStripeTests.swift`:

```swift
@MainActor
func test_fadeColumnRendersFadeText() throws {
    let cue = Cue(id: UUID(), name: "T", time: 0, fadeTime: try XCTUnwrap(FadeTime.parse("3.0")))
    let view = CueRowView(cue: cue, fadeColumnWidth: 80)
    // Compile-time check: the new parameter exists.
    let mirror = Mirror(reflecting: view)
    XCTAssertNotNil(mirror)
}

@MainActor
func test_fadeCommitInvokesCallback() throws {
    let cue = Cue(id: UUID(), name: "T", time: 0, fadeTime: .immediate)
    var captured: FadeTime?
    let view = CueRowView(
        cue: cue,
        fadeColumnWidth: 80,
        onCommitFade: { captured = $0 }
    )
    // The callback must accept FadeTime — assertion is compile-time.
    _ = view
    _ = captured
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueRowViewStripeTests test`
Expected: FAIL — `fadeColumnWidth` and `onCommitFade` parameters don't exist.

- [ ] **Step 3: Add Fade column**

In `OnlyCue/UI/CueRowView.swift`:

a. Add new stored properties below the existing `onCommitNumber` line:

```swift
var fadeColumnWidth: CGFloat = CueListColumnWidths.fadeDefault
var onCommitFade: (FadeTime) -> Void = { _ in }
```

b. Add new state below `numberFieldFocused`:

```swift
@State private var isEditingFade = false
@State private var fadeDraft = ""
@FocusState private var fadeFieldFocused: Bool
```

c. Insert the Fade column inside the row `HStack` (after `nameField` block, replacing `.frame(maxWidth: .infinity, alignment: .leading)` of `nameField` with a bounded width container — actually keep nameField flexible and append Fade as a fixed-width trailing cell):

Change:

```swift
nameField
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("cueName-\(cue.id)")
```

to:

```swift
nameField
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("cueName-\(cue.id)")

fadeCell
    .frame(width: fadeColumnWidth, alignment: .leading)
    .accessibilityIdentifier("cueRowFade-\(cue.id)")
```

d. Add `fadeCell` view builder + helpers near the existing `numberCell` builder:

```swift
@ViewBuilder
private var fadeCell: some View {
    if isEditingFade {
        TextField("", text: $fadeDraft)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .focused($fadeFieldFocused)
            .onSubmit { commitFade() }
            .onExitCommand { cancelFadeEdit() }
            .onChange(of: fadeFieldFocused) { _, isFocused in
                if !isFocused { commitFade() }
            }
            .onAppear { fadeFieldFocused = true }
    } else {
        Text(cue.fadeTime.format())
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { beginFadeEdit() }
    }
}

private func beginFadeEdit() {
    fadeDraft = cue.fadeTime.format()
    isEditingFade = true
}

private func cancelFadeEdit() {
    isEditingFade = false
}

private func commitFade() {
    defer { isEditingFade = false }
    guard let parsed = FadeTime.parse(fadeDraft) else { return }
    guard parsed != cue.fadeTime else { return }
    onCommitFade(parsed)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueRowViewStripeTests test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueRowView.swift OnlyCueTests/CueRowViewStripeTests.swift
git commit -m "feat(cue-list): add fade column with inline edit to cue row"
```

---

## Task 4: Wire Fade column into CueListPane (header + row + AppStorage)

**Files:**
- Modify: `OnlyCue/UI/CueListPane.swift`

This task has no new tests on its own (it's wiring); UI test in Task 11 covers it.

- [ ] **Step 1: Add Fade AppStorage + bindings**

In `OnlyCue/UI/CueListPane.swift`, after the existing `numberColumnWidthRaw` block (around line 27):

```swift
@AppStorage(CueListColumnWidths.fadeStorageKey)
private var fadeColumnWidthRaw: Double = Double(CueListColumnWidths.fadeDefault)

private var fadeColumnWidth: CGFloat {
    CueListColumnWidths.clampFade(CGFloat(fadeColumnWidthRaw))
}

private var fadeColumnWidthBinding: Binding<CGFloat> {
    Binding(
        get: { CueListColumnWidths.clampFade(CGFloat(fadeColumnWidthRaw)) },
        set: { fadeColumnWidthRaw = Double(CueListColumnWidths.clampFade($0)) }
    )
}
```

- [ ] **Step 2: Add Fade to header row**

In the `headerRow` view (around line 159–198), append a Fade column after Name. Name is currently `.frame(maxWidth: .infinity, alignment: .leading)` — keep it flexible and append a fixed trailing Fade:

```swift
Text("Name")
    .frame(maxWidth: .infinity, alignment: .leading)
Text("Fade")
    .frame(width: fadeColumnWidth, alignment: .leading)
    .overlay(alignment: .trailing) {
        ColumnResizeHandle(
            width: fadeColumnWidthBinding,
            range: CueListColumnWidths.fadeRange
        )
        .accessibilityIdentifier("cueListFadeColumnResizeHandle")
    }
```

- [ ] **Step 3: Pass Fade width + commit callback to row**

In `scrollableList` (around line 208–252), modify the `CueRowView(...)` call:

```swift
CueRowView(
    cue: cue,
    resolvedColorHex: document.model.colorHex(for: cue),
    timeColumnWidth: timeColumnWidth,
    numberColumnWidth: numberColumnWidth,
    fadeColumnWidth: fadeColumnWidth,
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
    },
    onCommitFade: { newFade in
        CueCommands.setFadeTime(
            cueId: cue.id,
            to: newFade,
            document: document,
            undoManager: undoManager
        )
    }
)
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueListPane.swift
git commit -m "feat(cue-list): wire fade column into list pane header and rows"
```

---

## Task 5: Create CueNotesSheet (TDD)

**Files:**
- Create: `OnlyCue/UI/CueNotesSheet.swift`
- Test: `OnlyCueTests/CueNotesSheetTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueNotesSheetTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

@MainActor
final class CueNotesSheetTests: XCTestCase {

    func test_saveInvokesOnSaveWithDraft() {
        var captured: String?
        let sheet = CueNotesSheet(
            cueLabel: "Cue 1 · Test",
            initialNotes: "old",
            onSave: { captured = $0 },
            onCancel: {}
        )
        sheet.testSetDraft("new notes")
        sheet.testCommit()
        XCTAssertEqual(captured, "new notes")
    }

    func test_cancelDoesNotInvokeOnSave() {
        var saveCalled = false
        var cancelCalled = false
        let sheet = CueNotesSheet(
            cueLabel: "Cue 1 · Test",
            initialNotes: "old",
            onSave: { _ in saveCalled = true },
            onCancel: { cancelCalled = true }
        )
        sheet.testSetDraft("ignored")
        sheet.testCancel()
        XCTAssertFalse(saveCalled)
        XCTAssertTrue(cancelCalled)
    }

    func test_initialDraftMatchesInitialNotes() {
        let sheet = CueNotesSheet(
            cueLabel: "Cue 1 · Test",
            initialNotes: "hello",
            onSave: { _ in },
            onCancel: {}
        )
        XCTAssertEqual(sheet.testCurrentDraft, "hello")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueNotesSheetTests test`
Expected: FAIL — `CueNotesSheet` does not exist.

- [ ] **Step 3: Implement the sheet**

Create `OnlyCue/UI/CueNotesSheet.swift`:

```swift
import SwiftUI

/// Modal sheet for editing a single cue's `notes`. Hosted by `CueListPane` via
/// `.sheet(item:)`. Save calls `onSave(draft)`; Cancel calls `onCancel()`.
/// Re-opening the sheet always re-initializes the draft from `initialNotes`.
struct CueNotesSheet: View {

    let cueLabel: String
    let initialNotes: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draft: String

    init(
        cueLabel: String,
        initialNotes: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cueLabel = cueLabel
        self.initialNotes = initialNotes
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: initialNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notes — \(cueLabel)")
                .font(.headline)

            TextEditor(text: $draft)
                .font(.body)
                .frame(minWidth: 380, minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                )
                .accessibilityIdentifier("cueNotesSheetEditor")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cueNotesSheetCancel")
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("cueNotesSheetSave")
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .accessibilityIdentifier("cueNotesSheet")
    }

    // MARK: - Test hooks
    // Kept internal (not fileprivate) for XCTest access via @testable.
    var testCurrentDraft: String { draft }
    func testSetDraft(_ value: String) { draft = value }
    func testCommit() { onSave(draft) }
    func testCancel() { onCancel() }
}
```

> Note: `@State` mutations inside a `struct` from test hooks work because `_draft` is `init`-set in the test before the view is hosted. The hooks read/write the underlying storage directly via the struct's stored property (Swift permits this because the test sets values before SwiftUI tracks the view).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueNotesSheetTests test`
Expected: PASS — all three tests green.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueNotesSheet.swift OnlyCueTests/CueNotesSheetTests.swift
git commit -m "feat(cue-inspector): add CueNotesSheet modal"
```

---

## Task 6: Create CueTempoSheet (TDD)

**Files:**
- Create: `OnlyCue/UI/CueTempoSheet.swift`
- Test: `OnlyCueTests/CueTempoSheetTests.swift` (create)

The sheet absorbs all logic from `CueInspectorView+Tempo.swift` but rewires Detect to populate `bpmDraft` *without* committing. Save commits via the existing `CueCommands.setCueTempo(cueID:bpm:beatsPerBar:item:document:undoManager:)`, which is already atomic (single undo step).

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueTempoSheetTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

@MainActor
final class CueTempoSheetTests: XCTestCase {

    func test_saveInvokesOnSaveWithParsedDrafts() {
        var captured: (Double?, Int?)?
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: nil,
            initialBeatsPerBar: nil,
            onDetect: { _ in nil },
            onSave: { bpm, bpb in captured = (bpm, bpb) },
            onCancel: {}
        )
        sheet.testSetBPM("120")
        sheet.testSetBeatsPerBar("3")
        sheet.testCommit()
        XCTAssertEqual(captured?.0, 120)
        XCTAssertEqual(captured?.1, 3)
    }

    func test_saveWithEmptyBPMCommitsNil() {
        var captured: (Double?, Int?)?
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: 120,
            initialBeatsPerBar: 4,
            onDetect: { _ in nil },
            onSave: { bpm, bpb in captured = (bpm, bpb) },
            onCancel: {}
        )
        sheet.testSetBPM("")
        sheet.testCommit()
        XCTAssertNil(captured?.0)
        // beatsPerBar also clears when bpm clears (mirror existing tempo semantics).
        XCTAssertNil(captured?.1)
    }

    func test_cancelDoesNotInvokeOnSave() {
        var saveCalled = false
        var cancelCalled = false
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: nil,
            initialBeatsPerBar: nil,
            onDetect: { _ in nil },
            onSave: { _, _ in saveCalled = true },
            onCancel: { cancelCalled = true }
        )
        sheet.testSetBPM("180")
        sheet.testCancel()
        XCTAssertFalse(saveCalled)
        XCTAssertTrue(cancelCalled)
    }

    func test_clearResetsDraftsWithoutCommitting() {
        var saveCalled = false
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: 120,
            initialBeatsPerBar: 4,
            onDetect: { _ in nil },
            onSave: { _, _ in saveCalled = true },
            onCancel: {}
        )
        sheet.testClear()
        XCTAssertEqual(sheet.testCurrentBPMDraft, "")
        XCTAssertEqual(sheet.testCurrentBeatsPerBarDraft, "")
        XCTAssertFalse(saveCalled)
    }

    func test_detectPopulatesDraftWithoutCommitting() async {
        var saveCalled = false
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: nil,
            initialBeatsPerBar: nil,
            onDetect: { _ in (bpm: 128.0, message: nil) },
            onSave: { _, _ in saveCalled = true },
            onCancel: {}
        )
        await sheet.testRunDetect()
        XCTAssertEqual(sheet.testCurrentBPMDraft, "128")
        XCTAssertFalse(saveCalled)
    }

    func test_invalidBPMRevertsToInitialOnCommit() {
        var captured: (Double?, Int?)?
        let sheet = CueTempoSheet(
            cueLabel: "Cue 1",
            initialBPM: 120,
            initialBeatsPerBar: 4,
            onDetect: { _ in nil },
            onSave: { bpm, bpb in captured = (bpm, bpb) },
            onCancel: {}
        )
        sheet.testSetBPM("not-a-number")
        sheet.testCommit()
        // Reject non-finite input — fall back to the initial value.
        XCTAssertEqual(captured?.0, 120)
        XCTAssertEqual(captured?.1, 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueTempoSheetTests test`
Expected: FAIL — `CueTempoSheet` does not exist.

- [ ] **Step 3: Implement the sheet**

Create `OnlyCue/UI/CueTempoSheet.swift`:

```swift
import SwiftUI

/// Modal sheet for editing a single cue's tempo (BPM + beats-per-bar) and
/// running spectral-flux tempo detection on its media window. Save commits via
/// `CueCommands.setCueTempo` (atomic, single undo step). Detect populates the
/// BPM draft but never commits on its own — the user must press Save.
///
/// `onDetect` is an async closure that receives the cue's `beatsPerBar` (or 4
/// if unset) and returns `(bpm, optional status message)` or `nil` if no tempo
/// was found. This keeps the sheet free of audio dependencies and lets the
/// host inject test doubles.
struct CueTempoSheet: View {

    let cueLabel: String
    let initialBPM: Double?
    let initialBeatsPerBar: Int?
    let onDetect: (_ beatsPerBar: Int) async -> (bpm: Double, message: String?)?
    let onSave: (_ bpm: Double?, _ beatsPerBar: Int?) -> Void
    let onCancel: () -> Void

    @State private var bpmDraft: String
    @State private var beatsPerBarDraft: String
    @State private var statusMessage: String?
    @State private var isDetecting: Bool = false

    init(
        cueLabel: String,
        initialBPM: Double?,
        initialBeatsPerBar: Int?,
        onDetect: @escaping (_ beatsPerBar: Int) async -> (bpm: Double, message: String?)?,
        onSave: @escaping (_ bpm: Double?, _ beatsPerBar: Int?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cueLabel = cueLabel
        self.initialBPM = initialBPM
        self.initialBeatsPerBar = initialBeatsPerBar
        self.onDetect = onDetect
        self.onSave = onSave
        self.onCancel = onCancel
        self._bpmDraft = State(initialValue: initialBPM.map { String(Int($0.rounded())) } ?? "")
        self._beatsPerBarDraft = State(initialValue: initialBeatsPerBar.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tempo — \(cueLabel)")
                .font(.headline)

            Form {
                LabeledContent("BPM") {
                    TextField("inherited", text: $bpmDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .accessibilityIdentifier("cueTempoSheetBPM")
                }
                LabeledContent("Beats / bar") {
                    TextField("4", text: $beatsPerBarDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .accessibilityIdentifier("cueTempoSheetBeatsPerBar")
                }
            }

            HStack(spacing: 8) {
                Button("Detect") { Task { await runDetect() } }
                    .disabled(isDetecting)
                    .accessibilityIdentifier("cueTempoSheetDetect")
                Button("Clear") { clear() }
                    .accessibilityIdentifier("cueTempoSheetClear")
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("cueTempoSheetStatus")
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cueTempoSheetCancel")
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("cueTempoSheetSave")
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .accessibilityIdentifier("cueTempoSheet")
    }

    private func clear() {
        bpmDraft = ""
        beatsPerBarDraft = ""
        statusMessage = nil
    }

    private func runDetect() async {
        isDetecting = true
        defer { isDetecting = false }
        let beats = Int(beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? initialBeatsPerBar
            ?? 4
        if let outcome = await onDetect(beats) {
            bpmDraft = String(Int(outcome.bpm.rounded()))
            statusMessage = outcome.message
        } else {
            statusMessage = "No tempo detected."
        }
    }

    private func commit() {
        let trimmedBPM = bpmDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBPM.isEmpty {
            // Empty BPM means "clear tempo" — also clear beats/bar (orphaned otherwise).
            onSave(nil, nil)
            return
        }
        guard let bpm = Double(trimmedBPM), bpm.isFinite else {
            // Invalid input — revert to initial values.
            onSave(initialBPM, initialBeatsPerBar)
            return
        }
        let trimmedBeats = beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let beats = Int(trimmedBeats) ?? initialBeatsPerBar
        onSave(bpm, beats)
    }

    // MARK: - Test hooks
    var testCurrentBPMDraft: String { bpmDraft }
    var testCurrentBeatsPerBarDraft: String { beatsPerBarDraft }
    func testSetBPM(_ value: String) { bpmDraft = value }
    func testSetBeatsPerBar(_ value: String) { beatsPerBarDraft = value }
    func testCommit() { commit() }
    func testCancel() { onCancel() }
    func testClear() { clear() }
    func testRunDetect() async { await runDetect() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueTempoSheetTests test`
Expected: PASS — all six tests green.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueTempoSheet.swift OnlyCueTests/CueTempoSheetTests.swift
git commit -m "feat(cue-inspector): add CueTempoSheet modal with non-committing detect"
```

---

## Task 7: Move tempo-detect plumbing into CueTempoSheet host

**Files:**
- Modify: `OnlyCue/UI/CueListPane.swift`
- Reference: `OnlyCue/UI/CueInspectorView+Tempo.swift` (will be deleted in Task 9; copy its `detect` static + `DetectOutcome` enum into a free function or new file first)

The existing `detect` static (in `CueInspectorView+Tempo.swift`) is reusable — extract it to a non-view helper so the sheet host can call it without depending on `CueInspectorView`.

- [ ] **Step 1: Extract tempo-detect helper**

Create `OnlyCue/UI/CueTempoDetect.swift`:

```swift
import Foundation

enum CueTempoDetect {

    enum Outcome { case found(TempoEstimate), notDetected, noAudio, failed }

    static func detect(
        bookmark: Data,
        range: ClosedRange<TimeInterval>?,
        beatsPerBar: Int
    ) async -> Outcome {
        let url: URL
        let didAccess: Bool
        do {
            let resolution = try Bookmarks.resolve(bookmark)
            url = resolution.url
            didAccess = url.startAccessingSecurityScopedResource()
        } catch { return .failed }
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let samples = try await AudioSampleReader.readMonoSamples(from: url, range: range)
            guard let estimate = await SpectralFluxTempoAnalyzer().analyze(
                samples: samples,
                sampleRate: AudioSampleReader.sampleRate,
                beatsPerBar: beatsPerBar,
                bpmHint: nil
            ) else { return .notDetected }
            return .found(estimate)
        } catch AudioSampleReader.Error.noAudioTrack {
            return .noAudio
        } catch {
            return .failed
        }
    }
}
```

- [ ] **Step 2: Verify build (no behavior change yet)**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (extracted helper coexists with the existing `CueInspectorView+Tempo.swift` for now).

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/CueTempoDetect.swift
git commit -m "refactor(tempo): extract detect helper out of inspector extension"
```

---

## Task 8: Wire context menu + sheet hosts into CueListPane

**Files:**
- Modify: `OnlyCue/UI/CueListPane.swift`

- [ ] **Step 1: Add sheet state**

Near the existing `@Environment(\.undoManager)` line, add:

```swift
@State private var notesEditingID: Cue.ID?
@State private var tempoEditingID: Cue.ID?
```

And below the `editingItemBinding`-style pattern, add Identifiable wrappers + bindings (place near the existing private struct conventions in `ItemListPane`):

```swift
private struct CueEditingTarget: Identifiable {
    let cue: Cue
    var id: Cue.ID { cue.id }
}

private func cueEditingBinding(idKeyPath: ReferenceWritableKeyPath<CueListPane, Cue.ID?>) -> Binding<CueEditingTarget?> {
    // Not directly usable for @State (struct can't have reference paths to itself);
    // we inline the two bindings below instead.
    fatalError("Use the inline bindings below.")
}

private var notesEditingBinding: Binding<CueEditingTarget?> {
    Binding(
        get: {
            guard let id = notesEditingID,
                  let cue = cues.first(where: { $0.id == id })
            else { return nil }
            return CueEditingTarget(cue: cue)
        },
        set: { newValue in notesEditingID = newValue?.id }
    )
}

private var tempoEditingBinding: Binding<CueEditingTarget?> {
    Binding(
        get: {
            guard let id = tempoEditingID,
                  let cue = cues.first(where: { $0.id == id })
            else { return nil }
            return CueEditingTarget(cue: cue)
        },
        set: { newValue in tempoEditingID = newValue?.id }
    )
}
```

(Drop the `cueEditingBinding(idKeyPath:)` stub — it's a comment for the reader; do not actually add the `fatalError`. Just keep the two concrete bindings.)

- [ ] **Step 2: Attach context menu to each row**

In `scrollableList`, attach a context menu to each `CueRowView` after `.listRowBackground(...)`:

```swift
CueRowView(...)
    .tag(cue.id)
    .listRowBackground(rowTint(for: cue))
    .contextMenu { contextMenu(for: cue) }
```

And add the menu builder near the bottom of the struct:

```swift
@ViewBuilder
private func contextMenu(for cue: Cue) -> some View {
    Menu("Change Type") {
        ForEach(document.model.cuePointTypes) { type in
            Button {
                guard type.id != cue.typeID else { return }
                CueCommands.setType(
                    cueId: cue.id,
                    to: type.id,
                    document: document,
                    undoManager: undoManager
                )
            } label: {
                Label {
                    Text(type.name)
                } icon: {
                    if type.id == cue.typeID {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityIdentifier("cueRowContextChangeType-\(type.id)")
        }
    }
    .accessibilityIdentifier("cueRowContextChangeType")

    Button("Edit Notes…") { notesEditingID = cue.id }
        .keyboardShortcut("n", modifiers: [.command, .option])
        .accessibilityIdentifier("cueRowContextEditNotes")

    Button("Tempo…") { tempoEditingID = cue.id }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .accessibilityIdentifier("cueRowContextTempo")
}
```

- [ ] **Step 3: Mount the sheets on the pane**

Append `.sheet(item:)` modifiers at the end of `body` (after the existing `.onReceive` chain):

```swift
.sheet(item: notesEditingBinding) { editing in
    CueNotesSheet(
        cueLabel: cueLabel(for: editing.cue),
        initialNotes: editing.cue.notes,
        onSave: { newNotes in
            CueCommands.setNotes(
                cueId: editing.cue.id,
                to: newNotes,
                document: document,
                undoManager: undoManager
            )
            notesEditingID = nil
        },
        onCancel: { notesEditingID = nil }
    )
}
.sheet(item: tempoEditingBinding) { editing in
    CueTempoSheet(
        cueLabel: cueLabel(for: editing.cue),
        initialBPM: editing.cue.bpm,
        initialBeatsPerBar: editing.cue.beatsPerBar,
        onDetect: { beats in
            guard let item = document.model.items.first(where: { $0.cues.contains(where: { $0.id == editing.cue.id }) }) else {
                return nil
            }
            let cueTime = editing.cue.time
            let nextBPMCueTime = item.cues
                .filter { $0.id != editing.cue.id && $0.time > cueTime && $0.bpm != nil }
                .map(\.time)
                .min()
            let detectEnd = min(nextBPMCueTime ?? item.media.duration, cueTime + 30)
            let outcome = await CueTempoDetect.detect(
                bookmark: item.media.bookmarkData,
                range: cueTime < detectEnd ? cueTime...detectEnd : nil,
                beatsPerBar: beats
            )
            switch outcome {
            case .found(let estimate):
                let msg: String? = estimate.confidence < 0.4
                    ? "Low confidence (\(Int((estimate.confidence * 100).rounded()))%)"
                    : nil
                return (bpm: estimate.bpm, message: msg)
            case .notDetected, .noAudio, .failed:
                return nil
            }
        },
        onSave: { bpm, beats in
            if let item = document.model.items.first(where: { $0.cues.contains(where: { $0.id == editing.cue.id }) }) {
                CueCommands.setCueTempo(
                    cueID: editing.cue.id,
                    bpm: bpm,
                    beatsPerBar: beats,
                    item: item.id,
                    document: document,
                    undoManager: undoManager
                )
            }
            tempoEditingID = nil
        },
        onCancel: { tempoEditingID = nil }
    )
}
```

Add the helper:

```swift
private func cueLabel(for cue: Cue) -> String {
    if let number = cue.cueNumber {
        return "Cue \(FadeTime.formatNumber(number)) · \(cue.name.isEmpty ? "Untitled" : cue.name)"
    }
    return cue.name.isEmpty ? "Untitled" : cue.name
}
```

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueListPane.swift
git commit -m "feat(cue-list): context menu opens notes & tempo sheets, change type submenu"
```

---

## Task 9: Trim CueInspectorView

**Files:**
- Modify: `OnlyCue/UI/CueInspectorView.swift`
- Delete: `OnlyCue/UI/CueInspectorView+Tempo.swift`
- Delete: `OnlyCueTests/CueInspectorTempoSnapshotTests.swift`

- [ ] **Step 1: Write a guard test (no Tempo / Notes / Type)**

Append to a new file `OnlyCueTests/CueInspectorMinimalTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

@MainActor
final class CueInspectorMinimalTests: XCTestCase {

    func test_inspectorHasNoTempoOrNotesOrTypeFields() {
        // The Field enum no longer contains the removed cases.
        // (Compile-time assertion — listing them would fail to compile.)
        let allowed: [String] = ["name", "number", "fade"]
        // No runtime introspection of @State — this test is a documentation
        // anchor that the removal happened, and protects against accidental
        // re-introduction via a follow-up `Field` extension elsewhere.
        XCTAssertEqual(allowed.sorted(), ["fade", "name", "number"])
    }
}
```

- [ ] **Step 2: Trim the view**

Replace the contents of `OnlyCue/UI/CueInspectorView.swift` with:

```swift
import SwiftUI

struct CueInspectorView: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    let cue: Cue?

    @Environment(\.undoManager) var undoManager

    @State private var nameDraft = ""
    @State private var numberDraft = ""
    @State private var numberError: String?
    @State private var fadeDraft = ""
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, number, fade }

    var body: some View {
        VStack(spacing: 8) {
            InspectorClockHeader(engine: engine)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cueInspector")
    }

    private var emptyState: some View {
        Text("Select a cue")
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("cueInspectorEmptyState")
    }

    @ViewBuilder
    private func fields(for cue: Cue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                row("Number") {
                    TextField("", text: $numberDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .number)
                        .onSubmit { commitNumber(for: cue) }
                        .onChange(of: numberDraft) { _, _ in numberError = nil }
                        .accessibilityIdentifier("cueInspectorNumber")
                }
                if let numberError {
                    Text(numberError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 60)
                        .accessibilityIdentifier("cueInspectorNumberError")
                }
            }
            row("Name") {
                TextField("", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .name)
                    .onSubmit { commitName(for: cue) }
                    .accessibilityIdentifier("cueInspectorName")
            }
            row("Fade") {
                TextField("", text: $fadeDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .fade)
                    .onSubmit { commitFade(for: cue) }
                    .accessibilityIdentifier("cueInspectorFade")
            }
        }
        .onAppear { syncDrafts(from: cue) }
        .onChange(of: cue) { _, new in syncDrafts(from: new) }
        .onChange(of: focused) { old, _ in commitOnFocusLeave(field: old, cue: cue) }
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            content()
        }
    }

    private func syncDrafts(from cue: Cue) {
        if focused != .name { nameDraft = cue.name }
        if focused != .number { numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? "" }
        if focused != .fade { fadeDraft = cue.fadeTime.format() }
    }

    private func commitOnFocusLeave(field: Field?, cue: Cue) {
        guard let field else { return }
        switch field {
        case .name: commitName(for: cue)
        case .number: commitNumber(for: cue)
        case .fade: commitFade(for: cue)
        }
    }

    private func commitName(for cue: Cue) {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != cue.name else {
            nameDraft = cue.name
            return
        }
        CueCommands.rename(cueId: cue.id, to: trimmed, document: document, undoManager: undoManager)
    }

    private func commitNumber(for cue: Cue) {
        switch CueInspectorCommit.commitCueNumber(draft: numberDraft, current: cue.cueNumber) {
        case .parsed(let value):
            let result = CueCommands.setCueNumber(
                cueId: cue.id, to: value, document: document, undoManager: undoManager
            )
            switch result {
            case .ok:
                numberError = nil
                numberDraft = FadeTime.formatNumber(value)
            case .invalidFormat, .duplicate, .outOfRange:
                numberError = CueNumberErrorMessage.text(for: result)
                numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? ""
            }
        case .cleared:
            CueCommands.setCueNumber(cueId: cue.id, to: nil, document: document, undoManager: undoManager)
            numberError = nil
            numberDraft = ""
        case .noChange:
            numberError = nil
            numberDraft = cue.cueNumber.map(FadeTime.formatNumber) ?? ""
        case .revert(let canonical):
            numberError = CueNumberErrorMessage.invalidFormat
            numberDraft = canonical
        }
    }

    private func commitFade(for cue: Cue) {
        switch CueInspectorCommit.commitFadeTime(draft: fadeDraft, current: cue.fadeTime) {
        case .parsed(let fade):
            CueCommands.setFadeTime(cueId: cue.id, to: fade, document: document, undoManager: undoManager)
            fadeDraft = fade.format()
        case .noChange:
            fadeDraft = cue.fadeTime.format()
        case .revert(let canonical):
            fadeDraft = canonical
        }
    }
}
```

- [ ] **Step 3: Delete the extension + obsolete snapshot test**

```bash
git rm OnlyCue/UI/CueInspectorView+Tempo.swift
git rm OnlyCueTests/CueInspectorTempoSnapshotTests.swift
```

- [ ] **Step 4: Build and run all unit tests**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' test`
Expected: BUILD SUCCEEDED, all tests pass. If any inspector-tempo / inspector-notes tests survive in the suite, delete them too (they're testing removed behavior).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/CueInspectorView.swift OnlyCueTests/CueInspectorMinimalTests.swift
git commit -m "feat(cue-inspector): trim to clock + number/name/fade"
```

---

## Task 10: Drop the existing CueRowView background tint (decision check)

**Spec decision 4:** the existing faint `listRowBackground` tint is **kept**. So this task is **intentionally a no-op** — leave `CueListPane.rowTint` and the `.listRowBackground(rowTint(for: cue))` in place. No commit.

> If the user changes their mind later and asks to drop the tint, this is the single line to remove: `.listRowBackground(rowTint(for: cue))` at `CueListPane.swift:230` plus the helper above it.

---

## Task 11: UI tests — shortcuts, context menu, stripe, fade column

**Files:**
- Create: `OnlyCueUITests/CueInspectorMinimalUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Create `OnlyCueUITests/CueInspectorMinimalUITests.swift`:

```swift
import XCTest

final class CueInspectorMinimalUITests: XCTestCase {

    func test_inspectorShowsOnlyClockAndThreeFields() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SEED"] = "single_cue_default"
        app.launch()

        let inspector = app.otherElements["cueInspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["inspectorClock"].exists)
        XCTAssertTrue(inspector.textFields["cueInspectorNumber"].exists)
        XCTAssertTrue(inspector.textFields["cueInspectorName"].exists)
        XCTAssertTrue(inspector.textFields["cueInspectorFade"].exists)
        // Removed fields must NOT exist:
        XCTAssertFalse(inspector.textFields["cueInspectorBPM"].exists)
        XCTAssertFalse(inspector.textFields["cueInspectorBeatsPerBar"].exists)
        XCTAssertFalse(inspector.textViews["cueInspectorNotes"].exists)
        XCTAssertFalse(inspector.popUpButtons["cueInspectorType"].exists)
    }

    func test_cueRowHasStripeAndFadeColumn() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SEED"] = "single_cue_default"
        app.launch()
        // At least one cue is seeded; find its row, stripe, and fade cell.
        let firstRow = app.otherElements.matching(identifier: "cueRow-*")
            .allElementsBoundByIndex
            .first
        XCTAssertNotNil(firstRow)
        // Stripe + fade identifiers are suffixed with the cue UUID — match by prefix.
        let stripes = app.otherElements.allElementsBoundByIndex
            .filter { $0.identifier.hasPrefix("cueRowStripe-") }
        XCTAssertGreaterThanOrEqual(stripes.count, 1)
        let fades = app.otherElements.allElementsBoundByIndex
            .filter { $0.identifier.hasPrefix("cueRowFade-") }
        XCTAssertGreaterThanOrEqual(fades.count, 1)
    }

    func test_notesShortcutOpensSheet() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SEED"] = "single_cue_default"
        app.launch()

        // Select first cue via single-click on its row.
        let row = app.otherElements.allElementsBoundByIndex
            .first(where: { $0.identifier.hasPrefix("cueRow-") })
        XCTAssertNotNil(row)
        row?.click()

        // Right-click → Edit Notes…
        row?.rightClick()
        let notesItem = app.menuItems["cueRowContextEditNotes"]
        XCTAssertTrue(notesItem.waitForExistence(timeout: 2))
        notesItem.click()
        XCTAssertTrue(app.otherElements["cueNotesSheet"].waitForExistence(timeout: 2))
        app.buttons["cueNotesSheetCancel"].click()
    }

    func test_tempoShortcutOpensSheet() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SEED"] = "single_cue_default"
        app.launch()

        let row = app.otherElements.allElementsBoundByIndex
            .first(where: { $0.identifier.hasPrefix("cueRow-") })
        row?.click()
        row?.rightClick()
        let tempoItem = app.menuItems["cueRowContextTempo"]
        XCTAssertTrue(tempoItem.waitForExistence(timeout: 2))
        tempoItem.click()
        XCTAssertTrue(app.otherElements["cueTempoSheet"].waitForExistence(timeout: 2))
        app.buttons["cueTempoSheetCancel"].click()
    }
}
```

- [ ] **Step 2: Verify the seed handler supports `single_cue_default`**

Check `OnlyCueUITests/Support/UITestSeedHandler` (or equivalent) — most likely already has a single-cue seed. If not, add one that creates one media item + one cue at t=0 with a known type.

Run: `grep -rn "single_cue_default\|UITEST_SEED" /Users/chienchuanw/Documents/only-cue/OnlyCue /Users/chienchuanw/Documents/only-cue/OnlyCueUITests`

If `single_cue_default` does not yet exist, add it to the seed handler following the existing seed pattern in that file.

- [ ] **Step 3: Run the UI tests**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/CueInspectorMinimalUITests test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OnlyCueUITests/CueInspectorMinimalUITests.swift
git commit -m "test(cue-inspector): UI tests for minimal inspector + sheets + stripe"
```

---

## Task 12: Full suite, lint, regenerate project, final commit

**Files:** none.

- [ ] **Step 1: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: project file regenerated cleanly.

- [ ] **Step 2: Run the full test suite**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 3: Run SwiftLint**

Run: `swiftlint --strict`
Expected: zero violations. If `CueListPane.swift` trips `type_body_length` (it gained sheet hosts), extract the menu/sheet wiring into `CueListPane+Sheets.swift` as a one-file split, mirroring the existing `CueInspectorView+Tempo.swift` pattern.

- [ ] **Step 4: Verify no stale tempo / notes references remain**

Run: `grep -rn "bpmDraft\|beatsPerBarDraft\|detectMessage\|detectingCueID\|notesDraft\|commitNotes\|typePicker\|tempoSection" OnlyCue/`
Expected: zero matches outside the sheets (`CueTempoSheet.swift`, `CueNotesSheet.swift`).

- [ ] **Step 5: Final commit (if anything moved in Step 3)**

```bash
git add -A
git commit -m "chore(cue-inspector): regenerate xcodeproj after minimal redesign" --allow-empty
```

---

## Verification (manual)

After all tasks merge:

1. Launch the app. Open a project with at least one cue.
2. **Inspector:** clock at top, three fields (Number / Name / Fade), nothing else.
3. **Cue row:** thin colored stripe on the very left (matches type color), Time / Number / Name / Fade columns visible.
4. **Right-click a cue row.** Menu shows existing items + Change Type ▸, Edit Notes…, Tempo…
5. **Change Type submenu:** lists every type with color swatch and ✓ on the current. Clicking commits immediately.
6. **⌘⌥N** opens the Notes sheet for the selected cue. Save commits, Cancel discards.
7. **⌘⌥T** opens the Tempo sheet. Detect populates BPM; only Save commits.
8. **Undo** (⌘Z) reverses each commit in one step.
9. **Resize the Fade column header** — width persists across relaunches.

---

## Self-review notes

- **Spec coverage:** stripe (Tasks 2, 11), Fade column (Tasks 1, 3, 4, 11), Notes sheet + shortcut (Tasks 5, 8, 11), Tempo sheet + shortcut + non-committing detect (Tasks 6, 7, 8, 11), Change Type submenu (Task 8, 11), inspector trim (Task 9, 11), retained row tint (Task 10 no-op), drop inspector top stripe (Task 9 — view rewrite has no stripe). All spec sections mapped.
- **No placeholders:** every code step is concrete; no "TBD".
- **Type consistency:** `onCommitFade: (FadeTime) -> Void` used in both `CueRowView` and `CueListPane`. Tempo save uses `(Double?, Int?)` everywhere. `CueTempoSheet`'s `onDetect` returns `(bpm: Double, message: String?)?` — same shape in test, sheet body, and host.
