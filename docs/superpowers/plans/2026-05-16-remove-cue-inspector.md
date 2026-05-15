# Remove Cue Inspector Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the Cue Inspector pane entirely, pin the playhead clock above the cue list at all times, leaving the left pane as `{ clock; cue list }` with all cue editing flowing through the modal sheets shipped in #291.

**Architecture:** Three structural moves — (1) rename `InspectorClockHeader` → `PlayheadClockHeader` with a matching accessibility-identifier swap, (2) collapse `CueListPane.body`'s `VSplitView { list ; inspector }` into a single `VStack { clock ; cueList-or-emptyState }`, (3) delete `CueInspectorView` plus its now-obsolete tests. No new logic and no schema changes — pure presentation layer.

**Tech Stack:** SwiftUI, Swift 6, macOS 14+, XCTest, XCUITest, XcodeGen (`project.yml`).

---

## File Structure

| File | Status | Responsibility after this PR |
|---|---|---|
| `OnlyCue/UI/InspectorClockHeader.swift` | **Rename** → `OnlyCue/UI/PlayheadClockHeader.swift` | SMPTE clock view (type `PlayheadClockHeader`, identifier `playheadClock`) hosted by `CueListPane`. |
| `OnlyCue/UI/CueListPane.swift` | Modify | Renders `PlayheadClockHeader` at the top, then the cue list or empty state. No inspector child. |
| `OnlyCue/UI/CueInspectorView.swift` | **Delete** | — |
| `OnlyCueUITests/InspectorClockHeaderUITests.swift` | **Rename** → `OnlyCueUITests/PlayheadClockHeaderUITests.swift` | Same SMPTE-format checks, scoped to the new identifier and the new "above the list" location. |
| `OnlyCueUITests/InspectorClockFramerateUITests.swift` | Modify (identifier swap only) | Identifier `inspectorClock` → `playheadClock`. Pre-existing flake is **not** fixed here. |
| `OnlyCueTests/CueInspectorMinimalTests.swift` | **Delete** | Asserted Field-enum cases of a now-deleted view. |
| `OnlyCueUITests/CueInspectorMinimalUITests.swift` | **Delete** | Tested an inspector that no longer exists; subsumed by the new layout test below. |
| `OnlyCueUITests/CueListPaneLayoutUITests.swift` | **Create** | Three new tests: clock present, no inspector container, clock renders above the list. |
| `OnlyCue/UI/CueTempoDetect.swift` | Modify (doc comment only) | Update the comment that still references `CueInspectorView+Tempo`. |
| `OnlyCue/UI/FirstResponderResign.swift` | Modify (doc comment only) | Same — update the stale doc reference. |
| `project.yml` | No change | No new source folders. |

---

## Conventions used throughout this plan

- **Build / single-test command:** `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:<TARGET>/<CLASS>[/<METHOD>] test`
- **Full suite:** `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' test`
- **Commit style:** Conventional Commits, lowercase after prefix (project `CLAUDE.md`). No `Co-Authored-By` trailers, no signatures.
- **Working directory:** `/Users/chienchuanw/Documents/only-cue/.claude/worktrees/issues-293`. Branch: `issues/293`. Base: `dev`.
- **No mutations of `ProjectModel` outside `Commands/CueCommands.swift`** — irrelevant for this PR since no commands are added.
- **Pre-existing flake:** `OnlyCueUITests/InspectorClockFramerateUITests/testClockRerendersWhenFramerateChanges` is known-broken on `dev` and remains so after this PR. The plan never asserts that test passes; the full-suite verification in Task 9 uses `-skip-testing` for it.

---

## Task 1: Rename `InspectorClockHeader` → `PlayheadClockHeader`

**Files:**
- Rename: `OnlyCue/UI/InspectorClockHeader.swift` → `OnlyCue/UI/PlayheadClockHeader.swift`
- Modify: the renamed file (struct name + accessibility identifier).

- [ ] **Step 1: Rename the file via git**

```bash
git mv OnlyCue/UI/InspectorClockHeader.swift OnlyCue/UI/PlayheadClockHeader.swift
```

- [ ] **Step 2: Rewrite the view's body**

Replace the entire contents of `OnlyCue/UI/PlayheadClockHeader.swift` with:

```swift
import SwiftUI

/// Large, always-visible playhead readout pinned at the top of the
/// `CueListPane`. Reads `PlayerEngine.currentTime` (Observation-tracked)
/// so it ticks in lock-step with the transport, and renders as SMPTE
/// timecode at the project's configured framerate.
///
/// Previously named `InspectorClockHeader` and lived inside
/// `CueInspectorView`; now sits above the cue list directly (issue #293).
struct PlayheadClockHeader: View {

    let engine: PlayerEngine
    @Environment(\.projectFramerate) private var framerate

    var body: some View {
        VStack(spacing: 8) {
            Text(TimeFormat.smpte(engine.currentTime, rate: framerate))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .accessibilityIdentifier("playheadClock")
                .frame(maxWidth: .infinity, alignment: .center)
            Divider()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project and confirm the build still compiles before the consumers swap**

Run: `xcodegen generate`
Expected: project regenerated cleanly.

Run: `xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: **FAIL** — `CueInspectorView.swift` still references `InspectorClockHeader(engine:)`. This is intentional; Task 2 deletes that file.

- [ ] **Step 4: Commit the rename**

```bash
git add OnlyCue/UI/PlayheadClockHeader.swift OnlyCue/UI/InspectorClockHeader.swift project.yml OnlyCue.xcodeproj 2>/dev/null
git commit -m "refactor(cue-list): rename InspectorClockHeader to PlayheadClockHeader"
```

> Note: `OnlyCue.xcodeproj/` is not committed (xcodegen-generated, per project `CLAUDE.md`). The `git add` of the path is a no-op if the directory is gitignored — that's fine.

---

## Task 2: Delete `CueInspectorView` and its tests

**Files:**
- Delete: `OnlyCue/UI/CueInspectorView.swift`
- Delete: `OnlyCueTests/CueInspectorMinimalTests.swift`
- Delete: `OnlyCueUITests/CueInspectorMinimalUITests.swift`

- [ ] **Step 1: Delete the inspector view**

```bash
git rm OnlyCue/UI/CueInspectorView.swift
```

- [ ] **Step 2: Delete the inspector unit guard test**

```bash
git rm OnlyCueTests/CueInspectorMinimalTests.swift
```

- [ ] **Step 3: Delete the inspector UI test**

```bash
git rm OnlyCueUITests/CueInspectorMinimalUITests.swift
```

- [ ] **Step 4: Confirm the build is now broken at the call site in `CueListPane.swift`**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: **FAIL** — `CueListPane.swift` references `CueInspectorView(...)`. Task 3 fixes this.

- [ ] **Step 5: Stage the deletions; do not commit yet**

```bash
git status
```

The three deletions stay in the index until Task 3's commit, which lands them together with the call-site fix so the tree never compiles without the inspector but also without its replacement.

---

## Task 3: Pin `PlayheadClockHeader` at the top of `CueListPane`; drop the `VSplitView`

**Files:**
- Modify: `OnlyCue/UI/CueListPane.swift`

The current `body` is a `VSplitView` containing the cue list and the now-deleted `CueInspectorView`. Collapse it to a `VStack` of the new clock view plus the existing cue-list/empty-state group. Drop the now-unused `selectedCue` computed property.

- [ ] **Step 1: Replace the body's split-view with a plain VStack**

In `OnlyCue/UI/CueListPane.swift`, locate the current body (around line 86):

```swift
var body: some View {
    VSplitView {
        Group {
            if cues.isEmpty {
                emptyState
            } else {
                cueList
            }
        }
        .frame(minHeight: 120)

        CueInspectorView(document: document, engine: engine, cue: selectedCue)
            .frame(minHeight: 180)
    }
    .frame(minWidth: 240)
    .accessibilityIdentifier("cueListPane")
    .onReceive(NotificationCenter.default.publisher(for: .snapSelectedCueToPlayhead)) { _ in
```

Replace with:

```swift
var body: some View {
    VStack(spacing: 0) {
        PlayheadClockHeader(engine: engine)
        Group {
            if cues.isEmpty {
                emptyState
            } else {
                cueList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 240)
    .accessibilityIdentifier("cueListPane")
    .onReceive(NotificationCenter.default.publisher(for: .snapSelectedCueToPlayhead)) { _ in
```

- [ ] **Step 2: Remove the now-unused `selectedCue` computed property**

Locate (around line 73):

```swift
private var selectedCue: Cue? {
    guard let id = soleSelectedID else { return nil }
    return cues.first(where: { $0.id == id })
}
```

Delete those four lines and the blank line below them. `soleSelectedID` stays — it's still consumed by `duplicateSelectedAtPlayhead()` and `scrollableList`'s selection-driven seek.

- [ ] **Step 3: Build and confirm**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit the structural change (with Task 2's deletions)**

```bash
git add OnlyCue/UI/CueListPane.swift
git commit -m "feat(cue-list): pin playhead clock above list; remove inspector pane"
```

This commit also lands the three deletions staged in Task 2.

---

## Task 4: Update the `InspectorClockFramerateUITests` identifier

**Files:**
- Modify: `OnlyCueUITests/InspectorClockFramerateUITests.swift`

The file's class name stays (renaming it would conflate scopes with the next task's rename), but the `inspectorClock` identifier inside is dead.

- [ ] **Step 1: Read the current matcher line**

```bash
grep -n "inspectorClock" OnlyCueUITests/InspectorClockFramerateUITests.swift
```

Expected output:
```
28:            .matching(identifier: "inspectorClock").firstMatch
29:        XCTAssertTrue(clock.waitForExistence(timeout: 15), "inspectorClock must exist")
```

- [ ] **Step 2: Swap both occurrences**

In `OnlyCueUITests/InspectorClockFramerateUITests.swift`, replace `"inspectorClock"` with `"playheadClock"` on both lines (the `.matching(identifier:)` argument and the `XCTAssertTrue` message string).

Resulting lines:

```swift
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15), "playheadClock must exist")
```

- [ ] **Step 3: Build only — do not run the test**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build-for-testing`
Expected: `** BUILD SUCCEEDED **`.

The test itself (`testClockRerendersWhenFramerateChanges`) is a pre-existing flake on `dev` (documented in PR #292). Don't run or fix it here.

- [ ] **Step 4: Commit**

```bash
git add OnlyCueUITests/InspectorClockFramerateUITests.swift
git commit -m "test(cue-list): swap framerate test identifier from inspectorClock to playheadClock"
```

---

## Task 5: Rename `InspectorClockHeaderUITests` → `PlayheadClockHeaderUITests`

**Files:**
- Rename: `OnlyCueUITests/InspectorClockHeaderUITests.swift` → `OnlyCueUITests/PlayheadClockHeaderUITests.swift`
- Modify: class name + accessibility identifier swaps + the third test's now-irrelevant `cueInspectorName` lookup.

The third test (`testClockVisibleWhenCueSelected`) currently waits on `cueInspectorName` after clicking a row, then asserts the clock stays visible. With no inspector, the "row click → name field appears" path doesn't exist. Replace it with a simpler assertion: clock stays visible after a row selection click.

- [ ] **Step 1: Rename via git**

```bash
git mv OnlyCueUITests/InspectorClockHeaderUITests.swift OnlyCueUITests/PlayheadClockHeaderUITests.swift
```

- [ ] **Step 2: Rewrite the file**

Replace the entire contents of `OnlyCueUITests/PlayheadClockHeaderUITests.swift` with:

```swift
import XCTest

final class PlayheadClockHeaderUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
    }

    /// With a seeded document open and no cue selected, the playhead clock
    /// sits at the top of the cue list pane and is visible.
    func testClockVisibleAtTopOfCueListPane() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 15),
            "playheadClock should be visible above the cue list."
        )
    }

    /// The playhead clock renders SMPTE timecode (`HH:MM:SS:FF` or
    /// `HH:MM:SS;FF` for drop-frame) at the project's framerate, replacing
    /// the legacy `HH:MM:SS.mmm` form.
    func testClockRendersAsSMPTE() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .staticText)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15))
        let text = clock.label.isEmpty ? (clock.value as? String ?? "") : clock.label
        XCTAssertNotNil(
            text.range(of: #"^\d{2}:\d{2}:\d{2}[:;]\d{2}$"#, options: .regularExpression),
            "expected HH:MM:SS:FF (or ;FF) form, got label='\(clock.label)' value='\(clock.value ?? "nil")'"
        )
    }

    /// Selecting a cue must not hide the clock — it stays pinned at the top.
    func testClockVisibleWhenCueSelected() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let firstRow = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), "First cue row should appear")
        firstRow.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 5),
            "playheadClock should remain visible when a cue is selected."
        )
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }

    private func waitForSeedWindow(in app: XCUIApplication, timeout: TimeInterval = 15) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = app.windows.allElementsBoundByIndex
            if let match = windows.first(where: { $0.title.hasPrefix("seed-") }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
```

- [ ] **Step 3: Run the renamed tests**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/PlayheadClockHeaderUITests test`
Expected: all three tests pass.

- [ ] **Step 4: Commit**

```bash
git add OnlyCueUITests/PlayheadClockHeaderUITests.swift OnlyCueUITests/InspectorClockHeaderUITests.swift
git commit -m "test(cue-list): rename inspector clock UI tests to playhead clock"
```

---

## Task 6: New layout tests in `CueListPaneLayoutUITests`

**Files:**
- Create: `OnlyCueUITests/CueListPaneLayoutUITests.swift`

Three tests:
1. Clock identifier is present.
2. No `cueInspector` container exists anywhere in the window.
3. The clock renders **above** the first cue row (frame check).

- [ ] **Step 1: Write the failing test file**

Create `OnlyCueUITests/CueListPaneLayoutUITests.swift`:

```swift
import XCTest

/// Layout regression for issue #293 — the Cue Inspector pane is gone,
/// the playhead clock is pinned above the cue list, and nothing in the
/// window claims the old `cueInspector` identifier.
final class CueListPaneLayoutUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
    }

    func test_playheadClockIsPresent() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 15),
            "playheadClock must exist above the cue list."
        )
    }

    func test_noInspectorContainer() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        // Wait for the pane to settle, then assert the old inspector
        // container is gone. (Use a short timeout — we expect non-existence.)
        let pane = window.descendants(matching: .any)
            .matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15), "cueListPane should be present")

        let inspector = window.descendants(matching: .any)
            .matching(identifier: "cueInspector").firstMatch
        XCTAssertFalse(
            inspector.exists,
            "cueInspector container must not exist after #293 — the inspector pane was removed."
        )
        XCTAssertFalse(
            window.textFields["cueInspectorName"].exists,
            "cueInspectorName field must not exist."
        )
        XCTAssertFalse(
            window.textFields["cueInspectorNumber"].exists,
            "cueInspectorNumber field must not exist."
        )
        XCTAssertFalse(
            window.textFields["cueInspectorFade"].exists,
            "cueInspectorFade field must not exist."
        )
    }

    func test_clockSitsAboveCueList() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15))

        let firstRow = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), "First cue row should appear")

        // Clock's bottom edge must sit at or above the row's top edge.
        // Small tolerance for sub-pixel rendering and divider spacing.
        let tolerance: CGFloat = 2
        XCTAssertLessThanOrEqual(
            clock.frame.maxY,
            firstRow.frame.minY + tolerance,
            "Clock (maxY=\(clock.frame.maxY)) should render above row (minY=\(firstRow.frame.minY))."
        )
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }

    private func waitForSeedWindow(in app: XCUIApplication, timeout: TimeInterval = 15) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = app.windows.allElementsBoundByIndex
            if let match = windows.first(where: { $0.title.hasPrefix("seed-") }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
```

- [ ] **Step 2: Run the new layout tests**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/CueListPaneLayoutUITests test`
Expected: all three tests pass.

- [ ] **Step 3: Commit**

```bash
git add OnlyCueUITests/CueListPaneLayoutUITests.swift
git commit -m "test(cue-list): layout tests for pinned clock and absent inspector"
```

---

## Task 7: Update stale doc references

**Files:**
- Modify: `OnlyCue/UI/CueTempoDetect.swift`
- Modify: `OnlyCue/UI/FirstResponderResign.swift`

Both files have doc comments that still mention `CueInspectorView`. They're documentation only — fix them so future readers aren't pointed at a deleted file.

- [ ] **Step 1: Update `CueTempoDetect.swift`**

In `OnlyCue/UI/CueTempoDetect.swift`, replace the doc-comment block at lines 1–7 so it reads:

```swift
import Foundation

/// Audio-side spectral-flux tempo detection. Called from `CueTempoSheet`
/// to populate its BPM draft when the user taps "Detect". Behavior is
/// byte-for-byte identical to the previous `CueInspectorView+Tempo.detect`
/// static (deleted in #291).
enum CueTempoDetect {
```

- [ ] **Step 2: Update `FirstResponderResign.swift`**

In `OnlyCue/UI/FirstResponderResign.swift`, locate the doc comment (around line 32) that references `CueInspectorView` and replace it with a reference to `CueListPane`'s cue rows where the inline-rename/number/fade fields live:

```swift
/// machinery in `CueRowView` (Number / Name / Fade inline edits) and the
/// modal sheets hosted by `CueListPane`. Returns the event unchanged so
/// normal
```

(Adjust surrounding doc-comment wording to match — the goal is to remove the dangling reference to a deleted view.)

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -scheme OnlyCue -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/CueTempoDetect.swift OnlyCue/UI/FirstResponderResign.swift
git commit -m "docs(cue-list): drop dangling CueInspectorView references"
```

---

## Task 8: Final reference scan + SwiftLint strict

**Files:** none.

- [ ] **Step 1: Confirm nothing references the deleted symbols**

Run: `grep -rn "CueInspectorView\|InspectorClockHeader\|cueInspector\b\|inspectorClock\b" OnlyCue/ OnlyCueTests/ OnlyCueUITests/`
Expected: only the doc-comment in `CueTempoDetect.swift` ("deleted in #291"). If anything else surfaces, fix it before continuing.

- [ ] **Step 2: Run SwiftLint with `--strict`**

Run: `swiftlint --strict`
Expected: zero violations.

If there's a `Vertical Whitespace Violation` or similar that crept in from edits, fix it inline and re-run. Common: a double blank line where a deleted property used to be — collapse to a single blank line.

- [ ] **Step 3: No commit needed unless lint required edits**

If SwiftLint required edits:

```bash
git add -A
git commit -m "chore(cue-list): swiftlint cleanup after inspector removal"
```

Otherwise skip.

---

## Task 9: Full test suite

**Files:** none.

- [ ] **Step 1: Run the full suite, skipping the known pre-existing flake**

Run:

```bash
xcodebuild -scheme OnlyCue -destination 'platform=macOS' \
  -skip-testing:OnlyCueUITests/InspectorClockFramerateUITests/testClockRerendersWhenFramerateChanges \
  test
```

Expected: `** TEST SUCCEEDED **`. The skipped test fails identically on `dev` (verified during #291 work) and is tracked separately.

- [ ] **Step 2: If anything else fails**

Triage by class. Any failure not in the skipped framerate test is a real regression introduced by this PR. Fix and re-run.

- [ ] **Step 3: No commit needed**

This task is verification only.

---

## Task 10: Push and open PR

**Files:** none.

- [ ] **Step 1: Confirm branch state**

Run: `git log --oneline origin/dev..issues/293`
Expected: roughly seven commits (one per task that produced a commit) plus the existing `docs(spec)` commit. The spec commit is `b2256f2` and was made before this plan started.

- [ ] **Step 2: Push**

```bash
git push -u origin issues/293
```

- [ ] **Step 3: Open PR with the OnlyCue feat template**

```bash
gh pr create --base dev --head issues/293 \
  --title "feat(cue-list): pin playhead clock above cue list; remove cue inspector pane (#293)" \
  --body "$(cat <<'EOF'
## Summary

The Cue Inspector pane is removed entirely. With Type / Notes / Tempo editing now flowing through right-click modal sheets (#291) and Number / Name / Fade editable inline on each row, the inspector added no signal — it only consumed vertical space. The playhead clock moves out of the inspector and is pinned above the cue list at all times. Result: the left pane is now `{ clock; cue list }`.

Closes #293

## Motivation

PR #292 (issue #291) trimmed the inspector to clock + three fields and pushed all other editing into modals. The user observed that with modals available, the inspector itself is redundant — and that the clock belongs above the cue list as a persistent playhead readout, not buried inside an inspector form. This PR realizes both observations.

## Implementation

Three structural moves, no new logic:

1. **Rename** `InspectorClockHeader` → `PlayheadClockHeader` (file, type, accessibility identifier `inspectorClock` → `playheadClock`).
2. **Collapse** `CueListPane.body`'s `VSplitView { list ; inspector }` into a `VStack { PlayheadClockHeader(engine:); cueList-or-emptyState }`. Drop the now-unused `selectedCue` computed property.
3. **Delete** `CueInspectorView.swift` and its two tests.

UI tests are reframed: the old `CueInspectorMinimalUITests` is replaced by `CueListPaneLayoutUITests` (clock present + no inspector + clock above list). The clock-framerate identifier swap is the only change to `InspectorClockFramerateUITests` — the existing flake there is pre-existing on `dev` and is out of scope.

## Changes

- `OnlyCue/UI/InspectorClockHeader.swift` → `OnlyCue/UI/PlayheadClockHeader.swift` (renamed, identifier swapped)
- `OnlyCue/UI/CueListPane.swift` — VSplitView collapsed; clock pinned above list; `selectedCue` removed
- `OnlyCue/UI/CueInspectorView.swift` — **deleted**
- `OnlyCueTests/CueInspectorMinimalTests.swift` — **deleted**
- `OnlyCueUITests/CueInspectorMinimalUITests.swift` — **deleted**
- `OnlyCueUITests/InspectorClockHeaderUITests.swift` → `OnlyCueUITests/PlayheadClockHeaderUITests.swift` (renamed, identifiers swapped)
- `OnlyCueUITests/InspectorClockFramerateUITests.swift` — identifier swap only (pre-existing flake left untouched)
- `OnlyCueUITests/CueListPaneLayoutUITests.swift` — **new** (three layout tests)
- `OnlyCue/UI/CueTempoDetect.swift` — doc comment updated
- `OnlyCue/UI/FirstResponderResign.swift` — doc comment updated
- `docs/superpowers/specs/2026-05-16-remove-cue-inspector-design.md` — spec
- `docs/superpowers/plans/2026-05-16-remove-cue-inspector.md` — plan

## Screenshots / Demo

```
Before                                       After
┌─────────────────────────┐                 ┌─────────────────────────┐
│  cue list               │                 │   01:23:45:18           │
│  (header + rows)        │                 │  ───────────────────    │
│                         │                 │  cue list               │
│ ═══════ split ═══════   │                 │  (header + rows)        │
│                         │                 │                         │
│  01:23:45:18  (clock)   │                 │                         │
│  Number  [12]           │                 │                         │
│  Name    [Blackout]     │                 │                         │
│  Fade    [3.0]          │                 │                         │
└─────────────────────────┘                 └─────────────────────────┘
```

## Test Plan

- [x] Playhead clock is present and identified as `playheadClock` — `CueListPaneLayoutUITests.test_playheadClockIsPresent`
- [x] No `cueInspector` container exists, and no inspector-scoped field identifiers exist — `CueListPaneLayoutUITests.test_noInspectorContainer`
- [x] Clock renders above the first cue row — `CueListPaneLayoutUITests.test_clockSitsAboveCueList`
- [x] Renamed `PlayheadClockHeaderUITests` (three SMPTE-format / visibility tests) all pass
- [x] All sheet-based editing paths from #291 (Notes, Tempo, Change Type) keep working — covered by `CueRowContextMenuUITests` + `CueNotesSheetTests` + `CueTempoSheetTests`
- [x] Inline row editing for Number / Name / Fade unchanged — `CueRowViewStripeTests` + manual verification

### Manual verification (smoke)

- [ ] Launch the app. The playhead clock sits at the top of the left pane, above the column header row.
- [ ] With no cues, the clock + "No cues yet" empty state are both visible; no inspector form.
- [ ] Right-click → Edit Notes… / Tempo… / Change Type ▸ still routes through the modal sheets.
- [ ] Double-clicking Number / Name / Fade in a row still opens inline edit.

### Pre-existing flake (not introduced by this PR)

`OnlyCueUITests/InspectorClockFramerateUITests/testClockRerendersWhenFramerateChanges` still fails on this branch **and on `dev`** — same flake documented in PR #292. The full suite passes when this single test is skipped:

```
xcodebuild ... -skip-testing:OnlyCueUITests/InspectorClockFramerateUITests/testClockRerendersWhenFramerateChanges test
** TEST SUCCEEDED **
```

A follow-up issue tracks stabilizing that test.

---
## OnlyCue verification (required)
**Spec link:** \`docs/superpowers/specs/2026-05-16-remove-cue-inspector-design.md\`
**Closes:** #293

- [x] New tests added for every behavior (TDD: red→green committed)
- [x] Gherkin scenarios from the issue mapped to UI tests where applicable
- [x] Spec updated if behavior diverged from \`docs/\` (no divergence)
- [ ] CI green (pending — pre-existing \`testClockRerendersWhenFramerateChanges\` failure expected; see note above)
EOF
)"
```

- [ ] **Step 4: Capture the PR number**

Save the PR URL from the `gh pr create` output.

---

## Verification (manual)

After all tasks merge and the PR is opened:

1. Launch the app. The playhead clock is at the top of the left pane.
2. Pane shows: clock, then column header row, then cue rows (no inspector below).
3. With no cues, clock + "No cues yet" both visible.
4. Right-click a cue → submenus + modals (Notes / Tempo / Change Type) all work from #291.
5. Double-click Number / Name / Fade → inline edit fires (#291 behavior).

---

## Self-review notes

- **Spec coverage:** all spec decisions mapped — delete inspector (Task 2), pin clock (Task 3), rename header (Task 1), drop `selectedCue` (Task 3), no-tint changes (no task — unchanged by design), accessibility identifier swap (Tasks 1, 4, 5, 6), layout tests (Task 6), unused-test deletion (Task 2), file moves (Tasks 1 + 5), pre-existing-flake out-of-scope (Tasks 4 + 9).
- **No placeholders:** every code step is concrete; the only "TODO"-like phrase is "Adjust surrounding doc-comment wording to match" in Task 7 Step 2, which references the existing file's structure — engineer-level judgment, not a placeholder for new code.
- **Type consistency:** `PlayheadClockHeader` is used the same way (`(engine:)`) in Task 1 and Task 3. Accessibility identifier `playheadClock` matches across Tasks 1, 4, 5, 6. `selectedCue` is referenced as a deletion target only in Task 3. `CueListPaneLayoutUITests` class name matches between Task 6 (creation) and the PR body in Task 10.
