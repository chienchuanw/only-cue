# Beat-tempo countdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the transport bar's `Next: …` readout click-to-cycle between time-format and beat-format countdown, where beat mode shows `~N bars` outside one bar and a per-beat pulse `4 · 3 · 2 · 1` inside one bar, gracefully falling back to time when no cue tempo is available.

**Architecture:** Two pure helpers (`activeBPM`, `beatCountdown`) live as static methods on `TransportBar` next to the existing `nextCueInterval`. A `CountdownMode` enum is persisted via `@AppStorage`. The view body switches between formatters based on the mode and wraps the `Text` in a plain-styled `Button` so the readout itself is the toggle. No schema bump, no new files needed (helpers + enum colocated in `TransportBar.swift`).

**Tech Stack:** Swift 6 / SwiftUI / XCTest / XCUIApplication. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-05-15-beat-tempo-countdown-design.md`

---

## File Structure

- **Modify:** `OnlyCue/UI/TransportBar.swift` — add `CountdownMode`, `BeatCountdown`, `activeBPM`, `beatCountdown`, `countdownLabel`, `cycleMode`; replace the `Next: …` `Text` with a `Button { Text(...) }`.
- **Modify:** `OnlyCueTests/NextCueCountdownTests.swift` — add unit tests for `activeBPM`, `beatCountdown`, and `countdownLabel`. Extend `makeCue` helper to take `bpm`/`beatsPerBar`.
- **Create:** `OnlyCueUITests/BeatCountdownToggleUITests.swift` — UI tests for click-to-toggle and AppStorage persistence.

---

## Task 1: `activeBPM` helper

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift` (add static method next to `nextCueInterval` at `:34-40`)
- Modify: `OnlyCueTests/NextCueCountdownTests.swift` (extend `makeCue`, add tests)

- [ ] **Step 1: Extend the test helper to accept tempo**

In `OnlyCueTests/NextCueCountdownTests.swift`, replace the existing `makeCue` (currently at `:70-80`) with:

```swift
private func makeCue(
    time: TimeInterval,
    bpm: Double? = nil,
    beatsPerBar: Int? = nil
) -> Cue {
    Cue(
        id: UUID(),
        typeID: UUID(),
        cueNumber: 1,
        name: "test",
        time: time,
        notes: "",
        fadeTime: .zero,
        bpm: bpm,
        beatsPerBar: beatsPerBar
    )
}
```

- [ ] **Step 2: Write the failing tests for `activeBPM`**

Add to `OnlyCueTests/NextCueCountdownTests.swift`, inside `final class NextCueCountdownTests`:

```swift
// MARK: - TransportBar.activeBPM

func test_activeBPM_noCues_returnsNil() {
    XCTAssertNil(TransportBar.activeBPM(currentTime: 5.0, cues: []))
}

func test_activeBPM_noCueWithBPM_returnsNil() {
    let cues = [makeCue(time: 1.0), makeCue(time: 5.0)]
    XCTAssertNil(TransportBar.activeBPM(currentTime: 10.0, cues: cues))
}

func test_activeBPM_returnsLatestTempodCueAtOrBeforePlayhead() throws {
    let cues = [
        makeCue(time: 0.0, bpm: 120, beatsPerBar: 4),
        makeCue(time: 10.0, bpm: 90, beatsPerBar: 3),
        makeCue(time: 20.0, bpm: 140, beatsPerBar: 4),
    ]
    let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 15.0, cues: cues))
    XCTAssertEqual(result.bpm, 90, accuracy: 0.001)
    XCTAssertEqual(result.beatsPerBar, 3)
}

func test_activeBPM_includesCueExactlyAtPlayhead() throws {
    // "at or before" — a cue exactly at currentTime supplies the active tempo.
    let cues = [makeCue(time: 5.0, bpm: 100, beatsPerBar: 4)]
    let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 5.0, cues: cues))
    XCTAssertEqual(result.bpm, 100, accuracy: 0.001)
}

func test_activeBPM_skipsCuesWithoutBPM() throws {
    // Latest cue at-or-before is the tempo-less one; activeBPM should skip it
    // and return the earlier tempo'd cue.
    let cues = [
        makeCue(time: 0.0, bpm: 120, beatsPerBar: 4),
        makeCue(time: 10.0),                                  // no bpm
    ]
    let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 15.0, cues: cues))
    XCTAssertEqual(result.bpm, 120, accuracy: 0.001)
    XCTAssertEqual(result.beatsPerBar, 4)
}

func test_activeBPM_cueWithBPMButNoBeatsPerBar_defaultsTo4() throws {
    // beatsPerBar is independently optional on Cue. Treat missing as 4/4.
    let cues = [makeCue(time: 0.0, bpm: 120, beatsPerBar: nil)]
    let result = try XCTUnwrap(TransportBar.activeBPM(currentTime: 5.0, cues: cues))
    XCTAssertEqual(result.bpm, 120, accuracy: 0.001)
    XCTAssertEqual(result.beatsPerBar, 4)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/NextCueCountdownTests -destination 'platform=macOS'`

Expected: FAIL with "type 'TransportBar' has no member 'activeBPM'"

- [ ] **Step 4: Implement `activeBPM`**

In `OnlyCue/UI/TransportBar.swift`, add right below `nextCueInterval` (after line 40):

```swift
/// The bpm/beatsPerBar in effect at `currentTime` — taken from the most
/// recent cue with `time ≤ currentTime` AND a non-nil `bpm`. Cues without
/// `bpm` are skipped (a tempo-less cue does not "clear" prior tempo).
/// `beatsPerBar` defaults to 4 when the cue has bpm but no explicit meter.
/// Doesn't assume `cues` is time-sorted (mirrors `nextCueInterval`).
static func activeBPM(currentTime: TimeInterval, cues: [Cue]) -> (bpm: Double, beatsPerBar: Int)? {
    let candidate = cues
        .filter { $0.time <= currentTime && $0.bpm != nil }
        .max(by: { $0.time < $1.time })
    guard let cue = candidate, let bpm = cue.bpm else { return nil }
    return (bpm: bpm, beatsPerBar: cue.beatsPerBar ?? 4)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/NextCueCountdownTests -destination 'platform=macOS'`

Expected: PASS (all `activeBPM` tests + existing `nextCueInterval` tests).

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift OnlyCueTests/NextCueCountdownTests.swift
git commit -m "feat(transport): add activeBPM helper for beat countdown"
```

---

## Task 2: `BeatCountdown` formatter

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift` (add nested enum + static formatter)
- Modify: `OnlyCueTests/NextCueCountdownTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Add to `OnlyCueTests/NextCueCountdownTests.swift`:

```swift
// MARK: - TransportBar.beatCountdown

func test_beatCountdown_atZero_returnsPulseOne() {
    // Non-zero floor — a 0s interval still shows ".pulse(remaining: 1)"
    // so the readout never blanks at the cue boundary.
    let result = TransportBar.beatCountdown(interval: 0.0, bpm: 120, beatsPerBar: 4)
    XCTAssertEqual(result, .pulse(remaining: 1))
}

func test_beatCountdown_underOneBar_returnsPulseWithRemainingBeats() {
    // 120 bpm, 4/4 → 1 beat = 0.5s. Interval 1.0s → 2 beats left.
    let result = TransportBar.beatCountdown(interval: 1.0, bpm: 120, beatsPerBar: 4)
    XCTAssertEqual(result, .pulse(remaining: 2))
}

func test_beatCountdown_exactlyOneBar_returnsPulseFull() {
    // 120 bpm, 4/4 → 1 bar = 2.0s. Boundary case — still pulse, full bar.
    let result = TransportBar.beatCountdown(interval: 2.0, bpm: 120, beatsPerBar: 4)
    XCTAssertEqual(result, .pulse(remaining: 4))
}

func test_beatCountdown_overOneBar_returnsBarsRoundedDown() {
    // 120 bpm, 4/4 → 1 beat = 0.5s. Interval 4.5s → ceil(9) = 9 beats → 9/4 = 2 bars.
    let result = TransportBar.beatCountdown(interval: 4.5, bpm: 120, beatsPerBar: 4)
    XCTAssertEqual(result, .bars(2))
}

func test_beatCountdown_wellOverOneBar_returnsBars() {
    // 60 bpm, 4/4 → 1 beat = 1.0s, 1 bar = 4.0s. Interval 13.2s → 14 beats → 3 bars.
    let result = TransportBar.beatCountdown(interval: 13.2, bpm: 60, beatsPerBar: 4)
    XCTAssertEqual(result, .bars(3))
}

func test_beatCountdown_threeFourTime_respectsBeatsPerBar() {
    // 90 bpm, 3/4 → 1 beat ≈ 0.6667s, 1 bar = 2.0s. Interval 2.5s → 4 beats → 1 bar.
    let result = TransportBar.beatCountdown(interval: 2.5, bpm: 90, beatsPerBar: 3)
    XCTAssertEqual(result, .bars(1))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/NextCueCountdownTests -destination 'platform=macOS'`

Expected: FAIL with "type 'TransportBar' has no member 'beatCountdown'" / "cannot find 'BeatCountdown' in scope".

- [ ] **Step 3: Implement `BeatCountdown` and the formatter**

In `OnlyCue/UI/TransportBar.swift`, add inside `struct TransportBar`, below the `activeBPM` helper from Task 1:

```swift
/// Beat-mode display value. Two zones:
/// - `.bars(n)` outside one bar (n ≥ 1, integer bars rounded down).
/// - `.pulse(remaining: r)` inside one bar (r ∈ 1...beatsPerBar), drives the
///   per-beat "4 · 3 · 2 · 1" countdown.
enum BeatCountdown: Equatable {
    case bars(Int)
    case pulse(remaining: Int)
}

/// Computes the beat-mode display value from a time interval and the active
/// tempo. `beatsLeft = ceil(interval * bpm / 60)`. Pulse remaining is
/// floored at 1 so the readout never blanks at the cue boundary.
static func beatCountdown(interval: TimeInterval, bpm: Double, beatsPerBar: Int) -> BeatCountdown {
    let beatsLeft = Int(ceil(max(interval, 0) * bpm / 60.0))
    if beatsLeft > beatsPerBar {
        return .bars(beatsLeft / beatsPerBar)
    }
    return .pulse(remaining: max(1, beatsLeft))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/NextCueCountdownTests -destination 'platform=macOS'`

Expected: PASS (all new + existing tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift OnlyCueTests/NextCueCountdownTests.swift
git commit -m "feat(transport): add beatCountdown formatter"
```

---

## Task 3: `CountdownMode` + `countdownLabel`

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift` (add enum, AppStorage, label builder)
- Modify: `OnlyCueTests/NextCueCountdownTests.swift` (add label-string tests)

- [ ] **Step 1: Write the failing tests for `countdownLabel`**

Add to `OnlyCueTests/NextCueCountdownTests.swift`:

```swift
// MARK: - TransportBar.countdownLabel (pure string builder)

func test_countdownLabel_timeMode_formatsAsCompactCountdown() {
    let label = TransportBar.countdownLabel(
        mode: .time,
        interval: 4.2,
        activeTempo: nil
    )
    XCTAssertEqual(label, "Next: 4.2")
}

func test_countdownLabel_beatsMode_underOneBar_formatsAsPulse() {
    // 120 bpm, 4/4, 1.0s → 2 beats left → pulse "4 · 3 · 2 · 1" with index 1 (zero-based) emphasized.
    // The pure label builds the dot-joined "4 · 3 · 2 · 1" string; pulse position
    // is conveyed by AttributedString in the view, not the bare label.
    let label = TransportBar.countdownLabel(
        mode: .beats,
        interval: 1.0,
        activeTempo: (bpm: 120, beatsPerBar: 4)
    )
    XCTAssertEqual(label, "Next: 4 · 3 · 2 · 1")
}

func test_countdownLabel_beatsMode_overOneBar_formatsAsBars() {
    let label = TransportBar.countdownLabel(
        mode: .beats,
        interval: 4.5,
        activeTempo: (bpm: 120, beatsPerBar: 4)
    )
    XCTAssertEqual(label, "Next: ~2 bars")
}

func test_countdownLabel_beatsMode_singleBar_pluralization() {
    // 60 bpm, 4/4 → interval 5.0s → 5 beats > 4 → 1 bar. Singular "bar".
    let label = TransportBar.countdownLabel(
        mode: .beats,
        interval: 5.0,
        activeTempo: (bpm: 60, beatsPerBar: 4)
    )
    XCTAssertEqual(label, "Next: ~1 bar")
}

func test_countdownLabel_beatsMode_noActiveTempo_fallsBackToTimePlusHintGlyph() {
    let label = TransportBar.countdownLabel(
        mode: .beats,
        interval: 4.2,
        activeTempo: nil
    )
    XCTAssertEqual(label, "Next: 4.2 ⓘ")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/NextCueCountdownTests -destination 'platform=macOS'`

Expected: FAIL with "type 'TransportBar' has no member 'countdownLabel'" / "cannot find 'CountdownMode' in scope".

- [ ] **Step 3: Implement `CountdownMode` and `countdownLabel`**

In `OnlyCue/UI/TransportBar.swift`, add inside `struct TransportBar`, below the `BeatCountdown` enum from Task 2:

```swift
/// User preference for the next-cue countdown format. Persisted app-wide
/// via `@AppStorage("transport.countdownMode")`. A per-document preference
/// would require a ProjectModel schema bump; not worth it for a display toggle.
enum CountdownMode: String {
    case time
    case beats
}

/// Builds the countdown's display string. Pure — no view state, no engine.
/// In `.beats` mode without `activeTempo`, falls back to the time format
/// with a trailing `ⓘ` glyph so the user sees the mode is active but data
/// is missing (the View attaches a tooltip explaining how to fix it).
static func countdownLabel(
    mode: CountdownMode,
    interval: TimeInterval,
    activeTempo: (bpm: Double, beatsPerBar: Int)?
) -> String {
    let timeBody = TimeFormat.compactCountdown(interval)
    switch mode {
    case .time:
        return "Next: \(timeBody)"
    case .beats:
        guard let tempo = activeTempo else {
            return "Next: \(timeBody) ⓘ"
        }
        switch beatCountdown(interval: interval, bpm: tempo.bpm, beatsPerBar: tempo.beatsPerBar) {
        case .bars(let n):
            return "Next: ~\(n) bar\(n == 1 ? "" : "s")"
        case .pulse(let remaining):
            // Render full bar count (beatsPerBar … 1) so the user sees the
            // shape of the bar and the View can emphasize the active beat.
            let dots = (1...tempo.beatsPerBar)
                .reversed()
                .map(String.init)
                .joined(separator: " · ")
            _ = remaining  // emphasis applied in View, not in this pure label
            return "Next: \(dots)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueTests/NextCueCountdownTests -destination 'platform=macOS'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift OnlyCueTests/NextCueCountdownTests.swift
git commit -m "feat(transport): add CountdownMode and countdownLabel builder"
```

---

## Task 4: Wire toggle into the view

**Files:**
- Modify: `OnlyCue/UI/TransportBar.swift` (replace the `Text("Next: …")` block at `:77-82` with a `Button { Text(...) }` driven by `@AppStorage`)

- [ ] **Step 1: Add the AppStorage property**

In `OnlyCue/UI/TransportBar.swift`, inside `struct TransportBar`, add near the top of the struct (next to the existing `@Environment` / `@ObservedObject` declarations around `:17-18`):

```swift
@AppStorage("transport.countdownMode") private var countdownModeRaw: String = CountdownMode.time.rawValue

private var countdownMode: CountdownMode {
    CountdownMode(rawValue: countdownModeRaw) ?? .time
}

private func cycleCountdownMode() {
    countdownModeRaw = (countdownMode == .time ? CountdownMode.beats : .time).rawValue
}
```

- [ ] **Step 2: Replace the readout block**

In `OnlyCue/UI/TransportBar.swift`, replace lines `:77-82`:

```swift
if let interval = Self.nextCueInterval(currentTime: engine.currentTime, cues: cues) {
    Text("Next: \(TimeFormat.compactCountdown(interval))")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("nextCueCountdown")
}
```

with:

```swift
if let interval = Self.nextCueInterval(currentTime: engine.currentTime, cues: cues) {
    let label = Self.countdownLabel(
        mode: countdownMode,
        interval: interval,
        activeTempo: Self.activeBPM(currentTime: engine.currentTime, cues: cues)
    )
    Button(action: cycleCountdownMode) {
        Text(label)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("nextCueCountdown")
    }
    .buttonStyle(.plain)
    .help(countdownMode == .beats && Self.activeBPM(currentTime: engine.currentTime, cues: cues) == nil
          ? "Set a tempo on a cue to enable beat countdown. Click to switch back to time."
          : "Click to switch between time and beat countdown.")
    .accessibilityIdentifier("nextCueCountdownToggle")
}
```

- [ ] **Step 3: Build and run existing UI tests to confirm no regression**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests/TransportBarSMPTEGatingUITests -destination 'platform=macOS'`

Expected: PASS — the `nextCueCountdown` accessibility identifier is preserved on the inner `Text`, so any existing UI test querying that identifier still works.

- [ ] **Step 4: Reset AppStorage between test runs (housekeeping)**

The new `@AppStorage("transport.countdownMode")` key may carry state between dev runs. Verify the default behavior renders `Next: 4.2`-style by deleting the key once before manual smoke:

```bash
defaults delete com.chienchuanw.OnlyCue transport.countdownMode 2>/dev/null || true
```

(Bundle id may differ — check `Info.plist` if the above is a no-op. This step is informational; it does not affect tests, which set their own defaults via launch arguments.)

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/TransportBar.swift
git commit -m "feat(transport): make Next readout click-to-toggle time/beat mode"
```

---

## Task 5: UI test for click-to-toggle and persistence

**Files:**
- Create: `OnlyCueUITests/BeatCountdownToggleUITests.swift`

- [ ] **Step 1: Inspect the existing UI-test seed mechanism**

Run: `grep -rn "UITestSeedHandler\|launchArguments" OnlyCueUITests/ OnlyCue/App/UITestSeedHandler.swift | head -20`

Expected: confirms how UI tests seed a project with cues (existing pattern). The new test follows the same pattern — it must seed at least one cue with `bpm` set so beat mode renders the pulse string. If the seed handler does not yet support `bpm`, extend it minimally as part of this step (add `bpm: Double?` / `beatsPerBar: Int?` keys to the seed payload and pass them through to `Cue(...)`).

- [ ] **Step 2: Write the failing UI test**

Create `OnlyCueUITests/BeatCountdownToggleUITests.swift`:

```swift
import XCTest

/// Click-to-toggle for the transport bar's "Next: …" readout (Task 5 of
/// the beat-tempo countdown plan). Asserts:
///   1. Default mode is time → label matches the "Next: <digits>" shape.
///   2. Click flips to beat mode → label matches the bars-or-pulse shape.
///   3. AppStorage persists the mode across relaunch.
final class BeatCountdownToggleUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_clickReadout_togglesBetweenTimeAndBeatMode() throws {
        let app = launchAppWithSeededTempodCues()
        defer { app.terminate() }

        // Start playback or seek so that there IS a "next cue" interval.
        // (The seed handler should leave the playhead before the first cue;
        // confirm by checking the readout exists.)
        let readout = app.staticTexts["nextCueCountdown"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))

        let timeLabel = readout.label
        XCTAssertTrue(
            timeLabel.range(of: #"Next: \d"#, options: .regularExpression) != nil,
            "Expected default time-format label, got: \(timeLabel)"
        )

        // The button uses a separate identifier so we can target the click
        // without grabbing the inner Text.
        let toggle = app.buttons["nextCueCountdownToggle"]
        XCTAssertTrue(toggle.exists)
        toggle.click()

        // After click, label should match either bars or pulse format.
        // Re-read after a brief settle — Button has no animation but SwiftUI
        // re-renders on the next runloop tick.
        let beatLabel = readout.label
        let isBars = beatLabel.range(of: #"Next: ~\d+ bars?"#, options: .regularExpression) != nil
        let isPulse = beatLabel.contains(" · ")
        XCTAssertTrue(isBars || isPulse,
                      "Expected beat-format label, got: \(beatLabel)")
    }

    func test_countdownMode_persistsAcrossRelaunch() throws {
        // First launch: flip to beats.
        let app1 = launchAppWithSeededTempodCues()
        let toggle1 = app1.buttons["nextCueCountdownToggle"]
        XCTAssertTrue(toggle1.waitForExistence(timeout: 5))
        toggle1.click()
        let beatLabel = app1.staticTexts["nextCueCountdown"].label
        app1.terminate()

        // Second launch: should come up already in beat mode.
        let app2 = launchAppWithSeededTempodCues(resetDefaults: false)
        defer { app2.terminate() }
        let readout2 = app2.staticTexts["nextCueCountdown"]
        XCTAssertTrue(readout2.waitForExistence(timeout: 5))
        let label2 = readout2.label
        let isBars = label2.range(of: #"Next: ~\d+ bars?"#, options: .regularExpression) != nil
        let isPulse = label2.contains(" · ")
        XCTAssertTrue(isBars || isPulse,
                      "Expected mode to persist as beats, got: \(label2) (first run was: \(beatLabel))")
    }

    /// Launches the app with a seeded project containing at least one cue
    /// with `bpm` set, and (by default) clears the countdownMode AppStorage
    /// key so the test starts from the documented `.time` default.
    private func launchAppWithSeededTempodCues(resetDefaults: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestSeed", "tempodCues",        // handler must exist or be added
        ]
        if resetDefaults {
            app.launchArguments += [
                "-transport.countdownMode", "time",
            ]
        }
        app.launch()
        return app
    }
}
```

- [ ] **Step 3: Add the `tempodCues` seed if it doesn't exist**

If `OnlyCue/App/UITestSeedHandler.swift` does not yet handle `tempodCues`, add a branch that seeds a project with two cues — the first at `time: 0.0, bpm: 120, beatsPerBar: 4`, the second at `time: 30.0` — so `nextCueInterval` is non-nil at launch and `activeBPM` returns 120/4. Mirror the structure of any existing seed branch (e.g. `seedDocument(...)` style).

If unsure of the exact pattern, run: `grep -n "uiTestSeed\|case " OnlyCue/App/UITestSeedHandler.swift` and follow the existing switch.

- [ ] **Step 4: Run the new UI tests to verify they pass**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -only-testing:OnlyCueUITests/BeatCountdownToggleUITests -destination 'platform=macOS'`

Expected: PASS for both tests.

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'`

Expected: PASS — including the existing `NextCueCountdownTests` (time-format default still renders `Next: 4.2`-style).

- [ ] **Step 6: Commit**

```bash
git add OnlyCueUITests/BeatCountdownToggleUITests.swift OnlyCue/App/UITestSeedHandler.swift
git commit -m "test(transport): UI test click-to-toggle and persistence for beat countdown"
```

---

## Verification (post-implementation checklist)

- [ ] Default mode renders `Next: 4.2`-style — existing `NextCueCountdownTests` green.
- [ ] Click readout flips label to `Next: ~N bars` or `Next: 4 · 3 · 2 · 1`.
- [ ] Mode persists across app relaunch.
- [ ] Beat mode with a tempo-less project shows trailing `ⓘ` and a "Set a tempo…" tooltip.
- [ ] `nextCueCountdown` accessibility identifier preserved on the inner `Text` (no regression in tests that query it).
- [ ] No schema bump; no new files except the UI test file.
