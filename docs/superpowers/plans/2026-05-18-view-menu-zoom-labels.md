# View Menu Zoom-Label Disambiguation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the three horizontal-zoom items in the View menu so they state their axis, mirroring the vertical group — zero behavior change.

**Architecture:** Single declarative SwiftUI `Commands` file (`OnlyCue/App/AppCommands.swift`); three `Button` label strings change inside `CommandGroup(after: .sidebar)`. One UITest assertion in `MenuBarReorganizationUITests` is updated and the suite is extended to lock both axis groups.

**Tech Stack:** Swift 6, SwiftUI `Commands`, XCUITest, xcodegen.

Spec: `docs/superpowers/specs/2026-05-18-view-menu-zoom-labels-design.md`

---

### Task 1: Update + extend the UITest (failing-first)

**Files:**
- Modify: `OnlyCueUITests/MenuBarReorganizationUITests.swift`

- [ ] **Step 1: Update the sanity assertion and add the parallel-group assertions**

In `OnlyCueUITests/MenuBarReorganizationUITests.swift`, inside
`test_viewMenu_noLongerContainsCueEditingItems`, replace this line (currently
line 49):

```swift
        XCTAssertTrue(viewMenu.menuItems["Zoom In"].exists)
```

with:

```swift
        XCTAssertTrue(viewMenu.menuItems["Zoom In Horizontally"].exists)
        XCTAssertTrue(viewMenu.menuItems["Zoom In Vertically"].exists)
        XCTAssertFalse(viewMenu.menuItems["Zoom In"].exists)
```

Leave every other line in the file unchanged (the `XCTAssertFalse` cue/pause
assertions that follow stay exactly as they are).

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
after push, not locally (same constraint as PR #299). The assertion
`XCTAssertTrue(viewMenu.menuItems["Zoom In Horizontally"].exists)` is red
against the current code because the button is still titled `Zoom In`; Task 2
turns it green.

- [ ] **Step 4: Commit the failing test**

```bash
git add OnlyCueUITests/MenuBarReorganizationUITests.swift
git commit -m "test(ui): assert View menu zoom items state their axis"
```

---

### Task 2: Rename the three horizontal-zoom labels

**Files:**
- Modify: `OnlyCue/App/AppCommands.swift`

- [ ] **Step 1: Rename `Zoom In`**

In `OnlyCue/App/AppCommands.swift`, inside `CommandGroup(after: .sidebar)`,
change:

```swift
            Button("Zoom In") {
                NotificationCenter.default.post(name: .waveformZoomIn, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomIn))
```

to:

```swift
            Button("Zoom In Horizontally") {
                NotificationCenter.default.post(name: .waveformZoomIn, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomIn))
```

- [ ] **Step 2: Rename `Zoom Out`**

Change:

```swift
            Button("Zoom Out") {
                NotificationCenter.default.post(name: .waveformZoomOut, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomOut))
```

to:

```swift
            Button("Zoom Out Horizontally") {
                NotificationCenter.default.post(name: .waveformZoomOut, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomOut))
```

- [ ] **Step 3: Rename `Actual Size`**

Change:

```swift
            Button("Actual Size") {
                NotificationCenter.default.post(name: .waveformZoomReset, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomReset))
```

to:

```swift
            Button("Actual Horizontal Size") {
                NotificationCenter.default.post(name: .waveformZoomReset, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomReset))
```

Do not touch the vertical group (`Zoom In Vertically`,
`Zoom Out Vertically`, `Actual Vertical Size`), the dividers, or the three
display toggles.

- [ ] **Step 4: Build to confirm it compiles**

Run:
```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint --quiet OnlyCue/App/AppCommands.swift`
Expected: no violations (exit 0).

- [ ] **Step 6: Run the local-verifiable gate (unit suite)**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' -only-testing:OnlyCueTests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/App/AppCommands.swift
git commit -m "feat(menu): disambiguate View menu horizontal-zoom labels"
```

---

### Task 3: CI verification (UITest gate)

**Files:** none modified.

- [ ] **Step 1: Push and watch CI**

The branch is pushed via the PR workflow (handled by the orchestrating
skill). CI runs the full `xcodebuild test` including `OnlyCueUITests` on a
provisioned macOS runner — this is the authoritative gate for the renamed
UITest assertions, since local UITest execution is TCC-blocked.

Run (after the PR exists):
```bash
gh pr checks <PR_NUMBER> --watch
```
Expected: `Build & test (macOS)  pass`. The updated
`test_viewMenu_noLongerContainsCueEditingItems` now passes because
`Zoom In Horizontally` and `Zoom In Vertically` exist and the bare `Zoom In`
does not.

- [ ] **Step 2: If CI is red**

Read the failure (`gh run view <RUN_ID> --log-failed`), return to the
relevant task, fix, recommit, re-push, re-watch. Do not advance until green.

- [ ] **Step 3: No commit** (verification-only task).

---

## Self-Review

**Spec coverage:**
- Three horizontal-zoom renames (`Zoom In/Out Horizontally`,
  `Actual Horizontal Size`) → Task 2 Steps 1–3. ✓
- Vertical group / toggles / dividers unchanged → explicit "do not touch" in
  Task 2 Step 3. ✓
- Shortcuts + notification names preserved → same `shortcut(...)` and
  `NotificationCenter` lines reproduced verbatim in Task 2. ✓
- Update the one dependent assertion at
  `MenuBarReorganizationUITests.swift:49` → Task 1 Step 1. ✓
- Extend the suite to assert both axis groups labeled → Task 1 Step 1
  (`Zoom In Horizontally` + `Zoom In Vertically` present, bare `Zoom In`
  absent). ✓
- Local TCC blocker / CI is the UITest gate → noted in Task 1 Step 3 and
  Task 3. ✓

**Placeholder scan:** No TBD/TODO; all code shown verbatim;
`<PR_NUMBER>`/`<RUN_ID>` are runtime values supplied by the PR workflow, not
plan placeholders. ✓

**Type consistency:** Notification names (`.waveformZoomIn`,
`.waveformZoomOut`, `.waveformZoomReset`) and keymap actions match the current
`AppCommands.swift` exactly — only the three `Button` label strings change. The
UITest references the new strings `"Zoom In Horizontally"` /
`"Zoom In Vertically"` exactly as written in Task 2 / the existing code. ✓
