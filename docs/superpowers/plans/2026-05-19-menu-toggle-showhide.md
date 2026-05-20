# Menu Toggle Show/Hide Verb Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the four checkable menu `Toggle`s to state-flipping `Button`s so they no longer carry the native checkmark-column indentation, with zero behavior change.

**Architecture:** Single declarative SwiftUI `Commands` file (`OnlyCue/App/AppCommands.swift`). Each `Toggle("X", isOn: $flag)` becomes `Button(flag ? "<on title>" : "<off title>") { flag.toggle() }`, keeping the same `.keyboardShortcut(...)`. A UITest in `MenuBarReorganizationUITests` is extended to lock the state-flipping behavior.

**Tech Stack:** Swift 6, SwiftUI `Commands`, XCUITest, xcodegen.

Spec: `docs/superpowers/specs/2026-05-19-menu-toggle-showhide-design.md`

---

### Task 1: Extend the UITest (failing-first)

**Files:**

- Modify: `OnlyCueUITests/MenuBarReorganizationUITests.swift`

- [ ] **Step 1: Add a new test asserting the state-flipping verb**

Append this method to `final class MenuBarReorganizationUITests` in
`OnlyCueUITests/MenuBarReorganizationUITests.swift`, immediately after the
existing `test_pauseAtEachCue_isUnderPlaybackMenu()` method (before the
`private func launchSeeded()` helper):

```swift
    func test_viewMenuToggles_useShowHideVerb_andFlipOnClick() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let viewBarItem = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewBarItem.waitForExistence(timeout: 5))
        viewBarItem.click()

        let viewMenu = viewBarItem.menus.firstMatch
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 3))
        // Default seeded state: all flags off -> "Show ..." titles.
        XCTAssertTrue(viewMenu.menuItems["Show Notes Overlay"].exists)
        XCTAssertTrue(viewMenu.menuItems["Show Timeline Breakdown"].exists)
        XCTAssertTrue(viewMenu.menuItems["Show Tempo Grid"].exists)

        // Click Show Tempo Grid; it must flip to the Hide verb.
        viewMenu.menuItems["Show Tempo Grid"].click()
        viewBarItem.click()
        let viewMenu2 = viewBarItem.menus.firstMatch
        XCTAssertTrue(viewMenu2.waitForExistence(timeout: 3))
        XCTAssertTrue(viewMenu2.menuItems["Hide Tempo Grid"].exists)
        XCTAssertFalse(viewMenu2.menuItems["Show Tempo Grid"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
```

Do not modify `test_pauseAtEachCue_isUnderPlaybackMenu` or
`test_viewMenu_noLongerContainsCueEditingItems`; they still pass because the
default seeded state is off (off-state titles are unchanged strings).

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: `OnlyCue.xcodeproj` regenerated, no errors.

- [ ] **Step 3: Build the test target to confirm it compiles**

Run:

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "TEST BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** TEST BUILD SUCCEEDED **`.

Note on red phase: local UITest execution is blocked by a macOS TCC
automation-mode timeout on this machine, so the failing run is observed on CI
after push, not locally (same constraint as PRs #299/#301). The new test is
red against the current code because `Show Tempo Grid` is currently a
checkable `Toggle` whose title never changes to `Hide Tempo Grid`; Task 2
turns it green.

- [ ] **Step 4: Commit the failing test**

```bash
git add OnlyCueUITests/MenuBarReorganizationUITests.swift
git commit -m "test(ui): assert View menu toggles use state-flipping verb"
```

---

### Task 2: Convert the View-menu toggles to Buttons

**Files:**

- Modify: `OnlyCue/App/AppCommands.swift`

- [ ] **Step 1: Replace the three View `Toggle`s**

In `OnlyCue/App/AppCommands.swift`, inside `CommandGroup(after: .sidebar)`,
replace this block:

```swift
            Toggle("Show Notes Overlay", isOn: $showNotesOverlay)
                .keyboardShortcut(shortcut(.toggleNotesOverlay))

            Toggle("Show Timeline Breakdown", isOn: $showTimelineBreakdown)
                .keyboardShortcut(shortcut(.toggleTimelineBreakdown))

            Toggle("Show Tempo Grid", isOn: $showTempoGrid)
                .keyboardShortcut(shortcut(.toggleTempoGrid))
```

with:

```swift
            Button(showNotesOverlay ? "Hide Notes Overlay" : "Show Notes Overlay") {
                showNotesOverlay.toggle()
            }
            .keyboardShortcut(shortcut(.toggleNotesOverlay))

            Button(showTimelineBreakdown ? "Hide Timeline Breakdown" : "Show Timeline Breakdown") {
                showTimelineBreakdown.toggle()
            }
            .keyboardShortcut(shortcut(.toggleTimelineBreakdown))

            Button(showTempoGrid ? "Hide Tempo Grid" : "Show Tempo Grid") {
                showTempoGrid.toggle()
            }
            .keyboardShortcut(shortcut(.toggleTempoGrid))
```

- [ ] **Step 2: Build to confirm it compiles**

Run:

```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/App/AppCommands.swift
git commit -m "feat(menu): View toggles use Show/Hide verb buttons (de-indent)"
```

---

### Task 3: Convert the Playback "Pause at Each Cue" toggle

**Files:**

- Modify: `OnlyCue/App/AppCommands.swift`

- [ ] **Step 1: Replace the Playback `Toggle`**

In `OnlyCue/App/AppCommands.swift`, inside `CommandMenu("Playback")`, replace:

```swift
            Toggle("Pause at Each Cue", isOn: $pauseAtEachCue)
                .keyboardShortcut(shortcut(.togglePauseAtEachCue))
```

with:

```swift
            Button(pauseAtEachCue ? "Don't Pause at Each Cue" : "Pause at Each Cue") {
                pauseAtEachCue.toggle()
            }
            .keyboardShortcut(shortcut(.togglePauseAtEachCue))
```

- [ ] **Step 2: Build to confirm it compiles**

Run:

```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: SwiftLint**

Run: `swiftlint lint --quiet OnlyCue/App/AppCommands.swift`
Expected: no violations (exit 0).

- [ ] **Step 4: Run the local-verifiable gate (unit suite)**

Run:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueTests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/App/AppCommands.swift
git commit -m "feat(menu): Pause at Each Cue uses state-flipping button"
```

---

### Task 4: CI verification (UITest gate)

**Files:** none modified.

- [ ] **Step 1: Push and watch CI**

The branch is pushed via the PR workflow (handled by the orchestrating
skill). CI runs the full `xcodebuild test` including `OnlyCueUITests` on a
provisioned macOS runner — the authoritative gate for the new UITest, since
local UITest execution is TCC-blocked.

Run (after the PR exists):

```bash
gh pr checks <PR_NUMBER> --watch
```

Expected: `Build & test (macOS)  pass`. `test_viewMenuToggles_useShowHideVerb_andFlipOnClick`
passes (Show titles in default state; flips to `Hide Tempo Grid` after click)
and the unchanged `test_pauseAtEachCue_isUnderPlaybackMenu` /
`test_viewMenu_noLongerContainsCueEditingItems` stay green.

- [ ] **Step 2: If CI is red**

Read the failure (`gh run view <RUN_ID> --log-failed`), return to the
relevant task, fix, recommit, re-push, re-watch. Do not advance until green.

- [ ] **Step 3: No commit** (verification-only task).

---

## Self-Review

**Spec coverage:**

- 3 View toggles → state-flipping Show/Hide buttons → Task 2 Step 1. ✓
- Playback `Pause at Each Cue` → `Don't Pause at Each Cue` button → Task 3
  Step 1. ✓
- `@AppStorage` keys / shortcuts / behavior unchanged → same
  `shortcut(.toggleNotesOverlay/.toggleTimelineBreakdown/.toggleTempoGrid/.togglePauseAtEachCue)`
  reproduced verbatim; `.toggle()` mutates the same property; no property
  declarations changed. ✓
- No frozen-label breakage → existing tests untouched (Task 1 Step 1 note);
  new test added. ✓
- Local TCC blocker / CI is the UITest gate → Task 1 Step 3 and Task 4. ✓

**Placeholder scan:** No TBD/TODO; all code shown verbatim. `<PR_NUMBER>` /
`<RUN_ID>` are runtime values supplied by the PR workflow, not plan
placeholders. ✓

**Type consistency:** Property names `showNotesOverlay`,
`showTimelineBreakdown`, `showTempoGrid`, `pauseAtEachCue` and keymap actions
`.toggleNotesOverlay`, `.toggleTimelineBreakdown`, `.toggleTempoGrid`,
`.togglePauseAtEachCue` match the current `AppCommands.swift` declarations
exactly. The UITest references the off-state strings (`Show Notes Overlay`,
`Show Timeline Breakdown`, `Show Tempo Grid`, `Pause at Each Cue`) and the
flipped string `Hide Tempo Grid`, all consistent with Task 2 / Task 3. ✓
