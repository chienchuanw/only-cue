# Framerate-Based Time Display — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render every time display in the OnlyCue UI as SMPTE timecode (`HH:MM:SS:FF`, `;FF` for drop-frame) at the project's configured framerate, replacing the millisecond format `HH:MM:SS.mmm`.

**Architecture:** Extend `TimeFormat` with framerate-aware `smpte` / `smpteCountdown` wrappers over the existing `Timecode` struct. Thread the project framerate via a new `@Environment(\.projectFramerate)` value seeded once at the `DocumentView` body root. Migrate every `TimeFormat.hms` and `TimeFormat.compactCountdown` call site to the new API; delete the old millisecond formatters.

**Tech Stack:** Swift 6, SwiftUI, XCTest. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-05-15-framerate-time-display-design.md`

---

### Task 1: Add `TimeFormat.smpte` (TDD)

**Files:**
- Modify: `OnlyCue/Utilities/Time+Format.swift`
- Test: `OnlyCueTests/TimeFormatTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `OnlyCueTests/TimeFormatTests.swift`:

```swift
final class TimeFormatSMPTETests: XCTestCase {

    func test_smpte_zero_isAllZeros() {
        XCTAssertEqual(TimeFormat.smpte(0, rate: .fps30), "00:00:00:00")
    }

    func test_smpte_oneFrameAt30_isFrame01() {
        XCTAssertEqual(TimeFormat.smpte(1.0 / 30.0, rate: .fps30), "00:00:00:01")
    }

    func test_smpte_halfSecondAt24_is12Frames() {
        XCTAssertEqual(TimeFormat.smpte(3661.5, rate: .fps24), "01:01:01:12")
    }

    func test_smpte_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.smpte(-5, rate: .fps30), "00:00:00:00")
    }

    func test_smpte_dropFrame_usesSemicolonSeparator() {
        let s = TimeFormat.smpte(60.0, rate: .fps30drop)
        XCTAssertTrue(s.contains(";"), "drop-frame should use ';' between SS and FF, got \(s)")
        XCTAssertFalse(s.range(of: #"\d{2};\d{2}$"#, options: .regularExpression) == nil)
    }

    func test_smpte_matchesTimecodeDisplayString() {
        let samples: [(TimeInterval, SMPTEFramerate)] = [
            (0, .fps30), (1.234, .fps30), (3600, .fps24), (75.5, .fps25), (61.0, .fps30drop)
        ]
        for (seconds, rate) in samples {
            let expected = Timecode(totalSeconds: seconds, rate: rate).displayString
            XCTAssertEqual(TimeFormat.smpte(seconds, rate: rate), expected,
                           "smpte(\(seconds), \(rate)) should equal Timecode.displayString")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests/TimeFormatSMPTETests`
Expected: FAIL — `TimeFormat.smpte` is undefined.

- [ ] **Step 3: Implement `smpte`**

Add to `OnlyCue/Utilities/Time+Format.swift` inside the `TimeFormat` enum (do NOT delete `hms`/`compactCountdown` yet — call sites still depend on them):

```swift
    /// Formats `seconds` as SMPTE timecode `HH:MM:SS:FF` (`HH:MM:SS;FF` for
    /// drop-frame) at the given `rate`. Negative values clamp to zero; sub-frame
    /// values round half-away-from-zero (inherited from `Timecode`).
    static func smpte(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String {
        Timecode(totalSeconds: max(0, seconds), rate: rate).displayString
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests/TimeFormatSMPTETests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Utilities/Time+Format.swift OnlyCueTests/TimeFormatTests.swift
git commit -m "feat(time-format): add smpte formatter"
```

---

### Task 2: Add `TimeFormat.smpteCountdown` (TDD)

**Files:**
- Modify: `OnlyCue/Utilities/Time+Format.swift`
- Test: `OnlyCueTests/TimeFormatTests.swift`

Compact countdown form: `SS:FF` (sub-minute), `M:SS:FF` (sub-hour), `H:MM:SS:FF` (hour+). Drop-frame uses `;` between SS and FF.

- [ ] **Step 1: Write the failing tests**

Append to `OnlyCueTests/TimeFormatTests.swift`:

```swift
final class TimeFormatSMPTECountdownTests: XCTestCase {

    func test_smpteCountdown_zero_atSubMinute_isSSColonFF() {
        XCTAssertEqual(TimeFormat.smpteCountdown(0, rate: .fps30), "00:00")
    }

    func test_smpteCountdown_subMinute_at30() {
        // 5.5s @ 30fps = 5 sec 15 frames
        XCTAssertEqual(TimeFormat.smpteCountdown(5.5, rate: .fps30), "05:15")
        // 59.9s @ 30fps = 59 sec 27 frames
        XCTAssertEqual(TimeFormat.smpteCountdown(59.9, rate: .fps30), "59:27")
    }

    func test_smpteCountdown_subHour_includesMinute() {
        // 75.5s @ 30fps = 1:15:15
        XCTAssertEqual(TimeFormat.smpteCountdown(75.5, rate: .fps30), "1:15:15")
        // exactly 1 minute @ 24fps = 1:00:00
        XCTAssertEqual(TimeFormat.smpteCountdown(60.0, rate: .fps24), "1:00:00")
    }

    func test_smpteCountdown_hourPlus_includesHour() {
        // 3725.4s @ 30fps = 1:02:05:12
        XCTAssertEqual(TimeFormat.smpteCountdown(3725.4, rate: .fps30), "1:02:05:12")
    }

    func test_smpteCountdown_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.smpteCountdown(-5, rate: .fps30), "00:00")
    }

    func test_smpteCountdown_dropFrame_usesSemicolonBeforeFrames() {
        let sub = TimeFormat.smpteCountdown(5.0, rate: .fps30drop)
        XCTAssertTrue(sub.contains(";"), "expected ';' separator in \(sub)")
        let hour = TimeFormat.smpteCountdown(3725.0, rate: .fps30drop)
        XCTAssertTrue(hour.contains(";"), "expected ';' separator in \(hour)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests/TimeFormatSMPTECountdownTests`
Expected: FAIL — `smpteCountdown` undefined.

- [ ] **Step 3: Implement `smpteCountdown`**

Add to `OnlyCue/Utilities/Time+Format.swift` inside the `TimeFormat` enum:

```swift
    /// Compact SMPTE countdown for trend displays:
    /// - Sub-minute: `"SS:FF"`
    /// - Sub-hour:   `"M:SS:FF"`
    /// - Hour-plus:  `"H:MM:SS:FF"`
    /// Drop-frame uses `;` between SS and FF, matching `Timecode.displayString`.
    /// Negative values clamp to zero; sub-frame values round half-away-from-zero.
    static func smpteCountdown(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String {
        let tc = Timecode(totalSeconds: max(0, seconds), rate: rate)
        let sep = rate.isDropFrame ? ";" : ":"
        if tc.hours > 0 {
            return String(format: "%d:%02d:%02d%@%02d", tc.hours, tc.minutes, tc.seconds, sep, tc.frames)
        }
        if tc.minutes > 0 {
            return String(format: "%d:%02d%@%02d", tc.minutes, tc.seconds, sep, tc.frames)
        }
        return String(format: "%02d%@%02d", tc.seconds, sep, tc.frames)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests/TimeFormatSMPTECountdownTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Utilities/Time+Format.swift OnlyCueTests/TimeFormatTests.swift
git commit -m "feat(time-format): add smpteCountdown formatter"
```

---

### Task 3: Add `EnvironmentValues.projectFramerate` and seed it from `DocumentView`

**Files:**
- Create: `OnlyCue/UI/Environment+Framerate.swift`
- Modify: `OnlyCue/UI/DocumentView.swift:30-68` (body)
- Test: `OnlyCueTests/EnvironmentFramerateTests.swift` (new)
- Update: `project.yml` is folder-scanned for `OnlyCue/UI/`, so the new file is picked up on the next `xcodegen generate`.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/EnvironmentFramerateTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import OnlyCue

final class EnvironmentFramerateTests: XCTestCase {

    func test_default_isFps30() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.projectFramerate, .fps30)
    }

    func test_set_thenGet_roundTrips() {
        var env = EnvironmentValues()
        env.projectFramerate = .fps25
        XCTAssertEqual(env.projectFramerate, .fps25)
        env.projectFramerate = .fps30drop
        XCTAssertEqual(env.projectFramerate, .fps30drop)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests/EnvironmentFramerateTests`
Expected: FAIL — `EnvironmentValues.projectFramerate` undefined.

- [ ] **Step 3: Create the environment key**

Create `OnlyCue/UI/Environment+Framerate.swift`:

```swift
import SwiftUI

private struct ProjectFramerateKey: EnvironmentKey {
    /// Default keeps previews and isolated tests sensible without manual injection.
    static let defaultValue: SMPTEFramerate = .fps30
}

extension EnvironmentValues {
    /// The project's currently-configured SMPTE framerate, seeded once at the
    /// `DocumentView` body root from `project.timecodeSettings.framerate`. UI
    /// time formatters consume this via `@Environment(\.projectFramerate)`.
    var projectFramerate: SMPTEFramerate {
        get { self[ProjectFramerateKey.self] }
        set { self[ProjectFramerateKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Seed the environment at the DocumentView body root**

In `OnlyCue/UI/DocumentView.swift`, modify the body to add the environment modifier on the `NavigationSplitView`. Locate the `.ltcOutput(engine: engine, document: document)` line at the end of body and add the new modifier directly after it:

```swift
        .ltcOutput(engine: engine, document: document)
        .environment(\.projectFramerate, document.model.timecodeSettings.framerate)
```

- [ ] **Step 5: Regenerate Xcode project and run tests**

Run:
```
xcodegen generate
xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests/EnvironmentFramerateTests
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/Environment+Framerate.swift OnlyCue/UI/DocumentView.swift OnlyCueTests/EnvironmentFramerateTests.swift
git commit -m "feat(ui): add projectFramerate environment value seeded at DocumentView"
```

---

### Task 4: Migrate `InspectorClockHeader` to `smpte`

**Files:**
- Modify: `OnlyCue/UI/InspectorClockHeader.swift`
- Test: `OnlyCueUITests/InspectorClockHeaderUITests.swift` (extend, or create if missing — search first)

- [ ] **Step 1: Update the view to read the environment and format as SMPTE**

Replace the contents of `OnlyCue/UI/InspectorClockHeader.swift`:

```swift
import SwiftUI

/// Large, always-visible playhead readout pinned at the top of the Cue
/// Inspector pane. Reads `PlayerEngine.currentTime` (Observation-tracked) so
/// it ticks in lock-step with the transport, and renders as SMPTE timecode
/// at the project's configured framerate.
struct InspectorClockHeader: View {

    let engine: PlayerEngine
    @Environment(\.projectFramerate) private var framerate

    var body: some View {
        VStack(spacing: 8) {
            Text(TimeFormat.smpte(engine.currentTime, rate: framerate))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("inspectorClock")
            Divider()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 2: Update or add a UI test asserting the SMPTE shape**

Find the existing inspector-clock UI test:

```bash
grep -rln "inspectorClock" OnlyCueUITests/
```

In that file (or a new `InspectorClockHeaderUITests.swift` if none exists), add or replace the format assertion. Example shape — adapt to the test file's existing app-launch helpers:

```swift
func test_inspectorClock_rendersAsSMPTE() {
    let app = XCUIApplication()
    app.launchArguments += ["-uiTestSeed", "ProjectWithMedia"]
    app.launch()

    let clock = app.staticTexts["inspectorClock"]
    XCTAssertTrue(clock.waitForExistence(timeout: 5))
    let value = clock.label
    XCTAssertNotNil(value.range(of: #"^\d{2}:\d{2}:\d{2}[:;]\d{2}$"#, options: .regularExpression),
                    "expected HH:MM:SS:FF (or ;FF) form, got \(value)")
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueUITests/InspectorClockHeaderUITests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/InspectorClockHeader.swift OnlyCueUITests
git commit -m "feat(inspector): render clock as SMPTE timecode"
```

---

### Task 5: Migrate cue/media row + playhead/timeline views

**Files:**
- Modify: `OnlyCue/UI/ItemRowView.swift:17`
- Modify: `OnlyCue/UI/CueRowView.swift:24`
- Modify: `OnlyCue/UI/PlayheadOverlay.swift:32`
- Modify: `OnlyCue/UI/TimelineBreakdownView.swift:129`

These four are mechanical: read the environment, call `TimeFormat.smpte(..., rate: framerate)` instead of `TimeFormat.hms(...)`.

- [ ] **Step 1: Update `ItemRowView`**

In `OnlyCue/UI/ItemRowView.swift`, add `@Environment(\.projectFramerate) private var framerate` to the view struct alongside its other properties, and replace:

```swift
Text(TimeFormat.hms(item.media.duration))
```

with:

```swift
Text(TimeFormat.smpte(item.media.duration, rate: framerate))
```

- [ ] **Step 2: Update `CueRowView`**

In `OnlyCue/UI/CueRowView.swift`, add `@Environment(\.projectFramerate) private var framerate`, and replace:

```swift
Text(TimeFormat.hms(cue.time))
```

with:

```swift
Text(TimeFormat.smpte(cue.time, rate: framerate))
```

- [ ] **Step 3: Update `PlayheadOverlay`**

In `OnlyCue/UI/PlayheadOverlay.swift`, add `@Environment(\.projectFramerate) private var framerate`, and replace:

```swift
Text(TimeFormat.hms(currentTime))
```

with:

```swift
Text(TimeFormat.smpte(currentTime, rate: framerate))
```

- [ ] **Step 4: Update `TimelineBreakdownView`**

In `OnlyCue/UI/TimelineBreakdownView.swift`, add `@Environment(\.projectFramerate) private var framerate`, and replace:

```swift
.help(cue.name.isEmpty ? "Cue at \(TimeFormat.hms(cue.time))" : cue.name)
```

with:

```swift
.help(cue.name.isEmpty ? "Cue at \(TimeFormat.smpte(cue.time, rate: framerate))" : cue.name)
```

- [ ] **Step 5: Build to verify no remaining references**

Run:
```
grep -n "TimeFormat\.hms" OnlyCue/UI
xcodebuild build -scheme OnlyCue
```

`grep` should return no matches under `OnlyCue/UI/` (TransportBar still references `hms` until Task 6; that's the only remaining UI site). Build should succeed.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/ItemRowView.swift OnlyCue/UI/CueRowView.swift OnlyCue/UI/PlayheadOverlay.swift OnlyCue/UI/TimelineBreakdownView.swift
git commit -m "feat(ui): render cue/media row, playhead, timeline times as SMPTE"
```

---

### Task 6: Migrate `TransportBar` (current/duration + next-cue countdown)

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift:34-36` (current/duration), `:102` (countdown)

`TransportBar` already receives `timecodeSettings: ProjectTimecodeSettings` as a property — use `timecodeSettings.framerate` directly rather than the environment. The per-media SMPTE field at line 133 stays unchanged (it's the LTC-aligned readout).

- [ ] **Step 1: Update the current / duration readout**

In `OnlyCue/UI/TransportBar.swift`, locate the computed property building the current/total string (around lines 34–36). Replace:

```swift
let current = TimeFormat.hms(engine.currentTime)
…
return "\(current) / \(TimeFormat.hms(mediaDuration))"
```

with:

```swift
let current = TimeFormat.smpte(engine.currentTime, rate: timecodeSettings.framerate)
…
return "\(current) / \(TimeFormat.smpte(mediaDuration, rate: timecodeSettings.framerate))"
```

- [ ] **Step 2: Update the countdown body**

At line 102, replace:

```swift
let timeBody = TimeFormat.compactCountdown(interval)
```

with:

```swift
let timeBody = TimeFormat.smpteCountdown(interval, rate: timecodeSettings.framerate)
```

- [ ] **Step 3: Build to verify the file is clean of `hms`/`compactCountdown`**

Run:
```
grep -n "TimeFormat\.hms\|TimeFormat\.compactCountdown" OnlyCue/UI/TransportBar.swift
xcodebuild build -scheme OnlyCue
```

`grep` should return no matches. Build should succeed.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift
git commit -m "feat(transport): render current/duration and countdown as SMPTE"
```

---

### Task 7: Update countdown unit tests for the new SMPTE shape

**Files:**
- Modify: `OnlyCueTests/NextCueCountdownTests.swift` (replace decisecond assertions)

The existing `NextCueCountdownTests` pins decisecond literals (`"5.2"`, `"1:00.0"`) against `TimeFormat.compactCountdown`. Since the countdown view now calls `smpteCountdown`, these tests must be rewritten — and they MUST be rewritten in this task because Task 8 deletes `compactCountdown` entirely.

- [ ] **Step 1: Replace the decisecond test methods**

In `OnlyCueTests/NextCueCountdownTests.swift`, locate the `// MARK: - TimeFormat.compactCountdown` section (around line 43) and replace its test methods with SMPTE-shape equivalents:

```swift
    // MARK: - TimeFormat.smpteCountdown

    func test_smpteCountdown_subSecond_formatsAsSSColonFF() {
        XCTAssertEqual(TimeFormat.smpteCountdown(0.0, rate: .fps30), "00:00")
        XCTAssertEqual(TimeFormat.smpteCountdown(0.5, rate: .fps30), "00:15")
    }

    func test_smpteCountdown_subMinute_formatsAsSSColonFF() {
        XCTAssertEqual(TimeFormat.smpteCountdown(5.5, rate: .fps30), "05:15")
        XCTAssertEqual(TimeFormat.smpteCountdown(59.9, rate: .fps30), "59:27")
    }

    func test_smpteCountdown_subHour_includesMinute() {
        XCTAssertEqual(TimeFormat.smpteCountdown(60.0, rate: .fps30), "1:00:00")
        XCTAssertEqual(TimeFormat.smpteCountdown(75.5, rate: .fps30), "1:15:15")
        XCTAssertEqual(TimeFormat.smpteCountdown(125.3, rate: .fps30), "2:05:09")
    }

    func test_smpteCountdown_hour_includesHour() {
        XCTAssertEqual(TimeFormat.smpteCountdown(3600.0, rate: .fps30), "1:00:00:00")
        XCTAssertEqual(TimeFormat.smpteCountdown(3725.4, rate: .fps30), "1:02:05:12")
    }

    func test_smpteCountdown_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.smpteCountdown(-5.0, rate: .fps30), "00:00")
    }
```

- [ ] **Step 2: Run the file's tests**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests/NextCueCountdownTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add OnlyCueTests/NextCueCountdownTests.swift
git commit -m "test(transport): assert SMPTE-shape next-cue countdown"
```

---

### Task 8: Delete `TimeFormat.hms` and `TimeFormat.compactCountdown` + their tests

**Files:**
- Modify: `OnlyCue/Utilities/Time+Format.swift` (remove old functions)
- Modify: `OnlyCueTests/TimeFormatTests.swift` (remove old assertions)

- [ ] **Step 1: Verify no remaining call sites**

Run:
```
grep -rn "TimeFormat\.hms\|TimeFormat\.compactCountdown" OnlyCue OnlyCueTests OnlyCueUITests --include="*.swift"
```

Expected: only matches inside `Time+Format.swift` (the definitions) and possibly old test methods. If any production matches remain, stop and fix them before continuing.

- [ ] **Step 2: Delete the old functions**

In `OnlyCue/Utilities/Time+Format.swift`, the final file contents should be:

```swift
import Foundation

enum TimeFormat {
    /// Formats `seconds` as SMPTE timecode `HH:MM:SS:FF` (`HH:MM:SS;FF` for
    /// drop-frame) at the given `rate`. Negative values clamp to zero; sub-frame
    /// values round half-away-from-zero (inherited from `Timecode`).
    static func smpte(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String {
        Timecode(totalSeconds: max(0, seconds), rate: rate).displayString
    }

    /// Compact SMPTE countdown for trend displays:
    /// - Sub-minute: `"SS:FF"`
    /// - Sub-hour:   `"M:SS:FF"`
    /// - Hour-plus:  `"H:MM:SS:FF"`
    /// Drop-frame uses `;` between SS and FF, matching `Timecode.displayString`.
    /// Negative values clamp to zero; sub-frame values round half-away-from-zero.
    static func smpteCountdown(_ seconds: TimeInterval, rate: SMPTEFramerate) -> String {
        let tc = Timecode(totalSeconds: max(0, seconds), rate: rate)
        let sep = rate.isDropFrame ? ";" : ":"
        if tc.hours > 0 {
            return String(format: "%d:%02d:%02d%@%02d", tc.hours, tc.minutes, tc.seconds, sep, tc.frames)
        }
        if tc.minutes > 0 {
            return String(format: "%d:%02d%@%02d", tc.minutes, tc.seconds, sep, tc.frames)
        }
        return String(format: "%02d%@%02d", tc.seconds, sep, tc.frames)
    }
}
```

- [ ] **Step 3: Delete obsolete `hms` tests**

In `OnlyCueTests/TimeFormatTests.swift`, remove every method that asserts on `TimeFormat.hms(...)` (the original `TimeFormatTests` class). Keep `TimeFormatSMPTETests` and `TimeFormatSMPTECountdownTests` (added in Tasks 1 and 2).

- [ ] **Step 4: Build and run the full suites**

Run:
```
xcodebuild test -scheme OnlyCue -only-testing OnlyCueTests
xcodebuild test -scheme OnlyCue -only-testing OnlyCueUITests
```

Expected: all tests pass. Build clean. SwiftLint clean.

- [ ] **Step 5: Verify lint**

Run: `./scripts/lint.sh` (or whatever the project's lint entrypoint is — check `project.yml` / README if uncertain).
Expected: 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Utilities/Time+Format.swift OnlyCueTests/TimeFormatTests.swift
git commit -m "refactor(time-format): remove obsolete millisecond formatters"
```

---

### Task 9: End-to-end verification — flip framerate live

**Files:**
- Modify or extend: an existing UI test file under `OnlyCueUITests/` (e.g., `TimecodeSettingsUITests.swift` if present, otherwise the most appropriate inspector-clock test file)

This is a regression test that proves the new environment value reaches the clock when the user changes the framerate at runtime.

- [ ] **Step 1: Locate or create a framerate-change UI test**

Run:
```
grep -rln "TimecodeSettingsSheet\|setProjectTimecodeSettings\|framerate" OnlyCueUITests
```

Pick the most appropriate existing test file. If none, create `OnlyCueUITests/InspectorClockFramerateUITests.swift`.

- [ ] **Step 2: Add the live-flip test**

Example test — adapt selectors/launch args to the project's existing UI test patterns and `UITestSeedHandler` seeds:

```swift
func test_inspectorClock_updatesWhenFramerateChanges() {
    let app = XCUIApplication()
    app.launchArguments += ["-uiTestSeed", "ProjectWithMedia"]
    app.launch()

    let clock = app.staticTexts["inspectorClock"]
    XCTAssertTrue(clock.waitForExistence(timeout: 5))
    let before = clock.label

    // Open Tools → Timecode Settings… and switch the framerate to 24 fps.
    app.menuBarItems["Tools"].click()
    app.menuItems["Timecode Settings…"].click()
    let picker = app.popUpButtons["framerate"]
    XCTAssertTrue(picker.waitForExistence(timeout: 2))
    picker.click()
    app.menuItems["24 fps"].click()
    app.buttons["Done"].click()

    // The clock should re-render with the new rate. We don't assert a specific
    // value (depends on playback position); only that the readout changed shape
    // or value in response to the rate flip.
    XCTAssertTrue(clock.waitForExistence(timeout: 2))
    XCTAssertNotEqual(clock.label, before, "clock did not refresh after framerate change")
}
```

If the precise menu item / picker labels differ in the codebase, use Accessibility Inspector or `grep` for existing assertions on the timecode sheet to find the correct selectors.

- [ ] **Step 3: Run the UI test**

Run: `xcodebuild test -scheme OnlyCue -only-testing OnlyCueUITests/InspectorClockFramerateUITests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OnlyCueUITests
git commit -m "test(inspector): verify clock refreshes when framerate flips"
```

---

## Out of scope (do not implement in this plan)

- Display-preference toggle (`.mmm` vs `:FF`).
- Media-relative anchoring of general clocks (the per-media SMPTE field in `TransportBar:133` continues to handle that need; left untouched).
- Schema changes — the project framerate already exists.
- Any change to `Timecode`, `ProjectTimecodeSettings`, or the LTC pipeline.
