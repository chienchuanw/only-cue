# Playback Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three mutually-exclusive playback modes (Play Once / Loop Current Media / Auto Play Next Media) to OnlyCue, surfaced in the Playback menu and TransportBar, persisted per-document.

**Architecture:** New `PlaybackMode` enum on `ProjectModel` (schema v14 → v15, additive migration). All mutations through `CueCommands` (`setPlaybackMode`, `advanceToNextMediaAndPlay`). `PlayerEngine` exposes an `AVPlayerItem.didPlayToEndTimeNotification`-driven publisher; `DocumentView` subscribes and dispatches per mode, with LTC interlock suppressing transitions at fire time.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Combine, XCTest, XCUITest.

**Spec:** `docs/superpowers/specs/2026-05-24-playback-modes-design.md`

---

## File map

**Create:**

- `OnlyCue/Document/ProjectModel+MigrationV14.swift` — v14 → v15 additive migration
- `OnlyCue/Commands/CueCommands+Playback.swift` — `setPlaybackMode`, `advanceToNextMediaAndPlay`, `nextMediaItemID(after:in:)`
- `OnlyCue/UI/PlaybackModeBadge.swift` — SwiftUI view for the TransportControls badge
- `OnlyCueTests/ProjectModelMigrationV14Tests.swift`
- `OnlyCueTests/CueCommandsPlaybackModeTests.swift`
- `OnlyCueTests/CueCommandsAdvanceMediaTests.swift`
- `OnlyCueTests/PlayerEngineEndOfMediaTests.swift`
- `OnlyCueUITests/PlaybackModeMenuUITests.swift`
- `OnlyCueUITests/PlaybackModeBadgeUITests.swift`

**Modify:**

- `OnlyCue/Document/ProjectModel.swift` — add `PlaybackMode` enum, `playbackMode` field, bump `currentSchemaVersion` to 15
- `OnlyCue/Document/ProjectModel+Migration.swift` — add `case 14:` dispatch arm
- `OnlyCue/Media/PlayerEngine.swift` — add `mediaDidReachEnd` publisher
- `OnlyCue/App/AppCommands.swift` — add three mode items to Playback menu
- `OnlyCue/UI/DocumentView.swift` — subscribe to end-of-media, dispatch per mode
- `OnlyCue/UI/TransportControls.swift` — insert `PlaybackModeBadge`

---

## Conventions

- **Branch:** `issues/<N>` (handled by `gh-dev`).
- **Commits:** Conventional Commits, lowercase after prefix, imperative. No `Co-Authored-By`.
- **Test-first**: every implementation step is preceded by a failing test step.
- **One test commit per task** when natural; group small adjacent changes into a single commit if they share the same red-green cycle.
- **Regenerate the Xcode project** after adding any new file: `xcodegen generate` (then `xcodebuild test ...` from CLI to verify).

To build + test from CLI throughout (substitute scheme if different — confirm with `xcodebuild -list -project OnlyCue.xcodeproj`):

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests
```

---

## Task 1: Add `PlaybackMode` enum and field to `ProjectModel`

**Files:**

- Modify: `OnlyCue/Document/ProjectModel.swift`

This task ONLY adds the type and the stored property. Migration, commands, and UI come in later tasks. We deliberately bump `currentSchemaVersion` here even though the migration isn't written yet — Task 2 makes the migration and fixes the resulting test failure for old documents.

- [ ] **Step 1: Edit `OnlyCue/Document/ProjectModel.swift` to add the enum and field**

Replace the file contents with:

```swift
import Foundation

struct ProjectModel: Codable, Equatable {

    static let currentSchemaVersion = 15

    var schemaVersion: Int
    var id: UUID
    var name: String
    var cuePointTypes: [CuePointType] = []
    var items: [MediaItem]
    var activeItemID: UUID?
    var timecodeSettings: ProjectTimecodeSettings = .default
    var playbackMode: PlaybackMode = .playOnce

    var defaultCuePointTypeID: UUID? { cuePointTypes.first?.id }

    var activeItem: MediaItem? {
        guard let id = activeItemID else { return nil }
        return items.first { $0.id == id }
    }

    var activeItemIndex: Int? {
        guard let id = activeItemID else { return nil }
        return items.firstIndex { $0.id == id }
    }

    /// Resolves the cue's display color from its `CuePointType`. Returns `nil` when the
    /// `typeID` doesn't match any Type in `cuePointTypes` (a programmer error in production
    /// but tolerated so views can fall back to `.accentColor`).
    func colorHex(for cue: Cue) -> String? {
        cuePointTypes.first(where: { $0.id == cue.typeID })?.colorHex
    }

    /// Returns the Type bound to a digit hotkey, if any. Used by the number-key
    /// cue-creation dispatch in `DocumentView`. Returns nil for unbound digits;
    /// the caller no-ops in that case.
    func cuePointType(forHotkey digit: Int) -> CuePointType? {
        cuePointTypes.first(where: { $0.hotkey == digit })
    }
}

/// End-of-media transport policy. Mutually exclusive — exactly one mode is
/// active per document. Default `.playOnce` preserves pre-v15 behavior.
enum PlaybackMode: String, Codable, Equatable, CaseIterable {
    case playOnce
    case loop
    case autoNext
}

extension ProjectModel {

    enum LoadError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
    }

    static let defaultCuePointTypeName = "General"
    static let defaultCuePointTypeColorHex = "#4ECDC4"

    static func makeDefaultCuePointType() -> CuePointType {
        CuePointType(
            id: UUID(),
            name: defaultCuePointTypeName,
            colorHex: defaultCuePointTypeColorHex
        )
    }
}
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `xcodegen generate`
Expected: regenerates `OnlyCue.xcodeproj` with no errors.

- [ ] **Step 3: Build to confirm the type compiles**

Run: `xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/Document/ProjectModel.swift
git commit -m "feat(model): add PlaybackMode enum and bump schema to v15"
```

---

## Task 2: v14 → v15 migration

**Files:**

- Create: `OnlyCue/Document/ProjectModel+MigrationV14.swift`
- Create: `OnlyCueTests/ProjectModelMigrationV14Tests.swift`
- Modify: `OnlyCue/Document/ProjectModel+Migration.swift`

Additive migration — every v14 field decodes straight into v15; the only change is restamping `schemaVersion` and the `playbackMode` default coming from the field's `= .playOnce` initializer.

- [ ] **Step 1: Write the failing migration test**

Create `OnlyCueTests/ProjectModelMigrationV14Tests.swift`:

```swift
import XCTest
@testable import OnlyCue

/// v14 -> v15 migration: adds `ProjectModel.playbackMode` defaulting to
/// `.playOnce`. Additive — every other field decodes as-is.
final class ProjectModelMigrationV14Tests: XCTestCase {

    private static let typeIDString = "AAAA0001-0000-0000-0000-000000000001"

    private func v14Doc(schemaVersion: Int = 14) -> String {
        """
        {
          "schemaVersion": \(schemaVersion),
          "id": "11110000-1111-0000-1111-000011110000",
          "name": "doc",
          "cuePointTypes": [{
            "id":"\(Self.typeIDString)","name":"G","colorHex":"#FFFFFF",
            "defaultFadeTime":0,"defaultNamePattern":"Cue","hotkey":null,
            "isVisible":true,"isExportEnabled":true
          }],
          "items": [{
            "id": "22220000-2222-0000-2222-000022220000",
            "media": {"displayName":"x.wav","kind":"audio","duration":60,"bookmarkData":"AQID"},
            "cues": [],
            "startTimecodeFrames": 0,
            "ltcMuted": false,
            "alternateName": null,
            "lyrics": {"lines": [], "offsetSeconds": 0}
          }],
          "activeItemID": null,
          "timecodeSettings": {"framerate":"30"}
        }
        """
    }

    func test_v14ToV15_decodesAndBumpsSchemaVersion() throws {
        let migrated = try ProjectModel.decode(from: Data(v14Doc().utf8))
        XCTAssertEqual(migrated.schemaVersion, ProjectModel.currentSchemaVersion)
    }

    func test_v14ToV15_defaultsPlaybackModeToPlayOnce() throws {
        let migrated = try ProjectModel.decode(from: Data(v14Doc().utf8))
        XCTAssertEqual(migrated.playbackMode, .playOnce)
    }

    func test_v14ToV15_preservesItems() throws {
        let migrated = try ProjectModel.decode(from: Data(v14Doc().utf8))
        XCTAssertEqual(migrated.items.count, 1)
        XCTAssertEqual(migrated.items[0].media.displayName, "x.wav")
    }

    func test_currentVersionDoc_roundTripsWithExplicitPlaybackMode() throws {
        var model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "round",
            items: [],
            activeItemID: nil
        )
        model.playbackMode = .loop

        let data = try JSONEncoder().encode(model)
        let decoded = try ProjectModel.decode(from: data)

        XCTAssertEqual(decoded.playbackMode, .loop)
    }
}
```

- [ ] **Step 2: Regenerate project and run the test — expect failure**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/ProjectModelMigrationV14Tests -quiet
```

Expected: tests FAIL with `unsupportedSchemaVersion(14)` thrown from `decode(from:)`.

- [ ] **Step 3: Create the migration file**

Create `OnlyCue/Document/ProjectModel+MigrationV14.swift`:

```swift
import Foundation

/// v14 → v15 migration: adds `ProjectModel.playbackMode` (defaults to
/// `.playOnce`). Additive — every other field decodes as-is; only
/// `schemaVersion` is restamped.
extension ProjectModel {

    static func migrateFromV14(data: Data) throws -> ProjectModel {
        var model = try JSONDecoder().decode(ProjectModel.self, from: data)
        model.schemaVersion = currentSchemaVersion
        return model
    }
}
```

- [ ] **Step 4: Wire the case into the dispatch switch**

Edit `OnlyCue/Document/ProjectModel+Migration.swift`. Find the line:

```swift
        case 13: return try migrateFromV13(data: data)
```

and insert immediately after it:

```swift
        case 14: return try migrateFromV14(data: data)
```

- [ ] **Step 5: Regenerate and run the migration tests — expect pass**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/ProjectModelMigrationV14Tests -quiet
```

Expected: all four tests PASS.

- [ ] **Step 6: Run the full test suite to confirm no regression in older migration tests**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests -quiet
```

Expected: full suite passes. (Existing migration tests like `ProjectModelMigrationV13Tests` already assert `migrated.schemaVersion == ProjectModel.currentSchemaVersion`, so they continue to work because `migrateFromV13` re-stamps the version and `playbackMode` lands on its default.)

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/Document/ProjectModel+MigrationV14.swift \
        OnlyCue/Document/ProjectModel+Migration.swift \
        OnlyCueTests/ProjectModelMigrationV14Tests.swift
git commit -m "feat(model): migrate v14 documents to v15 with playbackMode default"
```

---

## Task 3: `CueCommands.setPlaybackMode` (undoable)

**Files:**

- Create: `OnlyCue/Commands/CueCommands+Playback.swift`
- Create: `OnlyCueTests/CueCommandsPlaybackModeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/CueCommandsPlaybackModeTests.swift`:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsPlaybackModeTests: XCTestCase {

    private func makeDocument() -> CueListDocument {
        let document = CueListDocument()
        // CueListDocument()'s default init seeds a current-schema model with
        // one default CuePointType and playbackMode == .playOnce.
        return document
    }

    func test_setPlaybackMode_updatesModel() {
        let document = makeDocument()
        XCTAssertEqual(document.model.playbackMode, .playOnce)

        CueCommands.setPlaybackMode(.loop, document: document, undoManager: nil)

        XCTAssertEqual(document.model.playbackMode, .loop)
    }

    func test_setPlaybackMode_noOpWhenAlreadyEqual() {
        let document = makeDocument()
        let undoManager = UndoManager()

        CueCommands.setPlaybackMode(.playOnce, document: document, undoManager: undoManager)

        XCTAssertEqual(document.model.playbackMode, .playOnce)
        XCTAssertFalse(undoManager.canUndo, "no-op write must not register an undo step")
    }

    func test_setPlaybackMode_undoRestoresPrevious() {
        let document = makeDocument()
        let undoManager = UndoManager()

        CueCommands.setPlaybackMode(.autoNext, document: document, undoManager: undoManager)
        XCTAssertEqual(document.model.playbackMode, .autoNext)

        undoManager.undo()
        XCTAssertEqual(document.model.playbackMode, .playOnce)

        undoManager.redo()
        XCTAssertEqual(document.model.playbackMode, .autoNext)
    }
}
```

- [ ] **Step 2: Verify `CueListDocument()` exists with a zero-arg init**

Run: `grep -n "class CueListDocument\|init()" OnlyCue/Document/CueListDocument.swift`
Expected: a `CueListDocument()` zero-arg init or a default-able init that seeds the current schema model with one CuePointType. If the existing project uses a different fixture pattern (e.g., a helper in tests), substitute that. Check one of the existing `CueCommandsItemTests`-style tests for the canonical fixture and mirror it.

- [ ] **Step 3: Run the test — expect failure**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsPlaybackModeTests -quiet
```

Expected: FAIL with `setPlaybackMode` undefined.

- [ ] **Step 4: Implement the command**

Create `OnlyCue/Commands/CueCommands+Playback.swift`:

```swift
import Foundation

@MainActor
extension CueCommands {

    /// Set the document's playback mode. No-op when the mode already matches —
    /// keeps the undo stack clean for menu clicks that re-pick the active mode.
    static func setPlaybackMode(
        _ mode: PlaybackMode,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        let previous = document.model.playbackMode
        guard previous != mode else { return }

        document.model.playbackMode = mode

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        undoManager?.registerUndo(withTarget: document) { doc in
            Self.setPlaybackMode(previous, document: doc, undoManager: undoManager)
        }
        undoManager?.setActionName("Set Playback Mode")
    }
}
```

- [ ] **Step 5: Run the test — expect pass**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsPlaybackModeTests -quiet
```

Expected: all three tests PASS.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/Commands/CueCommands+Playback.swift \
        OnlyCueTests/CueCommandsPlaybackModeTests.swift
git commit -m "feat(commands): add setPlaybackMode with undo support"
```

---

## Task 4: `nextMediaItemID(after:in:)` helper + `advanceToNextMediaAndPlay`

**Files:**

- Modify: `OnlyCue/Commands/CueCommands+Playback.swift`
- Create: `OnlyCueTests/CueCommandsAdvanceMediaTests.swift`

The command captures the next index at *fire time*, so we test that mid-stream `items[]` mutations are honored. The actual `engine.play()` side effect is verified by passing a test double.

- [ ] **Step 1: Write the failing test for the pure helper**

Create `OnlyCueTests/CueCommandsAdvanceMediaTests.swift`:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsAdvanceMediaTests: XCTestCase {

    // MARK: - Pure-helper tests

    private func makeItem(_ name: String) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 1,
                bookmarkData: Data([0x01])
            ),
            cues: [],
            startTimecodeFrames: 0,
            ltcMuted: false,
            alternateName: nil
        )
    }

    func test_nextMediaItemID_returnsNextWhenMiddle() {
        let a = makeItem("a"), b = makeItem("b"), c = makeItem("c")
        XCTAssertEqual(CueCommands.nextMediaItemID(after: a.id, in: [a, b, c]), b.id)
    }

    func test_nextMediaItemID_returnsNilAtLastItem() {
        let a = makeItem("a"), b = makeItem("b")
        XCTAssertNil(CueCommands.nextMediaItemID(after: b.id, in: [a, b]))
    }

    func test_nextMediaItemID_returnsNilForSingleItem() {
        let a = makeItem("a")
        XCTAssertNil(CueCommands.nextMediaItemID(after: a.id, in: [a]))
    }

    func test_nextMediaItemID_returnsNilForUnknownID() {
        let a = makeItem("a"), b = makeItem("b")
        XCTAssertNil(CueCommands.nextMediaItemID(after: UUID(), in: [a, b]))
    }

    func test_nextMediaItemID_returnsNilForEmptyList() {
        XCTAssertNil(CueCommands.nextMediaItemID(after: UUID(), in: []))
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsAdvanceMediaTests -quiet
```

Expected: FAIL with `nextMediaItemID` undefined.

- [ ] **Step 3: Add the helper to the extension**

Append to `OnlyCue/Commands/CueCommands+Playback.swift`:

```swift
@MainActor
extension CueCommands {

    /// Returns the id of the item immediately after `current` in `items`.
    /// Returns nil when `current` is the last item, when `current` is not in
    /// `items`, or when `items` is empty. Pure — no side effects.
    static func nextMediaItemID(
        after current: MediaItem.ID,
        in items: [MediaItem]
    ) -> MediaItem.ID? {
        guard let index = items.firstIndex(where: { $0.id == current }) else { return nil }
        let next = index + 1
        guard next < items.count else { return nil }
        return items[next].id
    }
}
```

- [ ] **Step 4: Run — expect pass**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsAdvanceMediaTests -quiet
```

Expected: PASS.

- [ ] **Step 5: Add advance-command tests using a play-spy closure**

Append to `OnlyCueTests/CueCommandsAdvanceMediaTests.swift`:

```swift
    // MARK: - Command tests (advanceToNextMediaAndPlay)

    private func seed(_ items: [MediaItem], active: MediaItem.ID?) -> CueListDocument {
        let document = CueListDocument()
        document.model.items = items
        document.model.activeItemID = active
        return document
    }

    func test_advance_movesActiveToNextAndInvokesPlay() async {
        let a = makeItem("a"), b = makeItem("b")
        let document = seed([a, b], active: a.id)

        let playCalled = expectation(description: "play invoked after reload")

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { document.model.activeItemID = $0; playCalled.fulfill() }
        )

        XCTAssertEqual(document.model.activeItemID, b.id)
        await fulfillment(of: [playCalled], timeout: 1)
    }

    func test_advance_atLastItem_isNoOp() async {
        let a = makeItem("a"), b = makeItem("b")
        let document = seed([a, b], active: b.id)

        var playCalled = false
        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertEqual(document.model.activeItemID, b.id)
        XCTAssertFalse(playCalled, "no transition → no play")
    }

    func test_advance_capturesNextIDAtFireTime() async {
        let a = makeItem("a"), b = makeItem("b"), c = makeItem("c")
        let document = seed([a, b, c], active: a.id)

        // Mutate items[] between mode-set time and fire time — remove `b`
        // so the "next" should now be `c`.
        document.model.items = [a, c]

        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { document.model.activeItemID = $0 }
        )

        XCTAssertEqual(document.model.activeItemID, c.id)
    }

    func test_advance_withNilActive_isNoOp() async {
        let a = makeItem("a")
        let document = seed([a], active: nil)

        var playCalled = false
        await CueCommands.advanceToNextMediaAndPlay(
            document: document,
            reloadAndPlay: { _ in playCalled = true }
        )

        XCTAssertNil(document.model.activeItemID)
        XCTAssertFalse(playCalled)
    }
```

- [ ] **Step 6: Run — expect failure**

Expected: FAIL with `advanceToNextMediaAndPlay` undefined.

- [ ] **Step 7: Implement the command with an injectable side effect**

Append to `OnlyCue/Commands/CueCommands+Playback.swift`:

```swift
@MainActor
extension CueCommands {

    /// Advances `activeItemID` to the next item in `items[]` and triggers the
    /// caller's reload-and-play side effect. No-op at the end of the list,
    /// for nil `activeItemID`, or when the active id isn't in `items[]`.
    ///
    /// **Non-undoable on purpose.** Cmd-Z mid-show snapping back to the just-
    /// finished song is the wrong recovery path; the operator wants the
    /// sidebar instead. Selection changes already bypass undo (see
    /// `setActiveItem(id:in:)` in `CueCommands+Items.swift`).
    ///
    /// `reloadAndPlay` is the production seam for `MediaImporter.loadActive`
    /// + `engine.play()`. Tests pass a spy closure.
    static func advanceToNextMediaAndPlay(
        document: CueListDocument,
        reloadAndPlay: @MainActor (MediaItem.ID) async -> Void
    ) async {
        guard let current = document.model.activeItemID else { return }
        guard let nextID = nextMediaItemID(after: current, in: document.model.items) else { return }
        document.model.activeItemID = nextID
        await reloadAndPlay(nextID)
    }
}
```

- [ ] **Step 8: Run — expect pass**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsAdvanceMediaTests -quiet
```

Expected: all 9 tests PASS (5 helper + 4 command).

- [ ] **Step 9: Commit**

```bash
git add OnlyCue/Commands/CueCommands+Playback.swift \
        OnlyCueTests/CueCommandsAdvanceMediaTests.swift
git commit -m "feat(commands): add advanceToNextMediaAndPlay with fire-time next-index capture"
```

---

## Task 5: `PlayerEngine.mediaDidReachEnd` publisher

**Files:**

- Modify: `OnlyCue/Media/PlayerEngine.swift`
- Create: `OnlyCueTests/PlayerEngineEndOfMediaTests.swift`

`AVPlayerItem.didPlayToEndTimeNotification` fires only on natural playback reaching end — not on programmatic `seek`. We re-broadcast it through a Combine `PassthroughSubject` so subscribers don't need to know about NotificationCenter or the current `AVPlayerItem` identity. The subscription is rebuilt on each `load(asset:)` because the underlying item is replaced.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/PlayerEngineEndOfMediaTests.swift`:

```swift
import XCTest
import Combine
import AVFoundation
@testable import OnlyCue

@MainActor
final class PlayerEngineEndOfMediaTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_publishesWhenAVPlayerItemEndsNaturally() async {
        let engine = PlayerEngine()
        // Load a one-frame silent asset so didPlayToEndTimeNotification
        // can target a real AVPlayerItem. Use the existing test fixture
        // helper if one is available; otherwise the 1-sample asset built
        // by AudioSampleReaderTests' helper is sufficient.
        let asset = AVURLAsset(url: SilentAssetFixture.oneSecondURL())
        await engine.load(asset: asset)

        let received = expectation(description: "mediaDidReachEnd fires")
        engine.mediaDidReachEnd
            .sink { received.fulfill() }
            .store(in: &cancellables)

        // Simulate AVPlayer's natural end by posting the notification for
        // the currently-loaded item — same delivery path as live playback.
        guard let item = engine.player.currentItem else {
            return XCTFail("expected a loaded AVPlayerItem")
        }
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )

        await fulfillment(of: [received], timeout: 1)
    }

    func test_doesNotPublishForADifferentItem() async {
        let engine = PlayerEngine()
        let asset = AVURLAsset(url: SilentAssetFixture.oneSecondURL())
        await engine.load(asset: asset)

        var fired = false
        engine.mediaDidReachEnd
            .sink { fired = true }
            .store(in: &cancellables)

        // Post for a *different* AVPlayerItem — must not fire.
        let strangerItem = AVPlayerItem(asset: AVURLAsset(url: SilentAssetFixture.oneSecondURL()))
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: strangerItem
        )

        // Give the run loop a tick.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired)
    }

    func test_resubscribesAfterReload() async {
        let engine = PlayerEngine()
        await engine.load(asset: AVURLAsset(url: SilentAssetFixture.oneSecondURL()))
        await engine.load(asset: AVURLAsset(url: SilentAssetFixture.oneSecondURL()))

        let received = expectation(description: "fires for the second item")
        engine.mediaDidReachEnd
            .sink { received.fulfill() }
            .store(in: &cancellables)

        guard let item = engine.player.currentItem else {
            return XCTFail("expected a loaded AVPlayerItem")
        }
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )

        await fulfillment(of: [received], timeout: 1)
    }
}
```

- [ ] **Step 2: Check `SilentAssetFixture` exists**

Run: `grep -rn "SilentAssetFixture\|oneSecondURL\|silentAsset" OnlyCueTests/ | head`

Expected: either an existing helper is found (mirror its API), or it doesn't exist. If it doesn't exist, write one — minimal CAF/WAV silent asset generator — and place it in `OnlyCueTests/Helpers/SilentAssetFixture.swift`. A 1-second 8-bit mono silent WAV is sufficient; see `AudioSampleReaderTests` for the existing audio-fixture pattern and reuse it directly.

- [ ] **Step 3: Run the test — expect failure**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/PlayerEngineEndOfMediaTests -quiet
```

Expected: FAIL with `mediaDidReachEnd` undefined.

- [ ] **Step 4: Add the publisher to `PlayerEngine`**

Edit `OnlyCue/Media/PlayerEngine.swift`.

At the top, change the imports:

```swift
import AVFoundation
import Combine
import Observation
import QuartzCore
```

Inside the class, after `private var timeObserver: Any?`, add:

```swift
    /// Publishes `()` when the **currently-loaded** `AVPlayerItem` reaches its
    /// end via natural playback. Programmatic `seek(to: duration)` does NOT
    /// fire this — AVFoundation only emits `didPlayToEndTimeNotification` on
    /// natural arrival at the boundary.
    let mediaDidReachEnd = PassthroughSubject<Void, Never>()

    @ObservationIgnored
    private var endOfMediaObserver: NSObjectProtocol?
```

In `load(asset:)`, after `player.replaceCurrentItem(with: item)`, append:

```swift
        rebindEndOfMediaObserver(to: item)
```

In `unload()`, after `player.replaceCurrentItem(with: nil)`, append:

```swift
        unbindEndOfMediaObserver()
```

In `deinit`, after the `timeObserver` cleanup, append:

```swift
        unbindEndOfMediaObserver()
```

At the bottom of the class (after `observeTime()`), add:

```swift
    private func rebindEndOfMediaObserver(to item: AVPlayerItem) {
        unbindEndOfMediaObserver()
        endOfMediaObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mediaDidReachEnd.send(())
            }
        }
    }

    private func unbindEndOfMediaObserver() {
        if let endOfMediaObserver {
            NotificationCenter.default.removeObserver(endOfMediaObserver)
        }
        endOfMediaObserver = nil
    }
```

- [ ] **Step 5: Run — expect pass**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/PlayerEngineEndOfMediaTests -quiet
```

Expected: all 3 tests PASS.

- [ ] **Step 6: Run the full unit suite to confirm no regression in existing PlayerEngine tests**

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests -quiet
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/Media/PlayerEngine.swift \
        OnlyCueTests/PlayerEngineEndOfMediaTests.swift \
        OnlyCueTests/Helpers/SilentAssetFixture.swift
git commit -m "feat(media): publish mediaDidReachEnd from PlayerEngine"
```

(Drop the `Helpers/SilentAssetFixture.swift` path from the `add` if you reused an existing fixture in step 2.)

---

## Task 6: Playback-mode menu items + checkmarks

**Files:**

- Modify: `OnlyCue/App/AppCommands.swift`
- Create: `OnlyCueUITests/PlaybackModeMenuUITests.swift`

UI test drives the menu interaction end-to-end (menu click → model mutation → checkmark moves). This task does not yet wire the dispatcher (that's Task 7) — selecting a mode only updates the model. The checkmark behavior is therefore independently testable.

- [ ] **Step 1: Inspect the current Playback menu**

Read lines 186–220 of `OnlyCue/App/AppCommands.swift` (already established above). Confirm the `pauseAtEachCue` binding pattern at line 216-219 and the `accessibilityIdentifier` convention.

- [ ] **Step 2: Write the failing UI test**

Create `OnlyCueUITests/PlaybackModeMenuUITests.swift`:

```swift
import XCTest

/// UI behavior of the new Playback menu mode items. The app's UITestSeedHandler
/// already exposes the document model for inspection; we exercise the menu and
/// then verify the active-mode checkmark via the menu item's `value` attribute.
final class PlaybackModeMenuUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitest-seed", "minimal"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    func test_defaultModeIsPlayOnce_andCheckmarkSitsThere() {
        app.menuBars.menuBarItems["Playback"].click()

        let playOnce = app.menuItems["playbackModePlayOnceMenuItem"]
        let loop = app.menuItems["playbackModeLoopMenuItem"]
        let autoNext = app.menuItems["playbackModeAutoNextMenuItem"]

        XCTAssertTrue(playOnce.exists)
        XCTAssertTrue(loop.exists)
        XCTAssertTrue(autoNext.exists)

        // NSMenuItem with `state == .on` exposes value "1" to the accessibility
        // tree; off items expose "0".
        XCTAssertEqual(playOnce.value as? String, "1")
        XCTAssertEqual(loop.value as? String, "0")
        XCTAssertEqual(autoNext.value as? String, "0")
    }

    func test_selectingLoop_movesTheCheckmark() {
        app.menuBars.menuBarItems["Playback"].click()
        app.menuItems["playbackModeLoopMenuItem"].click()

        app.menuBars.menuBarItems["Playback"].click()
        XCTAssertEqual(app.menuItems["playbackModePlayOnceMenuItem"].value as? String, "0")
        XCTAssertEqual(app.menuItems["playbackModeLoopMenuItem"].value as? String, "1")
        XCTAssertEqual(app.menuItems["playbackModeAutoNextMenuItem"].value as? String, "0")
    }

    func test_selectingAutoNext_movesTheCheckmark() {
        app.menuBars.menuBarItems["Playback"].click()
        app.menuItems["playbackModeAutoNextMenuItem"].click()

        app.menuBars.menuBarItems["Playback"].click()
        XCTAssertEqual(app.menuItems["playbackModeAutoNextMenuItem"].value as? String, "1")
        XCTAssertEqual(app.menuItems["playbackModePlayOnceMenuItem"].value as? String, "0")
    }
}
```

- [ ] **Step 3: Run the UI test — expect failure**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/PlaybackModeMenuUITests -quiet
```

Expected: FAIL — menu items don't exist yet.

- [ ] **Step 4: Add the menu items to `AppCommands.swift`**

Find the `CommandMenu("Playback")` block at line 186 of `OnlyCue/App/AppCommands.swift`. Replace its body with:

```swift
        CommandMenu("Playback") {
            // Spec §3.5: disable the speed items while LTC output is active —
            // any change would be rejected by the interlock anyway. The
            // keyboard shortcuts in `PlaybackRateShortcuts` still fire the
            // interlock beep/flash if used.
            let ltcOn = ltcRoutingStore.settings.isEnabled

            Button("Speed Up") {
                NotificationCenter.default.post(name: .playbackRateUp, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateUp))
            .accessibilityIdentifier("playbackRateUpMenuItem")
            .disabled(ltcOn)

            Button("Slow Down") {
                NotificationCenter.default.post(name: .playbackRateDown, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateDown))
            .accessibilityIdentifier("playbackRateDownMenuItem")
            .disabled(ltcOn)

            Button("Reset Speed") {
                NotificationCenter.default.post(name: .playbackRateReset, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateReset))
            .accessibilityIdentifier("playbackRateResetMenuItem")
            .disabled(ltcOn)

            Divider()

            playbackModeItem(.playOnce, title: "Play Once", id: "playbackModePlayOnceMenuItem")
            playbackModeItem(.loop, title: "Loop Current Media", id: "playbackModeLoopMenuItem")
            playbackModeItem(.autoNext, title: "Auto Play Next Media", id: "playbackModeAutoNextMenuItem")

            Divider()

            Button(pauseAtEachCue ? "Don't Pause at Each Cue" : "Pause at Each Cue") {
                pauseAtEachCue.toggle()
            }
            .keyboardShortcut(shortcut(.togglePauseAtEachCue))
        }
```

Then add this helper inside the `AppCommands` struct (next to other private builders):

```swift
    @ViewBuilder
    private func playbackModeItem(_ mode: PlaybackMode, title: String, id: String) -> some View {
        Button {
            guard let document = currentDocument else { return }
            CueCommands.setPlaybackMode(mode, document: document, undoManager: document.undoManager)
        } label: {
            // Use a leading checkmark when active. SwiftUI's macOS menu
            // renderer maps `Image(systemName: "checkmark")` to the
            // NSMenuItem `state` attribute when the Image leads the Label,
            // which is what XCUITest reads as the value "1" / "0".
            if currentDocument?.model.playbackMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .accessibilityIdentifier(id)
    }
```

> **If `currentDocument` is not the existing accessor name** — `AppCommands` in this repo uses the `@FocusedValue` / `@FocusedBinding` pattern for the active document. Mirror whichever accessor `pauseAtEachCue` and the speed buttons use; do not introduce a new pattern. The speed buttons send `Notification`s without touching the document because they are received by `DocumentView`. If that's the cleanest path here too, post a `Notification` named `.setPlaybackMode` with the `PlaybackMode` as `object`, and handle it in `DocumentView` via `commands.setPlaybackMode`. **Verify by re-reading lines 186-220 of `AppCommands.swift` and the existing focused-document accessor; use whichever pattern matches.**

- [ ] **Step 5: Run the UI test — expect pass**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/PlaybackModeMenuUITests -quiet
```

Expected: all 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/App/AppCommands.swift OnlyCueUITests/PlaybackModeMenuUITests.swift
git commit -m "feat(menu): add playback mode items with active checkmark"
```

---

## Task 7: End-of-media dispatcher in `DocumentView`

**Files:**

- Modify: `OnlyCue/UI/DocumentView.swift`
- Modify: `OnlyCueTests/PlayerEngineEndOfMediaTests.swift` (add dispatcher tests OR new file)

The dispatcher lives in `DocumentView` because it needs `document`, `engine`, `ltcRoutingStore`, and `undoManager` together. Subscribe to `engine.mediaDidReachEnd` via `.onReceive` and switch on `document.model.playbackMode`.

- [ ] **Step 1: Inspect existing `.onReceive` usage in `DocumentView`**

Run: `grep -n "onReceive\|ltcRoutingStore\|engine.play\|engine.seek" OnlyCue/UI/DocumentView.swift`

Expected: there are existing `.onReceive(NotificationCenter.default.publisher(for:))` chains at lines 69 and 77. Mirror that style for the `engine.mediaDidReachEnd` subscription.

- [ ] **Step 2: Add the dispatcher**

In `OnlyCue/UI/DocumentView.swift`, find the modifier chain on the document body (the cluster of `.task(...) / .onChange(...) / .onReceive(...)` between roughly lines 57-84). Add a new modifier:

```swift
        .onReceive(engine.mediaDidReachEnd) { _ in
            handleMediaDidReachEnd()
        }
```

Then add the dispatcher method to `DocumentView`'s private helpers (near `reloadActive()` at line 195):

```swift
    private func handleMediaDidReachEnd() {
        switch document.model.playbackMode {
        case .playOnce:
            return
        case .loop:
            if ltcRoutingStore.settings.isEnabled {
                NotificationCenter.default.post(name: .ltcInterlockEngaged, object: nil)
                return
            }
            Task {
                await engine.seek(to: 0)
                engine.play()
            }
        case .autoNext:
            if ltcRoutingStore.settings.isEnabled {
                NotificationCenter.default.post(name: .ltcInterlockEngaged, object: nil)
                return
            }
            Task {
                await CueCommands.advanceToNextMediaAndPlay(
                    document: document,
                    reloadAndPlay: { nextID in
                        do {
                            try await MediaImporter.loadActive(into: document, engine: engine)
                            engine.play()
                        } catch {
                            pendingAlert = .relink(document.model.activeItem?.media.displayName ?? "The media file")
                        }
                    }
                )
            }
        }
    }
```

- [ ] **Step 3: Verify the `.ltcInterlockEngaged` notification name exists**

Run: `grep -rn "ltcInterlockEngaged\|interlockEngaged\|ltcInterlock" OnlyCue/ --include="*.swift"`

Expected: a `Notification.Name` is already defined (the speed-key interlock uses it per `AppCommands.swift:188-190`). If it does NOT exist (i.e., the comment refers to a yet-unimplemented hook), add it in the same file `Notifications.swift` (or wherever `.playbackRateUp` lives) as:

```swift
extension Notification.Name {
    static let ltcInterlockEngaged = Notification.Name("ltcInterlockEngaged")
}
```

and route it to the existing beep/flash sink (search for `NSSound.beep` or a flash modifier on `DocumentView`; if neither exists, just post the notification — the visible interlock feedback can be a follow-up issue).

- [ ] **Step 4: Build to confirm everything compiles**

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Add an end-to-end UI test for Loop and Auto Next**

Append to `OnlyCueUITests/PlaybackModeMenuUITests.swift`:

```swift
    func test_loopMode_restartsAtZeroOnNaturalEnd() {
        // Seed a doc with one short audio item via the UITest seed handler,
        // then trigger the end-of-media event via a debug menu hook or a
        // notification injected by UITestSeedHandler. Verify the playhead
        // returns to 0 and playback continues.
        //
        // NOTE: if the codebase has no existing UITest-only NotificationCenter
        // injection, add one to UITestSeedHandler:
        //   if launchArguments.contains("--simulate-end-of-media") {
        //       NotificationCenter.default.post(
        //           name: AVPlayerItem.didPlayToEndTimeNotification,
        //           object: engine.player.currentItem)
        //   }
        // and gate the assertion accordingly. If that scaffolding is too
        // invasive for this PR, replace this test with a SwiftUI ViewInspector
        // unit test on the dispatcher, OR cover this case in
        // PlayerEngineEndOfMediaTests by directly invoking the dispatcher.
        throw XCTSkip("Wire via UITestSeedHandler injection — see comment")
    }
```

(This step intentionally surfaces the seam decision rather than guessing. **Resolve during implementation:** prefer a `UITestSeedHandler` injection if the existing handler supports it; otherwise skip and add a `DocumentViewDispatcherTests.swift` unit test calling `handleMediaDidReachEnd()` directly via a `@testable` exposure.)

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/DocumentView.swift OnlyCueUITests/PlaybackModeMenuUITests.swift
git commit -m "feat(playback): dispatch end-of-media per mode with LTC interlock"
```

---

## Task 8: TransportControls badge for non-default modes

**Files:**

- Create: `OnlyCue/UI/PlaybackModeBadge.swift`
- Modify: `OnlyCue/UI/TransportControls.swift`
- Create: `OnlyCueUITests/PlaybackModeBadgeUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Create `OnlyCueUITests/PlaybackModeBadgeUITests.swift`:

```swift
import XCTest

final class PlaybackModeBadgeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitest-seed", "minimal"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    func test_badgeHiddenInPlayOnceMode() {
        XCTAssertFalse(
            app.images["playbackModeBadge"].exists,
            "Play Once is default; badge must not render"
        )
    }

    func test_badgeAppearsInLoopMode() {
        app.menuBars.menuBarItems["Playback"].click()
        app.menuItems["playbackModeLoopMenuItem"].click()

        let badge = app.images["playbackModeBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 1))
        XCTAssertEqual(badge.value as? String, "loop")
    }

    func test_badgeAppearsInAutoNextMode() {
        app.menuBars.menuBarItems["Playback"].click()
        app.menuItems["playbackModeAutoNextMenuItem"].click()

        let badge = app.images["playbackModeBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 1))
        XCTAssertEqual(badge.value as? String, "autoNext")
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/PlaybackModeBadgeUITests -quiet
```

Expected: FAIL — `playbackModeBadge` not found.

- [ ] **Step 3: Implement the badge view**

Create `OnlyCue/UI/PlaybackModeBadge.swift`:

```swift
import SwiftUI

/// TransportControls indicator for non-default playback modes. Hidden when the
/// mode is `.playOnce` so the bar stays clean in the most common state. The
/// `accessibilityValue` is the raw `PlaybackMode.rawValue` so UI tests can
/// assert on it without parsing glyphs.
struct PlaybackModeBadge: View {

    let mode: PlaybackMode

    var body: some View {
        Group {
            switch mode {
            case .playOnce:
                EmptyView()
            case .loop:
                Image(systemName: "repeat")
            case .autoNext:
                Image(systemName: "forward.end")
            }
        }
        .imageScale(.medium)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("playbackModeBadge")
        .accessibilityValue(mode.rawValue)
    }
}
```

- [ ] **Step 4: Insert the badge into `TransportControls`**

Edit `OnlyCue/UI/TransportControls.swift`. Find the line that renders `PlaybackRateBadge` (around line 107). Immediately after it, insert:

```swift
            PlaybackModeBadge(mode: document.model.playbackMode)
```

(Confirm `document` is in scope at that point in the view — `TransportControls` already takes a `document` parameter for the rate badge; reuse it.)

- [ ] **Step 5: Run — expect pass**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/PlaybackModeBadgeUITests -quiet
```

Expected: all 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/PlaybackModeBadge.swift \
        OnlyCue/UI/TransportControls.swift \
        OnlyCueUITests/PlaybackModeBadgeUITests.swift
git commit -m "feat(transport): show playback mode badge for loop and auto-next"
```

---

## Task 9: Full-suite regression + spec cross-reference

**Files:** none modified — verification only.

- [ ] **Step 1: Run the full test suite**

```bash
xcodegen generate
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -quiet
```

Expected: all tests pass. Any failure means a regression from Tasks 1-8 — fix before continuing.

- [ ] **Step 2: Manually verify the menu end-to-end**

Launch the app:

```bash
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' -derivedDataPath build
open build/Build/Products/Debug/OnlyCue.app
```

Steps:

1. Create a new document. Open Playback menu → checkmark on Play Once, no badge in TransportBar.
2. Pick Loop. Checkmark moves; `↻` badge appears in TransportBar.
3. Pick Auto Play Next. Checkmark moves; `⏭` badge appears.
4. Save the document, close, reopen — mode persists.

- [ ] **Step 3: Cross-check the spec**

Open `docs/superpowers/specs/2026-05-24-playback-modes-design.md` and walk Section 2 (Decisions table). Confirm every row has a corresponding test in the suite. Any uncovered decision = add a test before opening the PR.

- [ ] **Step 4: Verify ADRs / docs do not need new entries**

This feature does not change architectural invariants (no new dependencies, no schema-versioning policy change, no LTC-engine change). It does add a new `PlaybackMode` enum and a new `ProjectModel` field — `docs/data-model.md` should mention it. Open that file, add a single bullet under the schema-v15 line:

```markdown
- v15 (2026-05-24): added `ProjectModel.playbackMode: PlaybackMode` defaulting to `.playOnce`. Additive migration from v14.
```

Commit:

```bash
git add docs/data-model.md
git commit -m "docs(data-model): note v15 playbackMode addition"
```

If `docs/data-model.md` does not have a schema-history section in that form, follow the file's existing convention.

- [ ] **Step 5: Done — proceed to PR via `gh-pr` skill**

The branch is ready to open as a PR. PR body must cite `docs/superpowers/specs/2026-05-24-playback-modes-design.md` in the OnlyCue verification footer (per CLAUDE.md).

---

## Self-review (post-write)

Walking the spec sections:

- §1 Overview, §2 Decisions table — covered by overall task structure; Q1 (radio) is enforced by `PlaybackMode` enum + `setPlaybackMode`; Q2 (per-doc persisted) by Task 1; Q3 (stop at end of list) by Task 4's `test_advance_atLastItem_isNoOp`; Q4 (LTC interlock at fire time) by Task 7's dispatcher; Q5 (preserve rate) is the *absence* of a `resetPlaybackRate()` call in the dispatcher — implicit; consider adding an explicit unit test asserting `engine.playbackRate` is unchanged after a simulated loop wrap. (Add if time allows; otherwise the spec is satisfied by code inspection of the dispatcher.); Q6 (menu checkmarks) by Task 6 UI tests; Q7 (default Play Once) by Task 2's `test_v14ToV15_defaultsPlaybackModeToPlayOnce`; Q8 (no shortcuts) is the *absence* of `.keyboardShortcut(...)` on the new items — verified by reading the diff in Task 6; Q9 (dedicated non-undoable command) by Task 4; Q10 (informational badge) by Task 8.
- §3 Data model — Tasks 1, 2.
- §4 End-of-media detection + edge cases — Tasks 4, 5, 7.
- §5 LTC interlock — Task 7 dispatcher (`ltcRoutingStore.settings.isEnabled` branch).
- §6 UI — Tasks 6, 8.
- §7 Test surface — Tasks 2, 3, 4, 5, 6, 7, 8 cover every listed scenario.
- §8 Out of scope — confirmed by code structure (no shortcuts, no click handler on badge, no wrap-around in `advanceToNextMediaAndPlay`).

**Placeholder scan:** Step 2 of Task 6 contains a conditional ("if `currentDocument` is not the existing accessor name…") — that's a deliberate seam for the implementer because the right accessor depends on how `AppCommands` already plumbs the focused document; the alternatives are spelled out (notification or focused-binding). Step 5 of Task 7 deliberately surfaces the UITest-injection question rather than fabricating an API. Both are explicit decision points, not TBDs.

**Type consistency:** `PlaybackMode` cases (`playOnce`, `loop`, `autoNext`) are spelled identically across Tasks 1, 3, 4, 6, 7, 8. `setPlaybackMode(_:document:undoManager:)` signature is consistent across Tasks 3, 6. `advanceToNextMediaAndPlay(document:reloadAndPlay:)` signature is consistent across Tasks 4, 7. `mediaDidReachEnd` publisher and `nextMediaItemID(after:in:)` helper used consistently.
