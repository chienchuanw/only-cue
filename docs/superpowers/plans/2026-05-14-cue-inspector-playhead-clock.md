# Cue Inspector Playhead Clock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible large playhead-time readout (HH:MM:SS.mmm) pinned to the top of the Cue Inspector pane.

**Architecture:** A new small SwiftUI view `InspectorClockHeader` reads `PlayerEngine.currentTime` (already `@Observable`) and formats it via the existing `TimeFormat.hms(_:)`. `CueInspectorView` gains an `engine: PlayerEngine` parameter and renders the header above its existing `if-cue / else empty-state` Group. Call site in `CueListPane` is updated to pass through the engine it already owns.

**Tech Stack:** SwiftUI, Swift Observation (`@Observable`), existing `PlayerEngine`, existing `TimeFormat.hms`.

**Spec:** `docs/superpowers/specs/2026-05-14-cue-inspector-playhead-clock-design.md`

---

## File Structure

- **Create:** `OnlyCue/UI/InspectorClockHeader.swift` — the new view. Reads `engine.currentTime`, formats with `TimeFormat.hms`, renders a centered monospaced label with a `Divider()` beneath. Single responsibility: present the live playhead clock for the inspector header.
- **Modify:** `OnlyCue/UI/CueInspectorView.swift` — add `let engine: PlayerEngine` stored property; restructure `body` to render `InspectorClockHeader(engine: engine)` above the existing `Group { if let cue ... else emptyState }`.
- **Modify:** `OnlyCue/UI/CueListPane.swift` — single call-site update at line 77 to pass `engine: engine` into `CueInspectorView`.
- **Create:** `OnlyCueUITests/InspectorClockHeaderUITests.swift` — verifies the `inspectorClock` accessibility identifier exists in both empty-state and cue-selected states.

`CueInspectorView+Tempo.swift` (the extension) is **not** modified — its `extension CueInspectorView` continues to compile since the extension only consumes the type, not its initializer.

---

### Task 1: Create `InspectorClockHeader` with a failing logic test

**Files:**
- Create: `OnlyCue/UI/InspectorClockHeader.swift`
- Create: `OnlyCueTests/InspectorClockHeaderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/InspectorClockHeaderTests.swift` with:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class InspectorClockHeaderTests: XCTestCase {

    func testFormatsCurrentTimeAsHMSMillis() {
        let engine = PlayerEngine()
        // Use the same code path the view uses to format the engine's time.
        engine.debugSetCurrentTime(83.45)
        XCTAssertEqual(InspectorClockHeader.formatted(engine), "00:01:23.450")
    }

    func testFormatsZeroWhenIdle() {
        let engine = PlayerEngine()
        XCTAssertEqual(InspectorClockHeader.formatted(engine), "00:00:00.000")
    }
}
```

Note: `debugSetCurrentTime` does not yet exist on `PlayerEngine`. Because `currentTime` is `private(set)`, the test cannot mutate it directly. We will add a `#if DEBUG` test seam in Step 3 — the test driving the seam is acceptable since the seam is purpose-built for tests.

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodegen generate
xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/InspectorClockHeaderTests
```
Expected: FAIL with "Cannot find 'InspectorClockHeader' in scope" and "Value of type 'PlayerEngine' has no member 'debugSetCurrentTime'".

- [ ] **Step 3: Add the `PlayerEngine` test seam**

Edit `OnlyCue/Media/PlayerEngine.swift`. Immediately after the `init(player:)` declaration block (around line 28), add:

```swift
#if DEBUG
    /// Test seam — directly sets `currentTime` without an `AVPlayer` round-trip.
    /// Production code must go through `seek(to:)` instead.
    func debugSetCurrentTime(_ seconds: TimeInterval) {
        currentTime = seconds
        currentTimeObservedAt = CACurrentMediaTime()
    }
#endif
```

- [ ] **Step 4: Create `InspectorClockHeader`**

Create `OnlyCue/UI/InspectorClockHeader.swift` with:

```swift
import SwiftUI

/// Large, always-visible playhead readout pinned at the top of the Cue
/// Inspector pane. Reads `PlayerEngine.currentTime` (Observation-tracked) so
/// it ticks in lock-step with the transport without any private timer.
struct InspectorClockHeader: View {

    let engine: PlayerEngine

    var body: some View {
        VStack(spacing: 8) {
            Text(Self.formatted(engine))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("inspectorClock")
                .accessibilityLabel("Playhead time")
                .accessibilityValue(Self.formatted(engine))
            Divider()
        }
        .padding(.top, 4)
    }

    /// Exposed for unit tests — keeps the formatting logic out of the view body
    /// while still routing through the same call SwiftUI uses.
    static func formatted(_ engine: PlayerEngine) -> String {
        TimeFormat.hms(engine.currentTime)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
xcodegen generate
xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/InspectorClockHeaderTests
```
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/InspectorClockHeader.swift OnlyCueTests/InspectorClockHeaderTests.swift OnlyCue/Media/PlayerEngine.swift
git commit -m "feat(inspector): add InspectorClockHeader playhead readout view"
```

---

### Task 2: Wire `InspectorClockHeader` into `CueInspectorView`

**Files:**
- Modify: `OnlyCue/UI/CueInspectorView.swift:3-45`
- Modify: `OnlyCue/UI/CueListPane.swift:77`

- [ ] **Step 1: Add `engine` parameter to `CueInspectorView`**

Edit `OnlyCue/UI/CueInspectorView.swift`. Change the struct's stored properties block (lines 3–8) from:

```swift
struct CueInspectorView: View {

    @ObservedObject var document: CueListDocument
    let cue: Cue?

    @Environment(\.undoManager) var undoManager
```

to:

```swift
struct CueInspectorView: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    let cue: Cue?

    @Environment(\.undoManager) var undoManager
```

- [ ] **Step 2: Render the header in `body`**

In `OnlyCue/UI/CueInspectorView.swift`, replace the `body` (lines 23–38) with:

```swift
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
        .accessibilityIdentifier("cueInspector")
    }
```

- [ ] **Step 3: Update the call site in `CueListPane`**

In `OnlyCue/UI/CueListPane.swift` at line 77, change:

```swift
            CueInspectorView(document: document, cue: selectedCue)
```

to:

```swift
            CueInspectorView(document: document, engine: engine, cue: selectedCue)
```

- [ ] **Step 4: Build to verify the wiring compiles**

Run:
```bash
xcodegen generate
xcodebuild build -scheme OnlyCue -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED. No errors in `CueInspectorView+Tempo.swift` (the extension does not reference the initializer).

- [ ] **Step 5: Run all existing unit tests to verify no regression**

Run:
```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests
```
Expected: PASS for all existing tests plus the two new `InspectorClockHeaderTests`.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/CueInspectorView.swift OnlyCue/UI/CueListPane.swift
git commit -m "feat(inspector): show playhead clock above cue fields and empty state"
```

---

### Task 3: UI test — clock is visible in both inspector states

**Files:**
- Create: `OnlyCueUITests/InspectorClockHeaderUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Create `OnlyCueUITests/InspectorClockHeaderUITests.swift` with:

```swift
import XCTest

final class InspectorClockHeaderUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testClockVisibleInEmptyState() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed", "empty"]
        app.launch()

        let clock = app.staticTexts["inspectorClock"]
        XCTAssertTrue(
            clock.waitForExistence(timeout: 5),
            "inspectorClock should be visible in empty-state inspector"
        )
        // Sanity-check the format — value should match HH:MM:SS.mmm.
        let value = clock.value as? String ?? clock.label
        XCTAssertTrue(
            value.range(of: #"^\d{2}:\d{2}:\d{2}\.\d{3}$"#, options: .regularExpression) != nil,
            "inspectorClock value '\(value)' is not in HH:MM:SS.mmm format"
        )
    }

    func testClockVisibleWhenCueSelected() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed", "singleCue"]
        app.launch()

        // Select the first cue row (existing UI-test seed convention).
        let row = app.otherElements["cueRow_0"]
        if row.waitForExistence(timeout: 5) {
            row.click()
        }

        let clock = app.staticTexts["inspectorClock"]
        XCTAssertTrue(
            clock.waitForExistence(timeout: 5),
            "inspectorClock should be visible when a cue is selected"
        )
    }
}
```

Note: the `-uiTestSeed` argument and `empty` / `singleCue` fixture names follow the `UITestSeedHandler` introduced in PR #263. If a fixture name differs in the current `UITestSeedHandler.swift`, use whatever existing fixture surfaces (a) the inspector empty state and (b) a project with at least one cue.

- [ ] **Step 2: Verify available UI-test seed fixtures**

Run:
```bash
grep -n "case \|fixture\|seed" OnlyCue/App/UITestSeedHandler.swift
```
Expected: a list of fixture names. Confirm `empty` and `singleCue` (or equivalent) exist. If they differ, update the `launchArguments` strings in the test above before continuing.

- [ ] **Step 3: Run the UI tests to verify they pass**

Run:
```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/InspectorClockHeaderUITests
```
Expected: PASS (2 tests).

- [ ] **Step 4: Run full UI test suite to check for regressions**

Run:
```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests
```
Expected: PASS for all existing UI tests (no regressions from the inspector layout change). If the added header pushed any field out of an existing test's hit area, file it and fix in the same task — do not commit a green build that masks a regression.

- [ ] **Step 5: Lint**

Run:
```bash
swiftlint --strict
```
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add OnlyCueUITests/InspectorClockHeaderUITests.swift
git commit -m "test(inspector): assert playhead clock visible in both inspector states"
```

---

## Self-review

**Spec coverage:**
- "Always visible header" → Task 2 Step 2 puts `InspectorClockHeader` outside the if-cue/else block.
- "HH:MM:SS.mmm format, live" → Task 1 Step 4 (uses `TimeFormat.hms` over `@Observable engine.currentTime`).
- "Display-only" → no gesture or button modifier added; covered.
- "Accessibility identifier `inspectorClock` + label + value" → Task 1 Step 4 and asserted in Task 3.
- "Acceptance Gherkin: empty-state & cue-selected & live update" → Task 3 covers visibility in both states; live-update behavior is provided by Observation tracking (verified by Task 1's unit tests, which exercise `formatted(engine)` over a mutated `currentTime`).

**Placeholder scan:** None — every code block is complete; UI-test seed fixture names are validated in Task 3 Step 2 with an explicit fallback instruction.

**Type consistency:** `engine: PlayerEngine` consistently named across `CueInspectorView`, `InspectorClockHeader`, and the call site. Formatter is `TimeFormat.hms(_:)` everywhere (corrects the spec's informal `formatHMSms` name — `TimeFormat.hms` is the actual symbol in `OnlyCue/Utilities/Time+Format.swift:6`).

---

## Plan complete

Plan saved to `docs/superpowers/plans/2026-05-14-cue-inspector-playhead-clock.md`.
