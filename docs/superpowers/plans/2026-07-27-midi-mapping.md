# MIDI Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user drive OnlyCue from a MIDI controller (first target: KORG nanoKONTROL2) via generic MIDI-learn, input-only.

**Architecture:** Mirror the existing OSC subsystem — a thin CoreMIDI host (`MIDIInputHost`) over a pure, unit-tested `parse → match → dispatch` core. A `MIDIMap` (control-keyed bindings) persists in `UserDefaults` via `MIDIMapStore` (shape of `KeymapStore`/`LTCRoutingStore`). Discrete controls fire `KeymapAction`s (extended with new shared `GO`/`Stop`); faders drive three continuous targets.

**Tech Stack:** Swift 5.9+, SwiftUI, CoreMIDI (no third-party deps), XCTest.

## Global Constraints

- macOS deployment target 14.0; CoreMIDI APIs available on 14.0 only (ADR-001).
- No App Sandbox entitlement (ADR-007) — CoreMIDI needs none outside the sandbox.
- No third-party runtime dependency — hand-rolled, like the OSC stack.
- No `.cuelist` schema change — the map is a global machine preference.
- `ProjectModel` mutations route through `Commands/CueCommands.swift` only.
- Conventional Commits, lowercase after prefix, imperative; no `Co-Authored-By` trailers.
- TDD: failing test first, committed separately where practical; `swiftlint --strict` must stay green.
- New source files under `OnlyCue/` are auto-included by the target's folder rule; run `xcodegen generate` after adding files so `OnlyCue.xcodeproj` (uncommitted) picks them up.
- Tests inject their own `UserDefaults(suiteName:)` — never a global suppression flag (the #697 class of bug: keep all persistence gating per-instance / injected).

**Test scaffold used by several tasks** — a throwaway defaults suite (mirrors `LTCRoutingStoreTests`):

```swift
private let suiteName = "com.chienchuanw.OnlyCue.MIDIMapStoreTests"
private var defaults: UserDefaults!

override func setUpWithError() throws {
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
}

override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
}
```

---

## Slice / Leaf overview

Four independently-mergeable leaves, each its own PR into `dev`:

1. **Pure core** — `MIDIMessage`, `MIDIControlID`, `MIDIAction`, trigger/scaling. (Tasks 1–4)
2. **Map + store** — `MIDIMap`, `MIDIMapStore`. (Tasks 5–6)
3. **Action extension + dispatch** — `KeymapAction` +GO/Stop, `MIDICommandDispatcher`. (Tasks 7–8)
4. **CoreMIDI host + Settings UI** — `MIDIInputHost`, `MIDISettingsView`, `MIDIMonitorView`, wire-in. (Tasks 9–12)

---

## Task 1: `MIDIMessage` — parse raw MIDI bytes (Leaf 1)

**Files:**
- Create: `OnlyCue/MIDI/MIDIMessage.swift`
- Test: `OnlyCueTests/MIDIMessageTests.swift`

**Interfaces:**
- Produces: `enum MIDIMessage: Equatable, Sendable` with cases `note(channel: UInt8, number: UInt8, velocity: UInt8)`, `controlChange(channel: UInt8, number: UInt8, value: UInt8)` (channel 1…16), and `static func parse(_ bytes: [UInt8]) -> MIDIMessage?`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MIDIMessageTests: XCTestCase {
    func test_parse_noteOn_decodesChannelNumberVelocity() {
        // 0x90 = Note On, channel 0 (→ 1-based 1); note 60; velocity 100.
        XCTAssertEqual(MIDIMessage.parse([0x90, 60, 100]),
                       .note(channel: 1, number: 60, velocity: 100))
    }

    func test_parse_noteOff_becomesZeroVelocityNote() {
        // 0x82 = Note Off, channel 2 (→ 3); any release velocity → 0.
        XCTAssertEqual(MIDIMessage.parse([0x82, 60, 40]),
                       .note(channel: 3, number: 60, velocity: 0))
    }

    func test_parse_noteOnWithZeroVelocity_isZeroVelocityNote() {
        // Running-status "note off": Note On, velocity 0.
        XCTAssertEqual(MIDIMessage.parse([0x90, 60, 0]),
                       .note(channel: 1, number: 60, velocity: 0))
    }

    func test_parse_controlChange_decodesChannelNumberValue() {
        // 0xB0 = CC, channel 0 (→ 1); controller 45; value 127.
        XCTAssertEqual(MIDIMessage.parse([0xB0, 45, 127]),
                       .controlChange(channel: 1, number: 45, value: 127))
    }

    func test_parse_unsupportedStatus_returnsNil() {
        XCTAssertNil(MIDIMessage.parse([0xE0, 0, 64]))   // pitch bend
        XCTAssertNil(MIDIMessage.parse([0xC0, 5]))       // program change
    }

    func test_parse_truncated_returnsNil() {
        XCTAssertNil(MIDIMessage.parse([0x90, 60]))      // missing velocity
        XCTAssertNil(MIDIMessage.parse([]))              // empty
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDIMessageTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDIMessage' in scope` (run `xcodegen generate` first so the new test file compiles once created).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A MIDI message OnlyCue acts on. v1 recognises Note and Control Change only;
/// every other status byte parses to `nil`. Channel is stored 1-based (1…16).
///
/// Pure and hardware-free — the mapping from raw bytes is pinned by
/// `MIDIMessageTests`; the live CoreMIDI edge (`MIDIInputHost`) only feeds bytes
/// in. Mirrors `OSCCommand` / `OSCMessage`.
enum MIDIMessage: Equatable, Sendable {
    case note(channel: UInt8, number: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, number: UInt8, value: UInt8)

    static func parse(_ bytes: [UInt8]) -> MIDIMessage? {
        guard let status = bytes.first, status >= 0x80 else { return nil }
        let kind = status & 0xF0
        let channel = (status & 0x0F) + 1   // 1-based
        switch kind {
        case 0x90:                          // Note On
            guard bytes.count >= 3 else { return nil }
            return .note(channel: channel, number: bytes[1], velocity: bytes[2])
        case 0x80:                          // Note Off → zero-velocity note
            guard bytes.count >= 3 else { return nil }
            return .note(channel: channel, number: bytes[1], velocity: 0)
        case 0xB0:                          // Control Change
            guard bytes.count >= 3 else { return nil }
            return .controlChange(channel: channel, number: bytes[1], value: bytes[2])
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MIDI/MIDIMessage.swift OnlyCueTests/MIDIMessageTests.swift
git commit -m "feat(midi): parse Note/CC from raw MIDI bytes (#699)"
```

---

## Task 2: `MIDIControlID` — control identity + stable token (Leaf 1)

**Files:**
- Create: `OnlyCue/MIDI/MIDIControlID.swift`
- Test: `OnlyCueTests/MIDIControlIDTests.swift`

**Interfaces:**
- Consumes: `MIDIMessage` (Task 1).
- Produces: `struct MIDIControlID: Hashable, Codable, Sendable` with `enum Kind: String, Codable, Sendable { case note, cc }`, members `channel: UInt8`, `kind: Kind`, `number: UInt8`; `init(channel:kind:number:)`; failable `init?(message: MIDIMessage)`; `var token: String` (`"cc:1:45"`); failable `init?(token: String)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MIDIControlIDTests: XCTestCase {
    func test_initFromNote_isNoteKind() {
        let id = MIDIControlID(message: .note(channel: 1, number: 60, velocity: 100))
        XCTAssertEqual(id, MIDIControlID(channel: 1, kind: .note, number: 60))
    }

    func test_initFromCC_isCCKind_ignoringValue() {
        let id = MIDIControlID(message: .controlChange(channel: 2, number: 45, value: 0))
        XCTAssertEqual(id, MIDIControlID(channel: 2, kind: .cc, number: 45))
    }

    func test_token_roundTrips() {
        let id = MIDIControlID(channel: 3, kind: .cc, number: 7)
        XCTAssertEqual(id.token, "cc:3:7")
        XCTAssertEqual(MIDIControlID(token: id.token), id)
    }

    func test_initFromBadToken_returnsNil() {
        XCTAssertNil(MIDIControlID(token: "cc:3"))
        XCTAssertNil(MIDIControlID(token: "pitch:1:1"))
        XCTAssertNil(MIDIControlID(token: "cc:x:1"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDIControlIDTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDIControlID' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Identity of one physical control on a MIDI surface — the key of `MIDIMap`.
/// A control is `(channel, kind, number)`; its value (velocity / CC value) is
/// deliberately excluded so the same knob is one identity regardless of position.
///
/// `token` is the **stable on-disk string** (`"cc:1:45"`, `"note:1:60"`) used as
/// the JSON key in the persisted map — never change its shape without a migration.
struct MIDIControlID: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case note, cc }

    let channel: UInt8   // 1…16
    let kind: Kind
    let number: UInt8    // 0…127

    init(channel: UInt8, kind: Kind, number: UInt8) {
        self.channel = channel
        self.kind = kind
        self.number = number
    }

    init?(message: MIDIMessage) {
        switch message {
        case let .note(channel, number, _):
            self.init(channel: channel, kind: .note, number: number)
        case let .controlChange(channel, number, _):
            self.init(channel: channel, kind: .cc, number: number)
        }
    }

    var token: String { "\(kind.rawValue):\(channel):\(number)" }

    init?(token: String) {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let kind = Kind(rawValue: String(parts[0])),
              let channel = UInt8(parts[1]),
              let number = UInt8(parts[2])
        else { return nil }
        self.init(channel: channel, kind: kind, number: number)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MIDI/MIDIControlID.swift OnlyCueTests/MIDIControlIDTests.swift
git commit -m "feat(midi): add MIDIControlID identity + stable token (#699)"
```

---

## Task 3: `MIDIAction` + `ContinuousTarget` — bindable actions (Leaf 1)

**Files:**
- Create: `OnlyCue/MIDI/MIDIAction.swift`
- Test: `OnlyCueTests/MIDIActionTests.swift`

**Interfaces:**
- Consumes: `KeymapAction` (existing; extended in Task 7 — the two extra cases are not needed for this task's tests).
- Produces: `enum ContinuousTarget: String, Codable, CaseIterable, Sendable { case scrub, playbackRate, ltcLevel }` with `var displayName: String`; `enum MIDIAction: Equatable, Codable, Sendable` with `case discrete(KeymapAction)`, `case continuous(ContinuousTarget)`, `var token: String`, `init?(token: String)`, `var isContinuous: Bool`, `var displayName: String`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MIDIActionTests: XCTestCase {
    func test_discreteToken_roundTrips() {
        let action = MIDIAction.discrete(.playPause)
        XCTAssertEqual(action.token, "discrete:playPause")
        XCTAssertEqual(MIDIAction(token: action.token), action)
    }

    func test_continuousToken_roundTrips() {
        let action = MIDIAction.continuous(.scrub)
        XCTAssertEqual(action.token, "continuous:scrub")
        XCTAssertEqual(MIDIAction(token: action.token), action)
    }

    func test_badToken_returnsNil() {
        XCTAssertNil(MIDIAction(token: "discrete:notAnAction"))
        XCTAssertNil(MIDIAction(token: "continuous:zoom"))
        XCTAssertNil(MIDIAction(token: "bogus"))
    }

    func test_isContinuous() {
        XCTAssertTrue(MIDIAction.continuous(.ltcLevel).isContinuous)
        XCTAssertFalse(MIDIAction.discrete(.stepNextCue).isContinuous)
    }

    func test_codable_encodesAsTokenString() throws {
        let data = try JSONEncoder().encode(MIDIAction.continuous(.playbackRate))
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"continuous:playbackRate\"")
        XCTAssertEqual(try JSONDecoder().decode(MIDIAction.self, from: data),
                       .continuous(.playbackRate))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDIActionTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDIAction' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A continuous parameter a fader/knob (CC value 0…127, absolute) can drive.
enum ContinuousTarget: String, Codable, CaseIterable, Sendable {
    case scrub          // playhead position across the track
    case playbackRate   // rehearsal speed
    case ltcLevel       // LTC output amplitude

    var displayName: String {
        switch self {
        case .scrub: "Scrub Playhead"
        case .playbackRate: "Playback Rate"
        case .ltcLevel: "LTC Output Level"
        }
    }
}

/// What a MIDI control is bound to: either a discrete `KeymapAction` (fired on a
/// press edge) or a continuous `ContinuousTarget` (driven by a fader's value).
///
/// Encodes as a single **stable token string** (`"discrete:playPause"`,
/// `"continuous:scrub"`) so a `MIDIMap` persists as a flat `[token: token]` JSON
/// object — diffable and migration-friendly. Mirrors the token discipline of
/// `KeymapAction.rawValue`.
enum MIDIAction: Equatable, Codable, Sendable {
    case discrete(KeymapAction)
    case continuous(ContinuousTarget)

    var isContinuous: Bool { if case .continuous = self { return true } else { return false } }

    var displayName: String {
        switch self {
        case .discrete(let action): action.displayName
        case .continuous(let target): target.displayName
        }
    }

    var token: String {
        switch self {
        case .discrete(let action): "discrete:\(action.rawValue)"
        case .continuous(let target): "continuous:\(target.rawValue)"
        }
    }

    init?(token: String) {
        guard let separator = token.firstIndex(of: ":") else { return nil }
        let tag = String(token[..<separator])
        let value = String(token[token.index(after: separator)...])
        switch tag {
        case "discrete":
            guard let action = KeymapAction(rawValue: value) else { return nil }
            self = .discrete(action)
        case "continuous":
            guard let target = ContinuousTarget(rawValue: value) else { return nil }
            self = .continuous(target)
        default:
            return nil
        }
    }

    // Codable: a single token string (not a keyed container).
    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        guard let action = MIDIAction(token: token) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown MIDIAction token \(token)"))
        }
        self = action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MIDI/MIDIAction.swift OnlyCueTests/MIDIActionTests.swift
git commit -m "feat(midi): add MIDIAction (discrete/continuous) with stable tokens (#699)"
```

---

## Task 4: press-edge + continuous scaling (pure) (Leaf 1)

**Files:**
- Create: `OnlyCue/MIDI/MIDISignal.swift`
- Test: `OnlyCueTests/MIDISignalTests.swift`

**Interfaces:**
- Consumes: `MIDIMessage` (Task 1).
- Produces: `enum MIDISignal` with `static func isPressEdge(_ message: MIDIMessage, previousCCValue: UInt8?) -> Bool`; `static func normalized(_ value: UInt8) -> Double`; `static func scrubTime(value: UInt8, duration: TimeInterval) -> TimeInterval`; `static func playbackRate(value: UInt8, range: ClosedRange<Float>) -> Float`; `static func ltcLevel(value: UInt8) -> Float`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MIDISignalTests: XCTestCase {
    // Discrete press edge
    func test_noteOn_isPress() {
        XCTAssertTrue(MIDISignal.isPressEdge(.note(channel: 1, number: 60, velocity: 1),
                                             previousCCValue: nil))
    }
    func test_noteOff_isNotPress() {
        XCTAssertFalse(MIDISignal.isPressEdge(.note(channel: 1, number: 60, velocity: 0),
                                              previousCCValue: nil))
    }
    func test_cc_risingThrough64_isPress() {
        XCTAssertTrue(MIDISignal.isPressEdge(.controlChange(channel: 1, number: 45, value: 127),
                                             previousCCValue: 0))
    }
    func test_cc_stayingHigh_isNotPress() {
        XCTAssertFalse(MIDISignal.isPressEdge(.controlChange(channel: 1, number: 45, value: 100),
                                              previousCCValue: 127))
    }
    func test_cc_firstMessageAtHigh_isPress() {
        // No previous value → treat prior as 0, so a first ≥64 counts as a press.
        XCTAssertTrue(MIDISignal.isPressEdge(.controlChange(channel: 1, number: 45, value: 127),
                                             previousCCValue: nil))
    }

    // Continuous scaling
    func test_normalized_endpoints() {
        XCTAssertEqual(MIDISignal.normalized(0), 0, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.normalized(127), 1, accuracy: 0.0001)
    }
    func test_scrubTime_mapsAcrossDuration() {
        XCTAssertEqual(MIDISignal.scrubTime(value: 127, duration: 200), 200, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.scrubTime(value: 0, duration: 200), 0, accuracy: 0.0001)
    }
    func test_playbackRate_mapsToRangeEndpoints() {
        let range: ClosedRange<Float> = 0.1...3.0
        XCTAssertEqual(MIDISignal.playbackRate(value: 0, range: range), 0.1, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.playbackRate(value: 127, range: range), 3.0, accuracy: 0.0001)
    }
    func test_ltcLevel_endpoints() {
        XCTAssertEqual(MIDISignal.ltcLevel(value: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MIDISignal.ltcLevel(value: 127), 1, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDISignalTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDISignal' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Pure helpers turning a `MIDIMessage` into either a discrete "press" decision
/// or a scaled continuous value. Hardware-free; pinned by `MIDISignalTests`.
///
/// Discrete press semantics (spec default #2): a Note fires when velocity > 0; a
/// CC fires only on the rising edge that crosses the 64 midpoint (`<64 → ≥64`),
/// so a button's release (value 0) never double-fires.
enum MIDISignal {
    static func isPressEdge(_ message: MIDIMessage, previousCCValue: UInt8?) -> Bool {
        switch message {
        case .note(_, _, let velocity):
            return velocity > 0
        case .controlChange(_, _, let value):
            let wasBelow = (previousCCValue ?? 0) < 64
            return wasBelow && value >= 64
        }
    }

    static func normalized(_ value: UInt8) -> Double { Double(value) / 127.0 }

    static func scrubTime(value: UInt8, duration: TimeInterval) -> TimeInterval {
        normalized(value) * duration
    }

    static func playbackRate(value: UInt8, range: ClosedRange<Float>) -> Float {
        range.lowerBound + Float(normalized(value)) * (range.upperBound - range.lowerBound)
    }

    static func ltcLevel(value: UInt8) -> Float { Float(normalized(value)) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (10 tests).

- [ ] **Step 5: Commit + open Leaf 1 PR**

```bash
git add OnlyCue/MIDI/MIDISignal.swift OnlyCueTests/MIDISignalTests.swift
git commit -m "feat(midi): add press-edge detection + continuous scaling (#699)"
swiftlint lint --strict --quiet   # expect clean
```
Open PR (Leaf 1) into `dev` using the `feat` template; verify CI green before starting Leaf 2.

---

## Task 5: `MIDIMap` — control-keyed bindings (Leaf 2)

**Files:**
- Create: `OnlyCue/MIDI/MIDIMap.swift`
- Test: `OnlyCueTests/MIDIMapTests.swift`

**Interfaces:**
- Consumes: `MIDIControlID` (Task 2), `MIDIAction` (Task 3).
- Produces: `struct MIDIMap: Codable, Equatable, Sendable` with `static let default`, `func action(for: MIDIControlID) -> MIDIAction?`, `func controls(for: MIDIAction) -> [MIDIControlID]`, `mutating func learn(_ control: MIDIControlID, as: MIDIAction)`, `mutating func clear(_ control: MIDIControlID)`, `static func decode(_ data: Data?) -> MIDIMap`, `func encoded() throws -> Data`. On-disk shape: `[controlToken: actionToken]`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MIDIMapTests: XCTestCase {
    private let cc45 = MIDIControlID(channel: 1, kind: .cc, number: 45)
    private let note60 = MIDIControlID(channel: 1, kind: .note, number: 60)

    func test_default_isEmpty() {
        XCTAssertNil(MIDIMap.default.action(for: cc45))
    }

    func test_learn_thenLookup() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        XCTAssertEqual(map.action(for: cc45), .discrete(.playPause))
    }

    func test_learn_sameControlReassigns() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        map.learn(cc45, as: .continuous(.scrub))
        XCTAssertEqual(map.action(for: cc45), .continuous(.scrub))
    }

    func test_twoControlsMayShareAnAction() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        map.learn(note60, as: .discrete(.playPause))
        XCTAssertEqual(Set(map.controls(for: .discrete(.playPause))), [cc45, note60])
    }

    func test_clear_removesBinding() {
        var map = MIDIMap.default
        map.learn(cc45, as: .discrete(.playPause))
        map.clear(cc45)
        XCTAssertNil(map.action(for: cc45))
    }

    func test_encode_decode_roundTrips() throws {
        var map = MIDIMap.default
        map.learn(cc45, as: .continuous(.scrub))
        map.learn(note60, as: .discrete(.stepNextCue))
        XCTAssertEqual(MIDIMap.decode(try map.encoded()), map)
    }

    func test_decode_nilOrCorrupt_isEmpty() {
        XCTAssertEqual(MIDIMap.decode(nil), .default)
        XCTAssertEqual(MIDIMap.decode(Data("garbage".utf8)), .default)
    }

    func test_decode_dropsUnknownTokens() throws {
        // A stored map with one good and one bogus entry keeps only the good one.
        let json = #"{"cc:1:45":"continuous:scrub","bogus":"discrete:playPause","note:1:60":"continuous:zoom"}"#
        let map = MIDIMap.decode(Data(json.utf8))
        XCTAssertEqual(map.action(for: cc45), .continuous(.scrub))
        XCTAssertNil(map.action(for: note60))   // "continuous:zoom" is not a valid action
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDIMapTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDIMap' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// The user's MIDI bindings: one `MIDIAction` per physical control
/// (control-as-key, spec decision). Re-learning a control reassigns it; two
/// controls may map to the same action. Absent/corrupt data → empty map.
///
/// On disk it is a flat `{controlToken: actionToken}` JSON object (unknown or
/// unparseable entries are dropped on decode) — mirrors `Keymap`'s lenient
/// `[String: KeyChord]` shape.
struct MIDIMap: Codable, Equatable, Sendable {
    private(set) var bindings: [MIDIControlID: MIDIAction]

    static let `default` = Self(bindings: [:])

    init(bindings: [MIDIControlID: MIDIAction]) { self.bindings = bindings }

    // MARK: Queries

    func action(for control: MIDIControlID) -> MIDIAction? { bindings[control] }

    /// Controls currently bound to `action`, in no particular order.
    func controls(for action: MIDIAction) -> [MIDIControlID] {
        bindings.compactMap { $0.value == action ? $0.key : nil }
    }

    // MARK: Mutation

    mutating func learn(_ control: MIDIControlID, as action: MIDIAction) {
        bindings[control] = action
    }

    mutating func clear(_ control: MIDIControlID) {
        bindings[control] = nil
    }

    // MARK: Persistence

    static func decode(_ data: Data?) -> Self {
        guard let data,
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return .default }
        var bindings: [MIDIControlID: MIDIAction] = [:]
        for (controlToken, actionToken) in stored {
            if let control = MIDIControlID(token: controlToken),
               let action = MIDIAction(token: actionToken) {
                bindings[control] = action
            }
        }
        return Self(bindings: bindings)
    }

    func encoded() throws -> Data {
        let stored = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.token, $0.value.token) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(stored)
    }

    // MARK: Codable — delegate to the flat-token form above.

    init(from decoder: Decoder) throws {
        let stored = try decoder.singleValueContainer().decode([String: String].self)
        var bindings: [MIDIControlID: MIDIAction] = [:]
        for (controlToken, actionToken) in stored {
            if let control = MIDIControlID(token: controlToken),
               let action = MIDIAction(token: actionToken) {
                bindings[control] = action
            }
        }
        self.init(bindings: bindings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.token, $0.value.token) }))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MIDI/MIDIMap.swift OnlyCueTests/MIDIMapTests.swift
git commit -m "feat(midi): add control-keyed MIDIMap with lenient persistence (#699)"
```

---

## Task 6: `MIDIMapStore` — persisted single source of truth (Leaf 2)

**Files:**
- Create: `OnlyCue/App/MIDIMapStore.swift`
- Test: `OnlyCueTests/MIDIMapStoreTests.swift`

**Interfaces:**
- Consumes: `MIDIMap` (Task 5), `MIDIControlID`, `MIDIAction`.
- Produces: `@MainActor final class MIDIMapStore: ObservableObject` with `static let storageKey = "midiMap.v1"`, `static let shared`, `@Published private(set) var map: MIDIMap`, `init(defaults: UserDefaults = .standard)`, `func learn(_ control: MIDIControlID, as: MIDIAction)`, `func clear(_ control: MIDIControlID)`, `func resetAll()`, `func reload()`. Also `@Published private(set) var selectedInputUID: String?` with `func selectInput(uid: String?)`, persisted under `midiInput.v1`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class MIDIMapStoreTests: XCTestCase {
    private let suiteName = "com.chienchuanw.OnlyCue.MIDIMapStoreTests"
    private var defaults: UserDefaults!
    private let cc45 = MIDIControlID(channel: 1, kind: .cc, number: 45)

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func test_freshStore_isEmpty() {
        XCTAssertNil(MIDIMapStore(defaults: defaults).map.action(for: cc45))
    }

    func test_learn_persistsAndSurvivesReload() {
        let store = MIDIMapStore(defaults: defaults)
        store.learn(cc45, as: .discrete(.playPause))
        XCTAssertEqual(MIDIMapStore(defaults: defaults).map.action(for: cc45), .discrete(.playPause))
        store.reload()
        XCTAssertEqual(store.map.action(for: cc45), .discrete(.playPause))
    }

    func test_clear_persists() {
        let store = MIDIMapStore(defaults: defaults)
        store.learn(cc45, as: .discrete(.playPause))
        store.clear(cc45)
        XCTAssertNil(MIDIMapStore(defaults: defaults).map.action(for: cc45))
    }

    func test_resetAll_persists() {
        let store = MIDIMapStore(defaults: defaults)
        store.learn(cc45, as: .discrete(.playPause))
        store.resetAll()
        XCTAssertNil(MIDIMapStore(defaults: defaults).map.action(for: cc45))
    }

    func test_selectedInputUID_persists() {
        let store = MIDIMapStore(defaults: defaults)
        store.selectInput(uid: "device-1")
        XCTAssertEqual(MIDIMapStore(defaults: defaults).selectedInputUID, "device-1")
    }

    func test_twoInjectedStores_areIndependentPerDefaults() {
        // Regression guard for the #697 class: no global suppression; each store
        // reads/writes only its injected defaults.
        let storeA = MIDIMapStore(defaults: defaults)
        storeA.learn(cc45, as: .discrete(.stop))
        XCTAssertEqual(MIDIMapStore(defaults: defaults).map.action(for: cc45), .discrete(.stop))
    }
}
```

> Note: `test_twoInjectedStores…` references `.discrete(.stop)` — the `.stop` case is added in Task 7. If Leaf 2 is implemented before Leaf 3, substitute `.discrete(.stepNextCue)` here and update in Task 7. (Chosen ordering: Leaf 3 before this test line, or use the substitute.)

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDIMapStoreTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDIMapStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import SwiftUI

/// Single source of truth for the user's MIDI bindings (`MIDIMap`) and the
/// chosen input device UID, persisted as JSON in `UserDefaults` under
/// `midiMap.v1` / `midiInput.v1`. Corrupt or absent data → empty map / nil
/// device. Mirrors `KeymapStore` / `LTCRoutingStore`.
///
/// No global suppression flag — tests inject their own `UserDefaults`, so the
/// #697 class of "persistence silently disabled process-wide" cannot occur here.
@MainActor
final class MIDIMapStore: ObservableObject {

    static let storageKey = "midiMap.v1"
    static let inputKey = "midiInput.v1"
    static let shared = MIDIMapStore()

    @Published private(set) var map: MIDIMap
    @Published private(set) var selectedInputUID: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        map = MIDIMap.decode(defaults.data(forKey: Self.storageKey))
        selectedInputUID = defaults.string(forKey: Self.inputKey)
    }

    func learn(_ control: MIDIControlID, as action: MIDIAction) {
        map.learn(control, as: action)
        persist()
    }

    func clear(_ control: MIDIControlID) {
        map.clear(control)
        persist()
    }

    func resetAll() {
        map = .default
        persist()
    }

    func selectInput(uid: String?) {
        selectedInputUID = uid
        if let uid { defaults.set(uid, forKey: Self.inputKey) }
        else { defaults.removeObject(forKey: Self.inputKey) }
    }

    /// Re-reads from `UserDefaults` — mostly a hook for round-trip tests.
    func reload() {
        map = MIDIMap.decode(defaults.data(forKey: Self.storageKey))
        selectedInputUID = defaults.string(forKey: Self.inputKey)
    }

    private func persist() {
        guard let data = try? map.encoded() else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (6 tests).

- [ ] **Step 5: Commit + open Leaf 2 PR**

```bash
git add OnlyCue/App/MIDIMapStore.swift OnlyCueTests/MIDIMapStoreTests.swift
git commit -m "feat(midi): add persisted MIDIMapStore (map + input device) (#699)"
swiftlint lint --strict --quiet
```
Open PR (Leaf 2) into `dev`; verify CI green.

---

## Task 7: extend `KeymapAction` with `go` / `stop` (Leaf 3)

**Files:**
- Modify: `OnlyCue/App/KeymapAction.swift`
- Modify: `OnlyCue/App/Keymap.swift:93-128` (`defaultBindings`)
- Test: `OnlyCueTests/KeymapActionTests.swift` (create if absent; else append)

**Interfaces:**
- Produces: `KeymapAction.go`, `KeymapAction.stop` (rawValues `"go"`, `"stop"`), each with a `displayName` and a default `KeyChord`.

**Decision (flag for reviewer):** `go`/`stop` get real default chords so the map stays total and they appear in the Keyboard settings table: `go = Return`, `stop = Escape`. These are idiomatic (console GO / panic-stop) and unused in the current defaults. Actual keyboard *installation* of these two is out of scope for this leaf (no change to `AppCommands`/`DocumentView+Shortcuts`); they exist for MIDI binding and future keyboard opt-in. If the reviewer objects to reserving Return/Escape, change only these two `defaultBindings` values.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class KeymapActionTests: XCTestCase {
    func test_goAndStop_exist_withStableRawValues() {
        XCTAssertEqual(KeymapAction(rawValue: "go"), .go)
        XCTAssertEqual(KeymapAction(rawValue: "stop"), .stop)
    }
    func test_goAndStop_haveDisplayNames() {
        XCTAssertEqual(KeymapAction.go.displayName, "Go")
        XCTAssertEqual(KeymapAction.stop.displayName, "Stop")
    }
    func test_defaultKeymap_isTotalOverAllActions() {
        // Every action (incl. the new two) resolves to its default chord, so the
        // map stays total and the settings table has no phantom fallback chords.
        let map = Keymap.default
        for action in KeymapAction.allCases {
            XCTAssertNotNil(Keymap.defaultBindings[action], "missing default for \(action.rawValue)")
            _ = map.chord(for: action)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/KeymapActionTests -parallel-testing-enabled NO`
Expected: FAIL — `type 'KeymapAction' has no member 'go'`.

- [ ] **Step 3: Write minimal implementation**

In `KeymapAction.swift`, add the two cases after `case addCueOfType9` (before `var id`):

```swift
    // External control — shared with MIDI (#699). Show-mode GO (seek + play) and Stop.
    case go
    case stop
```

Add to the `displayNames` dictionary (before the closing `]`):

```swift
        .go: "Go",
        .stop: "Stop",
```

In `Keymap.swift`, add to `defaultBindings` (before the closing `]`):

```swift
        .go: KeyChord(key: "return"),
        .stop: KeyChord(key: "escape"),
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests). Also run the full existing `KeymapTests`/`OnlyCueTests` keymap suites to confirm no total-map assertion broke.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/App/KeymapAction.swift OnlyCue/App/Keymap.swift OnlyCueTests/KeymapActionTests.swift
git commit -m "feat(midi): add shared GO/Stop KeymapAction cases (#699)"
```

---

## Task 8: `MIDICommandDispatcher` — apply a matched action (Leaf 3)

**Files:**
- Create: `OnlyCue/MIDI/MIDICommandDispatcher.swift`
- Test: `OnlyCueTests/MIDICommandDispatcherTests.swift`

**Interfaces:**
- Consumes: `MIDIAction`, `MIDISignal`, `KeymapAction`, `PlayerEngine` (`play()`, `pause()`, `seek(to:) async`, `currentTime`, `duration`, `playbackRate`, `setPlaybackRate(_:)`, `Self.playbackRateRange`), `LTCRoutingStore` (`update(_:)`, `settings.settingAmplitude(_:)`).
- Produces: a **pure resolver** `enum MIDIEffect: Equatable { case play, pause, stop, seek(TimeInterval), setRate(Float), setLTCLevel(Float), keymap(KeymapAction) }` and `static func effect(for action: MIDIAction, value: UInt8, engine: MIDIEngineSnapshot) -> MIDIEffect?` where `struct MIDIEngineSnapshot { let currentTime, duration: TimeInterval; let rateRange: ClosedRange<Float> }`. The impure side (calling the engine / stores / `CueCommands`) lives in the host (Task 9) and is deliberately thin.

**Rationale:** keep the value→effect mapping pure and testable (like `OSCServerHost.resolvedSeekTime`); the host just executes the `MIDIEffect`. Discrete `KeymapAction`s that aren't transport (e.g. `addCue`, `stepNextCue`) surface as `.keymap(action)` for the host to route to the same primitives OSC uses.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MIDICommandDispatcherTests: XCTestCase {
    private let snap = MIDIEngineSnapshot(currentTime: 10, duration: 200, rateRange: 0.1...3.0)

    func test_continuousScrub_resolvesToSeekAcrossDuration() {
        let effect = MIDICommandDispatcher.effect(for: .continuous(.scrub), value: 127, engine: snap)
        XCTAssertEqual(effect, .seek(200))
    }
    func test_continuousRate_resolvesToSetRate() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .continuous(.playbackRate), value: 0, engine: snap),
                       .setRate(0.1))
    }
    func test_continuousLTC_resolvesToSetLevel() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .continuous(.ltcLevel), value: 127, engine: snap),
                       .setLTCLevel(1.0))
    }
    func test_discretePlayPause_resolvesToKeymap() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .discrete(.playPause), value: 127, engine: snap),
                       .keymap(.playPause))
    }
    func test_discreteStop_resolvesToKeymapStop() {
        XCTAssertEqual(MIDICommandDispatcher.effect(for: .discrete(.stop), value: 127, engine: snap),
                       .keymap(.stop))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDICommandDispatcherTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDICommandDispatcher' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A snapshot of the engine state the pure resolver needs — passed in so the
/// resolver stays free of `@MainActor` / live objects and is unit-testable.
struct MIDIEngineSnapshot: Equatable {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let rateRange: ClosedRange<Float>
}

/// The concrete effect a matched MIDI action produces. The host executes it
/// against the live engine / stores / `CueCommands`.
enum MIDIEffect: Equatable {
    case seek(TimeInterval)
    case setRate(Float)
    case setLTCLevel(Float)
    case keymap(KeymapAction)
}

/// Pure resolver: `(action, value, engine snapshot) → effect`. Continuous
/// targets scale via `MIDISignal` (absolute snap, spec decision); discrete
/// actions pass through as `.keymap` for the host to route to the same
/// primitives OSC uses. Pinned by `MIDICommandDispatcherTests`.
enum MIDICommandDispatcher {
    static func effect(for action: MIDIAction, value: UInt8, engine: MIDIEngineSnapshot) -> MIDIEffect? {
        switch action {
        case .continuous(.scrub):
            return .seek(MIDISignal.scrubTime(value: value, duration: engine.duration))
        case .continuous(.playbackRate):
            return .setRate(MIDISignal.playbackRate(value: value, range: engine.rateRange))
        case .continuous(.ltcLevel):
            return .setLTCLevel(MIDISignal.ltcLevel(value: value))
        case .discrete(let keymapAction):
            return .keymap(keymapAction)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (5 tests).

- [ ] **Step 5: Commit + open Leaf 3 PR**

```bash
git add OnlyCue/MIDI/MIDICommandDispatcher.swift OnlyCueTests/MIDICommandDispatcherTests.swift
git commit -m "feat(midi): add pure MIDI action→effect resolver (#699)"
swiftlint lint --strict --quiet
```
Open PR (Leaf 3) into `dev`; verify CI green.

---

## Task 9: `MIDIInputHost` — CoreMIDI edge + dispatch wiring (Leaf 4)

**Files:**
- Create: `OnlyCue/MIDI/MIDIInput.swift` (thin CoreMIDI wrapper — the untested edge)
- Create: `OnlyCue/UI/MIDIInputHost.swift` (ViewModifier — mirrors `OSCServerHost`)
- Test: `OnlyCueTests/MIDIInputHostTests.swift` (pure dispatch-routing only)

**Interfaces:**
- Consumes: `MIDIMessage.parse`, `MIDISignal.isPressEdge`, `MIDIMapStore.shared`, `MIDICommandDispatcher.effect`, `MIDIEffect`, `PlayerEngine`, `CueListDocument`, `LTCRoutingStore.shared`, and the existing document primitives used by `OSCServerHost` (`CueCommands.addCueAtPlayhead`, `CueCreationGate`, `MediaItem.cue(steppingFrom:…)`, `item.showGoDecision(from:typeID:)`).
- Produces: `final class MIDIInput` (`@Observable`) with `var onMessage: ((MIDIMessage) -> Void)?`, `private(set) var recentMessages: [String]`, `func start(inputUID: String?)`, `func stop()`, `func availableSources() -> [(uid: String, name: String)]`, `static func formatLine(for:) -> String`, `func clearRecentMessages()`; and `struct MIDIInputHost: ViewModifier` + `View.midiInputHost(engine:document:undoManager:editorMode:showGoTypeID:)`.

**CoreMIDI note (thin, untested edge — like `OSCServer`'s socket code):** create one `MIDIClientRef` via `MIDIClientCreateWithBlock` (subscribe to `MIDIObjectAddRemoveNotification` for hot-plug), one input port via `MIDIInputPortCreateWithProtocol(_, ._1_0, …)`, and `MIDIPortConnectSource` to the source whose `kMIDIPropertyUniqueID`/name matches `inputUID` (nil → connect none). In the read block, walk the `MIDIEventList` (or use the legacy `MIDIPacketList` API) and hand each 3-byte status message to `MIDIMessage.parse`, then `onMessage`. Coalesce continuous CC (keep only the latest value per control per run-loop tick) before dispatch (spec default #5) by scheduling a `DispatchQueue.main.async` drain of a `[MIDIControlID: UInt8]` pending-values dict.

- [ ] **Step 1: Write the failing test** (pure routing, no CoreMIDI)

Add a pure, host-independent router the ViewModifier also uses, so it is testable without CoreMIDI or a live document:

```swift
import XCTest
@testable import OnlyCue

final class MIDIInputHostTests: XCTestCase {
    // Press-edge gating: a CC button release must not fire the discrete action.
    func test_shouldDispatchDiscrete_onlyOnPressEdge() {
        let press = MIDIMessage.controlChange(channel: 1, number: 45, value: 127)
        let release = MIDIMessage.controlChange(channel: 1, number: 45, value: 0)
        XCTAssertTrue(MIDIDispatchGate.shouldFireDiscrete(press, previousCCValue: 0))
        XCTAssertFalse(MIDIDispatchGate.shouldFireDiscrete(release, previousCCValue: 127))
    }
    // Continuous always dispatches (no edge gating).
    func test_continuous_alwaysDispatches() {
        let move = MIDIMessage.controlChange(channel: 1, number: 45, value: 64)
        XCTAssertTrue(MIDIDispatchGate.shouldFireContinuous(move))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MIDIInputHostTests -parallel-testing-enabled NO`
Expected: FAIL — `cannot find 'MIDIDispatchGate' in scope`.

- [ ] **Step 3: Write minimal implementation**

Add the tiny pure gate (in `OnlyCue/MIDI/MIDIInput.swift` or a small `MIDIDispatchGate.swift`):

```swift
enum MIDIDispatchGate {
    static func shouldFireDiscrete(_ message: MIDIMessage, previousCCValue: UInt8?) -> Bool {
        MIDISignal.isPressEdge(message, previousCCValue: previousCCValue)
    }
    static func shouldFireContinuous(_ message: MIDIMessage) -> Bool {
        if case .controlChange = message { return true } else { return true }
    }
}
```

Then implement `MIDIInput` (CoreMIDI wrapper) and `MIDIInputHost` (ViewModifier) mirroring `OSCServer`/`OSCServerHost`. The host's dispatch — executed on the main actor — resolves and applies effects:

```swift
private func dispatch(_ message: MIDIMessage) {
    input.appendRecent(message)                    // monitor buffer
    if learnSession.isActive {                     // Learn intercepts (Task 11)
        learnSession.capture(message); return
    }
    guard let control = MIDIControlID(message: message),
          let action = MIDIMapStore.shared.map.action(for: control) else { return }

    let value: UInt8 = {                           // velocity or CC value
        switch message { case .note(_, _, let v): return v; case .controlChange(_, _, let v): return v }
    }()

    if action.isContinuous {
        apply(MIDICommandDispatcher.effect(for: action, value: value, engine: snapshot()))
    } else if MIDIDispatchGate.shouldFireDiscrete(message, previousCCValue: previousCC[control]) {
        apply(MIDICommandDispatcher.effect(for: action, value: value, engine: snapshot()))
    }
    if case .controlChange(_, _, let v) = message { previousCC[control] = v }
}

private func snapshot() -> MIDIEngineSnapshot {
    MIDIEngineSnapshot(currentTime: engine.currentTime, duration: engine.duration,
                       rateRange: PlayerEngine.playbackRateRange)
}

private func apply(_ effect: MIDIEffect?) {
    guard let effect else { return }
    switch effect {
    case .seek(let t):        seekTask?.cancel(); seekTask = Task { await engine.seek(to: t) }
    case .setRate(let r):     engine.setPlaybackRate(r)
    case .setLTCLevel(let l): LTCRoutingStore.shared.update(LTCRoutingStore.shared.settings.settingAmplitude(l))
    case .keymap(let a):      applyKeymap(a)
    }
}

// Routes a KeymapAction to the SAME primitives OSCServerHost uses. GO/Stop and
// the transport/cue subset are handled here; editing actions no-op for v1 MIDI
// unless already reachable (documented). Reuse goNextCueAndPlay/step from OSC.
private func applyKeymap(_ action: KeymapAction) {
    switch action {
    case .playPause: engine.rate == 0 ? engine.play() : engine.pause()
    case .stop:      engine.pause(); seekTask?.cancel(); seekTask = Task { await engine.seek(to: 0) }
    case .go:        goNextCueAndPlay()
    case .stepNextCue: step(.next)
    case .stepPrevCue: step(.previous)
    case .addCue:
        guard CueCreationGate.allows(editorMode: editorMode, hasActiveItem: document.model.activeItem != nil) else { break }
        CueCommands.addCueAtPlayhead(time: engine.currentTime, document: document, undoManager: undoManager)
    default: break   // other KeymapActions not wired to MIDI in v1
    }
}
```

Copy `goNextCueAndPlay()` / `step(_:)` verbatim from `OSCServerHost` (or extract a shared `DocumentTransport` helper in a follow-up; not required for v1 — YAGNI). `snapshot`, `previousCC`, `seekTask`, `learnSession` are `@State` on the modifier.

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests). The CoreMIDI paths are exercised manually in Task 12.

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add OnlyCue/MIDI/ OnlyCue/UI/MIDIInputHost.swift OnlyCueTests/MIDIInputHostTests.swift
git commit -m "feat(midi): add CoreMIDI input host + effect dispatch (#699)"
```

---

## Task 10: attach the host + Settings monitor notification (Leaf 4)

**Files:**
- Modify: `OnlyCue/UI/DocumentView.swift` (add `.midiInputHost(…)` next to the existing `.oscServerHost(…)`)
- Create: `OnlyCue/UI/AppNotifications.swift` addition or new `Notification.Name.midiMonitorRequested` (mirror `.oscMonitorRequested`)

**Interfaces:**
- Consumes: `View.midiInputHost(...)` (Task 9), `MIDIMapStore.shared`.

- [ ] **Step 1: Attach the modifier**

Find the `.oscServerHost(engine:…)` call in `DocumentView.swift` and add directly below it:

```swift
.midiInputHost(
    engine: engine,
    document: document,
    undoManager: undoManager,
    editorMode: editorMode,
    showGoTypeID: showGoTypeID
)
```

- [ ] **Step 2: Add the monitor notification**

Mirror `.oscMonitorRequested` — add `static let midiMonitorRequested = Notification.Name("midiMonitorRequested")` wherever `oscMonitorRequested` is declared.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/DocumentView.swift OnlyCue/UI/AppNotifications.swift
git commit -m "feat(midi): attach MIDI input host to the document window (#699)"
```

---

## Task 11: `MIDISettingsView` + Learn (Leaf 4)

**Files:**
- Create: `OnlyCue/UI/MIDISettingsView.swift`
- Modify: the Settings scene (wherever `OSCSettingsView` / `KeyboardSettingsView` are added as tabs) to add a **MIDI** tab.

**Interfaces:**
- Consumes: `MIDIMapStore.shared`, `MIDIInput.availableSources()`, `MIDIAction`, `ContinuousTarget`, `KeymapAction.allCases`.
- Produces: `struct MIDISettingsView: View`; a `@MainActor final class MIDILearnSession: ObservableObject` with `@Published var isActive: Bool`, `@Published var target: MIDIAction?`, `func begin(_:)`, `func capture(_ message: MIDIMessage)`, `func cancel()`, `var onLearned: ((MIDIControlID, MIDIAction) -> Void)?`.

**UI shape (mirrors `KeyboardSettingsView` + `OSCSettingsView`):** a device `Picker` bound to `MIDIMapStore.shared.selectedInputUID`; a `List` with one section of continuous targets (`ContinuousTarget.allCases`) and one of discrete actions (a curated live subset first: `playPause, stop, go, stepPrevCue, stepNextCue, addCue`, then the rest of `KeymapAction.allCases`), each row showing the bound control token(s) or "—" plus **Learn** / **Clear** buttons. Learn sets `MIDILearnSession.target`; the next `MIDIMessage` the host feeds to the session binds it via `MIDIMapStore.shared.learn`.

- [ ] **Step 1: Manual test criteria (BDD)** — no unit test (SwiftUI view + live MIDI); verified in Task 12.

- [ ] **Step 2: Implement `MIDILearnSession`** (pure enough to unit-test the capture step)

```swift
@MainActor
final class MIDILearnSession: ObservableObject {
    @Published private(set) var target: MIDIAction?
    var isActive: Bool { target != nil }
    var onLearned: ((MIDIControlID, MIDIAction) -> Void)?

    func begin(_ action: MIDIAction) { target = action }
    func cancel() { target = nil }

    func capture(_ message: MIDIMessage) {
        guard let action = target, let control = MIDIControlID(message: message) else { return }
        onLearned?(control, action)
        target = nil
    }
}
```

- [ ] **Step 3: Write the failing test for capture**

```swift
@MainActor
final class MIDILearnSessionTests: XCTestCase {
    func test_capture_bindsFirstMessageToTarget_thenEnds() {
        let session = MIDILearnSession()
        var learned: (MIDIControlID, MIDIAction)?
        session.onLearned = { learned = ($0, $1) }
        session.begin(.discrete(.playPause))
        session.capture(.controlChange(channel: 1, number: 45, value: 127))
        XCTAssertEqual(learned?.0, MIDIControlID(channel: 1, kind: .cc, number: 45))
        XCTAssertEqual(learned?.1, .discrete(.playPause))
        XCTAssertFalse(session.isActive)
    }
    func test_capture_whenInactive_doesNothing() {
        let session = MIDILearnSession()
        var called = false
        session.onLearned = { _, _ in called = true }
        session.capture(.note(channel: 1, number: 60, velocity: 100))
        XCTAssertFalse(called)
    }
}
```

Run it (fails → passes) with the same `xcodebuild … -only-testing:OnlyCueTests/MIDILearnSessionTests …` pattern.

- [ ] **Step 4: Implement `MIDISettingsView`** and register the Settings tab (mirror the existing OSC/Keyboard tab registration). Wire `MIDILearnSession.onLearned = { MIDIMapStore.shared.learn($0, as: $1) }`; the host (Task 9) forwards messages to the shared session while `isActive`.

- [ ] **Step 5: Build + commit**

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'   # BUILD SUCCEEDED
git add OnlyCue/UI/MIDISettingsView.swift OnlyCueTests/MIDILearnSessionTests.swift OnlyCue/App/*Settings*.swift
git commit -m "feat(midi): add Settings → MIDI pane with MIDI-learn (#699)"
```

---

## Task 12: `MIDIMonitorView` + manual verification (Leaf 4)

**Files:**
- Create: `OnlyCue/UI/MIDIMonitorView.swift` (mirror `OSCMonitorView`)

**Interfaces:**
- Consumes: `MIDIInput.recentMessages`, `MIDIInput.clearRecentMessages()`, `.midiMonitorRequested`.

- [ ] **Step 1: Implement the monitor** — a sheet listing `input.recentMessages` (formatted `HH:mm:ss  CC  ch1  #45  127`) with a Clear button, presented on `.midiMonitorRequested` (mirror `OSCServerHost`'s `.sheet(isPresented:)` + `OSCMonitorView`).

- [ ] **Step 2: Build**

Run: `xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual acceptance (real nanoKONTROL2 or IAC + a MIDI sender)**

Verify each BDD scenario from issue #699:
- Select the input device → the monitor shows incoming CC/Note lines.
- Learn `Play/Pause` on a button → its press toggles playback; its release does nothing.
- Learn a fader to `Scrub Playhead` → moving 0→127 seeks 0→duration (absolute snap).
- Learn a fader to `LTC Output Level` / `Playback Rate` → values track.
- Re-learn a bound control for a different action → it moves (control-as-key).
- Quit & relaunch → bindings and device selection persist.

- [ ] **Step 4: Full suite + lint**

```bash
rm -f /tmp/.onlycue-ci-active
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests -parallel-testing-enabled NO
swiftlint lint --strict --quiet
```
Expected: all green.

- [ ] **Step 5: Commit + open Leaf 4 PR**

```bash
git add OnlyCue/UI/MIDIMonitorView.swift
git commit -m "feat(midi): add live MIDI monitor sheet (#699)"
```
Open PR (Leaf 4) into `dev`. This PR closes #699.

---

## Self-Review

**1. Spec coverage** (`docs/superpowers/specs/2026-07-25-midi-mapping-design.md`):
- Generic MIDI-learn → Tasks 11 (`MIDILearnSession`) ✓
- Input-only → no output path anywhere ✓
- CoreMIDI, no deps → Task 9 (`MIDIInput`) ✓
- Discrete = KeymapAction + GO/Stop → Tasks 7, 8 ✓
- Continuous = scrub/rate/LTC, absolute → Tasks 4, 8 ✓
- Control-as-key, reassign, shared → Task 5 ✓
- Absolute snap → Task 4/8 (no soft-takeover code) ✓
- Global `UserDefaults` `midiMap.v1` → Task 6 ✓
- One input device by UID → Task 6 (`selectedInputUID`) + Task 9 (`start(inputUID:)`) ✓
- Settings pane + Learn + monitor → Tasks 11, 12 ✓
- Defaults #1 empty (Task 5), #2 press-edge (Task 4/9), #3 both modes (host attached unconditionally in Task 10; editing gate via `CueCreationGate` mirrors OSC), #4 LTC-rate interlock (uses `engine.setPlaybackRate`, which the interlock already governs — documented, not fought), #5 CC coalescing (Task 9 note) ✓
- Out-of-scope items: none implemented ✓
- ADR/hard-rule checks: Global Constraints ✓

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Task 9's CoreMIDI wrapper and Tasks 11/12 SwiftUI views describe concrete structure with the key code shown; the CoreMIDI byte-walk and full view bodies are the thin, manually-verified edge (consistent with `OSCServer` socket code being untested) — acceptable, not a placeholder for logic-bearing code.

**3. Type consistency:** `MIDIControlID(message:)`, `MIDIAction.token`/`init?(token:)`, `MIDIMap.learn(_:as:)`/`action(for:)`/`controls(for:)`, `MIDIMapStore.learn/clear/resetAll/selectInput/reload`, `MIDIEngineSnapshot(currentTime:duration:rateRange:)`, `MIDIEffect` cases, `MIDISignal.isPressEdge/scrubTime/playbackRate/ltcLevel`, `MIDIDispatchGate.shouldFireDiscrete/Continuous`, `MIDILearnSession.begin/capture/cancel/onLearned` — names are consistent across tasks. `PlayerEngine` members (`play`,`pause`,`seek(to:)`,`currentTime`,`duration`,`setPlaybackRate`,`playbackRateRange`) verified against source. One noted cross-leaf coupling: Task 6's `.discrete(.stop)` needs Task 7 — flagged with a substitute if leaves land out of order.
