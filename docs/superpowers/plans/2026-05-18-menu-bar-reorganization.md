# Menu Bar Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move cue-editing commands out of the View menu into a new top-level `Cue` menu, relocate `Pause at Each Cue` into the `Playback` menu, and shorten the cue command labels — with zero behavior change.

**Architecture:** Single declarative SwiftUI `Commands` file (`OnlyCue/App/AppCommands.swift`). A new `CommandMenu("Cue")` is added between the View `CommandGroup` and the `Playback` `CommandMenu`; the six snap/duplicate/nudge buttons and the pause toggle are deleted from `CommandGroup(after: .sidebar)`; the pause toggle is re-added inside `CommandMenu("Playback")`. A new UITest locks the structure.

**Tech Stack:** Swift 6, SwiftUI `Commands`, XCUITest, xcodegen.

Spec: `docs/superpowers/specs/2026-05-18-menu-bar-reorganization-design.md`

---

### Task 1: Failing UITest for the new menu structure

**Files:**

- Create: `OnlyCueUITests/MenuBarReorganizationUITests.swift`

- [ ] **Step 1: Write the failing test**

Model on the existing `PlaybackSpeedUITests` pattern (`launchSeeded()` /
`waitForSeedWindow(in:)` are shared XCTestCase helpers already available to the
UITest target — `PlaybackSpeedUITests` uses them without redeclaring the
`waitForSeedWindow` helper). Create `OnlyCueUITests/MenuBarReorganizationUITests.swift`:

```swift
import XCTest

final class MenuBarReorganizationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_cueMenu_existsWithRenamedCueCommands() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let cueMenu = app.menuBars.menuBarItems["Cue"]
        XCTAssertTrue(cueMenu.waitForExistence(timeout: 5))
        cueMenu.click()

        XCTAssertTrue(app.menuItems["Duplicate at Playhead"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Nudge Back"].exists)
        XCTAssertTrue(app.menuItems["Nudge Forward"].exists)
        XCTAssertTrue(app.menuItems["Snap to Playhead"].exists)
        XCTAssertTrue(app.menuItems["Snap to Nearest Beat"].exists)
        XCTAssertTrue(app.menuItems["Snap to Nearest Bar"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_pauseAtEachCue_isUnderPlaybackMenu() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let playbackMenu = app.menuBars.menuBarItems["Playback"]
        XCTAssertTrue(playbackMenu.waitForExistence(timeout: 5))
        playbackMenu.click()
        XCTAssertTrue(app.menuItems["Pause at Each Cue"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_viewMenu_noLongerContainsCueEditingItems() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 5))
        viewMenu.click()
        XCTAssertFalse(app.menuItems["Snap to Playhead"].exists)
        XCTAssertFalse(app.menuItems["Snap Selected Cue to Playhead"].exists)
        XCTAssertFalse(app.menuItems["Pause at Each Cue"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            SeedKey.threeCuesAt1And3And6.launchArgument
        ]
        app.launch()
        return app
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new test file is picked up**

Run: `xcodegen generate`
Expected: `OnlyCue.xcodeproj` regenerated, no errors. (Folder-rule based
`sources` in `project.yml` picks up the new file automatically.)

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/MenuBarReorganizationUITests 2>&1 | tail -30
```

Expected: FAIL — `test_cueMenu_existsWithRenamedCueCommands` and
`test_pauseAtEachCue_isUnderPlaybackMenu` fail because there is no `Cue`
menu and `Pause at Each Cue` is still under View;
`test_viewMenu_noLongerContainsCueEditingItems` fails because the items are
still in View.

- [ ] **Step 4: Commit the failing test**

```bash
git add OnlyCueUITests/MenuBarReorganizationUITests.swift
git commit -m "test(ui): assert Cue menu and Playback-hosted pause toggle"
```

---

### Task 2: Reorganize AppCommands — add Cue menu, move pause toggle, trim View

**Files:**

- Modify: `OnlyCue/App/AppCommands.swift`

- [ ] **Step 1: Remove the cue-editing block and pause toggle from the View `CommandGroup`**

In `CommandGroup(after: .sidebar)`, delete everything from the `Divider()` that
precedes `Toggle("Pause at Each Cue", …)` through the end of the
`CommandGroup` (the pause toggle, the following `Divider()`, and all six
snap/duplicate/nudge buttons). The block to delete is exactly:

```swift
            Divider()

            Toggle("Pause at Each Cue", isOn: $pauseAtEachCue)
                .keyboardShortcut(shortcut(.togglePauseAtEachCue))

            Divider()

            Button("Snap Selected Cue to Playhead") {
                NotificationCenter.default.post(name: .snapSelectedCueToPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCueToPlayhead))

            Button("Snap Selected Cues to Nearest Beat") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBeat, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBeat))

            Button("Snap Selected Cues to Nearest Bar") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBar, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBar))

            Button("Duplicate Cue at Playhead") {
                NotificationCenter.default.post(name: .duplicateSelectedCueAtPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.duplicateCueAtPlayhead))

            Button("Nudge Selected Cue Back") {
                NotificationCenter.default.post(name: .nudgeSelectedCueBack, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueBack))

            Button("Nudge Selected Cue Forward") {
                NotificationCenter.default.post(name: .nudgeSelectedCueForward, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueForward))
```

After deletion, the `Toggle("Show Tempo Grid", …)` line is the last statement
in `CommandGroup(after: .sidebar)` (its closing `}` immediately follows).

- [ ] **Step 2: Add the new `CommandMenu("Cue")` before `CommandMenu("Playback")`**

Insert this block immediately before the existing `CommandMenu("Playback") {`
line:

```swift
        CommandMenu("Cue") {
            Button("Duplicate at Playhead") {
                NotificationCenter.default.post(name: .duplicateSelectedCueAtPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.duplicateCueAtPlayhead))

            Button("Nudge Back") {
                NotificationCenter.default.post(name: .nudgeSelectedCueBack, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueBack))

            Button("Nudge Forward") {
                NotificationCenter.default.post(name: .nudgeSelectedCueForward, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueForward))

            Divider()

            Button("Snap to Playhead") {
                NotificationCenter.default.post(name: .snapSelectedCueToPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCueToPlayhead))

            Button("Snap to Nearest Beat") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBeat, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBeat))

            Button("Snap to Nearest Bar") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBar, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBar))
        }
```

- [ ] **Step 3: Add the pause toggle to `CommandMenu("Playback")`**

Inside `CommandMenu("Playback")`, after the `Button("Reset Speed") { … }
.disabled(ltcOn)` (the last existing statement, ending with its
`.disabled(ltcOn)` modifier), append:

```swift

            Divider()

            Toggle("Pause at Each Cue", isOn: $pauseAtEachCue)
                .keyboardShortcut(shortcut(.togglePauseAtEachCue))
```

The `@AppStorage("pauseAtEachCue") private var pauseAtEachCue = false`
property at the top of the struct is unchanged.

- [ ] **Step 4: Build to confirm it compiles**

Run:

```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Run the new UITest suite to verify it passes**

Run:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/MenuBarReorganizationUITests 2>&1 | tail -20
```

Expected: PASS — all three tests green.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/App/AppCommands.swift
git commit -m "feat(menu): add Cue menu, move Pause toggle to Playback, slim View"
```

---

### Task 3: Regression — full UITest + lint

**Files:** none modified.

- [ ] **Step 1: Run the menu-title-dependent UITests to confirm no regression**

Run:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/PlaybackSpeedUITests \
  -only-testing:OnlyCueUITests/NewFromTemplateMenuTests 2>&1 | tail -20
```

Expected: PASS — frozen labels (`Speed Up`/`Slow Down`/`Reset Speed`,
`New from Template…`) untouched, so these stay green.

- [ ] **Step 2: SwiftLint**

Run: `swiftlint lint --quiet OnlyCue/App/AppCommands.swift`
Expected: no violations.

- [ ] **Step 3: Full test suite**

Run:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 4: Manual smoke check (cannot be automated for shortcuts)**

Launch the app. Verify: (a) `Cue` menu appears between `View` and `Playback`
with the six renamed items; (b) each fires its action and its keyboard
shortcut still works; (c) `Pause at Each Cue` under `Playback` toggles and
persists across relaunch; (d) `View` no longer shows cue-editing items. State
explicitly in the PR whether manual verification was performed.

- [ ] **Step 5: No commit** (verification-only task; nothing changed).

---

## Self-Review

**Spec coverage:**

- New `Cue` menu with 6 items + divider → Task 2 Step 2. ✓
- `Pause at Each Cue` → Playback → Task 2 Step 3. ✓
- Cue-edit + pause removed from View → Task 2 Step 1. ✓
- Six label renames → encoded verbatim in Task 2 Step 2 button titles. ✓
- Shortcuts/notifications/AppStorage preserved → same `shortcut(...)` calls and
  `NotificationCenter` names reused verbatim; `@AppStorage` untouched. ✓
- Frozen UI-test labels preserved → Task 3 Step 1 regression gate. ✓
- New TDD UITest → Task 1. ✓

**Placeholder scan:** No TBD/TODO; all code shown verbatim. ✓

**Type consistency:** Notification names (`.duplicateSelectedCueAtPlayhead`,
`.nudgeSelectedCueBack`, `.nudgeSelectedCueForward`, `.snapSelectedCueToPlayhead`,
`.snapSelectedCuesToBeat`, `.snapSelectedCuesToBar`, `.togglePauseAtEachCue`)
and keymap actions match the originals in the current `AppCommands.swift`
exactly — only `Button`/`Toggle` label strings change. ✓
