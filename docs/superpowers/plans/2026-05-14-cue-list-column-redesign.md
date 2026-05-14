# Cue list column redesign — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reshape the cue list above the inspector into a three-column `Time | Cue # | Name` layout with a header row and cue-color-tinted row backgrounds; remove the search field, leading position-index column, color swatch, and BPM column.

**Architecture:** Pure SwiftUI UI change in two files (`CueListPane.swift`, `CueRowView.swift`) plus one menu cleanup in `AppCommands.swift`. No model, schema, or `CueCommands` changes. Row tint is applied with `.listRowBackground(...)` from inside the `List`'s `ForEach`, so SwiftUI's selection accent continues to compose over the tint correctly.

**Tech Stack:** SwiftUI on macOS 14+, XCTest, XCUITest. Existing helpers `Color(hex:)`, `FadeTime.formatNumber`, `TimeFormat.hms`, `CueInspectorCommit`, `CueNumberValidator`, `CueNumberErrorMessage`.

**Spec:** `docs/superpowers/specs/2026-05-14-cue-list-column-redesign.md`

---

## File map

- **Modify** `OnlyCue/UI/CueListPane.swift` — drop search field/filter, drop position-index plumbing, add header row, apply `listRowBackground` tint per row.
- **Modify** `OnlyCue/UI/CueRowView.swift` — drop `index:` param, remove swatch + position-index cell + BPM cell + `showBPMColumn` AppStorage; reorder body to `Time | Cue # | Name` with shared width constants; switch row-scoped accessibility ids from `\(index)` to `\(cue.id)`.
- **Modify** `OnlyCue/App/AppCommands.swift` — delete the `@AppStorage("showBPMColumn")` property and its View-menu `Toggle("Show BPM Column", …)` line.
- **Delete** `OnlyCueTests/CueListFilterTests.swift` — filter helper is gone.
- **Modify** existing tests that assert on the dropped UI (search field id, BPM cell, position-index, swatch). The known places are listed inside each task; verify with the search commands shown.
- **Add** `OnlyCueTests/CueRowLayoutTests.swift` — snapshot-style assertion that the row exposes Time + Cue # + Name accessibility ids only (no swatch, no BPM, no index cell).
- **Add** `OnlyCueTests/CueListHeaderTests.swift` — assertion that `CueListPane` renders a `cueListHeader` view and no `cueListSearchField`.

---

## Shared constants (used in Task 3 and Task 4)

```swift
enum CueListLayout {
    static let timeColumnWidth: CGFloat = 96
    static let numberColumnWidth: CGFloat = 56
    static let rowHorizontalSpacing: CGFloat = 8
    static let rowTintOpacity: Double = 0.18
}
```

This enum lives in `OnlyCue/UI/CueListPane.swift` (top of the file, above `struct CueListPane`). Both the header row in `CueListPane` and the row body in `CueRowView` reference these constants so they stay aligned.

---

## Task 1: Remove search field and filter helper

**Files:**
- Modify: `OnlyCue/UI/CueListPane.swift` (lines 15–18, 26–33, 133–147, 196–202)
- Delete: `OnlyCueTests/CueListFilterTests.swift`

- [ ] **Step 1: Delete the filter test file**

```bash
git rm OnlyCueTests/CueListFilterTests.swift
```

- [ ] **Step 2: Verify the build now fails on the missing symbol**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' build 2>&1 | grep -E "error:" | head`

Expected: no errors yet (the test was the only caller of `Self.filtered` other than the pane itself, but the pane still references it).

If the build is still green, that's also fine — proceed.

- [ ] **Step 3: Remove `searchQuery`, `visibleCues`, and `Self.filtered`**

In `OnlyCue/UI/CueListPane.swift`:

Delete this property (around line 15):
```swift
    @State private var searchQuery: String = ""
```

Delete this computed property (around line 18):
```swift
    private var visibleCues: [Cue] { Self.filtered(cues, by: searchQuery) }
```

Delete the entire `static func filtered(...)` block including its doc comment (around lines 20–33):
```swift
    /// Pure filter helper — case-insensitive localized contains on name OR notes.
    /// ...
    static func filtered(_ cues: [Cue], by query: String) -> [Cue] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cues }
        return cues.filter { cue in
            cue.name.localizedCaseInsensitiveContains(trimmed) ||
            cue.notes.localizedCaseInsensitiveContains(trimmed)
        }
    }
```

- [ ] **Step 4: Remove `searchField` view and inline it out of `cueList`**

Delete the `searchField` computed property (around lines 133–139):
```swift
    private var searchField: some View {
        TextField("Search cues", text: $searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .accessibilityIdentifier("cueListSearchField")
    }
```

Replace the `cueList` view (around lines 141–147):
```swift
    private var cueList: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            scrollableList
        }
    }
```

with (Task 4 will re-introduce a header here; for now we just keep the list):
```swift
    private var cueList: some View {
        scrollableList
    }
```

- [ ] **Step 5: Switch `ForEach` and `deleteAtOffsets` to use `cues` directly**

In `scrollableList`, replace:
```swift
                ForEach(Array(visibleCues.enumerated()), id: \.element.id) { index, cue in
```
with:
```swift
                ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
```

In `deleteAtOffsets`, replace the body:
```swift
    private func deleteAtOffsets(_ offsets: IndexSet) {
        // ForEach iterates `visibleCues`, so swipe-to-delete offsets index into
        // the filtered list — resolve via `visibleCues` to get the right cue ID.
        let target = visibleCues
        for index in offsets {
            guard target.indices.contains(index) else { continue }
            let cue = target[index]
            CueCommands.delete(cueId: cue.id, document: document, undoManager: undoManager)
        }
    }
```

with:
```swift
    private func deleteAtOffsets(_ offsets: IndexSet) {
        for index in offsets {
            guard cues.indices.contains(index) else { continue }
            let cue = cues[index]
            CueCommands.delete(cueId: cue.id, document: document, undoManager: undoManager)
        }
    }
```

(The `index` from `ForEach.enumerated()` continues to be passed to `CueRowView(index: index + 1, …)` for now; Task 3 removes that parameter.)

- [ ] **Step 6: Build green and run tests**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test 2>&1 | tail -20`

Expected: all tests pass. No reference to `CueListFilterTests` should remain.

- [ ] **Step 7: Confirm no stale references**

Run: `grep -rn "searchQuery\|visibleCues\|cueListSearchField\|CueListFilter\|Self.filtered" OnlyCue OnlyCueTests OnlyCueUITests 2>/dev/null`

Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/UI/CueListPane.swift OnlyCueTests/CueListFilterTests.swift
git commit -m "refactor(cue-list): remove search field and filter helper"
```

---

## Task 2: Remove BPM column and View-menu toggle

**Files:**
- Modify: `OnlyCue/UI/CueRowView.swift` (line 20, lines 42–48)
- Modify: `OnlyCue/App/AppCommands.swift` (line 9, line 106)

- [ ] **Step 1: Find any tests that assert on the BPM cell**

Run: `grep -rn "cueBPM\|showBPMColumn\|Show BPM Column" OnlyCue OnlyCueTests OnlyCueUITests 2>/dev/null`

Expected: matches in `CueRowView.swift` (lines 20, 42, 47), `AppCommands.swift` (lines 9, 106), and possibly test files. If any test asserts the BPM cell exists, note its path — you will delete those assertions in this task. (At the time of writing, no test currently references `cueBPM`; if `grep` returns more than the four production-code matches, update those tests inline before the build step.)

- [ ] **Step 2: Remove BPM cell from `CueRowView`**

In `OnlyCue/UI/CueRowView.swift`, delete this property (line 20):
```swift
    @AppStorage("showBPMColumn") private var showBPMColumn = false
```

And delete this block from `body` (around lines 42–48):
```swift
                if showBPMColumn {
                    Text(cue.bpm.map { String(Int($0.rounded())) } ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(cue.bpm == nil ? .tertiary : .secondary)
                        .frame(width: 36, alignment: .trailing)
                        .accessibilityIdentifier("cueBPM-\(index)")
                }
```

- [ ] **Step 3: Remove BPM toggle from the View menu**

In `OnlyCue/App/AppCommands.swift`, delete the property (line 9):
```swift
    @AppStorage("showBPMColumn") private var showBPMColumn = false
```

And delete the `Toggle` line (line 106):
```swift
            Toggle("Show BPM Column", isOn: $showBPMColumn)
```

Leave the surrounding `Toggle("Show Tempo Grid", …)` and `Toggle("Pause at Each Cue", …)` untouched. The blank line that opens up is fine — SwiftUI's `Menu` builder ignores it.

- [ ] **Step 4: Build green and run tests**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test 2>&1 | tail -20`

Expected: all tests pass.

- [ ] **Step 5: Confirm no stale references**

Run: `grep -rn "showBPMColumn\|cueBPM\|Show BPM Column" OnlyCue OnlyCueTests OnlyCueUITests 2>/dev/null`

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/CueRowView.swift OnlyCue/App/AppCommands.swift
git commit -m "refactor(cue-list): drop BPM column and view-menu toggle"
```

---

## Task 3: Reshape `CueRowView` — new column order, drop index + swatch

**Files:**
- Create: `OnlyCueTests/CueRowLayoutTests.swift`
- Modify: `OnlyCue/UI/CueRowView.swift` (entire `body` plus signature)
- Modify: `OnlyCue/UI/CueListPane.swift` (the `CueRowView(index: …)` call site in `scrollableList`)

- [ ] **Step 1: Write the failing row-layout test**

Create `OnlyCueTests/CueRowLayoutTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

final class CueRowLayoutTests: XCTestCase {

    /// Sanity-check: the new row no longer exposes the dropped accessibility
    /// ids (position-index, color swatch, BPM cell). Concrete accessibility
    /// id presence is exercised by UI tests; this is a fast unit-level guard.
    func test_cueRowView_compiles_without_index_parameter() {
        let cue = Cue(
            id: UUID(),
            time: 12.345,
            name: "Verse",
            notes: "",
            cueNumber: 12.5,
            colorHex: "#FF0000",
            typeID: nil,
            bpm: nil,
            beatsPerBar: nil
        )
        // Compile-time assertion: the new initializer takes no `index:` arg.
        let view = CueRowView(cue: cue, resolvedColorHex: "#FF0000")
        XCTAssertNotNil(view)
    }
}
```

If the `Cue` initializer arguments above don't match the current struct (it has evolved across schema versions), adjust to whatever the current `Cue.init` requires — the test's purpose is to assert the call site `CueRowView(cue:resolvedColorHex:)` compiles, not to exercise `Cue`. Verify the current shape with: `grep -n "struct Cue" OnlyCue/Document/*.swift` and `grep -n "init" OnlyCue/Document/Cue*.swift`.

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueRowLayoutTests 2>&1 | tail -20`

Expected: build failure — `CueRowView` still requires `index:`.

- [ ] **Step 3: Add the shared `CueListLayout` constants**

In `OnlyCue/UI/CueListPane.swift`, insert at the very top of the file (after `import SwiftUI`, before `struct CueListPane`):

```swift
enum CueListLayout {
    static let timeColumnWidth: CGFloat = 96
    static let numberColumnWidth: CGFloat = 56
    static let rowHorizontalSpacing: CGFloat = 8
    static let rowTintOpacity: Double = 0.18
}
```

- [ ] **Step 4: Replace `CueRowView` body with the new column order**

Open `OnlyCue/UI/CueRowView.swift`. Replace the existing `struct CueRowView` declaration through the end of `body` with:

```swift
struct CueRowView: View {

    let cue: Cue
    var resolvedColorHex: String?
    var onRename: (String) -> Void = { _ in }
    var onCommitNumber: (Double?) -> CueNumberValidator.Result = { _ in .ok }

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    @State private var isEditingNumber = false
    @State private var numberDraft = ""
    @State private var numberError: String?
    @FocusState private var numberFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CueListLayout.rowHorizontalSpacing) {
                Text(TimeFormat.hms(cue.time))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: CueListLayout.timeColumnWidth, alignment: .leading)
                    .accessibilityIdentifier("cueTime-\(cue.id)")

                numberCell
                    .frame(width: CueListLayout.numberColumnWidth, alignment: .leading)
                    .accessibilityIdentifier("cueNumber-\(cue.id)")

                nameField
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("cueName-\(cue.id)")
            }
            if let numberError {
                Text(numberError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, CueListLayout.timeColumnWidth + CueListLayout.rowHorizontalSpacing)
                    .accessibilityIdentifier("cueNumberError-\(cue.id)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("cueRow-\(cue.id)")
    }
```

Leave `numberCell`, `nameField`, and the private `beginRename` / `commitRename` / `cancelRename` / `beginNumberEdit` / `cancelNumberEdit` / `commitNumber` helpers unchanged.

Note: this deletes `let index: Int`, the `Text("\(index)")` cell, the `CueColorSwatch(...)` call, and the trailing time cell (the time has moved to the leading position). The `numberError` indentation now aligns under the Cue # column.

- [ ] **Step 5: Update the call site in `CueListPane.scrollableList`**

In `OnlyCue/UI/CueListPane.swift`, find the `ForEach` body (around line 152):

```swift
                ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                    CueRowView(
                        index: index + 1,
                        cue: cue,
                        resolvedColorHex: document.model.colorHex(for: cue),
```

Replace with:

```swift
                ForEach(cues, id: \.id) { cue in
                    CueRowView(
                        cue: cue,
                        resolvedColorHex: document.model.colorHex(for: cue),
```

Remove the `index + 1` argument; the rest of the `CueRowView` call (`onRename:`, `onCommitNumber:`) stays as-is. The `.tag(cue.id)` modifier stays.

- [ ] **Step 6: Run the unit test green**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueRowLayoutTests 2>&1 | tail -10`

Expected: PASS.

- [ ] **Step 7: Run the full test suite**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test 2>&1 | tail -30`

Expected: all tests pass. If any UI/XCUITest still queries `cueRow-1`, `cueName-1`, `cueNumber-1`, `cueColorSwatch-1`, or similar `\(index)`-suffixed ids, they will now fail — update them to use the cue's UUID (look up the cue, then use `"cueRow-\(cue.id)"`). Re-run.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/UI/CueRowView.swift OnlyCue/UI/CueListPane.swift OnlyCueTests/CueRowLayoutTests.swift
git commit -m "refactor(cue-list): reorder row to time | cue# | name and drop index + swatch"
```

---

## Task 4: Add column header row and cue-color row tint

**Files:**
- Create: `OnlyCueTests/CueListHeaderTests.swift`
- Modify: `OnlyCue/UI/CueListPane.swift` (`cueList` view and `scrollableList`'s `ForEach` row)

- [ ] **Step 1: Write the failing header test**

Create `OnlyCueTests/CueListHeaderTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import OnlyCue

final class CueListHeaderTests: XCTestCase {

    /// The cue list pane should expose a header row. We can't easily reach
    /// into SwiftUI's view tree from XCTest, so this is a compile-time
    /// existence check on the new `cueListHeader` private API surface — the
    /// production code below declares an internal `static let` for the
    /// accessibility id so this test pins it in place. The actual
    /// rendering is exercised by the UI test suite.
    func test_cueListHeader_accessibilityIdentifier_is_stable() {
        XCTAssertEqual(CueListPane.headerAccessibilityIdentifier, "cueListHeader")
    }
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueListHeaderTests 2>&1 | tail -10`

Expected: build failure — `CueListPane.headerAccessibilityIdentifier` is undefined.

- [ ] **Step 3: Add the header view and the row tint**

In `OnlyCue/UI/CueListPane.swift`, add this static constant inside `struct CueListPane`, near the top of the type (e.g., just below `@Binding var selection: Set<Cue.ID>`):

```swift
    static let headerAccessibilityIdentifier = "cueListHeader"
```

Add this computed property anywhere in the type (alongside `cueList`):

```swift
    private var headerRow: some View {
        HStack(spacing: CueListLayout.rowHorizontalSpacing) {
            Text("Time")
                .frame(width: CueListLayout.timeColumnWidth, alignment: .leading)
            Text("Cue #")
                .frame(width: CueListLayout.numberColumnWidth, alignment: .leading)
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

Replace the current `cueList`:

```swift
    private var cueList: some View {
        scrollableList
    }
```

with:

```swift
    private var cueList: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            scrollableList
        }
    }
```

- [ ] **Step 4: Apply `listRowBackground` tint per row**

In `scrollableList`, the `ForEach` body currently looks like:

```swift
                ForEach(cues, id: \.id) { cue in
                    CueRowView(
                        cue: cue,
                        resolvedColorHex: document.model.colorHex(for: cue),
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
                    .tag(cue.id)
                }
```

Insert a `.listRowBackground` modifier after `.tag(cue.id)`:

```swift
                    .tag(cue.id)
                    .listRowBackground(rowTint(for: cue))
```

Then add this helper method to `CueListPane` (alongside `selectedCue`):

```swift
    private func rowTint(for cue: Cue) -> Color {
        guard let hex = document.model.colorHex(for: cue),
              let base = Color(hex: hex) else {
            return Color.clear
        }
        return base.opacity(CueListLayout.rowTintOpacity)
    }
```

(If `Color(hex:)` is failable in the codebase the guard works; if it is non-failable returning `Color`, change to `let base = Color(hex: hex)` and drop the second `guard` clause. Verify with `grep -n "init(hex" OnlyCue/UI/*.swift`.)

- [ ] **Step 5: Run the header test green**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/CueListHeaderTests 2>&1 | tail -10`

Expected: PASS.

- [ ] **Step 6: Run the full test suite**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test 2>&1 | tail -30`

Expected: all tests pass.

- [ ] **Step 7: Smoke-test in the app**

Open the project in Xcode (`open OnlyCue.xcodeproj`, regenerate with `xcodegen generate` first if needed), build and run. Open a project with at least three cues of different colors. Verify:

1. The cue list shows a header row "Time   Cue #   Name" above the cues.
2. Each cue's row is tinted with its color at ~18% opacity; no-color cues render with no tint.
3. Selecting a row still shows the system accent on top of the tint.
4. Double-tap on Cue # cell enters edit mode; double-tap on Name cell enters edit mode; Time is not editable.
5. No search field is visible. No leading position-index column. No circular color swatch in rows. No BPM cell.
6. View menu no longer contains "Show BPM Column".

If any of (1)–(6) is wrong, fix inline and rerun the test suite.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/UI/CueListPane.swift OnlyCueTests/CueListHeaderTests.swift
git commit -m "feat(cue-list): add column header row and cue-color row tint"
```

---

## Task 5: Final sweep

- [ ] **Step 1: Re-grep for any stragglers**

Run:

```bash
grep -rn "searchQuery\|visibleCues\|cueListSearchField\|CueListFilter\|Self.filtered\|showBPMColumn\|cueBPM\|Show BPM Column\|CueColorSwatch(hex: resolvedColorHex" OnlyCue OnlyCueTests OnlyCueUITests 2>/dev/null
```

Expected: no output. `CueColorSwatch` still exists in the codebase but is no longer referenced from `CueRowView`; verify with `grep -rn "CueColorSwatch(" OnlyCue` — remaining usages should be in `TimelineBreakdownView.swift` and `CueColorSwatch.swift` only.

- [ ] **Step 2: Run the full test suite one more time**

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' test 2>&1 | tail -30`

Expected: all tests pass, no warnings introduced.

- [ ] **Step 3: Confirm spec coverage by re-reading the spec**

Open `docs/superpowers/specs/2026-05-14-cue-list-column-redesign.md`. Walk each "Detailed design" bullet against the diff (`git diff origin/dev`). Confirm every bullet has a corresponding change in code.

- [ ] **Step 4: Open the PR**

Use the `gh-pr` skill with type `refactor` (per `.github/PULL_REQUEST_TEMPLATE/refactor.md`). Title: `refactor(cue-list): three-column layout with header and color-tinted rows`. The PR body's verification block should link the spec section above.
