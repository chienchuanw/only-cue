# grandMA2 telnet-command push (Approach A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the live "Send to grandMA2…" push's XML-over-FTP transport with a pure telnet command sequence that builds a sequence of `Trig=Timecode` / `TrigTime` cues — no FTP, no XML, works on grandMA2 onPC and real consoles.

**Architecture:** A new pure `MA2CommandPlanner` turns a media item's filtered cues + `MA2PushTarget` into an ordered telnet command list (`Store Sequence … Cue …`, `Assign … /Trig=Timecode`, `Assign … /TrigTime=…`, `/fade`, `Label`, `Assign … At Exec`). `MA2TrigTime` encodes each cue's absolute time as decimal seconds on the project frame grid. `MA2PushRunner` gains a commands-only run (connect → login → commands, no uploads). The push sheet drops its two upload rows. Existing preflight, telnet client, keychain, settings, and target model are reused unchanged.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `Network.framework` (existing `MA2TelnetClient`), xcodegen.

## Global Constraints

- Swift 6, macOS deployment target ≥ 14.0 (ADR-001) — do not lower.
- `swiftlint lint --strict` must stay clean (warnings fail CI).
- No direct `ProjectModel` mutations — go through `Commands/CueCommands.swift`.
- Conventional Commits, lowercase imperative, **no** `Co-Authored-By` / attribution.
- No schema change: `ProjectModel.currentSchemaVersion` stays `17`; `MA2PushTarget` is reused as-is (A ignores its `timecodeSlot` / `timecodeCommand`).
- No test may contact a real console/network — CI has none. Transport is mocked via the existing `MA2PushTransport` seam.
- Cue numbers/timings validated on the rig: `Store Sequence <s> Cue <n> "<name>" /nc`, `Assign Sequence <s> Cue <n> /Trig=Timecode`, `Assign Sequence <s> Cue <n> /TrigTime=<decimal seconds>`, `/fade=`, `Label Sequence <s> "<name>"`, `Assign Sequence <s> At Exec <p>.<e>`. Empty-slot `Delete Sequence <s> /nc` returns a WARNING, not an `Error #`.

## Reference types (already in the codebase)

- `Cue`: has `cueNumber: Double?`, `name: String`, `notes: String`, `time: TimeInterval`, `fadeTime.fadeIn`/`.fadeOut` (`Double`), `id: UUID`.
- `MA2PushTarget`: `sequenceSlot`, `timecodeSlot`, `executorPage`, `executorNumber`, `timecodeCommand`, `includedTypeIDs: Set<UUID>`, `isValid: Bool`.
- `MA2CueNumber.components(from: Double) -> Components(number: Int, subNumber: Int)` (thousandths).
- `SMPTEFramerate.framesPerSecond: Int` (24/25/30/30 for `.fps30drop`).
- `MA2PushPlanner.commandQuotable(_:)` is `private`; this plan promotes it (Task 2).
- `MA2PushRunner`: `@MainActor @Observable`, `run(plan:host:username:password:)`, step model `Step`/`StepState`, `MA2PushTransport` seam.
- `MA2PushRequestBuilder.outcome(item:target:framerate:showfile:datetime:) -> Outcome` (`.blocked([Issue])` / `.ready(MA2PushPlan)`).
- `FadeTime.formatNumber(_ value: Double) -> String` (used by the XML generator for fade formatting).

---

### Task 1: `MA2TrigTime` — absolute-time encoder

**Files:**

- Create: `OnlyCue/MA2/MA2TrigTime.swift`
- Test: `OnlyCueTests/MA2TrigTimeTests.swift`

**Interfaces:**

- Produces: `enum MA2TrigTime { static func seconds(cueTime: TimeInterval, startTimecodeFrames: Int, framerate: SMPTEFramerate) -> Double; static func command(cueTime: TimeInterval, startTimecodeFrames: Int, framerate: SMPTEFramerate) -> String }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MA2TrigTimeTests: XCTestCase {
    func testSecondsSnapsToFrameGridWithStartOffset() {
        // 30 fps, start at frame 90 (=3.0s), cue at 2.1333s → +64 frames → frame 154 → 154/30
        let s = MA2TrigTime.seconds(cueTime: 2.1333, startTimecodeFrames: 90, framerate: .fps30)
        XCTAssertEqual(s, 154.0 / 30.0, accuracy: 1e-9)
    }

    func testCommandStringTrimsTrailingZeros() {
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0, startTimecodeFrames: 150, framerate: .fps30), "5") // 150/30 = 5.0
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0, startTimecodeFrames: 0, framerate: .fps25), "0")
    }

    func testFps30DropUsesNominalThirty() {
        let s = MA2TrigTime.seconds(cueTime: 1.0, startTimecodeFrames: 0, framerate: .fps30drop)
        XCTAssertEqual(s, 30.0 / 30.0, accuracy: 1e-9) // 30 frames at nominal 30 fps
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests/MA2TrigTimeTests`
Expected: FAIL — `MA2TrigTime` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Encodes a cue's absolute timecode for a grandMA2 `Assign … /TrigTime=` command
/// (#683, Approach A). Value is decimal seconds on the project frame grid — the
/// console quantizes it to its slot's timecode format (1/100 s, 24, 25 or 30 fps).
/// Emitting seconds (not physical frames under a format label) avoids the
/// drop-frame hazard that the XML timecode path carried.
enum MA2TrigTime {

    static func seconds(cueTime: TimeInterval, startTimecodeFrames: Int, framerate: SMPTEFramerate) -> Double {
        let fps = Double(framerate.framesPerSecond)
        let absFrames = startTimecodeFrames + Int((cueTime * fps).rounded())
        return Double(absFrames) / fps
    }

    static func command(cueTime: TimeInterval, startTimecodeFrames: Int, framerate: SMPTEFramerate) -> String {
        let value = seconds(cueTime: cueTime, startTimecodeFrames: startTimecodeFrames, framerate: framerate)
        var text = String(format: "%.6f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests/MA2TrigTimeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2TrigTime.swift OnlyCueTests/MA2TrigTimeTests.swift
git commit -m "feat(ma2): add TrigTime absolute-seconds encoder for command push"
```

---

### Task 2: `MA2CommandPlanner` — build the telnet command list

**Files:**

- Create: `OnlyCue/MA2/MA2CommandPlanner.swift`
- Modify: `OnlyCue/MA2/MA2PushPlanner.swift` (promote `commandQuotable` from `private` to `static func` on a shared helper — see Step 3)
- Modify: `OnlyCue/MA2/MA2SequenceXMLGenerator.swift` (add `MA2CueNumber.commandString` — see Step 3)
- Test: `OnlyCueTests/MA2CommandPlannerTests.swift`

**Interfaces:**

- Consumes: `MA2TrigTime.command(...)`, `MA2CueNumber.components(from:)`, `MA2PushTarget`, `SMPTEFramerate`.
- Produces: `enum MA2CommandPlanner { static func commands(cues: [Cue], target: MA2PushTarget, sequenceName: String, startTimecodeFrames: Int, framerate: SMPTEFramerate) -> [String] }`; `MA2CueNumber.commandString(from: Double) -> String`; `MA2CommandQuoting.quotable(_:) -> String`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MA2CommandPlannerTests: XCTestCase {
    private func cue(_ n: Double, _ name: String, time: TimeInterval, fadeIn: Double = 0, fadeOut: Double = 0) -> Cue {
        var c = Cue(time: time)          // adjust to the real Cue initializer in the codebase
        c.cueNumber = n; c.name = name
        c.fadeTime = FadeTime(fadeIn: fadeIn, fadeOut: fadeOut)
        return c
    }

    func testBuildsOrderedCommandListWithDeleteFirst() {
        let target = MA2PushTarget(sequenceSlot: 900, timecodeSlot: 9, executorPage: 1,
                                   executorNumber: 15, timecodeCommand: .goto, includedTypeIDs: [])
        let cues = [cue(2.001, "Drop", time: 10), cue(1.15, "Intro", time: 5, fadeIn: 3)]
        let cmds = MA2CommandPlanner.commands(cues: cues, target: target, sequenceName: "Song A",
                                              startTimecodeFrames: 0, framerate: .fps30)
        XCTAssertEqual(cmds, [
            "Delete Sequence 900 /nc",
            "Store Sequence 900 Cue 1.15 \"Intro\" /nc",
            "Assign Sequence 900 Cue 1.15 /Trig=Timecode",
            "Assign Sequence 900 Cue 1.15 /TrigTime=5",
            "Assign Sequence 900 Cue 1.15 /fade=3",
            "Store Sequence 900 Cue 2.001 \"Drop\" /nc",
            "Assign Sequence 900 Cue 2.001 /Trig=Timecode",
            "Assign Sequence 900 Cue 2.001 /TrigTime=10",
            "Label Sequence 900 \"Song A\"",
            "Assign Sequence 900 At Exec 1.15"
        ])
    }

    func testStripsEmbeddedQuotesInNames() {
        let target = MA2PushTarget(sequenceSlot: 5, timecodeSlot: 1, executorPage: 2,
                                   executorNumber: 3, timecodeCommand: .go, includedTypeIDs: [])
        let cmds = MA2CommandPlanner.commands(cues: [cue(1, "he said \"hi\"", time: 0)],
                                              target: target, sequenceName: "a\"b",
                                              startTimecodeFrames: 0, framerate: .fps25)
        XCTAssertTrue(cmds.contains("Store Sequence 5 Cue 1 \"he said hi\" /nc"))
        XCTAssertTrue(cmds.contains("Label Sequence 5 \"ab\""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests/MA2CommandPlannerTests`
Expected: FAIL — `MA2CommandPlanner` undefined.

> If the `Cue` initializer in the test does not compile, open `OnlyCue/Document/Cue.swift`, copy the real initializer/property names, and fix the `cue(...)` helper. Do not change `Cue`.

- [ ] **Step 3: Write minimal implementation**

Add to `OnlyCue/MA2/MA2SequenceXMLGenerator.swift` (extend the `MA2CueNumber` enum):

```swift
extension MA2CueNumber {
    /// Cue number as an MA2 command token: integer when whole, else up to three
    /// decimals with trailing zeros trimmed (`1.15`, `2.001`, `3`).
    static func commandString(from value: Double) -> String {
        let c = components(from: value)
        guard c.subNumber != 0 else { return "\(c.number)" }
        var frac = String(format: "%03d", c.subNumber)
        while frac.hasSuffix("0") { frac.removeLast() }
        return "\(c.number).\(frac)"
    }
}
```

Create `OnlyCue/MA2/MA2CommandPlanner.swift`:

```swift
import Foundation

/// Shared MA2 command-name quoting (double quotes, no documented escape for
/// embedded quotes → strip them). Used by both the XML planner and the command
/// planner (#683).
enum MA2CommandQuoting {
    static func quotable(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "")
    }
}

/// Pure planner for the telnet-command push (#683, Approach A): a media item's
/// filtered cues → the exact ordered command list that rebuilds the target
/// sequence as `Trig=Timecode` / `TrigTime` cues. No FTP, no XML, no
/// timecode-pool object; the sequence's timecode slot defaults to "link
/// selected", so the operator's selected TC slot (fed by OnlyCue's LTC) drives it.
enum MA2CommandPlanner {

    static func commands(
        cues: [Cue],
        target: MA2PushTarget,
        sequenceName: String,
        startTimecodeFrames: Int,
        framerate: SMPTEFramerate
    ) -> [String] {
        let seq = target.sequenceSlot
        let ordered = cues.sorted { ($0.cueNumber ?? 0) < ($1.cueNumber ?? 0) }

        var commands: [String] = ["Delete Sequence \(seq) /nc"]

        for cue in ordered {
            let num = MA2CueNumber.commandString(from: cue.cueNumber ?? 0)
            let name = MA2CommandQuoting.quotable(cue.name)
            commands.append("Store Sequence \(seq) Cue \(num) \"\(name)\" /nc")
            commands.append("Assign Sequence \(seq) Cue \(num) /Trig=Timecode")
            let trig = MA2TrigTime.command(
                cueTime: cue.time, startTimecodeFrames: startTimecodeFrames, framerate: framerate
            )
            commands.append("Assign Sequence \(seq) Cue \(num) /TrigTime=\(trig)")
            if cue.fadeTime.fadeIn > 0 {
                commands.append("Assign Sequence \(seq) Cue \(num) /fade=\(FadeTime.formatNumber(cue.fadeTime.fadeIn))")
            }
            if cue.fadeTime.fadeOut > 0 {
                commands.append("Assign Sequence \(seq) Cue \(num) /outfade=\(FadeTime.formatNumber(cue.fadeTime.fadeOut))")
            }
        }

        commands.append("Label Sequence \(seq) \"\(MA2CommandQuoting.quotable(sequenceName))\"")
        commands.append("Assign Sequence \(seq) At Exec \(target.executorPage).\(target.executorNumber)")
        return commands
    }
}
```

Then in `OnlyCue/MA2/MA2PushPlanner.swift`, replace the `private static func commandQuotable` body with a call to the shared helper (keep the existing call sites working):

```swift
    private static func commandQuotable(_ name: String) -> String {
        MA2CommandQuoting.quotable(name)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests/MA2CommandPlannerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2CommandPlanner.swift OnlyCue/MA2/MA2SequenceXMLGenerator.swift OnlyCue/MA2/MA2PushPlanner.swift OnlyCueTests/MA2CommandPlannerTests.swift
git commit -m "feat(ma2): add telnet command planner for per-cue timecode push"
```

---

### Task 3: `MA2PushRequestBuilder` — command outcome

**Files:**

- Modify: `OnlyCue/MA2/MA2PushRequestBuilder.swift`
- Test: `OnlyCueTests/MA2PushRequestBuilderTests.swift` (add cases)

**Interfaces:**

- Consumes: `MA2CommandPlanner.commands(...)`, existing `CueExportFilter`, `MA2PushPreflight`.
- Produces: `MA2PushRequestBuilder.commandOutcome(item:target:framerate:) -> CommandOutcome` where `enum CommandOutcome: Equatable { case blocked([MA2PushPreflight.Issue]); case ready([String]) }`.

- [ ] **Step 1: Write the failing test**

```swift
func testCommandOutcomeReadyReturnsCommandList() {
    var item = MediaItem(/* real init */)      // give it two numbered cues + a duration
    // ...populate item.cues with cueNumber 1 and 2...
    let target = MA2PushTarget(sequenceSlot: 900, timecodeSlot: 9, executorPage: 1,
                               executorNumber: 15, timecodeCommand: .goto, includedTypeIDs: [])
    let outcome = MA2PushRequestBuilder.commandOutcome(item: item, target: target, framerate: .fps30)
    guard case let .ready(cmds) = outcome else { return XCTFail("expected ready") }
    XCTAssertEqual(cmds.first, "Delete Sequence 900 /nc")
    XCTAssertEqual(cmds.last, "Assign Sequence 900 At Exec 1.15")
}

func testCommandOutcomeBlockedOnUnnumberedCue() {
    var item = MediaItem(/* real init */)      // one cue with cueNumber == nil
    let target = MA2PushTarget(sequenceSlot: 1, timecodeSlot: 1, executorPage: 1,
                               executorNumber: 1, timecodeCommand: .goto, includedTypeIDs: [])
    let outcome = MA2PushRequestBuilder.commandOutcome(item: item, target: target, framerate: .fps30)
    guard case .blocked = outcome else { return XCTFail("expected blocked") }
}
```

> Copy the real `MediaItem` / `Cue` construction from `MA2PushRequestBuilderTests`'s existing helpers — reuse them rather than re-deriving.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PushRequestBuilderTests`
Expected: FAIL — `commandOutcome` undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `OnlyCue/MA2/MA2PushRequestBuilder.swift`:

```swift
    enum CommandOutcome: Equatable {
        case blocked([MA2PushPreflight.Issue])
        case ready([String])
    }

    static func commandOutcome(
        item: MediaItem,
        target: MA2PushTarget,
        framerate: SMPTEFramerate
    ) -> CommandOutcome {
        let cues = CueExportFilter.cues(item.cues, onlyTypeIDs: target.includedTypeIDs)
        let issues = MA2PushPreflight.validate(cues)
        guard issues.isEmpty else { return .blocked(issues) }
        return .ready(MA2CommandPlanner.commands(
            cues: cues,
            target: target,
            sequenceName: item.resolvedName,
            startTimecodeFrames: item.startTimecodeFrames,
            framerate: framerate
        ))
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PushRequestBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PushRequestBuilder.swift OnlyCueTests/MA2PushRequestBuilderTests.swift
git commit -m "feat(ma2): add command outcome to push request builder"
```

---

### Task 4: `MA2PushRunner` — commands-only run

**Files:**

- Modify: `OnlyCue/MA2/MA2PushRunner.swift`
- Test: `OnlyCueTests/MA2PushRunnerTests.swift` (add cases; reuse the existing mock transport)

**Interfaces:**

- Consumes: existing `MA2PushTransport` seam + `Step`/`StepState`.
- Produces: `MA2PushRunner.run(commands: [String], host: String, username: String, password: String) async`.

- [ ] **Step 1: Write the failing test** (reuse the existing `MockTransport` in `MA2PushRunnerTests`)

```swift
func testRunCommandsConnectsLoginsAndSendsEachCommand() async {
    let mock = MockTransport()                 // existing test double
    let runner = MA2PushRunner(transport: mock, interCommandDelay: 0)
    await runner.run(commands: ["Delete Sequence 900 /nc", "Label Sequence 900 \"X\""],
                     host: "1.2.3.4", username: "administrator", password: "admin")
    XCTAssertTrue(runner.didSucceed)
    XCTAssertEqual(mock.sentCommands, ["Delete Sequence 900 /nc", "Label Sequence 900 \"X\""])
    XCTAssertTrue(runner.steps.allSatisfy { $0.state == .done })
    XCTAssertEqual(runner.steps.map(\.title).prefix(2), ["Connect to 1.2.3.4", "Login as administrator"])
}

func testRunCommandsStopsOnFirstConsoleError() async {
    let mock = MockTransport()
    mock.failOn = "Assign Sequence 900 At Exec 1.15"   // make send throw MA2TelnetClient.Failure.console
    let runner = MA2PushRunner(transport: mock, interCommandDelay: 0)
    await runner.run(commands: ["Delete Sequence 900 /nc", "Assign Sequence 900 At Exec 1.15", "Label Sequence 900 \"X\""],
                     host: "h", username: "u", password: "p")
    XCTAssertFalse(runner.didSucceed)
    XCTAssertFalse(mock.sentCommands.contains("Label Sequence 900 \"X\""))  // stopped before the last
    XCTAssertTrue(mock.didDisconnect)
}
```

> Check the existing `MockTransport` for how it records sends / simulates failures / disconnect. Extend it minimally (e.g. a `failOn` hook) if not present, matching its current style.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PushRunnerTests`
Expected: FAIL — `run(commands:…)` undefined.

- [ ] **Step 3: Write minimal implementation** — add alongside the existing `run(plan:…)`:

```swift
    /// Commands-only push (#683, Approach A): connect → login → run each command,
    /// no FTP uploads. Stop on the first error; idempotent, so re-push recovers.
    func run(commands: [String], host: String, username: String, password: String) async {
        var titles = ["Connect to \(host)", "Login as \(username)"]
        titles.append(contentsOf: commands)
        steps = titles.enumerated().map { Step(id: $0.offset, title: $0.element) }
        isRunning = true
        didSucceed = false
        failureMessage = nil
        defer { isRunning = false }

        guard await perform(step: 0, { try await self.transport.connect() }) else { return }
        guard await perform(step: 1, {
            try await self.transport.login(username: username, password: password)
        }) else {
            await transport.disconnect()
            return
        }

        for (offset, command) in commands.enumerated() {
            let succeeded = await perform(step: 2 + offset) {
                try await self.transport.send(command)
                if self.interCommandDelay > 0 {
                    try await Task.sleep(for: .seconds(self.interCommandDelay))
                }
            }
            guard succeeded else {
                await transport.disconnect()
                return
            }
        }

        await transport.disconnect()
        didSucceed = true
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PushRunnerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PushRunner.swift OnlyCueTests/MA2PushRunnerTests.swift
git commit -m "feat(ma2): add commands-only run path to push runner"
```

---

### Task 5: Wire the push sheet to the command path

**Files:**

- Modify: `OnlyCue/UI/MA2PushSheet.swift` (call `commandOutcome` + `run(commands:…)`)
- Test: `OnlyCueTests/` — add/adjust the push-sheet-facing test if one exists; otherwise assert via `MA2PushRequestBuilder`/`MA2PushRunner` (covered by Tasks 3–4) and verify the sheet compiles + the app builds.

**Interfaces:**

- Consumes: `MA2PushRequestBuilder.commandOutcome(item:target:framerate:)`, `MA2PushRunner.run(commands:host:username:password:)`.

- [ ] **Step 1: Read the sheet** to find where it currently calls `MA2PushRequestBuilder.outcome(...)` / `runner.run(plan:…)`.

Run: `grep -n "outcome\|run(plan\|MA2PushRunner\|MA2PushRequestBuilder" OnlyCue/UI/MA2PushSheet.swift`

- [ ] **Step 2: Replace the plan build + run with the command path**

Change the `.ready(plan)` branch to use commands:

```swift
switch MA2PushRequestBuilder.commandOutcome(item: item, target: target, framerate: framerate) {
case let .blocked(issues):
    // present issues exactly as before
    self.preflightIssues = issues
case let .ready(commands):
    await runner.run(commands: commands, host: host, username: username, password: password)
}
```

Delete the now-unused `showfile` / `datetime` arguments threaded only into the XML plan (leave them if other UI still needs them — grep first).

- [ ] **Step 3: Regenerate the project and build**

Run:

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-"
```

Expected: BUILD SUCCEEDED (new files picked up by folder rules).

- [ ] **Step 4: Run the full MA2 suite + lint**

Run:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests
swiftlint lint --strict
```

Expected: all tests pass; lint clean.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/MA2PushSheet.swift
git commit -m "feat(ma2): push sheet uses telnet command path instead of ftp+xml"
```

---

### Task 6: Prune the FTP path from the live push (defer, not delete)

**Files:**

- Modify: `OnlyCue/MA2/MA2PushRunner.swift` (mark `run(plan:…)` unused-by-UI; keep for Approach C reuse)
- Docs: note in the spec that `MA2FTPUploader` / `MA2CurlUploader` / `MA2Uploading` now have no live caller and are retained for Phase C.

**Interfaces:** none new.

- [ ] **Step 1: Confirm no remaining live caller of the FTP path**

Run: `grep -rn "run(plan:\|MA2CurlUploader\|MA2FTPUploader\|uploader" OnlyCue --include="*.swift" | grep -v Tests`
Expected: only `MA2PushRunner` internals + (later) Phase C. No UI caller.

- [ ] **Step 2: Add a doc-comment marker** on `run(plan:…)` and the uploader types:

```swift
    // Retained for Approach C (plugin export) reuse; the live UI uses run(commands:…).
```

- [ ] **Step 3: Build + full test + lint**

Run:

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests
swiftlint lint --strict
```

Expected: green, clean.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/MA2/MA2PushRunner.swift docs/superpowers/specs/2026-07-20-ma2-telnet-command-push-and-plugin-export-design.md
git commit -m "chore(ma2): mark ftp push path as approach-c-only"
```

---

## Self-Review

- **Spec coverage (Approach A):** TrigTime encoding + 4-format note → Task 1; command list incl. fractional numbers/fades/quoting/idempotent delete → Task 2; preflight reuse + command outcome → Task 3; commands-only runner (connect/login/stop-on-error/disconnect) → Task 4; UI without upload rows → Task 5; FTP retired from live → Task 6. No schema change (Global Constraints). Approach C is a separate plan (out of scope here).
- **No real-console tests:** all tests use the `MA2PushTransport` mock (Task 4) or are pure (Tasks 1–3).
- **Type consistency:** `MA2CommandPlanner.commands(...)`, `MA2TrigTime.command(...)`, `MA2CueNumber.commandString(...)`, `MA2CommandQuoting.quotable(...)`, `MA2PushRequestBuilder.commandOutcome(...) → CommandOutcome`, `MA2PushRunner.run(commands:host:username:password:)` — names are used identically across tasks.
- **Placeholder scan:** test bodies that construct `Cue` / `MediaItem` say to copy the real initializers from existing tests (the codebase's `Cue`/`MediaItem` inits are not reproduced here); every implementation step ships complete code.

## Execution note

This plan covers **Approach A only**. Approach C (plugin export) gets its own plan after A lands and is green on the self-hosted CI runner; it reuses `MA2CommandPlanner` (for the sequence half) and the existing `MA2SequenceXMLGenerator` / `MA2TimecodeXMLGenerator` (for the local-write timecode object). Do not open PR #684 → ready or merge until the owner approves and (per the spec) a real-console / real-LTC playback pass is scheduled for the DF case.
