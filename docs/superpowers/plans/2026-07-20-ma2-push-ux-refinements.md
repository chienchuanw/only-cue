# grandMA2 push UX refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add console discovery to Settings, an editable/sanitized sequence name to the push sheet (persisted, schema v18), and cue-info (`/info=`) emission on the live telnet path — for the grandMA2 push (#686, extends #683 / v0.15.0).

**Architecture:** Three mostly-independent additions on top of the shipped push. `MA2ConsoleScanner` (async, injected probe + subnet list) scans interface /24s for a banner-verified console. `MA2Name.sanitize` produces an ASCII-only sequence name; it's stored on `MA2PushTarget.sequenceName` (schema v17→v18) and threaded through `MA2PushRequestBuilder`. `MA2CommandPlanner` gains a `/info=` line per cue with notes. UI: a Scan combo in `MA2SettingsView`, a Sequence-name field in `MA2PushSheet`.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `Network.framework` (`NWConnection`/`NWListener`), `getifaddrs`, xcodegen.

## Global Constraints

- Swift 6, macOS ≥ 14.0 (ADR-001); `swiftlint lint --strict` clean (multi-line calls one-arg-per-line; no `force_unwrapping` in tests).
- No direct `ProjectModel` mutations — via `Commands/CueCommands.swift` (reuse `setMA2PushTarget`).
- Conventional Commits, lowercase imperative, **no** `Co-Authored-By`.
- Schema bump is mandatory: `ProjectModel.currentSchemaVersion` 17 → 18 + a `migrateFromV17`.
- No test touches a real network — `NWListener` fixtures / injected probes only.
- Regenerate the project after adding files: `xcodegen generate`. Filter test noise with `2>&1 | grep -v "Connection\]"`.

## Reference types (already in the codebase)

- `MA2PushTarget` (struct, synthesized memberwise init + Codable): `sequenceSlot`, `timecodeSlot`, `executorPage`, `executorNumber`, `timecodeCommand: MA2TimecodeCommand`, `includedTypeIDs: Set<UUID>`, `isValid`.
- `MA2CommandPlanner.commands(cues:target:sequenceName:startTimecodeFrames:framerate:) -> [String]`; uses `MA2CueNumber.commandString`, `MA2CommandQuoting.quotable`, `MA2TrigTime.command`, `FadeTime.formatNumber`.
- `MA2PushRequestBuilder`: `commandOutcome(item:target:framerate:) -> CommandOutcome`, `outcome(item:target:framerate:showfile:datetime:) -> Outcome`, `pluginOutcome(item:target:framerate:datetime:) -> PluginOutcome`. `outcome`/`commandOutcome` currently pass `item.resolvedName` as the sequence name.
- `Cue`: `notes: String`, `name`, `cueNumber: Double?`, `time`, `fadeTime`.
- `ProjectModel.currentSchemaVersion = 17`; dispatcher `ProjectModel.decode(from:)` in `ProjectModel+Migration.swift` (`case 16: migrateFromV16(data:)`, `case currentSchemaVersion: decode directly`). `migrateFromV16` in `ProjectModel+MigrationV16.swift` decodes a `LegacyV16` snapshot and re-stamps `currentSchemaVersion`.
- `MA2SettingsView` — `@AppStorage(MA2ConnectionSettings.hostKey) host`, plain `TextField`.
- `MA2PushSheet` — `init(item:cuePointTypes:framerate:showfile:onSaveTarget:onDismiss:)`; seeds a default target `MA2PushTarget(sequenceSlot:1, timecodeSlot:1, executorPage:1, executorNumber:1, timecodeCommand:.goto, includedTypeIDs:[])`; `currentTarget` computed from `@State` slot fields; `prepare()` calls `commandOutcome`; `onSaveTarget(target)`.
- `MA2SequenceXMLGenerator.escape`; `MediaItem.resolvedName`.

---

### Task 1: `MA2Name.sanitize` — ASCII-only sequence name

**Files:**

- Create: `OnlyCue/MA2/MA2Name.swift`
- Test: `OnlyCueTests/MA2NameTests.swift`

**Interfaces:**

- Produces: `enum MA2Name { static func sanitize(_ raw: String, fallbackSlot: Int) -> String }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MA2NameTests: XCTestCase {
    func test_passesThroughPlainAscii() {
        XCTAssertEqual(MA2Name.sanitize("Opening", fallbackSlot: 5), "Opening")
    }
    func test_dropsNonAscii_andCollapsesWhitespace() {
        XCTAssertEqual(MA2Name.sanitize("開場  Intro", fallbackSlot: 5), "Intro")
        XCTAssertEqual(MA2Name.sanitize("Café  Set", fallbackSlot: 5), "Caf Set")
    }
    func test_stripsDoubleQuotes() {
        XCTAssertEqual(MA2Name.sanitize("a\"b\"c", fallbackSlot: 5), "abc")
    }
    func test_fallsBackWhenEmptyAfterSanitizing() {
        XCTAssertEqual(MA2Name.sanitize("純中文", fallbackSlot: 900), "OnlyCue 900")
        XCTAssertEqual(MA2Name.sanitize("   ", fallbackSlot: 7), "OnlyCue 7")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests/MA2NameTests`
Expected: FAIL — `MA2Name` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Sanitizes a clip name into a grandMA2-safe sequence name (#686): ASCII
/// printable only (MA names are effectively ASCII), embedded double quotes
/// stripped, whitespace runs collapsed. Falls back to `OnlyCue <slot>` when
/// nothing usable survives (e.g. an all-CJK name).
enum MA2Name {
    static func sanitize(_ raw: String, fallbackSlot: Int) -> String {
        let asciiPrintable = raw.unicodeScalars
            .filter { $0.isASCII && $0.value >= 0x20 && $0.value != 0x22 }  // 0x22 = "
            .map(Character.init)
        let collapsed = String(asciiPrintable)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        return collapsed.isEmpty ? "OnlyCue \(fallbackSlot)" : collapsed
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2Name.swift OnlyCueTests/MA2NameTests.swift
git commit -m "feat(ma2): add ascii sequence-name sanitizer"
```

---

### Task 2: `MA2PushTarget.sequenceName` + schema v18 migration

**Files:**

- Modify: `OnlyCue/MA2/MA2PushTarget.swift`
- Modify: `OnlyCue/Document/ProjectModel.swift` (`currentSchemaVersion` 17 → 18)
- Modify: `OnlyCue/Document/ProjectModel+Migration.swift` (add `case 17`)
- Create: `OnlyCue/Document/ProjectModel+MigrationV17.swift`
- Test: `OnlyCueTests/MA2PushTargetTests.swift` + `OnlyCueTests/ProjectModelMigrationV17Tests.swift`

**Interfaces:**

- Produces: `MA2PushTarget.sequenceName: String?` (default `nil`); `ProjectModel.migrateFromV17(data:) throws -> ProjectModel`.

- [ ] **Step 1: Write the failing tests**

Add to `MA2PushTargetTests.swift`:

```swift
func test_sequenceName_defaultsNil_andRoundTrips() throws {
    let target = MA2PushTarget(
        sequenceSlot: 1, timecodeSlot: 1, executorPage: 1, executorNumber: 1,
        timecodeCommand: .goto, includedTypeIDs: []
    )
    XCTAssertNil(target.sequenceName)

    var named = target
    named.sequenceName = "Opening"
    let data = try JSONEncoder().encode(named)
    let decoded = try JSONDecoder().decode(MA2PushTarget.self, from: data)
    XCTAssertEqual(decoded.sequenceName, "Opening")
}

func test_decodesLegacyTargetWithoutSequenceName_asNil() throws {
    let json = """
    {"sequenceSlot":1,"timecodeSlot":1,"executorPage":1,"executorNumber":1,"timecodeCommand":"goto","includedTypeIDs":[]}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(MA2PushTarget.self, from: json)
    XCTAssertNil(decoded.sequenceName)
}
```

Create `ProjectModelMigrationV17Tests.swift` (mirror an existing migration test — copy the fixture-building helper from `ProjectModelMigrationV16Tests` if present):

```swift
import XCTest
@testable import OnlyCue

final class ProjectModelMigrationV17Tests: XCTestCase {
    func test_v17Document_migratesToCurrent_withNilSequenceName() throws {
        // A minimal v17 document: one item with an ma2PushTarget lacking sequenceName.
        let json = """
        {"schemaVersion":17,"id":"\(UUID())","name":"P","cuePointTypes":[],"items":[],"activeItemID":null,
         "timecodeSettings":{"framerate":"30","startTimecodeFrames":0},"playbackMode":"stop"}
        """.data(using: .utf8)!
        let model = try ProjectModel.decode(from: json)
        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
    }
}
```

> Before running, open `ProjectModel.swift` and an existing migration test to copy the exact JSON shape of `timecodeSettings` / `playbackMode` (field names/values) so the fixture decodes. Adjust the fixture to match.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test … -only-testing:OnlyCueTests/MA2PushTargetTests -only-testing:OnlyCueTests/ProjectModelMigrationV17Tests`
Expected: FAIL — no `sequenceName`; `migrateFromV17` missing (v17 doc hits the `currentSchemaVersion` case or default and either decodes as-is or throws — the schemaVersion assert fails once current is 18).

- [ ] **Step 3: Write minimal implementation**

In `MA2PushTarget.swift`, add the property (default keeps the memberwise init source-compatible):

```swift
    /// User-facing English sequence name (#686). `nil` = derive from the clip's
    /// sanitized resolved name at push time.
    var sequenceName: String?
```

Place it after `includedTypeIDs`, with `= nil`? Swift's memberwise init needs the default so existing call sites compile:

```swift
    var includedTypeIDs: Set<UUID>
    var sequenceName: String? = nil
```

In `ProjectModel.swift`: `static let currentSchemaVersion = 18`.

In `ProjectModel+Migration.swift`, add to the switch before the `currentSchemaVersion` case:

```swift
        case 17: return try migrateFromV17(data: data)
```

Create `ProjectModel+MigrationV17.swift` (mirror `MigrationV16`):

```swift
import Foundation

/// v17 → v18 migration: `MA2PushTarget` gains the optional `sequenceName`
/// (#686, defaults to nil). A v17 document never wrote it, so this is
/// structurally a no-op — decode a `LegacyV17` snapshot and re-stamp the
/// current schema version. `items: [MediaItem]` decodes directly because the
/// only change is a nested optional field (missing key → nil).
extension ProjectModel {

    static func migrateFromV17(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV17.self, from: data)
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items,
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings,
            playbackMode: legacy.playbackMode
        )
    }

    private struct LegacyV17: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [MediaItem]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
        let playbackMode: PlaybackMode
    }
}
```

> Confirm `ProjectModel.init(...)` argument labels match `MigrationV16`'s call (they should be identical). If `ProjectModel` has more required init params, copy them from `migrateFromV16`.

- [ ] **Step 4: Run tests to verify they pass** — same command as Step 2. Expected: PASS. Then the full suite to confirm no other migration/round-trip test broke:

`xcodebuild test … -only-testing:OnlyCueTests 2>&1 | grep -v "Connection\]" | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -2`

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PushTarget.swift OnlyCue/Document/ProjectModel.swift OnlyCue/Document/ProjectModel+Migration.swift OnlyCue/Document/ProjectModel+MigrationV17.swift OnlyCueTests/MA2PushTargetTests.swift OnlyCueTests/ProjectModelMigrationV17Tests.swift
git commit -m "feat(ma2): persist sequence name on push target (schema v18)"
```

---

### Task 3: `MA2CommandPlanner` — emit cue `/info=`

**Files:**

- Modify: `OnlyCue/MA2/MA2CommandPlanner.swift`
- Test: `OnlyCueTests/MA2CommandPlannerTests.swift`

**Interfaces:** unchanged signature; new command lines only.

- [ ] **Step 1: Write the failing test** (add to `MA2CommandPlannerTests`, reuse its `cue`/`target` helpers — extend `cue` with a `notes:` param):

```swift
func test_emitsInfo_forCueWithNotes_singleLinedAndQuoteStripped() {
    let c = Cue(
        id: UUID(), typeID: UUID(), cueNumber: 1, name: "C",
        time: 0, notes: "line1\nline2 \"q\"", fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
    )
    let commands = MA2CommandPlanner.commands(
        cues: [c],
        target: target(),
        sequenceName: "S",
        startTimecodeFrames: 0,
        framerate: .fps30
    )
    XCTAssertTrue(commands.contains("Assign Sequence 900 Cue 1 /info=\"line1 line2 q\""))
}

func test_omitsInfo_whenNotesEmpty() {
    let c = Cue(
        id: UUID(), typeID: UUID(), cueNumber: 1, name: "C",
        time: 0, notes: "", fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
    )
    let commands = MA2CommandPlanner.commands(
        cues: [c], target: target(), sequenceName: "S", startTimecodeFrames: 0, framerate: .fps30
    )
    XCTAssertFalse(commands.contains(where: { $0.contains("/info=") }))
}
```

- [ ] **Step 2: Run test to verify it fails** — `xcodebuild test … -only-testing:OnlyCueTests/MA2CommandPlannerTests`. Expected: FAIL (no `/info=`).

- [ ] **Step 3: Write minimal implementation** — in the per-cue loop, after the `/outfade` block and before the loop closes:

```swift
            if !cue.notes.isEmpty {
                let info = MA2CommandQuoting.quotable(
                    cue.notes.split(whereSeparator: \.isNewline).joined(separator: " ")
                )
                commands.append("Assign Sequence \(seq) Cue \(num) /info=\"\(info)\"")
            }
```

- [ ] **Step 4: Run test to verify it passes** — same command. Expected: PASS (existing golden-order tests still pass — the `/info` line only appears when notes are non-empty, and those tests use empty notes).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2CommandPlanner.swift OnlyCueTests/MA2CommandPlannerTests.swift
git commit -m "feat(ma2): carry cue notes into grandMA2 cue info on the command path"
```

---

### Task 4: Thread the resolved sequence name through `MA2PushRequestBuilder`

**Files:**

- Modify: `OnlyCue/MA2/MA2PushRequestBuilder.swift`
- Test: `OnlyCueTests/MA2PushRequestBuilderTests.swift`

**Interfaces:**

- Produces: `MA2PushRequestBuilder.resolvedSequenceName(item:target:) -> String` (`target.sequenceName ?? MA2Name.sanitize(item.resolvedName, fallbackSlot: target.sequenceSlot)`), used by `commandOutcome` and `outcome`.

- [ ] **Step 1: Write the failing test**

```swift
func test_resolvedName_prefersTargetSequenceName() {
    var t = target()                                   // resolvedName is "Opening"
    t.sequenceName = "My Cues"
    let item = item(cues: [cue(number: 1, typeID: typeA, time: 0)])
    guard case .ready(let commands) = MA2PushRequestBuilder.commandOutcome(item: item, target: t, framerate: .fps30) else {
        return XCTFail("expected ready")
    }
    XCTAssertTrue(commands.contains("Label Sequence 18 \"My Cues\""))
}

func test_resolvedName_sanitizesResolvedName_whenTargetNameNil() {
    let t = target()                                   // sequenceName nil
    // item.resolvedName sanitizes to ASCII; give the clip an ASCII alternateName in the helper.
    let item = item(cues: [cue(number: 1, typeID: typeA, time: 0)])
    guard case .ready(let commands) = MA2PushRequestBuilder.commandOutcome(item: item, target: t, framerate: .fps30) else {
        return XCTFail("expected ready")
    }
    XCTAssertTrue(commands.contains("Label Sequence 18 \"Opening\""))   // helper's alternateName is "Opening"
}
```

> The existing `item(...)` helper sets `alternateName: "Opening"` → `resolvedName == "Opening"`, which sanitizes to itself. `target()` uses `sequenceSlot: 18`.

- [ ] **Step 2: Run test to verify it fails** — `xcodebuild test … -only-testing:OnlyCueTests/MA2PushRequestBuilderTests`. Expected: the first test FAILS (target name ignored; label still uses resolvedName).

- [ ] **Step 3: Write minimal implementation** — add the helper and use it in `commandOutcome` and `outcome`:

```swift
    static func resolvedSequenceName(item: MediaItem, target: MA2PushTarget) -> String {
        target.sequenceName ?? MA2Name.sanitize(item.resolvedName, fallbackSlot: target.sequenceSlot)
    }
```

In `commandOutcome`, replace `sequenceName: item.resolvedName` with `sequenceName: resolvedSequenceName(item: item, target: target)`.
In `outcome`, replace `sequenceName: item.resolvedName` (the argument to `MA2PushPlanner.plan`) with the same call, and `timecodeName: "\(resolvedSequenceName(item: item, target: target)) TC"`.

- [ ] **Step 4: Run test to verify it passes** — same command; then the full `MA2PushRequestBuilderTests` (existing `.ready` tests still expect `"Opening"`, which the sanitizer preserves). Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PushRequestBuilder.swift OnlyCueTests/MA2PushRequestBuilderTests.swift
git commit -m "feat(ma2): use persisted/sanitized sequence name in the push plan"
```

---

### Task 5: `MA2ConsoleScanner` — discover consoles

**Files:**

- Create: `OnlyCue/MA2/MA2ConsoleScanner.swift`
- Test: `OnlyCueTests/MA2ConsoleScannerTests.swift`

**Interfaces:**

- Produces:
  - `struct MA2Console: Equatable, Identifiable { let host: String; let label: String?; var id: String { host } }`
  - `enum MA2ConsoleScanner`:
    - `static func scan(subnets: [String], hosts: ClosedRange<Int> = 1...254, probe: @Sendable (String) async -> MA2Console?) async -> [MA2Console]` (orchestration; injected probe)
    - `static func localSubnets() -> [String]` (getifaddrs → `"a.b.c"` prefixes for up, non-loopback, non-point-to-point IPv4 interfaces)
    - `static func bannerProbe(_ host: String, port: UInt16 = 30000, connectTimeout: TimeInterval = 0.4, bannerWindow: TimeInterval = 0.5) async -> MA2Console?` (connect, read banner, keep if it contains a grandMA2 marker)
    - `static func scan() async -> [MA2Console]` = `scan(subnets: localSubnets(), probe: bannerProbe)` de-duped, excluding the Mac's own interface IPs

- [ ] **Step 1: Write the failing test** (orchestration with a fake probe; banner probe against an in-process `NWListener`)

```swift
import XCTest
import Network
@testable import OnlyCue

final class MA2ConsoleScannerTests: XCTestCase {
    func test_scan_collectsProbedConsoles_acrossSubnets_deduped() async {
        let probe: @Sendable (String) async -> MA2Console? = { host in
            host == "10.0.0.5" || host == "2.0.0.7" ? MA2Console(host: host, label: nil) : nil
        }
        let found = await MA2ConsoleScanner.scan(subnets: ["10.0.0", "2.0.0"], hosts: 1...10, probe: probe)
        XCTAssertEqual(Set(found.map(\.host)), ["10.0.0.5", "2.0.0.7"])
    }

    func test_bannerProbe_acceptsMaBanner_rejectsOther() async throws {
        let maPort = try await startListener(banner: "…\r\n [Channel]>Please login !\r\n")
        defer { stopListeners() }
        let otherPort = try await startListener(banner: "220 vsFTPd ready\r\n")

        let ma = await MA2ConsoleScanner.bannerProbe("127.0.0.1", port: maPort)
        XCTAssertNotNil(ma)
        let other = await MA2ConsoleScanner.bannerProbe("127.0.0.1", port: otherPort)
        XCTAssertNil(other)
    }

    // startListener/stopListeners: spin up an NWListener on an ephemeral port that
    // writes `banner` to the first inbound connection. Return the chosen port.
    // (Copy the NWListener fixture pattern from MA2TelnetClientTests, which already
    //  stands up a local listener for the telnet client's tests.)
}
```

> Reuse the local-`NWListener` fixture from `MA2TelnetClientTests` (it already tests the telnet client against an in-process server) — copy its listener setup so this test needs no new infrastructure.

- [ ] **Step 2: Run test to verify it fails** — `xcodegen generate && xcodebuild test … -only-testing:OnlyCueTests/MA2ConsoleScannerTests`. Expected: FAIL — `MA2ConsoleScanner` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import Network

/// A discovered grandMA2 console (#686).
struct MA2Console: Equatable, Identifiable {
    let host: String
    let label: String?
    var id: String { host }
}

/// Discovers grandMA2 consoles by scanning each active interface's /24 for the
/// telnet port and keeping hosts whose banner looks like grandMA2 (#686).
/// Always user-initiated; never runs on its own.
enum MA2ConsoleScanner {

    /// grandMA2 telnet banner markers (see the real onPC banner: MA art +
    /// "Please login !" + " [Channel]>").
    private static let markers = ["Please login", "[Channel]"]

    static func scan(
        subnets: [String],
        hosts: ClosedRange<Int> = 1...254,
        probe: @Sendable @escaping (String) async -> MA2Console?
    ) async -> [MA2Console] {
        var results: [MA2Console] = []
        await withTaskGroup(of: MA2Console?.self) { group in
            for subnet in subnets {
                for i in hosts { group.addTask { await probe("\(subnet).\(i)") } }
            }
            for await found in group where found != nil { results.append(found!) }
        }
        // De-dupe by host, stable-ish order.
        var seen = Set<String>()
        return results.filter { seen.insert($0.host).inserted }.sorted { $0.host < $1.host }
    }

    static func bannerProbe(
        _ host: String,
        port: UInt16 = 30000,
        connectTimeout: TimeInterval = 0.4,
        bannerWindow: TimeInterval = 0.5
    ) async -> MA2Console? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "OnlyCue.MA2ConsoleScanner")
        defer { connection.cancel() }

        // Connect (bounded).
        let connected: Bool = await withCheckedContinuation { cont in
            let box = ResumeOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if box.take() { cont.resume(returning: true) }
                case .failed, .waiting, .cancelled: if box.take() { cont.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + connectTimeout) { if box.take() { cont.resume(returning: false) } }
        }
        guard connected else { return nil }

        // Read the banner within the window.
        let data: Data = await withCheckedContinuation { cont in
            let box = ResumeOnce()
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, _, _ in
                if box.take() { cont.resume(returning: d ?? Data()) }
            }
            queue.asyncAfter(deadline: .now() + bannerWindow) { if box.take() { cont.resume(returning: Data()) } }
        }
        let text = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
        guard markers.contains(where: text.contains) else { return nil }
        return MA2Console(host: host, label: nil)
    }

    static func scan() async -> [MA2Console] {
        let mine = Set(localInterfaceIPs())
        return await scan(subnets: localSubnets(), probe: bannerProbe)
            .filter { !mine.contains($0.host) }
    }

    /// `"a.b.c"` /24 prefixes of up, non-loopback, non-point-to-point IPv4 interfaces.
    static func localSubnets() -> [String] {
        Set(localInterfaceIPs().compactMap { ip -> String? in
            let parts = ip.split(separator: ".")
            return parts.count == 4 ? parts.prefix(3).joined(separator: ".") : nil
        }).sorted()
    }

    /// IPv4 addresses of up, non-loopback, non-point-to-point interfaces.
    static func localInterfaceIPs() -> [String] {
        var addrs: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isP2P = (flags & IFF_POINTOPOINT) != 0
            if isUp, !isLoopback, !isP2P, let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    addrs.append(String(cString: host))
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return addrs
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
```

- [ ] **Step 4: Run test to verify it passes** — same command. Expected: PASS. Then full suite + lint.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2ConsoleScanner.swift OnlyCueTests/MA2ConsoleScannerTests.swift
git commit -m "feat(ma2): add console scanner (bounded /24 port-30000 banner probe)"
```

---

### Task 6: UI — Settings scan combo + sheet sequence-name field

**Files:**

- Modify: `OnlyCue/UI/MA2SettingsView.swift`
- Modify: `OnlyCue/UI/MA2PushSheet.swift`
- Test: build + full suite + lint (UI over already-tested logic).

**Interfaces:** consumes `MA2ConsoleScanner.scan()`, `MA2Name.sanitize`, `MA2PushTarget.sequenceName`.

- [ ] **Step 1: Settings — host combo + Scan button.** In `MA2SettingsView`, add scan state and replace the host `TextField` region:

```swift
    @State private var discovered: [MA2Console] = []
    @State private var isScanning = false
    @State private var scanNote: String?
```

```swift
                HStack {
                    TextField("Console IP / hostname", text: $host)
                        .accessibilityIdentifier("ma2HostField")
                    if !discovered.isEmpty {
                        Picker("", selection: $host) {
                            ForEach(discovered) { c in Text(c.host).tag(c.host) }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        .accessibilityIdentifier("ma2HostPicker")
                    }
                    Button(isScanning ? "Scanning…" : "Scan") { scan() }
                        .disabled(isScanning)
                        .accessibilityIdentifier("ma2ScanButton")
                }
                if let scanNote {
                    Text(scanNote).font(.caption).foregroundStyle(DS.Color.textSecondary)
                }
```

Add the action:

```swift
    private func scan() {
        isScanning = true
        scanNote = nil
        Task {
            let found = await MA2ConsoleScanner.scan()
            await MainActor.run {
                discovered = found
                isScanning = false
                if found.isEmpty {
                    scanNote = "No consoles found on \(MA2ConsoleScanner.localSubnets().map { "\($0).0/24" }.joined(separator: ", "))."
                } else if host.isEmpty, let first = found.first {
                    host = first.host
                }
            }
        }
    }
```

- [ ] **Step 2: Sheet — editable Sequence name field.** In `MA2PushSheet`, add state seeded from the saved target (fall back to the sanitized clip name), include it in `currentTarget`, and surface a field in the target card:

```swift
    @State private var sequenceName: String
```

In `init`, after seeding the slot fields:

```swift
        _sequenceName = State(initialValue: saved.sequenceName
            ?? MA2Name.sanitize(item.resolvedName, fallbackSlot: saved.sequenceSlot))
```

In `currentTarget`, set `sequenceName: sequenceName.isEmpty ? nil : sequenceName`.

In the target card (near the slot fields), add:

```swift
                TextField("Sequence name (English)", text: $sequenceName)
                    .accessibilityIdentifier("ma2SequenceNameField")
```

> `currentTarget` currently constructs `MA2PushTarget(...)` from the slot `@State`s — add `sequenceName:` to that initializer call. Because the push already persists `currentTarget` via `onSaveTarget`, the edited name is saved with no extra wiring.

- [ ] **Step 3: Regenerate + build.**

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Full suite + lint.**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests 2>&1 | grep -v "Connection\]" | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -2
swiftlint lint --strict
```

Expected: all tests pass; lint clean.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/MA2SettingsView.swift OnlyCue/UI/MA2PushSheet.swift
git commit -m "feat(ma2): scan combo in settings and editable sequence name in push sheet"
```

---

## Self-Review

- **Spec coverage:** discovery → Tasks 5 (scanner) + 6 (Settings UI); sequence name → Tasks 1 (sanitizer) + 2 (persist/v18) + 4 (thread) + 6 (sheet field); cue info → Task 3. Schema v18 + migration in Task 2. All new tests use fixtures/injected probes (no real network).
- **Type consistency:** `MA2Name.sanitize(_:fallbackSlot:)`, `MA2PushTarget.sequenceName`, `MA2PushRequestBuilder.resolvedSequenceName(item:target:)`, `MA2ConsoleScanner.scan(subnets:hosts:probe:)` / `.scan()` / `.bannerProbe(_:port:…)` / `.localSubnets()`, `MA2Console` — used identically across tasks.
- **Placeholder scan:** Tasks 2 & 5 flag the two real-code lookups to confirm before running (exact `ProjectModel.init` params / migration-test fixture shape; the `NWListener` fixture to copy from `MA2TelnetClientTests`). Everything else ships complete code.

## Notes for implementer

- The v17→v18 migration is additive-optional, so `migrateFromV16` (now stamping 18) still correctly loads v16 docs with both new optionals nil — do not special-case it.
- `bannerProbe`'s markers (`Please login`, `[Channel]`) come from the real onPC banner; keep them broad. A real console reached over a slow link may need a larger `bannerWindow` — the default 0.5 s matched the local rig.
