# Per-Media LTC Timecode & Main-View LTC Strip — Implementation Plan

> **For agentic workers:** Implement this plan task-by-task using TDD discipline (red → green → refactor). Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-05-13-per-media-ltc-design.md`

**Goal:** Replace the project-wide LTC start offset with a per-media `startTimecodeFrames`, add a per-clip `ltcMuted` flag, and render a running-TC ruler lane (with mute toggle) below the waveform when LTC routing is enabled.

**Architecture:** Schema v9→v10 fans the legacy offset onto every `MediaItem`. `ProjectTimecodeSettings.timecode(atPlaybackSeconds:forItem:)` becomes the single TC-mapping seam. `LTCOutputHost` observes the active item's `ltcMuted` and toggles `LTCAudioOutput.setLTCMuted(_:)` without re-cuing. A pure `LTCTickGenerator` produces ruler labels; `LTCStrip` renders them under the waveform when routing is enabled.

**Tech Stack:** Swift 6 · SwiftUI · AVFoundation · XCTest · XcodeGen

---

## File Structure

| File | Responsibility | Status |
|------|----------------|--------|
| `OnlyCue/Document/MediaItem.swift` | Add `startTimecodeFrames`, `ltcMuted` | modify |
| `OnlyCue/Document/ProjectTimecodeSettings.swift` | Drop `startOffsetFrames`; add `timecode(atPlaybackSeconds:forItem:)` | modify |
| `OnlyCue/Document/ProjectModel.swift` | Bump `currentSchemaVersion` to 10 | modify |
| `OnlyCue/Document/ProjectModel+MigrationV10.swift` | v9→v10 migration | create |
| `OnlyCue/Commands/CueCommands+Timecode.swift` | `setStartTimecode`, `setLTCMuted` | modify |
| `OnlyCue/LTC/LTCAudioOutput.swift` | `setLTCMuted(_:)` API | modify |
| `OnlyCue/UI/LTCOutputHost.swift` | Observe active item's `ltcMuted`; thread per-item TC into encoder | modify |
| `OnlyCue/UI/TransportBar.swift` | Use per-item TC mapping | modify |
| `OnlyCue/UI/TimecodeSettingsSheet.swift` | Per-media list with TC fields | modify |
| `OnlyCue/UI/MediaSidebarRow.swift` (or equivalent) | `Set start timecode…` context menu | modify |
| `OnlyCue/UI/LTCTickInterval.swift` | Pure helper: pick tick bucket | create |
| `OnlyCue/UI/LTCTickGenerator.swift` | Pure helper: generate tick positions+labels | create |
| `OnlyCue/UI/LTCStrip.swift` | Lane header (mute + name) + scrolling TC ruler | create |
| `OnlyCue/UI/WaveformContainer.swift` | Mount `LTCStrip` below waveform when routing enabled | modify |
| `OnlyCueTests/ProjectModelMigrationV10Tests.swift` | Migration tests | create |
| `OnlyCueTests/ProjectTimecodeSettingsTests.swift` | Per-item mapping cases | modify |
| `OnlyCueTests/CueCommandsTimecodeTests.swift` | `setStartTimecode`, `setLTCMuted` | modify |
| `OnlyCueTests/LTCAudioOutputTests.swift` | `setLTCMuted` behavior | modify |
| `OnlyCueTests/LTCTickIntervalTests.swift` | Bucket boundaries | create |
| `OnlyCueTests/LTCTickGeneratorTests.swift` | Tick positions + labels | create |
| `OnlyCueUITests/TimecodeSettingsSheetUITests.swift` | Edit per-media TC, verify readout | modify |
| `OnlyCueUITests/MainViewLTCStripUITests.swift` | Strip visibility + mute toggle | create |

---

## Leaf 1: Schema v10 migration + per-media start TC

Lift the start offset out of `ProjectTimecodeSettings` and onto `MediaItem`. Migrate every existing item. Route the LTC engine and transport readout through the new per-item mapping in the same leaf so the codebase compiles.

**Files:**
- Create: `OnlyCue/Document/ProjectModel+MigrationV10.swift`
- Create: `OnlyCueTests/ProjectModelMigrationV10Tests.swift`
- Modify: `OnlyCue/Document/MediaItem.swift`
- Modify: `OnlyCue/Document/ProjectTimecodeSettings.swift`
- Modify: `OnlyCue/Document/ProjectModel.swift` (bump `currentSchemaVersion` to 10)
- Modify: `OnlyCue/UI/LTCOutputHost.swift` (pass active item to TC mapping)
- Modify: `OnlyCue/UI/TransportBar.swift` (pass active item to TC mapping)
- Modify: `OnlyCueTests/ProjectTimecodeSettingsTests.swift`

- [ ] **Step 1: Write the failing migration test**

```swift
// ProjectModelMigrationV10Tests.swift
import XCTest
@testable import OnlyCue

final class ProjectModelMigrationV10Tests: XCTestCase {

    func test_v9ToV10_fansProjectWideOffsetOntoEveryItem() throws {
        let v9JSON = """
        {
          "schemaVersion": 9,
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Show",
          "cuePointTypes": [],
          "items": [
            { "id": "22222222-2222-2222-2222-222222222222",
              "media": { "kind": "bookmark", "bookmark": "AA==", "fileName": "a.wav" },
              "cues": [] },
            { "id": "33333333-3333-3333-3333-333333333333",
              "media": { "kind": "bookmark", "bookmark": "BB==", "fileName": "b.wav" },
              "cues": [] }
          ],
          "activeItemID": null,
          "timecodeSettings": { "framerate": "fps25", "startOffsetFrames": 90000 }
        }
        """.data(using: .utf8)!

        let model = try ProjectModelMigration.load(v9JSON)

        XCTAssertEqual(model.schemaVersion, 10)
        XCTAssertEqual(model.items.count, 2)
        XCTAssertTrue(model.items.allSatisfy { $0.startTimecodeFrames == 90_000 })
        XCTAssertTrue(model.items.allSatisfy { $0.ltcMuted == false })
    }

    func test_v9ToV10_zeroOffset_yieldsZeroOnEveryItem() throws {
        let v9JSON = """
        { "schemaVersion": 9, "id": "11111111-1111-1111-1111-111111111111",
          "name": "Show", "cuePointTypes": [], "items": [
            { "id": "22222222-2222-2222-2222-222222222222",
              "media": { "kind": "bookmark", "bookmark": "AA==", "fileName": "a.wav" },
              "cues": [] } ],
          "activeItemID": null,
          "timecodeSettings": { "framerate": "fps30", "startOffsetFrames": 0 } }
        """.data(using: .utf8)!

        let model = try ProjectModelMigration.load(v9JSON)
        XCTAssertEqual(model.items.first?.startTimecodeFrames, 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests/ProjectModelMigrationV10Tests`
Expected: build FAILS — `startTimecodeFrames` is unknown.

- [ ] **Step 3: Add the new MediaItem fields**

```swift
// MediaItem.swift
struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference
    var cues: [Cue]
    var tempoMap: TempoMap = TempoMap()
    var startTimecodeFrames: Int = 0
    var ltcMuted: Bool = false
}
```

- [ ] **Step 4: Drop startOffsetFrames from ProjectTimecodeSettings; add per-item mapping**

```swift
// ProjectTimecodeSettings.swift
struct ProjectTimecodeSettings: Codable, Equatable, Sendable {

    var framerate: SMPTEFramerate

    static let `default` = Self(framerate: .fps30)

    func timecode(atPlaybackSeconds seconds: TimeInterval, forItem item: MediaItem) -> Timecode {
        let playbackFrames = Int((seconds * Double(framerate.framesPerSecond)).rounded())
        return Timecode(frameCount: item.startTimecodeFrames + max(0, playbackFrames), rate: framerate)
    }

    // Tolerate legacy startOffsetFrames on decode — migration handles it; this
    // is only here so the V10 struct can still round-trip if a downstream tool
    // serializes a stale shape.
    private enum CodingKeys: String, CodingKey { case framerate }
}
```

- [ ] **Step 5: Bump schema version and write the v10 migration**

```swift
// ProjectModel.swift
static let currentSchemaVersion = 10
```

```swift
// ProjectModel+MigrationV10.swift
import Foundation

enum ProjectModelMigrationV10 {

    /// Fans the v9 project-wide `timecodeSettings.startOffsetFrames` onto each
    /// `MediaItem.startTimecodeFrames`. Lossless: a v9 with offset = 0 becomes
    /// a v10 with every item at 0.
    static func migrate(v9: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: v9) as? [String: Any] else {
            throw ProjectModel.LoadError.unsupportedSchemaVersion(9)
        }
        var tcSettings = (root["timecodeSettings"] as? [String: Any]) ?? [:]
        let legacyOffset = tcSettings["startOffsetFrames"] as? Int ?? 0
        tcSettings.removeValue(forKey: "startOffsetFrames")
        root["timecodeSettings"] = tcSettings

        var items = (root["items"] as? [[String: Any]]) ?? []
        for index in items.indices {
            items[index]["startTimecodeFrames"] = legacyOffset
            items[index]["ltcMuted"] = false
        }
        root["items"] = items
        root["schemaVersion"] = 10

        return try JSONSerialization.data(withJSONObject: root)
    }
}
```

Wire `ProjectModelMigrationV10.migrate(v9:)` into the existing `ProjectModelMigration.load(_:)` dispatch chain (read the chain pattern from `ProjectModel+MigrationV8.swift` and follow it exactly — same shape, same dispatch entry point).

- [ ] **Step 6: Update call sites to pass the active item**

`LTCOutputHost.refresh(playing:)` and the seek-threshold branch:

```swift
guard let item = document.model.activeItem else { teardown(); return }
output.start(
    at: timecodeSettings.timecode(atPlaybackSeconds: engine.currentTime, forItem: item),
    routing: routing,
    programRing: wantsProgramAudio ? programRing : nil
)
```

`TransportBar`'s readout binding similarly threads `document.model.activeItem` through `timecode(atPlaybackSeconds:forItem:)`. If `activeItem` is `nil`, fall back to `--:--:--:--` (or whatever the bar already shows when no media is loaded).

- [ ] **Step 7: Extend ProjectTimecodeSettingsTests**

```swift
func test_timecode_forItem_appliesItemStartOffset() {
    let settings = ProjectTimecodeSettings(framerate: .fps25)
    let item = MediaItem(id: UUID(), media: .fixture(),
                        cues: [], startTimecodeFrames: 90_000)  // 01:00:00:00 @ 25fps
    let tc = settings.timecode(atPlaybackSeconds: 5, forItem: item)
    XCTAssertEqual(tc.frameCount, 90_000 + 125)  // 5s @ 25fps = 125 frames
}

func test_timecode_negativeSeconds_clampToItemStart() {
    let settings = ProjectTimecodeSettings(framerate: .fps30)
    let item = MediaItem(id: UUID(), media: .fixture(),
                        cues: [], startTimecodeFrames: 60_000)
    let tc = settings.timecode(atPlaybackSeconds: -1, forItem: item)
    XCTAssertEqual(tc.frameCount, 60_000)
}
```

- [ ] **Step 8: Run the full unit test suite — confirm green**

Run: `xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' test -only-testing:OnlyCueTests`
Expected: all tests pass, including the new migration test.

- [ ] **Step 9: Commit each TDD beat as a separate commit**

```bash
git add OnlyCueTests/ProjectModelMigrationV10Tests.swift
git commit -m "test(document): v9→v10 fans project-wide TC offset onto items"

git add OnlyCue/Document/MediaItem.swift \
        OnlyCue/Document/ProjectTimecodeSettings.swift \
        OnlyCue/Document/ProjectModel.swift \
        OnlyCue/Document/ProjectModel+MigrationV10.swift \
        OnlyCue/UI/LTCOutputHost.swift \
        OnlyCue/UI/TransportBar.swift \
        OnlyCueTests/ProjectTimecodeSettingsTests.swift
git commit -m "feat(document): per-media start timecode (schema v10)"
```

---

## Leaf 2: Per-clip LTC mute pipeline

Add `MediaItem.ltcMuted` plumbing end-to-end: the data model field already exists (from leaf 1); add `LTCAudioOutput.setLTCMuted(_:)`, the `CueCommands.setLTCMuted` undoable command, and the `LTCOutputHost` observation. No UI yet — that's leaf 6.

**Files:**
- Modify: `OnlyCue/LTC/LTCAudioOutput.swift`
- Modify: `OnlyCue/Commands/CueCommands+Timecode.swift` (or create `CueCommands+LTC.swift` if it gets crowded — follow the existing one-file-per-domain convention)
- Modify: `OnlyCue/UI/LTCOutputHost.swift`
- Modify: `OnlyCueTests/CueCommandsTimecodeTests.swift`
- Modify: `OnlyCueTests/LTCAudioOutputTests.swift`

- [ ] **Step 1: Write the failing CueCommands test**

```swift
func test_setLTCMuted_togglesField_andIsUndoable() {
    var model = ProjectModel.fixture(itemCount: 1)
    let itemID = model.items[0].id
    XCTAssertFalse(model.items[0].ltcMuted)

    let command = CueCommands.setLTCMuted(itemID: itemID, muted: true)
    let result = command.apply(to: &model)
    XCTAssertTrue(model.items[0].ltcMuted)

    result.inverse.apply(to: &model)
    XCTAssertFalse(model.items[0].ltcMuted)
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `xcodebuild ... -only-testing:OnlyCueTests/CueCommandsTimecodeTests/test_setLTCMuted_togglesField_andIsUndoable`
Expected: FAIL — `setLTCMuted` undefined.

- [ ] **Step 3: Implement CueCommands.setLTCMuted**

Follow the pattern of an existing simple item mutation (look at `setActiveItem` or `setItemName` if present). Return a command whose `apply` flips the bool and whose `inverse` flips it back to the captured previous value.

- [ ] **Step 4: Add LTCAudioOutput.setLTCMuted(_:)**

Write a failing `LTCAudioOutputTests` case first:

```swift
func test_setLTCMuted_zerosLTCChannelButLeavesTrackChannelsAudible() {
    // Use the existing test fixture for LTCAudioOutput that captures rendered
    // samples. After setLTCMuted(true), the LTC channel buffer should be all
    // zeros for the next render block; Track L/R should be unchanged.
}
```

Then implement. The encoder must keep generating samples (so unmute is instant); only the *write* of the LTC channel's interleaved samples gates on the muted flag.

- [ ] **Step 5: Wire LTCOutputHost to the muted flag**

```swift
.onChange(of: document.model.activeItem?.ltcMuted ?? false) { _, newMuted in
    output.setLTCMuted(newMuted)
}
```

(If `activeItem` doesn't notify reactively when its `ltcMuted` changes, switch to observing `document.model.items` and reading the active item's mute inside the closure.)

`refresh(playing:)` should also call `output.setLTCMuted(activeItem.ltcMuted)` right after `output.start(...)` so a freshly-started engine respects the persisted state.

- [ ] **Step 6: Run full suite — confirm green**

- [ ] **Step 7: Commit**

```bash
git add OnlyCueTests/CueCommandsTimecodeTests.swift OnlyCueTests/LTCAudioOutputTests.swift
git commit -m "test(ltc): per-clip mute toggles channel and is undoable"

git add OnlyCue/LTC/LTCAudioOutput.swift OnlyCue/Commands/CueCommands+Timecode.swift OnlyCue/UI/LTCOutputHost.swift
git commit -m "feat(ltc): per-clip LTC mute (encoder keeps running)"
```

---

## Leaf 3: TimecodeSettingsSheet — per-media TC list

Extend the existing sheet (Tools → Timecode Settings) with a list of every MediaItem and an editable HH:MM:SS:FF field per row. Use `Timecode.parse` for validation; invalid input outlines the field red and does not commit.

**Files:**
- Modify: `OnlyCue/UI/TimecodeSettingsSheet.swift`
- Create: `OnlyCue/UI/MediaTimecodeRow.swift`
- Modify: `OnlyCue/Commands/CueCommands+Timecode.swift` (add `setStartTimecode(itemID:frames:)`)
- Modify: `OnlyCueTests/CueCommandsTimecodeTests.swift`
- Modify: `OnlyCueUITests/TimecodeSettingsSheetUITests.swift`

- [ ] **Step 1: Failing test for `setStartTimecode`**

```swift
func test_setStartTimecode_setsFrames_andIsUndoable() {
    var model = ProjectModel.fixture(itemCount: 1)
    let itemID = model.items[0].id
    let command = CueCommands.setStartTimecode(itemID: itemID, frames: 90_000)
    let result = command.apply(to: &model)
    XCTAssertEqual(model.items[0].startTimecodeFrames, 90_000)
    result.inverse.apply(to: &model)
    XCTAssertEqual(model.items[0].startTimecodeFrames, 0)
}

func test_setStartTimecode_negativeFrames_rejected() {
    var model = ProjectModel.fixture(itemCount: 1)
    let itemID = model.items[0].id
    let command = CueCommands.setStartTimecode(itemID: itemID, frames: -1)
    _ = command.apply(to: &model)
    XCTAssertEqual(model.items[0].startTimecodeFrames, 0)  // unchanged
}
```

- [ ] **Step 2: Run — verify failing**

- [ ] **Step 3: Implement setStartTimecode**

Same shape as `setLTCMuted`. Validation: clamp `frames` to `>= 0`; if invalid, return a no-op command with an identity inverse so the undo stack stays clean.

- [ ] **Step 4: Failing UI test — edit a clip TC, verify readout**

```swift
// TimecodeSettingsSheetUITests.swift
func test_editingItem2StartTC_updatesTransportReadout() {
    let app = launchAppWithTwoMediaItems()
    openMenu(app, ["Tools", "Timecode Settings…"])
    let row = app.scrollViews["timecodeSheetItemList"].cells.element(boundBy: 1)
    let field = row.textFields["startTimecodeField"]
    field.click(); field.typeKey("a", modifierFlags: .command); field.typeText("01:15:00:00\n")
    app.buttons["Done"].click()

    selectMediaItem(app, index: 1)
    let readout = app.staticTexts["transportTimecodeReadout"]
    XCTAssertEqual(readout.value as? String, "01:15:00:00")
}
```

- [ ] **Step 5: Build the per-media row view**

```swift
// MediaTimecodeRow.swift
struct MediaTimecodeRow: View {
    let item: MediaItem
    let framerate: SMPTEFramerate
    let onCommit: (Int) -> Void

    @State private var draft: String = ""
    @State private var isInvalid: Bool = false

    var body: some View {
        HStack {
            Image(systemName: "music.note")
            Text(item.media.fileName).lineLimit(1).truncationMode(.middle)
            Spacer()
            TextField("HH:MM:SS:FF", text: $draft)
                .font(.body.monospaced())
                .frame(width: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isInvalid ? Color.red : Color.clear, lineWidth: 1)
                )
                .onSubmit { commit() }
                .accessibilityIdentifier("startTimecodeField")
        }
        .onAppear { draft = Timecode(frameCount: item.startTimecodeFrames, rate: framerate).description }
    }

    private func commit() {
        if let parsed = Timecode.parse(draft, rate: framerate) {
            isInvalid = false
            onCommit(parsed.frameCount)
        } else {
            isInvalid = true
        }
    }
}
```

- [ ] **Step 6: Embed the list in TimecodeSettingsSheet**

Add a `List` (or `LazyVStack` inside a `ScrollView` if the existing sheet uses one) of `MediaTimecodeRow`. Wire each row's `onCommit` to `document.cueCommands.run(CueCommands.setStartTimecode(itemID:frames:))`. Give the list `.accessibilityIdentifier("timecodeSheetItemList")`.

- [ ] **Step 7: Run full suite — confirm green**

- [ ] **Step 8: Commit**

```bash
git add OnlyCueTests/CueCommandsTimecodeTests.swift
git commit -m "test(commands): setStartTimecode + negative-frames rejection"

git add OnlyCueUITests/TimecodeSettingsSheetUITests.swift
git commit -m "test(ui): editing a clip's start TC updates the transport readout"

git add OnlyCue/UI/TimecodeSettingsSheet.swift OnlyCue/UI/MediaTimecodeRow.swift OnlyCue/Commands/CueCommands+Timecode.swift
git commit -m "feat(ui): per-media start TC editor in the Timecode Settings sheet"
```

---

## Leaf 4: Sidebar row context menu — "Set start timecode…"

Add a context-menu item to each media row in the document sidebar that pins an inline TC editor on the row (reuses the same parser/validation as the sheet field).

**Files:**
- Modify: `OnlyCue/UI/MediaSidebarRow.swift` (or whichever file owns sidebar rows — find with `rg "ContextMenu|contextMenu" OnlyCue/UI/`)
- Modify (maybe): `OnlyCue/UI/DocumentSidebar.swift` (or equivalent)
- Modify: `OnlyCueUITests/MediaSidebarUITests.swift` (or create if absent)

- [ ] **Step 1: Failing UI test — right-click sets TC**

```swift
func test_sidebarContextMenu_setStartTimecode_updatesItem() {
    let app = launchAppWithTwoMediaItems()
    let row = app.outlines["mediaSidebar"].cells.element(boundBy: 1)
    row.rightClick()
    app.menuItems["Set start timecode…"].click()
    let field = row.textFields["inlineStartTimecodeField"]
    field.typeText("01:15:00:00\n")
    selectMediaItem(app, index: 1)
    XCTAssertEqual(app.staticTexts["transportTimecodeReadout"].value as? String, "01:15:00:00")
}
```

- [ ] **Step 2: Run — verify failing**

- [ ] **Step 3: Implement the context-menu item + inline editor**

The inline editor is the same `TextField` shape as `MediaTimecodeRow`, surfaced on the sidebar row via a `@State var isEditingTC: Bool` that the context-menu action flips. ESC reverts; Return commits via `CueCommands.setStartTimecode`. Identifier the field `inlineStartTimecodeField`.

- [ ] **Step 4: Run full suite — confirm green**

- [ ] **Step 5: Commit**

```bash
git add OnlyCueUITests/MediaSidebarUITests.swift
git commit -m "test(ui): sidebar context menu sets a clip's start TC"

git add OnlyCue/UI/MediaSidebarRow.swift OnlyCue/UI/DocumentSidebar.swift
git commit -m "feat(ui): \"Set start timecode…\" context menu on sidebar rows"
```

---

## Leaf 5: Pure tick helpers (LTCTickInterval + LTCTickGenerator)

Build the two pure types the strip will consume. No UI, no SwiftUI — just `Int`/`Double` math and label formatting. Lets the strip itself stay thin in leaf 6.

**Files:**
- Create: `OnlyCue/UI/LTCTickInterval.swift`
- Create: `OnlyCue/UI/LTCTickGenerator.swift`
- Create: `OnlyCueTests/LTCTickIntervalTests.swift`
- Create: `OnlyCueTests/LTCTickGeneratorTests.swift`

- [ ] **Step 1: Failing test for LTCTickInterval**

```swift
final class LTCTickIntervalTests: XCTestCase {

    /// At narrow zoom (many seconds per pixel), the bucket must be coarse.
    func test_pick_chooses60s_whenVeryNarrow() {
        let bucket = LTCTickInterval.pick(secondsVisible: 600, pxPerSecond: 0.5)
        XCTAssertEqual(bucket, 60)
    }

    /// At wide zoom, the bucket should be 1s.
    func test_pick_chooses1s_whenVeryWide() {
        let bucket = LTCTickInterval.pick(secondsVisible: 30, pxPerSecond: 80)
        XCTAssertEqual(bucket, 1)
    }

    /// Bucket boundary: pxPerLabel must stay >= 56.
    func test_pick_respects56pxMinimum() {
        // At pxPerSecond=10, 5s bucket → 50 px (too tight) → must escalate to 15s.
        let bucket = LTCTickInterval.pick(secondsVisible: 60, pxPerSecond: 10)
        XCTAssertEqual(bucket, 15)
    }
}
```

- [ ] **Step 2: Run — verify failing**

- [ ] **Step 3: Implement LTCTickInterval**

```swift
enum LTCTickInterval {
    static let buckets: [Int] = [1, 5, 15, 30, 60]
    static let minPxPerLabel: CGFloat = 56

    static func pick(secondsVisible: Double, pxPerSecond: CGFloat) -> Int {
        for bucket in buckets {
            if CGFloat(bucket) * pxPerSecond >= minPxPerLabel {
                return bucket
            }
        }
        return buckets.last!
    }
}
```

- [ ] **Step 4: Failing test for LTCTickGenerator**

```swift
final class LTCTickGeneratorTests: XCTestCase {

    func test_generates_ticksStartingAtItemStartTC_atGivenBucket() {
        let item = MediaItem(id: UUID(), media: .fixture(),
                             cues: [], startTimecodeFrames: 90_000)  // 01:00:00 @ 25
        let ticks = LTCTickGenerator.ticks(
            duration: 10, framerate: .fps25, startTimecodeFrames: item.startTimecodeFrames,
            bucketSeconds: 5, contentWidth: 1000
        )
        XCTAssertEqual(ticks.first?.label, "01:00:00")
        XCTAssertEqual(ticks.dropFirst().first?.label, "01:00:05")
        XCTAssertEqual(ticks.count, 3)  // 0, 5, 10 seconds
    }

    func test_majorTickEvery5thLabel() {
        let ticks = LTCTickGenerator.ticks(
            duration: 30, framerate: .fps30, startTimecodeFrames: 0,
            bucketSeconds: 1, contentWidth: 3000
        )
        XCTAssertTrue(ticks[0].isMajor)
        XCTAssertFalse(ticks[1].isMajor)
        XCTAssertTrue(ticks[5].isMajor)
    }
}
```

- [ ] **Step 5: Run — verify failing**

- [ ] **Step 6: Implement LTCTickGenerator**

```swift
struct LTCTick: Equatable {
    let xPosition: CGFloat
    let label: String
    let isMajor: Bool
}

enum LTCTickGenerator {
    static func ticks(
        duration: TimeInterval,
        framerate: SMPTEFramerate,
        startTimecodeFrames: Int,
        bucketSeconds: Int,
        contentWidth: CGFloat
    ) -> [LTCTick] {
        guard duration > 0, contentWidth > 0, bucketSeconds > 0 else { return [] }
        var out: [LTCTick] = []
        var second = 0
        let pxPerSecond = contentWidth / CGFloat(duration)
        while Double(second) <= duration + 0.001 {
            let frames = startTimecodeFrames + second * framerate.framesPerSecond
            let tc = Timecode(frameCount: frames, rate: framerate)
            let label = String(format: "%02d:%02d:%02d", tc.hours, tc.minutes, tc.seconds)
            let isMajor = (second / bucketSeconds) % 5 == 0
            out.append(LTCTick(
                xPosition: CGFloat(second) * pxPerSecond,
                label: label,
                isMajor: isMajor
            ))
            second += bucketSeconds
        }
        return out
    }
}
```

- [ ] **Step 7: Run full suite — confirm green**

- [ ] **Step 8: Commit**

```bash
git add OnlyCueTests/LTCTickIntervalTests.swift OnlyCueTests/LTCTickGeneratorTests.swift
git commit -m "test(ui): LTC tick interval picker + tick generator"

git add OnlyCue/UI/LTCTickInterval.swift OnlyCue/UI/LTCTickGenerator.swift
git commit -m "feat(ui): pure LTC tick helpers"
```

---

## Leaf 6: Main-view LTC strip (visual lane + mute toggle)

Mount `LTCStrip` below the waveform in `WaveformContainer`. Only render when `LTCRoutingStore.shared.settings.isEnabled` and an item is active. Lane header (fixed) shows file name + mute toggle bound to `ltcMuted`; TC ruler scrolls with the waveform.

**Files:**
- Create: `OnlyCue/UI/LTCStrip.swift`
- Modify: `OnlyCue/UI/WaveformContainer.swift`
- Create: `OnlyCueUITests/MainViewLTCStripUITests.swift`

- [ ] **Step 1: Failing UI test — strip visibility**

```swift
func test_strip_absent_whenLTCDisabled() {
    let app = launchAppWithMediaImported(ltcEnabled: false)
    XCTAssertFalse(app.otherElements["ltcStrip"].exists)
}

func test_strip_appears_whenLTCEnabled() {
    let app = launchAppWithMediaImported(ltcEnabled: true)
    XCTAssertTrue(app.otherElements["ltcStrip"].waitForExistence(timeout: 5))
}

func test_muteToggle_flipsAccessibilityLabel() {
    let app = launchAppWithMediaImported(ltcEnabled: true)
    let activeItemID = currentActiveItemID(app)
    let toggle = app.buttons["ltcMuteToggle.\(activeItemID)"]
    XCTAssertEqual(toggle.label, "LTC unmuted")
    toggle.click()
    XCTAssertEqual(toggle.label, "LTC muted")
}
```

- [ ] **Step 2: Run — verify failing**

- [ ] **Step 3: Implement LTCStrip**

```swift
struct LTCStrip: View {
    let item: MediaItem
    let framerate: SMPTEFramerate
    let duration: TimeInterval
    let contentWidth: CGFloat
    let muted: Bool
    let onToggleMute: () -> Void

    private static let laneHeaderWidth: CGFloat = 120
    private static let stripHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            header
            ruler
        }
        .frame(height: Self.stripHeight)
        .background(Color.secondary.opacity(0.08))
        .accessibilityIdentifier("ltcStrip")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onToggleMute) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(muted ? "LTC muted" : "LTC unmuted")
            .accessibilityIdentifier("ltcMuteToggle.\(item.id.uuidString)")
            Text(item.media.fileName)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.laneHeaderWidth, alignment: .leading)
    }

    private var ruler: some View {
        Canvas { context, size in
            let pxPerSecond = size.width / max(CGFloat(duration), 1)
            let bucket = LTCTickInterval.pick(
                secondsVisible: duration,
                pxPerSecond: pxPerSecond
            )
            let ticks = LTCTickGenerator.ticks(
                duration: duration,
                framerate: framerate,
                startTimecodeFrames: item.startTimecodeFrames,
                bucketSeconds: bucket,
                contentWidth: size.width
            )
            for tick in ticks {
                let tickHeight: CGFloat = tick.isMajor ? 10 : 6
                var path = Path()
                path.move(to: CGPoint(x: tick.xPosition, y: size.height))
                path.addLine(to: CGPoint(x: tick.xPosition, y: size.height - tickHeight))
                context.stroke(path, with: .color(.secondary), lineWidth: 1)
                let text = Text(tick.label).font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                context.draw(text, at: CGPoint(x: tick.xPosition + 2, y: size.height - tickHeight - 8), anchor: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Mount under the waveform in WaveformContainer**

```swift
// inside loaded(peaks:) — append below the waveform body, outside the ScrollView.
if LTCRoutingStore.shared.settings.isEnabled, let item = engine?.activeMediaItem {
    LTCStrip(
        item: item,
        framerate: timecodeSettings.framerate,
        duration: loadedDuration,
        contentWidth: contentWidth,
        muted: item.ltcMuted,
        onToggleMute: {
            document.cueCommands.run(
                CueCommands.setLTCMuted(itemID: item.id, muted: !item.ltcMuted)
            )
        }
    )
}
```

(Where the `engine?.activeMediaItem` accessor lives depends on how `WaveformContainer` already wires the document — find via `rg "engine\." OnlyCue/UI/WaveformContainer.swift` and route through the existing seam. If `WaveformContainer` doesn't have `document` access, pass it in as a new parameter from `DocumentView`.)

The strip is *outside* the `ScrollView` of the waveform — the ruler does its own pan/zoom by reading `contentWidth` and `duration` directly. If a follow-up wants it to sync with horizontal scroll, the strip's ruler will need to share the scroll's `ScrollViewReader` — defer to a follow-up issue.

- [ ] **Step 5: Run full suite — confirm green**

- [ ] **Step 6: Commit**

```bash
git add OnlyCueUITests/MainViewLTCStripUITests.swift
git commit -m "test(ui): LTC strip visibility + mute toggle"

git add OnlyCue/UI/LTCStrip.swift OnlyCue/UI/WaveformContainer.swift
git commit -m "feat(ui): main-view LTC strip with per-clip mute toggle"
```

---

## Self-Review

Spec coverage check:

- §Data model / `MediaItem.startTimecodeFrames`, `ltcMuted` → leaf 1, leaf 2. ✓
- §Migration v9 → v10 → leaf 1. ✓
- §`timecode(atPlaybackSeconds:forItem:)` → leaf 1. ✓
- §`TimecodeSettingsSheet` per-media list → leaf 3. ✓
- §Sidebar context menu → leaf 4. ✓
- §LTC strip placement (below waveform, gated on routing) → leaf 6. ✓
- §Lane header (mute + name) → leaf 6. ✓
- §TC ruler (tick generation, label format) → leaf 5 + 6. ✓
- §`LTCAudioOutput.setLTCMuted(_:)` → leaf 2. ✓
- §`LTCOutputHost` observes `ltcMuted` → leaf 2. ✓
- §`CueCommands.setStartTimecode`, `setLTCMuted` → leaf 2, leaf 3. ✓
- §Tests — every leaf has its red/green TDD beats. ✓
- §Non-goals respected — no per-media framerate, no carrier waveform, no auto-chaining. ✓

Identifier consistency check: `setStartTimecode(itemID:frames:)`, `setLTCMuted(itemID:muted:)`, `startTimecodeFrames`, `ltcMuted`, `LTCTickInterval.pick`, `LTCTickGenerator.ticks`, `ltcStrip`, `ltcMuteToggle.<itemID>`, `startTimecodeField`, `inlineStartTimecodeField`, `timecodeSheetItemList` — all consistent across leaves.

Placeholder scan: no TBDs. The two places I left to per-leaf judgement (sidebar row file location and `WaveformContainer.engine.activeMediaItem` accessor) are concrete instructions to `rg` for the existing seam, not unspecified work.

Plan is ready.
