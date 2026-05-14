# Transport Bar Declutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declutter the bottom of the Main Pane: remove the Play/Pause button, the Add Cue button, the `Last:` readout, and the `Pause: each cue` indicator; gate the SMPTE readout on LTC output being enabled in Settings and prefix it with `SMPTE`.

**Architecture:** Two-file UI change in `OnlyCue/UI/TransportBar.swift` and `OnlyCue/UI/DocumentView.swift`. No schema change, no command layer change. The `A` (Add Cue) shortcut is preserved by adding a hidden command into `DocumentView`'s existing `transportShortcuts` pattern. UI tests that use `playPauseButton` as a "document loaded" sentinel are migrated to `currentTimeReadout` as a preliminary refactor so the button removal doesn't cascade across the test suite.

**Tech Stack:** Swift 6, SwiftUI, XCTest + XCUIApplication, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-05-14-transport-bar-declutter-design.md`

---

## File Map

**Modify:**
- `OnlyCue/UI/TransportBar.swift` — primary view changes (remove Play button, gate SMPTE, drop `Last:`, drop `Pause: each cue` indicator + `@AppStorage`).
- `OnlyCue/UI/DocumentView.swift` — remove the standalone `Button("Add Cue")` (lines 94-97); add a hidden Add Cue button inside `transportShortcuts` to preserve the keyboard shortcut.
- `OnlyCueUITests/TransportBarScreenshotTests.swift` — rewrite assertions for the LTC-off default (no `smpteTimecode`, no `playPauseButton`) and re-baseline the screenshot.
- 10 UI test files using `app.buttons["playPauseButton"]` as a "document loaded" sentinel — migrate to `app.staticTexts["currentTimeReadout"]`:
  `MainViewDeclutterUITests.swift`, `AudioSettingsUITests.swift`, `AudioSettingsScreenshotTests.swift`, `TempoGridOverlayScreenshotTests.swift`, `DocumentLaunchTests.swift`, `KeyboardSettingsScreenshotTests.swift`, `ExportSheetScreenshotTests.swift`, `OSCMonitorScreenshotTests.swift`, `OSCSettingsScreenshotTests.swift`, `TimecodeSettingsSheetScreenshotTests.swift`.

**Delete:**
- `OnlyCueTests/LastCueElapsedTests.swift` — covers the `TransportBar.lastCueElapsed` helper being removed.

**Untouched:**
- `OnlyCue/App/Keymap.swift`, `OnlyCue/App/KeymapAction.swift` — bindings for `.addCue` and `.playPause` remain as-is.
- `OnlyCue/LTC/LTCRoutingStore.swift`, `OnlyCue/LTC/LTCRoutingSettings.swift` — read-only consumer; no changes.
- `OnlyCue/UI/DocumentShortcutHints.swift` — the hint text still references `.addCue`; remains valid.

---

## Task 1: Migrate UI test "document loaded" sentinel to `currentTimeReadout`

`playPauseButton` is removed in Task 3. Eleven UI tests rely on its existence as a check that the document window finished opening. We migrate them first so Task 3's removal does not cascade. `currentTimeReadout` is the always-on HMS `staticText` (already exists at TransportBar.swift:90) and survives every later change in this plan.

**Files:**
- Modify (replace `app.buttons["playPauseButton"]` with `app.staticTexts["currentTimeReadout"]` and adjust assertion messages):
  - `OnlyCueUITests/MainViewDeclutterUITests.swift:19`
  - `OnlyCueUITests/AudioSettingsUITests.swift:17`
  - `OnlyCueUITests/AudioSettingsScreenshotTests.swift:24-25`
  - `OnlyCueUITests/TempoGridOverlayScreenshotTests.swift:22`
  - `OnlyCueUITests/DocumentLaunchTests.swift:22`
  - `OnlyCueUITests/KeyboardSettingsScreenshotTests.swift:23-24`
  - `OnlyCueUITests/ExportSheetScreenshotTests.swift:22-25` (uses an extracted `playPauseButton` variable — rename to `timeReadout`)
  - `OnlyCueUITests/OSCMonitorScreenshotTests.swift:25-28` (same pattern)
  - `OnlyCueUITests/OSCSettingsScreenshotTests.swift:25-26`
  - `OnlyCueUITests/TimecodeSettingsSheetScreenshotTests.swift:25-26`
  - `OnlyCueUITests/TransportBarScreenshotTests.swift:31-34` — *also* affected; Task 7 rewrites this file more thoroughly, so for Task 1 just do the minimal sentinel swap to keep the suite green between Task 1 and Task 7.

- [ ] **Step 1: Run the existing UI suite to confirm green starting state**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests -destination 'platform=macOS' | tail -40
```
Expected: All UI tests pass. (If `OnlyCue.xcodeproj` is absent, run `xcodegen generate` first per `CLAUDE.md`.)

- [ ] **Step 2: Replace the sentinel in `MainViewDeclutterUITests.swift`**

Open `OnlyCueUITests/MainViewDeclutterUITests.swift`. At lines 18–21 the file currently reads:

```swift
XCTAssertTrue(
    app.buttons["playPauseButton"].waitForExistence(timeout: 10),
    "document window should open within 10s of ⌘N"
)
```

Replace with:

```swift
XCTAssertTrue(
    app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 10),
    "document window should open within 10s of ⌘N"
)
```

- [ ] **Step 3: Replace the sentinel in the remaining nine files**

Apply the same swap (`app.buttons["playPauseButton"]` → `app.staticTexts["currentTimeReadout"]`) in each of these files. Where the file extracts a variable named `playPauseButton` (e.g. `ExportSheetScreenshotTests.swift:22`, `OSCMonitorScreenshotTests.swift:25`, `TransportBarScreenshotTests.swift:31`), rename the variable to `timeReadout`. Where the assertion message contains the literal string `"playPauseButton"`, replace with `"currentTimeReadout"`.

Files to edit (left-as-found in the grep output):
- `AudioSettingsUITests.swift`
- `AudioSettingsScreenshotTests.swift`
- `TempoGridOverlayScreenshotTests.swift`
- `DocumentLaunchTests.swift`
- `KeyboardSettingsScreenshotTests.swift`
- `ExportSheetScreenshotTests.swift`
- `OSCMonitorScreenshotTests.swift`
- `OSCSettingsScreenshotTests.swift`
- `TimecodeSettingsSheetScreenshotTests.swift`
- `TransportBarScreenshotTests.swift` (sentinel only; full rewrite happens in Task 7)

- [ ] **Step 4: Run the UI suite to confirm still green**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests -destination 'platform=macOS' | tail -40
```
Expected: All UI tests still pass — the sentinel swap is behaviour-neutral because both elements appear at the same lifecycle point.

- [ ] **Step 5: Commit**

```bash
git add OnlyCueUITests/
git commit -m "refactor(uitests): use currentTimeReadout as document-loaded sentinel"
```

---

## Task 2: TDD — gate the SMPTE readout on LTC output, and label it `SMPTE`

The only piece of new behaviour in this plan. Drive it test-first: by default (fresh launch) `LTCRoutingStore.shared.settings.isEnabled == false`, so the `smpteTimecode` static text must not appear. Write that assertion as a failing UI test, watch it fail (the current code unconditionally renders SMPTE), then add the gate and the `SMPTE ` label prefix.

**Files:**
- Create: `OnlyCueUITests/TransportBarSMPTEGatingUITests.swift`
- Modify: `OnlyCue/UI/TransportBar.swift:1-124`

- [ ] **Step 1: Write the failing UI test**

Create `OnlyCueUITests/TransportBarSMPTEGatingUITests.swift` with this content:

```swift
import XCTest

/// Verifies the SMPTE readout in TransportBar is hidden when LTC output is
/// disabled in Settings (the fresh-launch default). The companion `LTC-on`
/// path is covered manually — toggling LTCRoutingStore from a UI test would
/// require driving Settings, which is out of scope for this gating check.
final class TransportBarSMPTEGatingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_smpteReadout_hiddenByDefault_whenLTCOutputDisabled() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        // Sanity: document opened.
        XCTAssertTrue(
            app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 10),
            "document window should open within 10s of ⌘N"
        )

        // The gate under test: with LTCRoutingStore.shared.settings.isEnabled
        // == false (fresh-launch default), the SMPTE readout must be hidden.
        XCTAssertFalse(
            app.staticTexts["smpteTimecode"].exists,
            "smpteTimecode must be hidden when LTC output is disabled"
        )
    }
}
```

- [ ] **Step 2: Add the new file to `project.yml` if needed**

`project.yml` uses folder-based source rules; new files under `OnlyCueUITests/` are picked up automatically. Regenerate the Xcode project:

```bash
xcodegen generate
```

- [ ] **Step 3: Run the new test and confirm it fails**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests/TransportBarSMPTEGatingUITests -destination 'platform=macOS' | tail -20
```
Expected: FAIL with `smpteTimecode must be hidden when LTC output is disabled` — the SMPTE `Text` is currently unconditional in `TransportBar.swift:92-96`.

- [ ] **Step 4: Add the LTC-routing gate and `SMPTE ` label to `TransportBar.swift`**

Open `OnlyCue/UI/TransportBar.swift`. Two changes:

(a) Add an `@ObservedObject` for the routing store at the top of the struct, alongside the existing `@Environment(\.stripedTimecode)` declaration (around line 17). Insert after line 18 (the existing `@AppStorage` line):

```swift
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared
```

(b) Replace the SMPTE `Text` block (currently lines 92-96):

```swift
            Text(smpteReadout)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("smpteTimecode")
                .help(smpteReadoutHelp)
```

with the gated, labeled version:

```swift
            if ltcRoutingStore.settings.isEnabled {
                Text("SMPTE \(smpteReadout)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("smpteTimecode")
                    .help(smpteReadoutHelp)
            }
```

- [ ] **Step 5: Run the new test and confirm it passes**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests/TransportBarSMPTEGatingUITests -destination 'platform=macOS' | tail -20
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift OnlyCueUITests/TransportBarSMPTEGatingUITests.swift OnlyCue.xcodeproj
git commit -m "feat(ui): gate SMPTE readout on LTC output and label it \"SMPTE\""
```

(If `OnlyCue.xcodeproj` is in `.gitignore` per `CLAUDE.md`, omit it from the `git add` — only the regenerated `project.yml`-driven content is tracked. Verify with `git status` before committing.)

---

## Task 3: Remove the Play/Pause button from TransportBar

The Space shortcut for play/pause is already wired through the hidden `transportShortcuts` block in `DocumentView.swift:212-213` (independent of the visible button), so deleting the visible button does not break the shortcut.

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift:75-86`

- [ ] **Step 1: Delete the Play/Pause `Button` block**

Open `OnlyCue/UI/TransportBar.swift`. Inside `body`'s `HStack` (currently lines 76-86), remove the entire Play/Pause button:

```swift
            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.rate > 0 ? "pause.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
            .accessibilityIdentifier("playPauseButton")
            .accessibilityLabel(engine.rate > 0 ? "Pause" : "Play")
            .help("Play / Pause (Space)")
```

After deletion, `body` starts directly with `HStack(spacing: 12) { Text(timeReadout) ... }`.

- [ ] **Step 2: Build and confirm the project compiles**

Run:
```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the UI suite to verify Space still toggles playback and no test references the removed identifier**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests -destination 'platform=macOS' | tail -40
```
Expected: All UI tests pass. (Task 7 rewrites `TransportBarScreenshotTests`; for now it still passes because Task 1 already swapped its sentinel away from `playPauseButton`.)

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift
git commit -m "refactor(ui): remove play/pause button from transport bar"
```

---

## Task 4: Remove the Add Cue button and re-home its keyboard shortcut

The `A`-equivalent shortcut (currently bound to whichever key `Keymap.swift` assigns to `.addCue`) lives only on the visible Button. Add a hidden `Button` inside the existing `transportShortcuts` `ZStack` so SwiftUI still registers the shortcut after the visible button is gone.

**Files:**
- Modify: `OnlyCue/UI/DocumentView.swift:94-97` (remove the visible button)
- Modify: `OnlyCue/UI/DocumentView.swift:210-222` (add hidden Add Cue Button to `transportShortcuts`)

- [ ] **Step 1: Add the hidden Add Cue button to `transportShortcuts`**

Open `OnlyCue/UI/DocumentView.swift`. The `transportShortcuts` computed property (currently lines 210-222) reads:

```swift
    private var transportShortcuts: some View {
        ZStack {
            Button("Play/Pause") { engine.toggle() }
                .keyboardShortcut(shortcut(.playPause))
            Button("Back 1s") { jump(by: -1) }
                .keyboardShortcut(shortcut(.jumpBack))
            Button("Forward 1s") { jump(by: 1) }
                .keyboardShortcut(shortcut(.jumpForward))
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
```

Replace with:

```swift
    private var transportShortcuts: some View {
        ZStack {
            Button("Play/Pause") { engine.toggle() }
                .keyboardShortcut(shortcut(.playPause))
            Button("Back 1s") { jump(by: -1) }
                .keyboardShortcut(shortcut(.jumpBack))
            Button("Forward 1s") { jump(by: 1) }
                .keyboardShortcut(shortcut(.jumpForward))
            Button("Add Cue") { addCueAtPlayhead() }
                .keyboardShortcut(shortcut(.addCue))
                .disabled(document.model.activeItem == nil)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
```

The `.disabled` modifier mirrors the visible button's previous behaviour (Add Cue was disabled when no media was loaded).

- [ ] **Step 2: Delete the visible Add Cue Button**

In the same file, remove lines 94-97:

```swift
            Button("Add Cue") { addCueAtPlayhead() }
                .accessibilityIdentifier("addCueButton")
                .keyboardShortcut(shortcut(.addCue))
                .disabled(activeItem == nil)
```

(The surrounding `VStack` now goes straight from `TransportBar(…)` to `transportShortcuts`.)

- [ ] **Step 3: Build and confirm the project compiles**

Run:
```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full test suite to confirm Add Cue shortcut still works**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' | tail -40
```
Expected: All tests pass. If any UI test imports media and presses the Add Cue shortcut, it should still succeed; if any test queries `app.buttons["addCueButton"]` explicitly, expect a failure here — grep `OnlyCueUITests` for `addCueButton` and update those assertions to query state changes rather than the (now-hidden) button. (As of writing, no such reference exists — verified by grep in plan preparation.)

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/DocumentView.swift
git commit -m "refactor(ui): remove add-cue button, keep shortcut via hidden command"
```

---

## Task 5: Remove the `Last:` readout, its helper, and its test file

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift` — remove `lastCueElapsed` static helper (currently lines 42-53) and its renderer (currently lines 98-103).
- Delete: `OnlyCueTests/LastCueElapsedTests.swift`

- [ ] **Step 1: Confirm there are no other callers of `lastCueElapsed`**

Run:
```bash
grep -rn "lastCueElapsed" OnlyCue OnlyCueTests OnlyCueUITests
```
Expected: only matches are inside `TransportBar.swift` and `LastCueElapsedTests.swift`. If any other caller exists, stop and report — the spec assumes none.

- [ ] **Step 2: Delete the renderer block from `TransportBar.swift`**

Remove lines 98-103 (the `if let interval = Self.lastCueElapsed(...) { ... }` block):

```swift
            if let interval = Self.lastCueElapsed(currentTime: engine.currentTime, cues: cues) {
                Text("Last: \(TimeFormat.compactCountdown(interval))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("lastCueElapsed")
            }
```

- [ ] **Step 3: Delete the `lastCueElapsed` static helper from `TransportBar.swift`**

Remove the helper (currently lines 42-53):

```swift
    /// Mirror of `nextCueInterval`: time elapsed since the most recent cue at
    /// `time <= currentTime`. Inclusive `<=` so a cue exactly at `currentTime`
    /// reads as "Last: 0.0s" (operator just hit it). Returns nil when no past
    /// cue exists. Like the forward helper, doesn't assume sortedness — `max()`
    /// picks the most recent regardless of input order.
    static func lastCueElapsed(currentTime: TimeInterval, cues: [Cue]) -> TimeInterval? {
        cues
            .map(\.time)
            .filter { $0 <= currentTime }
            .max()
            .map { currentTime - $0 }
    }
```

- [ ] **Step 4: Delete the test file**

```bash
git rm OnlyCueTests/LastCueElapsedTests.swift
```

- [ ] **Step 5: Regenerate the Xcode project**

```bash
xcodegen generate
```

- [ ] **Step 6: Run the unit suite to confirm it still compiles and passes**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests -destination 'platform=macOS' | tail -20
```
Expected: All unit tests pass; the deleted test no longer appears in the test list.

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift
git commit -m "refactor(ui): remove \"Last:\" elapsed readout and its helper"
```

---

## Task 6: Remove the `Pause: each cue` indicator and the `@AppStorage` from TransportBar

The `pauseAtEachCue` `@AppStorage` key continues to be written by the `⇧⌘P` toggle elsewhere; only the visual indicator in TransportBar is removed.

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift` — remove `@AppStorage("pauseAtEachCue")` (currently line 18) and the indicator block (currently lines 112-121).

- [ ] **Step 1: Delete the indicator block from `TransportBar.swift`**

Remove the `if pauseAtEachCue { ... }` block (currently lines 112-121):

```swift
            if pauseAtEachCue {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle")
                    Text("Pause: each cue")
                }
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pauseAtEachCueIndicator")
                .help("Toggle with ⇧⌘P")
            }
```

- [ ] **Step 2: Delete the `@AppStorage` property**

Remove line 18 (the property declaration `@AppStorage("pauseAtEachCue") private var pauseAtEachCue = false`).

- [ ] **Step 3: Confirm no other reference to `pauseAtEachCue` in `TransportBar.swift`**

Run:
```bash
grep -n "pauseAtEachCue" OnlyCue/UI/TransportBar.swift
```
Expected: no matches. (Other files in the codebase that own the toggle remain untouched — verify with `grep -rn "pauseAtEachCue" OnlyCue` if curious, but do not modify them in this plan.)

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift
git commit -m "refactor(ui): remove \"Pause: each cue\" indicator from transport bar"
```

---

## Task 7: Rewrite TransportBarScreenshotTests and re-baseline the screenshot

The existing baseline test asserts the presence of `playPauseButton` (already swapped to `currentTimeReadout` in Task 1) and `smpteTimecode`. With the new gating, `smpteTimecode` must be *absent* on fresh launch. Update the assertions, re-run the test to refresh the screenshot artifact, and confirm the artifact reflects the new bar.

**Files:**
- Modify: `OnlyCueUITests/TransportBarScreenshotTests.swift` — adjust assertions for the LTC-off default; keep the screenshot capture.

- [ ] **Step 1: Update the assertions in the baseline test**

Open `OnlyCueUITests/TransportBarScreenshotTests.swift`. After Task 1, the test already uses `timeReadout` / `currentTimeReadout` as its sentinel. Replace the SMPTE-presence assertion (currently around line 39-42, which asserts `app.staticTexts["smpteTimecode"]` exists) with an *absence* assertion that matches the new gating default:

```swift
        XCTAssertFalse(
            app.staticTexts["smpteTimecode"].exists,
            "the SMPTE readout must be hidden when LTC output is disabled (fresh-launch default)"
        )
```

Update the Gherkin comment immediately above the test method to match:

```swift
    /// Scenario: Transport bar renders on a fresh document with LTC output disabled
    /// Given the app is launched and an untitled document is opened
    /// And LTCRoutingStore.shared.settings.isEnabled is false (the fresh-launch default)
    /// Then the HMS time readout is visible
    /// And the SMPTE readout is hidden
    /// And a screenshot of the document window is captured for review.
```

- [ ] **Step 2: Run the baseline test to refresh the screenshot**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests/TransportBarScreenshotTests -destination 'platform=macOS' | tail -30
```
Expected: PASS. The runner logs a temp path containing `transport-bar-baseline.png`; open it and confirm visually:
- No Play/Pause button.
- No `Add Cue` button.
- No `Last:` readout.
- No `SMPTE …` readout.
- No `Pause: each cue` indicator.
- HMS clock + (if any cues) `Next: …` visible.

Run:
```bash
open "$(find /var/folders -name 'transport-bar-baseline.png' 2>/dev/null | head -n 1)"
```

- [ ] **Step 3: Commit**

```bash
git add OnlyCueUITests/TransportBarScreenshotTests.swift
git commit -m "test(ui): rebaseline transport-bar screenshot for declutter"
```

---

## Task 8: Final verification — full suite + manual UI walk

- [ ] **Step 1: Run the full test suite**

Run:
```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' | tail -50
```
Expected: All tests pass (units + UI + screenshot).

- [ ] **Step 2: Manual: LTC-off path**

Launch the app, open a new document, import a short media file.

Verify in the bottom of the Main Pane:
- HMS readout shows `current / total`.
- No Play/Pause button visible.
- No standalone Add Cue button visible.
- No `Last:` readout.
- No `SMPTE …` readout.
- No `Pause: each cue` indicator.
- Press Space → playback toggles.
- Press the `.addCue` shortcut (per `Keymap.swift`) → a cue is added at the playhead.
- Press `⇧⌘P` → the pause-at-each-cue behaviour still toggles (the cue runner honours the flag even though no indicator is shown); verify by playing past a cue with the toggle on, and confirming playback pauses there.

- [ ] **Step 3: Manual: LTC-on path**

Open Settings → enable LTC output. Return to the document window.

Verify:
- `SMPTE …` readout appears between the HMS clock and `Next:`.
- The SMPTE value updates frame-accurately as the playhead moves.
- Disable LTC output again → the SMPTE readout disappears.

- [ ] **Step 4: Confirm git history is clean and on a feature branch**

Run:
```bash
git log --oneline dev..HEAD
```
Expected output: 7 focused commits, one per task (Tasks 1–7). No `Co-Authored-By` trailers (per `CLAUDE.md`).

- [ ] **Step 5: Open the PR**

Hand off to the `gh:gh-pr` skill. The PR type is `refactor`. Use the OnlyCue forked template at `.github/PULL_REQUEST_TEMPLATE/refactor.md` per `CLAUDE.md`. The spec link for the verification footer is `docs/superpowers/specs/2026-05-14-transport-bar-declutter-design.md`.

---

## Self-Review

**Spec coverage check:**

| Spec item | Task |
|---|---|
| Remove Play/Pause button | Task 3 |
| Remove Add Cue button + preserve `A` shortcut (option b) | Task 4 |
| Remove `Last:` readout + helper | Task 5 |
| Remove `Pause: each cue` indicator | Task 6 |
| Gate SMPTE on `LTCRoutingStore.shared.settings.isEnabled` | Task 2 |
| Prefix SMPTE readout with `SMPTE ` | Task 2 |
| Update unit + UI + snapshot tests | Tasks 1, 2, 5, 7 |
| Drop `accessibilityIdentifier`s for removed elements | Tasks 3, 4, 5, 6 |
| Verify Space + Add Cue shortcuts still work (manual) | Task 8 |
| No schema / no `ProjectModel` change | Enforced by file map (`ProjectModel` not in the modify list) |

**Placeholder scan:** None. Every code block contains the exact code to write or remove. Every command is runnable as-is.

**Type / identifier consistency:** `currentTimeReadout`, `smpteTimecode`, `playPauseButton`, `addCueButton`, `lastCueElapsed`, `pauseAtEachCueIndicator`, `LTCRoutingStore.shared.settings.isEnabled`, `pauseAtEachCue` (the `@AppStorage` key) — all used consistently across tasks.

**One nuance worth flagging to the executor:** in Task 4 Step 1 the hidden Add Cue button uses `document.model.activeItem == nil` for the `.disabled` check, while the previous visible button at line 97 used the local `activeItem` variable. Both reference the same source of truth (the local `activeItem` is derived from `document.model.activeItem` upstream in `DocumentView.body`); the hidden-shortcut form must use `document.model.activeItem` because `transportShortcuts` is defined outside `body`'s local scope. Verified by reading lines 210-222.
