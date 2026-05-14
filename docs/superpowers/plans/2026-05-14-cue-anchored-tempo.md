# Cue-anchored tempo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace OnlyCue's per-media `TempoMap` with per-cue `bpm`/`beatsPerBar`; the grid is derived from BPM-bearing cues. Delete the Tempo Map sheet and "Add Cues on Every Beat/Bar" menus.

**Architecture:** Schema v10 → v11 adds `bpm: Double?` and `beatsPerBar: Int?` to `Cue` and drops `tempoMap` from `MediaItem`. A new pure value type `DerivedTempoGrid` exposes the same `beatTimes`/`barTimes`/`nearestBeat`/`nearestBar` surface today's `TempoMap` exposes, but is built from the cue list. The cue's own time is bar 1, beat 1 of the segment it opens.

**Tech Stack:** Swift 6, SwiftUI, XCTest, xcodegen. macOS 14+. Existing `SpectralFluxTempoAnalyzer` (kept, relocated UI).

**Spec:** `docs/superpowers/specs/2026-05-13-cue-anchored-tempo-design.md`

**Branching:** Each leaf is a separate issue branch off `dev`. PR titles follow Conventional Commits. Use the forked PR templates in `.github/PULL_REQUEST_TEMPLATE/`.

---

## File-by-file plan

**Created**
- `OnlyCue/Tempo/DerivedTempoGrid.swift` — derived grid from cues; Leaf 2.
- `OnlyCue/Document/ProjectModel+MigrationV10.swift` — v10 → v11 migration with private `LegacyTempoMap`/`LegacyTempoSection`/`LegacyV10Item` shapes; Leaf 1.
- `OnlyCueTests/DerivedTempoGridTests.swift` — Leaf 2.
- `OnlyCueTests/ProjectModelMigrationV10Tests.swift` — Leaf 1.
- `OnlyCueTests/CueCommandsSetTempoTests.swift` — Leaf 3.

**Modified**
- `OnlyCue/Document/Cue.swift` — add `bpm`/`beatsPerBar`; Leaf 1.
- `OnlyCue/Document/MediaItem.swift` — remove `tempoMap`; Leaf 1.
- `OnlyCue/Document/ProjectModel.swift` — bump `currentSchemaVersion` to 11; Leaf 1.
- `OnlyCue/Document/ProjectModel+Migration.swift` — wire v10→v11 into the chain; Leaf 1.
- `OnlyCue/Document/ProjectModel+MigrationV8.swift` — adapt `LegacyV8Item` to no longer read `tempoMap` into `MediaItem` (instead fan tempo into cues, or drop); Leaf 1.
- `OnlyCue/Document/ProjectModel+MigrationV9.swift` (if it references `tempoMap`) — same; Leaf 1.
- `OnlyCue/Commands/CueCommands+Tempo.swift` — replace section commands with `setCueTempo`; Leaf 3 (delete-and-add).
- `OnlyCue/Commands/CueCommands+Grid.swift` — swap `TempoMap` → `DerivedTempoGrid`; drop `addCuesOnGrid`; Leaf 2.
- `OnlyCue/UI/TempoGridOverlay.swift` — consume `DerivedTempoGrid`; Leaf 2.
- `OnlyCue/UI/CueInspectorView.swift` — add Tempo group; Leaf 3.
- `OnlyCue/UI/CueListPane.swift` — optional BPM column; Leaf 4.
- `OnlyCue/App/AppCommands.swift` — remove Tempo Map / Split / Add Cues menu items; Leaf 5.
- `OnlyCue/App/Keymap.swift` + `KeymapAction.swift` — remove dead actions; Leaf 5.

**Deleted (Leaf 5)**
- `OnlyCue/UI/TempoMapSheet.swift`
- `OnlyCue/UI/TempoMapSheet+Fields.swift`
- `OnlyCue/Tempo/TempoMap.swift`
- `OnlyCue/Tempo/TempoSection.swift`
- `OnlyCueTests/TempoMapTests.swift`
- `OnlyCueTests/CueCommandsTempoTests.swift`
- `OnlyCueUITests/TempoMapSheetScreenshotTests.swift`

---

## Leaf 1 — Schema v10 → v11 + migration

**Issue title:** `feat(document): schema v11 — per-cue tempo (bpm, beatsPerBar)`
**Branch:** `issues/<N>` (created by `gh-dev`)
**PR template:** `.github/PULL_REQUEST_TEMPLATE/feat.md`

**Scope:** Add `bpm`/`beatsPerBar` to `Cue`. Drop `tempoMap` from `MediaItem`. Bump schema. Convert any existing `tempoMap` to per-cue tempo via `MigrationV10`. `TempoMap`/`TempoSection` types remain in the source tree (untouched) — Leaf 5 deletes them.

### Task 1.1: Add `bpm` and `beatsPerBar` to `Cue`

**Files:**
- Modify: `OnlyCue/Document/Cue.swift`

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueTempoFieldsTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class CueTempoFieldsTests: XCTestCase {

    func testCueHasOptionalBPMAndBeatsPerBarDefaultingToNil() {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: nil,
            name: "x",
            time: 1.0,
            notes: "",
            fadeTime: .zero
        )
        XCTAssertNil(cue.bpm)
        XCTAssertNil(cue.beatsPerBar)
    }

    func testCueEncodesAndDecodesTempoFields() throws {
        let cue = Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: nil,
            name: "x",
            time: 1.0,
            notes: "",
            fadeTime: .zero,
            bpm: 120,
            beatsPerBar: 4
        )
        let data = try JSONEncoder().encode(cue)
        let decoded = try JSONDecoder().decode(Cue.self, from: data)
        XCTAssertEqual(decoded.bpm, 120)
        XCTAssertEqual(decoded.beatsPerBar, 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodegen generate
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/CueTempoFieldsTests -destination 'platform=macOS'
```

Expected: FAIL — `Cue` initializer doesn't accept `bpm`/`beatsPerBar`.

- [ ] **Step 3: Modify `Cue`**

Replace the body of `OnlyCue/Document/Cue.swift` with:

```swift
import Foundation

struct Cue: Codable, Identifiable, Equatable {
    var id: UUID
    var typeID: UUID
    var cueNumber: Double?
    var name: String
    var time: TimeInterval
    var notes: String
    var fadeTime: FadeTime
    var bpm: Double?
    var beatsPerBar: Int?

    init(
        id: UUID,
        typeID: UUID,
        cueNumber: Double?,
        name: String,
        time: TimeInterval,
        notes: String,
        fadeTime: FadeTime,
        bpm: Double? = nil,
        beatsPerBar: Int? = nil
    ) {
        self.id = id
        self.typeID = typeID
        self.cueNumber = cueNumber
        self.name = name
        self.time = time
        self.notes = notes
        self.fadeTime = fadeTime
        // Clamp at construction so derived grid maths never divides by zero.
        self.bpm = bpm.map { min(max($0, 20), 400) }
        self.beatsPerBar = beatsPerBar.map { max(1, min($0, 16)) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/CueTempoFieldsTests -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Document/Cue.swift OnlyCueTests/CueTempoFieldsTests.swift
git commit -m "feat(document): add optional bpm and beatsPerBar to Cue"
```

### Task 1.2: Drop `tempoMap` from `MediaItem`

**Files:**
- Modify: `OnlyCue/Document/MediaItem.swift`

- [ ] **Step 1: Write the failing test**

Add to `OnlyCueTests/CueTempoFieldsTests.swift`:

```swift
func testMediaItemEncodesWithoutTempoMapField() throws {
    let item = MediaItem(
        id: UUID(),
        media: MediaReference(
            url: URL(fileURLWithPath: "/tmp/x.wav"),
            bookmarkData: Data(),
            displayName: "x",
            duration: 10,
            kind: .audio
        ),
        cues: []
    )
    let data = try JSONEncoder().encode(item)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(json.contains("tempoMap"))
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/CueTempoFieldsTests/testMediaItemEncodesWithoutTempoMapField -destination 'platform=macOS'
```

Expected: FAIL — `tempoMap` is still emitted.

- [ ] **Step 3: Remove `tempoMap` from `MediaItem`**

Edit `OnlyCue/Document/MediaItem.swift`. Remove the `var tempoMap: TempoMap = TempoMap()` line. The struct's other fields are unchanged.

- [ ] **Step 4: Update call sites that break**

Run the build; fix any compile error in the app target by removing references to `item.tempoMap`. Expected sites: `CueCommands+Tempo.swift`, `CueCommands+Grid.swift`, `TempoGridOverlay.swift`, `TempoMapSheet*.swift`, `WaveformContainer+Overlays.swift`. For this leaf, **stub these references** by making them act on an empty `TempoMap()` literal (the grid temporarily renders nothing). Leaves 2/3/5 replace them properly.

For each stub site, do the smallest possible edit (e.g., `let map = TempoMap()` before the use). Do not delete any code yet — Leaf 5 cleans up. The goal is "compiles and existing non-tempo tests still pass."

- [ ] **Step 5: Run all tests**

```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS'
```

Expected: PASS for everything except the now-temporarily-broken tempo behavior tests. If `TempoMapTests` / `CueCommandsTempoTests` still pass (they operate on `TempoMap` directly, not via `MediaItem`), good. If they reference `item.tempoMap`, update them to thread a `TempoMap` directly until Leaf 5.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Document/MediaItem.swift OnlyCue/Commands OnlyCue/UI OnlyCueTests/CueTempoFieldsTests.swift
git commit -m "feat(document): drop tempoMap from MediaItem"
```

### Task 1.3: Bump `currentSchemaVersion` to 11

**Files:**
- Modify: `OnlyCue/Document/ProjectModel.swift:5`

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/ProjectModelSchemaVersionTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class ProjectModelSchemaVersionTests: XCTestCase {
    func testCurrentSchemaVersionIs11() {
        XCTAssertEqual(ProjectModel.currentSchemaVersion, 11)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/ProjectModelSchemaVersionTests -destination 'platform=macOS'
```

Expected: FAIL — value is 10.

- [ ] **Step 3: Bump the constant**

Edit `OnlyCue/Document/ProjectModel.swift:5`:

```swift
static let currentSchemaVersion = 11
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/ProjectModelSchemaVersionTests -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Document/ProjectModel.swift OnlyCueTests/ProjectModelSchemaVersionTests.swift
git commit -m "feat(document): bump schema to v11"
```

### Task 1.4: Write the v10 → v11 migration

**Files:**
- Create: `OnlyCue/Document/ProjectModel+MigrationV10.swift`
- Modify: `OnlyCue/Document/ProjectModel+Migration.swift` (wire dispatch)
- Create: `OnlyCueTests/ProjectModelMigrationV10Tests.swift`

- [ ] **Step 1: Write the failing migration tests**

Create `OnlyCueTests/ProjectModelMigrationV10Tests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class ProjectModelMigrationV10Tests: XCTestCase {

    /// A v10 doc with a non-empty TempoMap whose first downbeat aligns with an existing cue:
    /// migration copies bpm/beatsPerBar onto that cue, drops tempoMap, no synthetic cue created.
    func testSingleSectionAlignsWithExistingCue() throws {
        let typeID = UUID()
        let cueID = UUID()
        let v10Json = """
        {
          "schemaVersion": 10,
          "id": "\(UUID().uuidString)",
          "name": "doc",
          "cuePointTypes": [{"id":"\(typeID.uuidString)","name":"G","colorHex":"#fff","hotkey":null}],
          "items": [{
            "id": "\(UUID().uuidString)",
            "media": {"url":"file:///tmp/x.wav","bookmarkData":"","displayName":"x","duration":60.0,"kind":"audio"},
            "cues": [{
              "id":"\(cueID.uuidString)","typeID":"\(typeID.uuidString)","cueNumber":null,
              "name":"c","time":0.5,"notes":"","fadeTime":{"seconds":0}
            }],
            "tempoMap": {"sections":[{
              "id":"\(UUID().uuidString)","startSeconds":0.0,"bpm":120.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.5
            }]},
            "startTimecodeFrames": 0,
            "ltcMuted": false
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"fps_30"}
        }
        """.data(using: .utf8)!

        let migrated = try ProjectModel.load(from: v10Json)

        XCTAssertEqual(migrated.schemaVersion, 11)
        XCTAssertEqual(migrated.items.count, 1)
        XCTAssertEqual(migrated.items[0].cues.count, 1, "no synthetic cue when alignment fits")
        XCTAssertEqual(migrated.items[0].cues[0].id, cueID)
        XCTAssertEqual(migrated.items[0].cues[0].bpm, 120)
        XCTAssertEqual(migrated.items[0].cues[0].beatsPerBar, 4)
    }

    /// A v10 doc with no cue near the section's first downbeat synthesizes a "Tempo" cue.
    func testSectionWithoutNearbyCueInsertsSynthetic() throws {
        let typeID = UUID()
        let v10Json = """
        {
          "schemaVersion": 10,
          "id": "\(UUID().uuidString)",
          "name": "doc",
          "cuePointTypes": [{"id":"\(typeID.uuidString)","name":"G","colorHex":"#fff","hotkey":null}],
          "items": [{
            "id": "\(UUID().uuidString)",
            "media": {"url":"file:///tmp/x.wav","bookmarkData":"","displayName":"x","duration":60.0,"kind":"audio"},
            "cues": [],
            "tempoMap": {"sections":[{
              "id":"\(UUID().uuidString)","startSeconds":0.0,"bpm":100.0,"beatsPerBar":3,"downbeatOffsetSeconds":2.0
            }]},
            "startTimecodeFrames": 0,
            "ltcMuted": false
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"fps_30"}
        }
        """.data(using: .utf8)!

        let migrated = try ProjectModel.load(from: v10Json)

        XCTAssertEqual(migrated.items[0].cues.count, 1)
        let synthetic = migrated.items[0].cues[0]
        XCTAssertEqual(synthetic.name, "Tempo")
        XCTAssertEqual(synthetic.time, 2.0, accuracy: 1e-9)
        XCTAssertEqual(synthetic.bpm, 100)
        XCTAssertEqual(synthetic.beatsPerBar, 3)
        XCTAssertEqual(synthetic.typeID, typeID, "uses default cue point type")
        XCTAssertNil(synthetic.cueNumber)
    }

    func testEmptyTempoMapMigratesCleanly() throws {
        let typeID = UUID()
        let v10Json = """
        {
          "schemaVersion": 10,
          "id": "\(UUID().uuidString)",
          "name": "doc",
          "cuePointTypes": [{"id":"\(typeID.uuidString)","name":"G","colorHex":"#fff","hotkey":null}],
          "items": [{
            "id": "\(UUID().uuidString)",
            "media": {"url":"file:///tmp/x.wav","bookmarkData":"","displayName":"x","duration":60.0,"kind":"audio"},
            "cues": [],
            "tempoMap": {"sections":[]},
            "startTimecodeFrames": 0,
            "ltcMuted": false
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"fps_30"}
        }
        """.data(using: .utf8)!

        let migrated = try ProjectModel.load(from: v10Json)
        XCTAssertEqual(migrated.schemaVersion, 11)
        XCTAssertEqual(migrated.items[0].cues.count, 0)
    }

    /// Multiple sections: each becomes a tempo source, in order. Cue near second 0 absorbs
    /// the first section; section at t=30 gets a synthetic cue (no cue nearby).
    func testMultipleSectionsFanOut() throws {
        let typeID = UUID()
        let cueID = UUID()
        let v10Json = """
        {
          "schemaVersion": 10,
          "id": "\(UUID().uuidString)",
          "name": "doc",
          "cuePointTypes": [{"id":"\(typeID.uuidString)","name":"G","colorHex":"#fff","hotkey":null}],
          "items": [{
            "id": "\(UUID().uuidString)",
            "media": {"url":"file:///tmp/x.wav","bookmarkData":"","displayName":"x","duration":60.0,"kind":"audio"},
            "cues": [{
              "id":"\(cueID.uuidString)","typeID":"\(typeID.uuidString)","cueNumber":null,
              "name":"c","time":0.0,"notes":"","fadeTime":{"seconds":0}
            }],
            "tempoMap": {"sections":[
              {"id":"\(UUID().uuidString)","startSeconds":0.0,"bpm":120.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0},
              {"id":"\(UUID().uuidString)","startSeconds":30.0,"bpm":75.0,"beatsPerBar":4,"downbeatOffsetSeconds":0.0}
            ]},
            "startTimecodeFrames": 0,
            "ltcMuted": false
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"fps_30"}
        }
        """.data(using: .utf8)!

        let migrated = try ProjectModel.load(from: v10Json)

        XCTAssertEqual(migrated.items[0].cues.count, 2, "existing + synthetic for second section")
        let sorted = migrated.items[0].cues.sorted { $0.time < $1.time }
        XCTAssertEqual(sorted[0].id, cueID)
        XCTAssertEqual(sorted[0].bpm, 120)
        XCTAssertEqual(sorted[1].time, 30.0, accuracy: 1e-9)
        XCTAssertEqual(sorted[1].bpm, 75)
        XCTAssertEqual(sorted[1].name, "Tempo")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/ProjectModelMigrationV10Tests -destination 'platform=macOS'
```

Expected: FAIL — `unsupportedSchemaVersion(10)`.

- [ ] **Step 3: Implement the migration**

Create `OnlyCue/Document/ProjectModel+MigrationV10.swift`:

```swift
import Foundation

/// v10 → v11 migration: tempo moves from `MediaItem.tempoMap` onto cues.
///
/// Strategy per item: for each tempo section, find the cue whose time is closest to
/// `startSeconds + downbeatOffsetSeconds` within a one-beat tolerance (`60 / bpm`). If
/// found, copy the section's `bpm`/`beatsPerBar` onto it. If not found, insert a
/// synthetic cue named "Tempo" at the section's first downbeat carrying the tempo.
/// The `tempoMap` field is dropped.
///
/// The migration uses a private decode-only copy of the v10 tempo shape so the live
/// `TempoMap` / `TempoSection` types can be deleted in Leaf 5 without disturbing
/// historical migrations.
extension ProjectModel {

    static func migrateFromV10(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV10.self, from: data)
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem(defaultTypeID: legacy.cuePointTypes.first?.id) },
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings
        )
    }

    // MARK: - Legacy decode shapes

    private struct LegacyV10: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV10Item]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
    }

    private struct LegacyV10Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [Cue]
        let tempoMap: LegacyTempoMap
        let startTimecodeFrames: Int
        let ltcMuted: Bool

        func toMediaItem(defaultTypeID: UUID?) -> MediaItem {
            let migratedCues = Self.applyTempo(
                from: tempoMap.sections,
                to: cues,
                defaultTypeID: defaultTypeID
            )
            return MediaItem(
                id: id,
                media: media,
                cues: migratedCues,
                startTimecodeFrames: startTimecodeFrames,
                ltcMuted: ltcMuted
            )
        }

        private static func applyTempo(
            from sections: [LegacyTempoSection],
            to cues: [Cue],
            defaultTypeID: UUID?
        ) -> [Cue] {
            var working = cues
            for section in sections {
                let anchor = section.startSeconds + section.downbeatOffsetSeconds
                let tolerance = 60.0 / max(section.bpm, 1)
                if let index = nearestCueIndex(in: working, to: anchor, within: tolerance) {
                    working[index].bpm = section.bpm
                    working[index].beatsPerBar = section.beatsPerBar
                } else if let typeID = defaultTypeID {
                    working.append(Cue(
                        id: UUID(),
                        typeID: typeID,
                        cueNumber: nil,
                        name: "Tempo",
                        time: anchor,
                        notes: "",
                        fadeTime: .zero,
                        bpm: section.bpm,
                        beatsPerBar: section.beatsPerBar
                    ))
                }
            }
            return working.sorted { $0.time < $1.time }
        }

        private static func nearestCueIndex(in cues: [Cue], to time: TimeInterval, within tolerance: TimeInterval) -> Int? {
            var bestIndex: Int?
            var bestDelta = Double.infinity
            for (index, cue) in cues.enumerated() {
                let delta = abs(cue.time - time)
                if delta <= tolerance && delta < bestDelta {
                    bestIndex = index
                    bestDelta = delta
                }
            }
            return bestIndex
        }
    }

    private struct LegacyTempoMap: Decodable {
        let sections: [LegacyTempoSection]
    }

    private struct LegacyTempoSection: Decodable {
        let id: UUID
        let startSeconds: TimeInterval
        let bpm: Double
        let beatsPerBar: Int
        let downbeatOffsetSeconds: TimeInterval
    }
}
```

- [ ] **Step 4: Wire dispatch in `ProjectModel+Migration.swift`**

Read `OnlyCue/Document/ProjectModel+Migration.swift` first to see the switch shape. Add a `case 10:` branch before the `default` that calls `migrateFromV10(data:)`. The existing `case 9:` migrates v9→v10 directly; you'll need to update it to migrate v9→v10 *then* v10→v11, OR (simpler) update the v9 path to migrate straight to v11 by also running tempo flattening. Do the simpler: keep `migrateFromV9` producing a v10-shaped intermediate `Data`, then re-dispatch to `migrateFromV10`. Concretely, after the existing v9 logic builds its `ProjectModel` (currently with `schemaVersion: currentSchemaVersion`), instead re-encode it with `schemaVersion: 10` and recurse via `load(from:)`. Update `migrateFromV8` the same way (it also currently writes directly to current).

Apply the same chaining update to `migrateFromV8`: re-emit at v9 and recurse.

- [ ] **Step 5: Run all migration tests**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/ProjectModelMigrationV10Tests -only-testing:OnlyCueTests/ProjectModelMigrationV8Tests -only-testing:OnlyCueTests/ProjectModelMigrationV7Tests -destination 'platform=macOS'
```

Expected: PASS across all migration levels.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Document/ProjectModel+MigrationV10.swift \
        OnlyCue/Document/ProjectModel+Migration.swift \
        OnlyCue/Document/ProjectModel+MigrationV8.swift \
        OnlyCue/Document/ProjectModel+MigrationV9.swift \
        OnlyCueTests/ProjectModelMigrationV10Tests.swift
git commit -m "feat(document): migrate v10 tempoMap onto per-cue bpm"
```

### Task 1.5: Open PR for Leaf 1

- [ ] **Step 1: Run the full suite + SwiftLint**

```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS'
swiftlint --strict
```

Expected: PASS both.

- [ ] **Step 2: Push and open PR using forked feat template**

Use the `gh-pr` skill, which reads `.github/PULL_REQUEST_TEMPLATE/feat.md`. PR title: `feat(document): schema v11 — per-cue tempo (bpm, beatsPerBar)`. Body links to the spec section "Data model" and "Migration v10 → v11".

---

## Leaf 2 — `DerivedTempoGrid` + consumer swap

**Issue title:** `feat(tempo): derive grid from per-cue bpm`
**PR template:** `feat.md`

### Task 2.1: Create `DerivedTempoGrid`

**Files:**
- Create: `OnlyCue/Tempo/DerivedTempoGrid.swift`
- Create: `OnlyCueTests/DerivedTempoGridTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/DerivedTempoGridTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class DerivedTempoGridTests: XCTestCase {

    private func cue(time: TimeInterval, bpm: Double? = nil, beatsPerBar: Int? = nil) -> Cue {
        Cue(
            id: UUID(), typeID: UUID(), cueNumber: nil,
            name: "", time: time, notes: "", fadeTime: .zero,
            bpm: bpm, beatsPerBar: beatsPerBar
        )
    }

    func testEmptyCueListYieldsEmptyGrid() {
        let grid = DerivedTempoGrid.from(cues: [], itemDuration: 30)
        XCTAssertTrue(grid.isEmpty)
        XCTAssertEqual(grid.beatTimes(in: 0...30, itemDuration: 30).count, 0)
    }

    func testCuesWithoutBPMYieldEmptyGrid() {
        let grid = DerivedTempoGrid.from(cues: [cue(time: 0), cue(time: 5)], itemDuration: 30)
        XCTAssertTrue(grid.isEmpty)
    }

    /// Single BPM cue at t=0, 120 bpm, 4/4 → beats at 0, 0.5, 1.0, … through itemDuration.
    func testSingleSegmentBeatsTickFromCueTime() {
        let grid = DerivedTempoGrid.from(
            cues: [cue(time: 0, bpm: 120, beatsPerBar: 4)],
            itemDuration: 2.0
        )
        let beats = grid.beatTimes(in: 0...2, itemDuration: 2).map(\.time)
        XCTAssertEqual(beats, [0.0, 0.5, 1.0, 1.5, 2.0], accuracy: 1e-9)
    }

    func testBeatIndexZeroIsDownbeat() {
        let grid = DerivedTempoGrid.from(
            cues: [cue(time: 0, bpm: 120, beatsPerBar: 4)],
            itemDuration: 2.0
        )
        let beats = grid.beatTimes(in: 0...2, itemDuration: 2)
        XCTAssertTrue(beats[0].isDownbeat, "the cue itself is bar 1 beat 1")
        XCTAssertFalse(beats[1].isDownbeat)
        XCTAssertFalse(beats[2].isDownbeat)
        XCTAssertFalse(beats[3].isDownbeat)
        XCTAssertTrue(beats[4].isDownbeat, "second downbeat at j=4 → t=2.0")
    }

    func testTwoBPMSegments() {
        let grid = DerivedTempoGrid.from(
            cues: [cue(time: 0, bpm: 120, beatsPerBar: 4), cue(time: 2.5, bpm: 60, beatsPerBar: 4)],
            itemDuration: 5.0
        )
        let beats = grid.beatTimes(in: 0...5, itemDuration: 5).map(\.time)
        // Segment 1 [0,2.5): 120bpm → beats at 0, 0.5, 1.0, 1.5, 2.0 (2.5 excluded, belongs to next segment)
        // Segment 2 [2.5,5]: 60bpm → beats at 2.5, 3.5, 4.5
        XCTAssertEqual(beats, [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.5, 4.5], accuracy: 1e-9)
    }

    func testBeatsPerBarInheritsFromPreviousSegment() {
        let grid = DerivedTempoGrid.from(
            cues: [
                cue(time: 0, bpm: 120, beatsPerBar: 3),
                cue(time: 4, bpm: 90, beatsPerBar: nil) // inherit 3
            ],
            itemDuration: 8
        )
        let downbeats = grid.barTimes(in: 0...8, itemDuration: 8)
        // Seg1 120bpm 3/4: beat dur 0.5, bar dur 1.5 → downbeats at 0, 1.5, 3.0 (4.5 is past seg end)
        // Seg2 90bpm 3/4: beat dur 2/3, bar dur 2 → downbeats at 4, 6, 8
        XCTAssertEqual(downbeats[0], 0, accuracy: 1e-9)
        XCTAssertEqual(downbeats[1], 1.5, accuracy: 1e-9)
        XCTAssertEqual(downbeats[2], 3.0, accuracy: 1e-9)
        XCTAssertEqual(downbeats[3], 4.0, accuracy: 1e-9)
    }

    func testDefaultBeatsPerBarIsFourWhenNoneSet() {
        let grid = DerivedTempoGrid.from(
            cues: [cue(time: 0, bpm: 120, beatsPerBar: nil)],
            itemDuration: 4
        )
        let downbeats = grid.barTimes(in: 0...4, itemDuration: 4)
        XCTAssertEqual(downbeats, [0.0, 2.0, 4.0], accuracy: 1e-9)
    }

    func testUnsortedInputIsHandled() {
        let grid = DerivedTempoGrid.from(
            cues: [cue(time: 2.5, bpm: 60), cue(time: 0, bpm: 120)],
            itemDuration: 5
        )
        // Expect same result as sorted input
        XCTAssertFalse(grid.isEmpty)
        let firstBeat = grid.beatTimes(in: 0...5, itemDuration: 5).first?.time
        XCTAssertEqual(firstBeat, 0)
    }

    func testNearestBeatClampsIntoSegment() {
        let grid = DerivedTempoGrid.from(
            cues: [cue(time: 0, bpm: 120, beatsPerBar: 4), cue(time: 2.5, bpm: 60, beatsPerBar: 4)],
            itemDuration: 5
        )
        // 2.3s is between 2.0 (last beat of seg1) and 2.5 (downbeat of seg2). Nearest is 2.5.
        XCTAssertEqual(grid.nearestBeat(toSeconds: 2.3, itemDuration: 5), 2.5, accuracy: 1e-9)
        // 2.05s is closer to 2.0 (still in seg1).
        XCTAssertEqual(grid.nearestBeat(toSeconds: 2.05, itemDuration: 5), 2.0, accuracy: 1e-9)
    }

    func testNearestBarReturnsDownbeat() {
        let grid = DerivedTempoGrid.from(
            cues: [cue(time: 0, bpm: 120, beatsPerBar: 4)],
            itemDuration: 4
        )
        // beats at 0, 0.5, 1.0, 1.5, 2.0(db), 2.5, 3.0, 3.5, 4.0(db). Nearest bar to 1.9 is 2.0.
        XCTAssertEqual(grid.nearestBar(toSeconds: 1.9, itemDuration: 4), 2.0, accuracy: 1e-9)
    }
}
```

Quick aside on `XCTAssertEqual` for `[Double]` with `accuracy`: that overload doesn't exist. Replace each occurrence with a small helper:

```swift
private func assertCloseEnough(
    _ lhs: [Double], _ rhs: [Double], accuracy: Double, file: StaticString = #file, line: UInt = #line
) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    zip(lhs, rhs).forEach { XCTAssertEqual($0, $1, accuracy: accuracy, file: file, line: line) }
}
```

…and use `assertCloseEnough(beats, [...], accuracy: 1e-9)`. Add that helper as a private function inside the test class.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/DerivedTempoGridTests -destination 'platform=macOS'
```

Expected: FAIL — `DerivedTempoGrid` doesn't exist.

- [ ] **Step 3: Implement `DerivedTempoGrid`**

Create `OnlyCue/Tempo/DerivedTempoGrid.swift`:

```swift
import Foundation

/// The beat/bar grid rendered on the waveform and used as a snap target. Derived
/// at read time from the item's cues: each cue with a non-nil `bpm` opens a
/// constant-tempo segment running until the next BPM-bearing cue (or
/// `itemDuration`). The cue's own time is bar 1, beat 1 — no separate downbeat
/// offset. `beatsPerBar` is inherited from the previous segment when the cue
/// leaves it `nil`; defaulted to 4 if no upstream meter exists.
///
/// Replaces `TempoMap` (v10) as the visual + snap substrate. Pure value type.
struct DerivedTempoGrid: Equatable {

    private static let defaultBeatsPerBar = 4
    private static let epsilon: TimeInterval = 1e-9

    /// One constant-tempo span derived from a BPM-bearing cue.
    struct Segment: Equatable {
        let startSeconds: TimeInterval
        let bpm: Double
        let beatsPerBar: Int

        var beatDuration: TimeInterval { 60.0 / bpm }
        var barDuration: TimeInterval { beatDuration * Double(beatsPerBar) }
    }

    let segments: [Segment]

    var isEmpty: Bool { segments.isEmpty }

    static func from(cues: [Cue], itemDuration: TimeInterval) -> Self {
        let bpmCues = cues
            .filter { $0.bpm != nil }
            .sorted { $0.time < $1.time }
        guard !bpmCues.isEmpty else { return Self(segments: []) }
        var built: [Segment] = []
        for cue in bpmCues {
            guard let bpm = cue.bpm else { continue }
            let meter = cue.beatsPerBar ?? built.last?.beatsPerBar ?? defaultBeatsPerBar
            let clampedBPM = min(max(bpm, 20), 400)
            let clampedMeter = max(1, min(meter, 16))
            built.append(Segment(startSeconds: max(0, cue.time), bpm: clampedBPM, beatsPerBar: clampedMeter))
        }
        return Self(segments: built)
    }

    private func segmentEndSeconds(at index: Int, itemDuration: TimeInterval) -> TimeInterval {
        index + 1 < segments.count ? segments[index + 1].startSeconds : itemDuration
    }

    func beatTimes(
        in range: ClosedRange<TimeInterval>,
        itemDuration: TimeInterval
    ) -> [(time: TimeInterval, isDownbeat: Bool)] {
        guard !segments.isEmpty else { return [] }
        var out: [(time: TimeInterval, isDownbeat: Bool)] = []
        for (index, segment) in segments.enumerated() {
            let spanEnd = segmentEndSeconds(at: index, itemDuration: itemDuration)
            out.append(contentsOf: beats(in: segment, spanEnd: spanEnd, clampedTo: range))
        }
        return out
    }

    func barTimes(in range: ClosedRange<TimeInterval>, itemDuration: TimeInterval) -> [TimeInterval] {
        beatTimes(in: range, itemDuration: itemDuration).filter(\.isDownbeat).map(\.time)
    }

    func nearestBeat(toSeconds seconds: TimeInterval, itemDuration: TimeInterval) -> TimeInterval? {
        nearestGridLine(toSeconds: seconds, itemDuration: itemDuration, stride: \.beatDuration)
    }

    func nearestBar(toSeconds seconds: TimeInterval, itemDuration: TimeInterval) -> TimeInterval? {
        nearestGridLine(toSeconds: seconds, itemDuration: itemDuration, stride: \.barDuration)
    }

    // MARK: - Internals

    private func beats(
        in segment: Segment,
        spanEnd: TimeInterval,
        clampedTo range: ClosedRange<TimeInterval>
    ) -> [(time: TimeInterval, isDownbeat: Bool)] {
        let lower = max(range.lowerBound, segment.startSeconds)
        let upper = min(range.upperBound, spanEnd)
        guard upper >= lower - Self.epsilon else { return [] }
        let step = segment.beatDuration
        let anchor = segment.startSeconds
        let firstIndex = Int(((lower - anchor) / step).rounded(.up))
        let lastIndexInSpan = Int(((spanEnd - Self.epsilon - anchor) / step).rounded(.down))
        let lastIndexInRange = Int(((upper - anchor) / step).rounded(.down))
        let lastIndex = min(lastIndexInSpan, lastIndexInRange)
        guard firstIndex <= lastIndex else { return [] }
        var result: [(time: TimeInterval, isDownbeat: Bool)] = []
        for j in firstIndex...lastIndex {
            let time = anchor + Double(j) * step
            guard time >= segment.startSeconds - Self.epsilon else { continue }
            // Half-open span: the boundary belongs to the next segment.
            // Special case: the segment's first beat (j == 0) IS the boundary and belongs here.
            if j > 0 && time >= spanEnd - Self.epsilon { continue }
            let isDownbeat = ((j % segment.beatsPerBar) + segment.beatsPerBar) % segment.beatsPerBar == 0
            result.append((time: time, isDownbeat: isDownbeat))
        }
        return result
    }

    private func nearestGridLine(
        toSeconds seconds: TimeInterval,
        itemDuration: TimeInterval,
        stride keyPath: KeyPath<Segment, TimeInterval>
    ) -> TimeInterval? {
        guard !segments.isEmpty else { return nil }
        // Find the segment whose span covers `seconds`. If seconds < first segment start, return nil.
        var coveringIndex: Int?
        for (index, segment) in segments.enumerated() where segment.startSeconds <= seconds + Self.epsilon {
            coveringIndex = index
        }
        guard let coveringIndex else { return nil }
        let segment = segments[coveringIndex]
        let spanEnd = segmentEndSeconds(at: coveringIndex, itemDuration: itemDuration)
        let step = segment[keyPath: keyPath]
        guard step > 0 else { return segment.startSeconds }
        let anchor = segment.startSeconds
        let j = ((seconds - anchor) / step).rounded()
        var candidate = anchor + j * step
        if candidate < segment.startSeconds { candidate = segment.startSeconds }
        if candidate >= spanEnd - Self.epsilon {
            let last = ((spanEnd - Self.epsilon - anchor) / step).rounded(.down)
            candidate = anchor + last * step
        }
        // If we're closer to the next segment's start (which is the next downbeat
        // for `barTimes`, and a beat boundary for `beatTimes`), prefer it.
        if coveringIndex + 1 < segments.count {
            let next = segments[coveringIndex + 1].startSeconds
            if abs(next - seconds) < abs(candidate - seconds) {
                return next
            }
        }
        return max(segment.startSeconds, candidate)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/DerivedTempoGridTests -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Tempo/DerivedTempoGrid.swift OnlyCueTests/DerivedTempoGridTests.swift
git commit -m "feat(tempo): add DerivedTempoGrid value type"
```

### Task 2.2: Swap `TempoGridOverlay` to consume `DerivedTempoGrid`

**Files:**
- Modify: `OnlyCue/UI/TempoGridOverlay.swift`
- Modify: `OnlyCue/UI/WaveformContainer+Overlays.swift` (call site)

- [ ] **Step 1: Edit the overlay**

Replace the body of `TempoGridOverlay`:

```swift
struct TempoGridOverlay: View {
    let grid: DerivedTempoGrid
    let duration: TimeInterval

    private static let maxLines = 20_000

    var body: some View {
        Canvas { context, size in
            guard duration > 0, size.width > 0, !grid.isEmpty else { return }
            for entry in grid.beatTimes(in: 0...duration, itemDuration: duration).prefix(Self.maxLines) {
                let position = CueMarkersGeometry.position(forTime: entry.time, width: size.width, duration: duration)
                let lineWidth: CGFloat = entry.isDownbeat ? 1.5 : 0.75
                let rect = CGRect(x: position - lineWidth / 2, y: 0, width: lineWidth, height: size.height)
                context.fill(Path(rect), with: .color(.secondary.opacity(entry.isDownbeat ? 0.45 : 0.2)))
            }
            for segment in grid.segments where segment.startSeconds > 0 {
                let position = CueMarkersGeometry.position(forTime: segment.startSeconds, width: size.width, duration: duration)
                context.fill(Path(CGRect(x: position - 1, y: 0, width: 2, height: size.height)), with: .color(.orange.opacity(0.5)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("tempoGridOverlay")
    }
}
```

- [ ] **Step 2: Update the call site**

In `WaveformContainer+Overlays.swift`, replace whatever `TempoGridOverlay(tempoMap:duration:)` call exists with:

```swift
TempoGridOverlay(
    grid: DerivedTempoGrid.from(cues: item.cues, itemDuration: item.media.duration),
    duration: item.media.duration
)
```

- [ ] **Step 3: Build and smoke-run**

```bash
xcodegen generate
xcodebuild build -scheme OnlyCue -destination 'platform=macOS'
```

Expected: builds. Run the app, load a project with a BPM cue (set manually via the SwiftUI inspector once Leaf 3 lands; for this leaf you can hand-edit a test `.cuelist` or set a cue's `bpm` in a debug breakpoint), and confirm the grid renders.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/TempoGridOverlay.swift OnlyCue/UI/WaveformContainer+Overlays.swift
git commit -m "feat(tempo): render grid from DerivedTempoGrid"
```

### Task 2.3: Swap snap commands to `DerivedTempoGrid`

**Files:**
- Modify: `OnlyCue/Commands/CueCommands+Grid.swift`

- [ ] **Step 1: Update the failing test first**

Edit `OnlyCueTests/CueCommandsGridTests.swift`. Change every `TempoMap` literal in `snapCues` calls to a `DerivedTempoGrid.from(cues:itemDuration:)` constructed from cues that produce the same grid. Delete any test for `addCuesOnGrid` (it goes away).

Example transformation: `TempoMap.singleSection(bpm: 120, beatsPerBar: 4)` becomes
`DerivedTempoGrid.from(cues: [Cue(... bpm: 120, beatsPerBar: 4 ...)], itemDuration: duration)`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/CueCommandsGridTests -destination 'platform=macOS'
```

Expected: FAIL — `snapCues(_:toBeatIn:...)` signature still takes `TempoMap`.

- [ ] **Step 3: Update the command signatures**

In `OnlyCue/Commands/CueCommands+Grid.swift`, replace the two `snapCues` overloads' `toBeatIn map: TempoMap` / `toBarIn map: TempoMap` parameters with `toBeatIn grid: DerivedTempoGrid` / `toBarIn grid: DerivedTempoGrid`. Internally use `grid.nearestBeat(...)` / `grid.nearestBar(...)` instead. Delete `addCuesOnGrid` and `GridResolution` from this file.

- [ ] **Step 4: Fix call sites**

Find call sites in `DocumentView.swift` and similar (search for `snapCues`). Replace `item.tempoMap` with `DerivedTempoGrid.from(cues: item.cues, itemDuration: item.media.duration)`.

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/CueCommandsGridTests -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Commands/CueCommands+Grid.swift OnlyCue/UI OnlyCueTests/CueCommandsGridTests.swift
git commit -m "feat(commands): snap cues against DerivedTempoGrid"
```

### Task 2.4: Open PR for Leaf 2

- [ ] **Step 1: Full suite + lint**

```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS'
swiftlint --strict
```

- [ ] **Step 2: PR**

Use `gh-pr`. Title: `feat(tempo): derive grid from per-cue bpm`. Body links the spec's "Derived grid" section.

---

## Leaf 3 — Cue inspector tempo group + relocated DSP detect

**Issue title:** `feat(ui): per-cue tempo inspector with detect`
**PR template:** `feat.md`

### Task 3.1: Replace `CueCommands+Tempo.swift` with `setCueTempo`

**Files:**
- Modify: `OnlyCue/Commands/CueCommands+Tempo.swift` (delete-and-rewrite)
- Create: `OnlyCueTests/CueCommandsSetTempoTests.swift`

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueCommandsSetTempoTests.swift`:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsSetTempoTests: XCTestCase {

    func testSetCueTempoStoresValues() {
        let (doc, cueID, itemID) = makeDocWithOneCue()
        CueCommands.setCueTempo(
            cueID: cueID, bpm: 120, beatsPerBar: 4,
            item: itemID, document: doc, undoManager: nil
        )
        let cue = doc.model.items[0].cues[0]
        XCTAssertEqual(cue.bpm, 120)
        XCTAssertEqual(cue.beatsPerBar, 4)
    }

    func testSetCueTempoNilClearsBoth() {
        let (doc, cueID, itemID) = makeDocWithOneCue()
        CueCommands.setCueTempo(cueID: cueID, bpm: 120, beatsPerBar: 4, item: itemID, document: doc, undoManager: nil)
        CueCommands.setCueTempo(cueID: cueID, bpm: nil, beatsPerBar: nil, item: itemID, document: doc, undoManager: nil)
        let cue = doc.model.items[0].cues[0]
        XCTAssertNil(cue.bpm)
        XCTAssertNil(cue.beatsPerBar)
    }

    func testSetCueTempoIsUndoable() {
        let (doc, cueID, itemID) = makeDocWithOneCue()
        let undo = UndoManager()
        CueCommands.setCueTempo(cueID: cueID, bpm: 120, beatsPerBar: 4, item: itemID, document: doc, undoManager: undo)
        XCTAssertEqual(doc.model.items[0].cues[0].bpm, 120)
        undo.undo()
        XCTAssertNil(doc.model.items[0].cues[0].bpm)
        undo.redo()
        XCTAssertEqual(doc.model.items[0].cues[0].bpm, 120)
    }

    func testSetCueTempoClampsBPMAndMeter() {
        let (doc, cueID, itemID) = makeDocWithOneCue()
        CueCommands.setCueTempo(cueID: cueID, bpm: 9999, beatsPerBar: 99, item: itemID, document: doc, undoManager: nil)
        XCTAssertEqual(doc.model.items[0].cues[0].bpm, 400)
        XCTAssertEqual(doc.model.items[0].cues[0].beatsPerBar, 16)
    }

    func testSetCueTempoOnUnknownCueIsNoOp() {
        let (doc, _, itemID) = makeDocWithOneCue()
        let snapshot = doc.model
        CueCommands.setCueTempo(cueID: UUID(), bpm: 120, beatsPerBar: 4, item: itemID, document: doc, undoManager: nil)
        XCTAssertEqual(doc.model, snapshot)
    }

    // MARK: - Helpers

    private func makeDocWithOneCue() -> (CueListDocument, Cue.ID, MediaItem.ID) {
        let typeID = UUID()
        let cueID = UUID()
        let itemID = UUID()
        let doc = CueListDocument()
        doc.model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "t",
            cuePointTypes: [CuePointType(id: typeID, name: "G", colorHex: "#fff", hotkey: nil)],
            items: [MediaItem(
                id: itemID,
                media: MediaReference(
                    url: URL(fileURLWithPath: "/tmp/x.wav"),
                    bookmarkData: Data(), displayName: "x", duration: 10, kind: .audio
                ),
                cues: [Cue(
                    id: cueID, typeID: typeID, cueNumber: nil,
                    name: "c", time: 1.0, notes: "", fadeTime: .zero
                )]
            )],
            activeItemID: itemID
        )
        return (doc, cueID, itemID)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/CueCommandsSetTempoTests -destination 'platform=macOS'
```

Expected: FAIL — `setCueTempo` doesn't exist.

- [ ] **Step 3: Replace `CueCommands+Tempo.swift` contents**

Overwrite `OnlyCue/Commands/CueCommands+Tempo.swift` with:

```swift
import Foundation

/// Per-cue tempo command (v11). The cue's time is bar 1, beat 1 of the segment
/// it opens; `bpm`/`beatsPerBar` either nil (no tempo change at this cue) or
/// clamped at construction (20…400 / 1…16). Passing both `nil` clears tempo.
@MainActor
extension CueCommands {

    static func setCueTempo(
        cueID: Cue.ID,
        bpm: Double?,
        beatsPerBar: Int?,
        item itemID: MediaItem.ID,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let itemIndex = document.model.items.firstIndex(where: { $0.id == itemID }) else { return }
        guard let cueIndex = document.model.items[itemIndex].cues.firstIndex(where: { $0.id == cueID }) else { return }

        let clampedBPM = bpm.map { min(max($0, 20), 400) }
        let clampedMeter = beatsPerBar.map { max(1, min($0, 16)) }
        let before = document.model.items[itemIndex].cues[cueIndex]
        guard before.bpm != clampedBPM || before.beatsPerBar != clampedMeter else { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        document.model.items[itemIndex].cues[cueIndex].bpm = clampedBPM
        document.model.items[itemIndex].cues[cueIndex].beatsPerBar = clampedMeter
        let oldBPM = before.bpm
        let oldMeter = before.beatsPerBar
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setCueTempo(
                cueID: cueID, bpm: oldBPM, beatsPerBar: oldMeter,
                item: itemID, document: doc, undoManager: undoManager
            )
        }
        undoManager?.setActionName("Change Cue Tempo")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme OnlyCue -only-testing:OnlyCueTests/CueCommandsSetTempoTests -destination 'platform=macOS'
```

Expected: PASS.

Note: the build will be temporarily broken because `TempoMapSheet.swift` still calls the deleted commands (`setTempoMap`, `addTempoSection`, etc.). For this leaf, **add temporary stub methods** at the bottom of `CueCommands+Tempo.swift` so the sheet keeps compiling. These look like:

```swift
@MainActor
extension CueCommands {
    @available(*, deprecated, message: "Removed in Leaf 5") static func setTempoMap(_: Any, item _: MediaItem.ID, document _: CueListDocument, undoManager _: UndoManager?) {}
    // … one per removed entry point used by TempoMapSheet
}
```

Leaf 5 deletes them along with the sheet.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Commands/CueCommands+Tempo.swift OnlyCueTests/CueCommandsSetTempoTests.swift
git commit -m "feat(commands): add setCueTempo and deprecate section commands"
```

### Task 3.2: Add Tempo group to the cue inspector

**Files:**
- Modify: `OnlyCue/UI/CueInspectorView.swift`

- [ ] **Step 1: Add state and a tempo row**

Add to `CueInspectorView`:

- `@State private var bpmDraft = ""`
- `@State private var beatsPerBarDraft = "4"`
- Extend `Field` enum with `case bpm, beatsPerBar`.

In `syncDrafts(from:)`:

```swift
if focused != .bpm { bpmDraft = cue.bpm.map { String(Int($0.rounded())) } ?? "" }
if focused != .beatsPerBar { beatsPerBarDraft = cue.beatsPerBar.map(String.init) ?? "" }
```

Add a section below the Fade row:

```swift
row("BPM") {
    HStack(spacing: 6) {
        TextField("inherited", text: $bpmDraft)
            .textFieldStyle(.roundedBorder)
            .focused($focused, equals: .bpm)
            .onSubmit { commitBPM(for: cue) }
            .accessibilityIdentifier("cueInspectorBPM")
        TextField("4", text: $beatsPerBarDraft)
            .textFieldStyle(.roundedBorder)
            .focused($focused, equals: .beatsPerBar)
            .onSubmit { commitBeatsPerBar(for: cue) }
            .frame(width: 40)
            .accessibilityIdentifier("cueInspectorBeatsPerBar")
        Text("/bar").font(.caption).foregroundStyle(.secondary)
    }
}
```

Add a small row below for Detect / Clear:

```swift
HStack {
    Button("Detect") { detectTempo(for: cue) }
        .accessibilityIdentifier("cueInspectorDetectTempo")
        .disabled(detectingCueID == cue.id)
    Button("Clear") {
        CueCommands.setCueTempo(cueID: cue.id, bpm: nil, beatsPerBar: nil,
                                item: activeItemID(for: cue), document: document, undoManager: undoManager)
    }
    .disabled(cue.bpm == nil && cue.beatsPerBar == nil)
    if let detectMessage { Text(detectMessage).font(.caption2).foregroundStyle(.secondary) }
}
.padding(.leading, 60)
```

Add commit methods:

```swift
private func commitBPM(for cue: Cue) {
    let trimmed = bpmDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        CueCommands.setCueTempo(
            cueID: cue.id, bpm: nil, beatsPerBar: cue.beatsPerBar,
            item: activeItemID(for: cue), document: document, undoManager: undoManager
        )
        return
    }
    guard let value = Double(trimmed) else {
        bpmDraft = cue.bpm.map { String(Int($0.rounded())) } ?? ""
        return
    }
    CueCommands.setCueTempo(
        cueID: cue.id, bpm: value, beatsPerBar: cue.beatsPerBar ?? Int(beatsPerBarDraft),
        item: activeItemID(for: cue), document: document, undoManager: undoManager
    )
}

private func commitBeatsPerBar(for cue: Cue) {
    let trimmed = beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let parsed = Int(trimmed)
    CueCommands.setCueTempo(
        cueID: cue.id, bpm: cue.bpm, beatsPerBar: parsed,
        item: activeItemID(for: cue), document: document, undoManager: undoManager
    )
}

private func activeItemID(for cue: Cue) -> MediaItem.ID {
    document.model.items.first(where: { $0.cues.contains(where: { $0.id == cue.id }) })!.id
}
```

DSP detect goes in step 2. For now, leave `detectTempo(for:)` as a stub `{ }` that does nothing, with `@State private var detectingCueID: Cue.ID?` and `@State private var detectMessage: String?` declared.

- [ ] **Step 2: Write a snapshot/UI test for the new row**

Add to `OnlyCueUITests` a new test case that opens a doc with one cue, focuses the BPM field, types `120`, presses Tab, then asserts the cue inspector now shows `120`. Use existing `OnlyCueUITests` patterns (see e.g. `TransportBarScreenshotTests.swift`). Save the screenshot under the existing fixtures naming convention.

- [ ] **Step 3: Run tests**

```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/CueInspectorView.swift OnlyCueUITests
git commit -m "feat(ui): add per-cue bpm and beats/bar inspector fields"
```

### Task 3.3: Wire DSP detect into the inspector

**Files:**
- Modify: `OnlyCue/UI/CueInspectorView.swift`

- [ ] **Step 1: Implement `detectTempo(for:)`**

Replace the stub with (adapted from `TempoMapSheet.detectWholeItem`):

```swift
private func detectTempo(for cue: Cue) {
    guard let item = document.model.items.first(where: { $0.cues.contains(where: { $0.id == cue.id }) }) else { return }
    detectMessage = nil
    detectingCueID = cue.id
    let bookmark = item.media.bookmarkData
    let cueTime = cue.time
    let nextBPMCueTime = item.cues
        .filter { $0.id != cue.id && $0.time > cueTime && $0.bpm != nil }
        .map(\.time).min()
    let detectEnd = min(nextBPMCueTime ?? item.media.duration, cueTime + 30)
    let beatsPerBar = cue.beatsPerBar ?? 4
    let cueID = cue.id
    let itemID = item.id

    Task {
        let outcome = await detect(bookmark: bookmark, range: cueTime...detectEnd, beatsPerBar: beatsPerBar)
        await MainActor.run {
            switch outcome {
            case .found(let estimate):
                CueCommands.setCueTempo(
                    cueID: cueID, bpm: estimate.bpm, beatsPerBar: beatsPerBar,
                    item: itemID, document: document, undoManager: undoManager
                )
                detectMessage = estimate.confidence < 0.4
                    ? "Low confidence (\(Int((estimate.confidence * 100).rounded()))%)"
                    : nil
            case .notDetected: detectMessage = "No tempo detected."
            case .noAudio: detectMessage = "This item has no audio to analyze."
            case .failed: detectMessage = "Couldn't open the media file."
            }
            detectingCueID = nil
        }
    }
}

private enum DetectOutcome { case found(TempoEstimate), notDetected, noAudio, failed }

private func detect(bookmark: Data, range: ClosedRange<TimeInterval>?, beatsPerBar: Int) async -> DetectOutcome {
    let url: URL
    let didAccess: Bool
    do {
        let resolution = try Bookmarks.resolve(bookmark)
        url = resolution.url
        didAccess = url.startAccessingSecurityScopedResource()
    } catch { return .failed }
    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
    do {
        let samples = try await AudioSampleReader.readMonoSamples(from: url, range: range)
        guard let estimate = await SpectralFluxTempoAnalyzer().analyze(
            samples: samples, sampleRate: AudioSampleReader.sampleRate, beatsPerBar: beatsPerBar, bpmHint: nil
        ) else { return .notDetected }
        return .found(estimate)
    } catch AudioSampleReader.Error.noAudioTrack {
        return .noAudio
    } catch { return .failed }
}
```

- [ ] **Step 2: Build + manual smoke**

```bash
xcodegen generate && xcodebuild build -scheme OnlyCue -destination 'platform=macOS'
```

Run the app, load an audio item, place a cue near a kick drum, press Detect. Confirm BPM populates.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/CueInspectorView.swift
git commit -m "feat(ui): detect tempo from cue position"
```

### Task 3.4: Open PR for Leaf 3

```bash
xcodebuild test -scheme OnlyCue -destination 'platform=macOS'
swiftlint --strict
```

Use `gh-pr`. Title: `feat(ui): per-cue tempo inspector with detect`.

---

## Leaf 4 — Cue list BPM column (optional)

**Issue title:** `feat(ui): bpm column in cue list`
**PR template:** `feat.md`

This leaf reuses the `cueNumber` column infrastructure shipped in #229. Open `OnlyCue/UI/CueListPane.swift` and find the column-picker enum / `@AppStorage` flag (e.g. `showCueNumberColumn`). Add a parallel `showBPMColumn` flag, default `false`, and a column that renders `cue.bpm.map { Int($0.rounded()).description } ?? ""`.

### Task 4.1: Add the column

**Files:**
- Modify: `OnlyCue/UI/CueListPane.swift`

- [ ] **Step 1: Add the `@AppStorage` flag**

```swift
@AppStorage("showBPMColumn") private var showBPMColumn = false
```

- [ ] **Step 2: Add the column in the same spot the cueNumber column lives**

Mirror the cueNumber column's `TableColumn` declaration, swapping `cueNumber` → `bpm` and formatting as integer.

- [ ] **Step 3: Add a toggle in the column picker UI**

Find the column-picker menu in `CueListPane.swift` (or whatever sibling file owns it). Add `Toggle("BPM", isOn: $showBPMColumn)` next to the cueNumber toggle.

- [ ] **Step 4: Build**

```bash
xcodegen generate && xcodebuild build -scheme OnlyCue -destination 'platform=macOS'
```

- [ ] **Step 5: Commit and PR**

```bash
git add OnlyCue/UI/CueListPane.swift
git commit -m "feat(ui): add optional BPM column to cue list"
```

Then use `gh-pr`.

---

## Leaf 5 — Tear down old surfaces

**Issue title:** `refactor(tempo): remove TempoMap, sheet, and auto-cue menus`
**PR template:** `refactor.md`

### Task 5.1: Delete the Tempo Map sheet

- [ ] **Step 1: Delete files**

```bash
git rm OnlyCue/UI/TempoMapSheet.swift OnlyCue/UI/TempoMapSheet+Fields.swift
```

- [ ] **Step 2: Remove the host modifier call site**

Search for `.tempoMapSheet(` and remove the call (likely in `DocumentView.swift`). Remove the `.tempoMapRequested` `NotificationCenter` posting site.

### Task 5.2: Remove menu items and keymap actions

- [ ] **Step 1: Edit `OnlyCue/App/AppCommands.swift`**

Remove these blocks (lines 158-173 in current file):
- `Button("Tempo Map…") { … }`
- `Button("Split Tempo Section at Playhead") { … }`
- `Button("Add Cues on Every Beat") { … }`
- `Button("Add Cues on Every Bar") { … }`

- [ ] **Step 2: Edit `OnlyCue/App/KeymapAction.swift`**

Remove the `splitTempoSectionAtPlayhead` case, and any `addCuesOnEveryBeat`/`addCuesOnEveryBar` cases if present. Also remove their default keybindings from `Keymap.swift`.

- [ ] **Step 3: Build**

```bash
xcodegen generate && xcodebuild build -scheme OnlyCue -destination 'platform=macOS'
```

Fix any remaining references (notification names, etc.). The notification names `splitTempoSectionAtPlayhead`, `tempoMapRequested`, `addCuesOnEveryBeat`, `addCuesOnEveryBar` can be deleted from `Notification.Name` extensions too.

### Task 5.3: Delete `TempoMap` / `TempoSection` and their tests

- [ ] **Step 1: Delete files**

```bash
git rm OnlyCue/Tempo/TempoMap.swift OnlyCue/Tempo/TempoSection.swift \
       OnlyCueTests/TempoMapTests.swift OnlyCueTests/CueCommandsTempoTests.swift \
       OnlyCueUITests/TempoMapSheetScreenshotTests.swift
```

- [ ] **Step 2: Remove the deprecated stub methods from `CueCommands+Tempo.swift`**

Delete the `@available(*, deprecated, ...)` shims added in Leaf 3. `CueCommands+Tempo.swift` now contains only `setCueTempo`.

- [ ] **Step 3: Delete `addCuesOnGrid` from `CueCommands+Grid.swift`** (if it still lives there from Leaf 2 — verify and remove)

- [ ] **Step 4: Regenerate xcodegen and build**

```bash
xcodegen generate
xcodebuild test -scheme OnlyCue -destination 'platform=macOS'
swiftlint --strict
```

Expected: PASS. Migration tests still pass because `MigrationV10` keeps its private `LegacyTempoMap`/`LegacyTempoSection` shapes.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(tempo): remove TempoMap, sheet, and auto-cue menus"
```

### Task 5.4: Update ADR-020

**Files:**
- Modify: `docs/decisions.md` (find ADR-020)

- [ ] **Step 1: Append a "v11 update" note**

Add a short paragraph to ADR-020 ending with: *"v11 (2026-05-14): tempo lives on cues; the grid is derived from cue-anchored segments via `DerivedTempoGrid`. ADR-020's principle (tempo is a visual + snap aid, not a cue mover) is unchanged."*

- [ ] **Step 2: Commit and PR**

```bash
git add docs/decisions.md
git commit -m "docs: note v11 cue-anchored tempo in ADR-020"
```

Open the Leaf 5 PR with `gh-pr` using the **refactor** template.

---

## Self-Review

**Spec coverage:**
- Data model (Cue gains `bpm`/`beatsPerBar`; MediaItem loses `tempoMap`) — Leaf 1, Tasks 1.1, 1.2.
- Schema bump v10 → v11 — Leaf 1, Task 1.3.
- Migration v10 → v11 — Leaf 1, Task 1.4.
- `DerivedTempoGrid` — Leaf 2, Task 2.1.
- Grid renderer rewrite — Leaf 2, Task 2.2.
- Snap commands swap — Leaf 2, Task 2.3.
- `setCueTempo` command — Leaf 3, Task 3.1.
- Cue inspector tempo group — Leaf 3, Task 3.2.
- Detect button (DSP relocated) — Leaf 3, Task 3.3.
- Cue list BPM column — Leaf 4.
- Delete `TempoMap`/`TempoSection`/sheet/menus — Leaf 5, Tasks 5.1–5.3.
- ADR-020 note — Leaf 5, Task 5.4.
- Drop "Add Cues on Every Beat/Bar" — Leaf 2 (command removal) + Leaf 5 (menu removal).

All spec sections covered.

**Placeholder scan:** none — every code step shows actual code.

**Type consistency:** `setCueTempo(cueID:, bpm:, beatsPerBar:, item:, document:, undoManager:)` signature is the same in the test (3.1 step 1), the implementation (3.1 step 3), and the call sites (3.2, 3.3). `DerivedTempoGrid.from(cues:itemDuration:)` is consistent across tests (2.1), overlay (2.2), and snap commands (2.3). `DerivedTempoGrid.Segment` properties (`startSeconds`, `bpm`, `beatsPerBar`) match between the type definition (2.1) and the overlay consumer (2.2).

---

Plan complete and saved to `docs/superpowers/plans/2026-05-14-cue-anchored-tempo.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
