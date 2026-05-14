# Per-Media Edit Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users right-click a media row in the Library sidebar and open a focused modal that edits the clip's alternate display name, start-timecode offset, and per-clip LTC mute as a single undoable change.

**Architecture:** Add one new field (`MediaItem.alternateName: String?`) plus a `resolvedName` helper; bump schema v11→v12 with an additive migration; route saves through a new atomic `CueCommands.updateMediaItem`; surface a new `MediaEditSheet` from a `.contextMenu` on each sidebar row. Framerate stays on the project; the existing per-field commands (`setStartTimecode`, `setLTCMuted`) remain for the in-sheet rows of `TimecodeSettingsSheet`.

**Tech Stack:** Swift 6 / SwiftUI / macOS 14+ / XCTest / XCUITest. Project uses XcodeGen; sources are picked up from `OnlyCue/` automatically — no `project.yml` edits needed when adding files under existing folders. Run unit tests with `xcodebuild test -scheme OnlyCue -destination 'platform=macOS'`.

**Spec:** `docs/superpowers/specs/2026-05-15-per-media-edit-panel-design.md`

---

## File Structure

**Create:**
- `OnlyCue/Document/ProjectModel+MigrationV11.swift` — v11→v12 migration; `LegacyV11` decode shapes.
- `OnlyCue/Commands/CueCommands+Media.swift` — `updateMediaItem(id:alternateName:startTimecodeFrames:ltcMuted:)`.
- `OnlyCue/UI/MediaEditSheet.swift` — modal sheet view.
- `OnlyCueTests/MediaItemResolvedNameTests.swift`
- `OnlyCueTests/ProjectModelMigrationV11Tests.swift`
- `OnlyCueTests/CueCommandsUpdateMediaItemTests.swift`
- `OnlyCueUITests/MediaEditSheetUITests.swift`

**Modify:**
- `OnlyCue/Document/MediaItem.swift` — add `alternateName`, add `resolvedName` computed property.
- `OnlyCue/Document/ProjectModel.swift` — bump `currentSchemaVersion` from 11 to 12.
- `OnlyCue/Document/ProjectModel+Migration.swift` — add `case 11:` dispatch to `migrateFromV11`.
- `OnlyCue/UI/ItemListPane.swift` (or `ItemRowView.swift`) — `.contextMenu` with "Edit Media…" + sheet presentation.
- Call sites that render the user-facing media name — switch from `item.media.displayName` to `item.resolvedName`. Concrete files: `OnlyCue/UI/ItemRowView.swift`, `OnlyCue/UI/MediaTimecodeRow.swift`, and any export/title surface confirmed during Task 6.

---

## Task 1: `MediaItem.alternateName` field + `resolvedName` helper

**Files:**
- Modify: `OnlyCue/Document/MediaItem.swift`
- Test: `OnlyCueTests/MediaItemResolvedNameTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/MediaItemResolvedNameTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class MediaItemResolvedNameTests: XCTestCase {

    private func makeItem(displayName: String, alternateName: String? = nil) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: displayName),
            cues: [],
            startTimecodeFrames: 0,
            ltcMuted: false,
            alternateName: alternateName
        )
    }

    func test_resolvedName_returnsFileBasename_whenAlternateIsNil() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: nil).resolvedName, "track.wav")
    }

    func test_resolvedName_returnsFileBasename_whenAlternateIsEmpty() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: "").resolvedName, "track.wav")
    }

    func test_resolvedName_returnsFileBasename_whenAlternateIsWhitespace() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: "   \n\t").resolvedName, "track.wav")
    }

    func test_resolvedName_returnsTrimmedAlternate_whenSet() {
        XCTAssertEqual(makeItem(displayName: "track.wav", alternateName: "  Opening  ").resolvedName, "Opening")
    }

    func test_alternateName_defaultsToNil() {
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "a.wav"),
            cues: []
        )
        XCTAssertNil(item.alternateName)
    }
}
```

Verify `MediaReference`'s public initializer signature in `OnlyCue/Document/MediaReference.swift` before assuming `MediaReference(displayName:)` compiles — if it takes more parameters, fill them in with the smallest valid values. The test file is the only place this matters.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MediaItemResolvedNameTests 2>&1 | tail -40`
Expected: compile error — `MediaItem` has no `alternateName` initializer parameter and no `resolvedName` member.

- [ ] **Step 3: Add the field and helper**

Edit `OnlyCue/Document/MediaItem.swift`. After `var ltcMuted: Bool = false`, add a new stored property:

```swift
    /// Per-clip user-facing display override. nil/empty/whitespace ⇒ fall back
    /// to `media.displayName` (the file basename). v12.
    var alternateName: String? = nil
```

Then below the `extension MediaItem { ... }` block (or inside it), add:

```swift
extension MediaItem {
    /// User-facing name for this clip. Returns the trimmed `alternateName`
    /// when set to a non-empty string, otherwise falls back to the file
    /// basename in `media.displayName`. Use everywhere the clip's name is
    /// shown to the user; keep `media.displayName` for file-system lookups.
    var resolvedName: String {
        if let trimmed = alternateName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            return trimmed
        }
        return media.displayName
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MediaItemResolvedNameTests 2>&1 | tail -20`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Document/MediaItem.swift OnlyCueTests/MediaItemResolvedNameTests.swift
git commit -m "test(media-item): resolvedName + alternateName field"
```

---

## Task 2: Schema bump v11 → v12 with additive migration

**Files:**
- Modify: `OnlyCue/Document/ProjectModel.swift`
- Modify: `OnlyCue/Document/ProjectModel+Migration.swift`
- Create: `OnlyCue/Document/ProjectModel+MigrationV11.swift`
- Test: `OnlyCueTests/ProjectModelMigrationV11Tests.swift`

- [ ] **Step 1: Write the failing migration test**

Create `OnlyCueTests/ProjectModelMigrationV11Tests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class ProjectModelMigrationV11Tests: XCTestCase {

    func test_loadingV11Document_migratesToCurrent_withNilAlternateName() throws {
        let json = """
        {
          "schemaVersion": 11,
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Test",
          "cuePointTypes": [
            { "id": "22222222-2222-2222-2222-222222222222", "name": "General", "colorHex": "#4ECDC4", "hotkey": null }
          ],
          "items": [
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "media": { "displayName": "song.wav" },
              "cues": [],
              "startTimecodeFrames": 240,
              "ltcMuted": true
            }
          ],
          "activeItemID": null,
          "timecodeSettings": { "framerate": "fps30" }
        }
        """.data(using: .utf8)!

        let model = try ProjectModel.load(from: json)

        XCTAssertEqual(model.schemaVersion, ProjectModel.currentSchemaVersion)
        XCTAssertEqual(model.items.count, 1)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertEqual(item.media.displayName, "song.wav")
        XCTAssertEqual(item.startTimecodeFrames, 240)
        XCTAssertTrue(item.ltcMuted)
        XCTAssertNil(item.alternateName)
    }

    func test_v12Document_roundTripsWithAlternateName() throws {
        var model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "RT",
            cuePointTypes: [ProjectModel.makeDefaultCuePointType()],
            items: [
                MediaItem(
                    id: UUID(),
                    media: MediaReference(displayName: "a.wav"),
                    cues: [],
                    startTimecodeFrames: 0,
                    ltcMuted: false,
                    alternateName: "Opening"
                )
            ],
            activeItemID: nil
        )
        let data = try JSONEncoder().encode(model)
        let decoded = try ProjectModel.load(from: data)
        XCTAssertEqual(decoded.items.first?.alternateName, "Opening")
    }
}
```

If `ProjectModel.load(from:)` has a different name in this codebase, check the migration dispatch entry point and update the call. The structural intent is "feed bytes, get a current-version model out."

If the existing `CuePointType` doesn't take a `hotkey` field (or takes more fields), align the JSON fixture with the actual `CuePointType` shape from `OnlyCue/Document/CuePointType.swift`. Same for `ProjectTimecodeSettings`'s `framerate` raw value — adjust if `fps30` isn't the rawValue (check `SMPTEFramerate`).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/ProjectModelMigrationV11Tests 2>&1 | tail -30`
Expected: Either compile failure (no `migrateFromV11`) or runtime `unsupportedSchemaVersion(11)`.

- [ ] **Step 3: Bump current schema version**

In `OnlyCue/Document/ProjectModel.swift`, change:

```swift
    static let currentSchemaVersion = 11
```

to:

```swift
    static let currentSchemaVersion = 12
```

- [ ] **Step 4: Add the v11 migration file**

Create `OnlyCue/Document/ProjectModel+MigrationV11.swift`:

```swift
import Foundation

/// v11 → v12 migration: adds `MediaItem.alternateName` (defaults to nil).
/// Additive only — no data is rewritten; every other field is decoded as-is.
extension ProjectModel {

    static func migrateFromV11(data: Data) throws -> ProjectModel {
        let legacy = try JSONDecoder().decode(LegacyV11.self, from: data)
        return ProjectModel(
            schemaVersion: currentSchemaVersion,
            id: legacy.id,
            name: legacy.name,
            cuePointTypes: legacy.cuePointTypes,
            items: legacy.items.map { $0.toMediaItem() },
            activeItemID: legacy.activeItemID,
            timecodeSettings: legacy.timecodeSettings
        )
    }

    private struct LegacyV11: Decodable {
        let schemaVersion: Int
        let id: UUID
        let name: String
        let cuePointTypes: [CuePointType]
        let items: [LegacyV11Item]
        let activeItemID: UUID?
        let timecodeSettings: ProjectTimecodeSettings
    }

    private struct LegacyV11Item: Decodable {
        let id: UUID
        let media: MediaReference
        let cues: [Cue]
        let startTimecodeFrames: Int
        let ltcMuted: Bool

        func toMediaItem() -> MediaItem {
            MediaItem(
                id: id,
                media: media,
                cues: cues,
                startTimecodeFrames: startTimecodeFrames,
                ltcMuted: ltcMuted,
                alternateName: nil
            )
        }
    }
}
```

- [ ] **Step 5: Wire the dispatch**

In `OnlyCue/Document/ProjectModel+Migration.swift`, find the `switch probe.schemaVersion` block. After the existing `case 10:` line that returns `try migrateFromV10(data: data)`, insert:

```swift
        case 11:
            return try migrateFromV11(data: data)
```

The new `case currentSchemaVersion:` still handles a v12 document (decodes directly), since `currentSchemaVersion` is now 12.

- [ ] **Step 6: Run migration test to verify it passes**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/ProjectModelMigrationV11Tests 2>&1 | tail -20`
Expected: 2 tests pass.

- [ ] **Step 7: Run full unit-test suite to catch regressions in earlier migrations**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests 2>&1 | tail -40`
Expected: All tests pass. If any prior migration test breaks (e.g. a fixture in a v8/v9/v10 test now decodes to schemaVersion 12 rather than 11 and asserts on the version), update the assertion to `ProjectModel.currentSchemaVersion` rather than a hard-coded number.

- [ ] **Step 8: Commit**

```bash
git add OnlyCue/Document/ProjectModel.swift OnlyCue/Document/ProjectModel+Migration.swift OnlyCue/Document/ProjectModel+MigrationV11.swift OnlyCueTests/ProjectModelMigrationV11Tests.swift
git commit -m "feat(schema): v11→v12 adds MediaItem.alternateName"
```

---

## Task 3: `CueCommands.updateMediaItem` atomic command

**Files:**
- Create: `OnlyCue/Commands/CueCommands+Media.swift`
- Test: `OnlyCueTests/CueCommandsUpdateMediaItemTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/CueCommandsUpdateMediaItemTests.swift`:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class CueCommandsUpdateMediaItemTests: XCTestCase {

    private func makeDocument(items: [MediaItem]) -> CueListDocument {
        let doc = CueListDocument()
        doc.model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "T",
            cuePointTypes: [ProjectModel.makeDefaultCuePointType()],
            items: items,
            activeItemID: items.first?.id
        )
        return doc
    }

    private func makeItem(name: String) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: name),
            cues: [],
            startTimecodeFrames: 0,
            ltcMuted: false,
            alternateName: nil
        )
    }

    func test_updateMediaItem_setsAllThreeFields_inOneStep() {
        let a = makeItem(name: "a.wav")
        let b = makeItem(name: "b.wav")
        let doc = makeDocument(items: [a, b])

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: "Intro",
            startTimecodeFrames: 600,
            ltcMuted: true,
            document: doc,
            undoManager: nil
        )

        let updated = doc.model.items.first { $0.id == a.id }
        XCTAssertEqual(updated?.alternateName, "Intro")
        XCTAssertEqual(updated?.startTimecodeFrames, 600)
        XCTAssertEqual(updated?.ltcMuted, true)
    }

    func test_updateMediaItem_doesNotTouchOtherItems() {
        let a = makeItem(name: "a.wav")
        let b = makeItem(name: "b.wav")
        let doc = makeDocument(items: [a, b])

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: "X",
            startTimecodeFrames: 1,
            ltcMuted: true,
            document: doc,
            undoManager: nil
        )

        let other = doc.model.items.first { $0.id == b.id }
        XCTAssertNil(other?.alternateName)
        XCTAssertEqual(other?.startTimecodeFrames, 0)
        XCTAssertEqual(other?.ltcMuted, false)
    }

    func test_updateMediaItem_isSingleUndoStep() {
        let a = makeItem(name: "a.wav")
        let doc = makeDocument(items: [a])
        let undo = UndoManager()
        undo.groupsByEvent = false

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: "Intro",
            startTimecodeFrames: 600,
            ltcMuted: true,
            document: doc,
            undoManager: undo
        )

        XCTAssertTrue(undo.canUndo)
        undo.undo()

        let restored = doc.model.items.first { $0.id == a.id }
        XCTAssertNil(restored?.alternateName)
        XCTAssertEqual(restored?.startTimecodeFrames, 0)
        XCTAssertEqual(restored?.ltcMuted, false)
        XCTAssertTrue(undo.canRedo)
    }

    func test_updateMediaItem_unknownID_isNoOp() {
        let a = makeItem(name: "a.wav")
        let doc = makeDocument(items: [a])

        CueCommands.updateMediaItem(
            id: UUID(),
            alternateName: "X",
            startTimecodeFrames: 999,
            ltcMuted: true,
            document: doc,
            undoManager: nil
        )

        let unchanged = doc.model.items.first { $0.id == a.id }
        XCTAssertNil(unchanged?.alternateName)
        XCTAssertEqual(unchanged?.startTimecodeFrames, 0)
        XCTAssertEqual(unchanged?.ltcMuted, false)
    }

    func test_updateMediaItem_negativeFrames_clampedToZero() {
        let a = makeItem(name: "a.wav")
        let doc = makeDocument(items: [a])

        CueCommands.updateMediaItem(
            id: a.id,
            alternateName: nil,
            startTimecodeFrames: -10,
            ltcMuted: false,
            document: doc,
            undoManager: nil
        )

        XCTAssertEqual(doc.model.items.first?.startTimecodeFrames, 0)
    }
}
```

If `CueListDocument()` requires arguments in your codebase, replace the construction with whatever the existing per-command tests use (look at e.g. `OnlyCueTests/CueCommands*Tests.swift` for the pattern). The intent is "an in-memory document we can mutate."

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsUpdateMediaItemTests 2>&1 | tail -30`
Expected: compile error — `CueCommands.updateMediaItem` not found.

- [ ] **Step 3: Implement the command**

Create `OnlyCue/Commands/CueCommands+Media.swift`:

```swift
import Foundation

@MainActor
extension CueCommands {

    /// Atomically update a media item's user-editable metadata
    /// (`alternateName`, `startTimecodeFrames`, `ltcMuted`). Registers a
    /// single undo step covering all three fields so the modal "Edit Media…"
    /// sheet's Save is one user-perceived action. Unknown item IDs are
    /// no-ops; negative frames are clamped to zero. When the incoming values
    /// already match the current item the call is a no-op and no undo is
    /// registered, so spurious "Save" presses don't pollute the undo stack.
    static func updateMediaItem(
        id: MediaItem.ID,
        alternateName: String?,
        startTimecodeFrames: Int,
        ltcMuted: Bool,
        document: CueListDocument,
        undoManager: UndoManager?
    ) {
        guard let index = document.model.items.firstIndex(where: { $0.id == id }) else { return }
        let clampedFrames = max(0, startTimecodeFrames)
        let previous = document.model.items[index]

        let alreadyMatches = previous.alternateName == alternateName
            && previous.startTimecodeFrames == clampedFrames
            && previous.ltcMuted == ltcMuted
        if alreadyMatches { return }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }

        document.model.items[index].alternateName = alternateName
        document.model.items[index].startTimecodeFrames = clampedFrames
        document.model.items[index].ltcMuted = ltcMuted

        undoManager?.registerUndo(withTarget: document) { doc in
            Self.updateMediaItem(
                id: id,
                alternateName: previous.alternateName,
                startTimecodeFrames: previous.startTimecodeFrames,
                ltcMuted: previous.ltcMuted,
                document: doc,
                undoManager: undoManager
            )
        }
        undoManager?.setActionName("Edit Media")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsUpdateMediaItemTests 2>&1 | tail -20`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Commands/CueCommands+Media.swift OnlyCueTests/CueCommandsUpdateMediaItemTests.swift
git commit -m "feat(commands): atomic updateMediaItem for edit-media sheet"
```

---

## Task 4: `MediaEditSheet` view

**Files:**
- Create: `OnlyCue/UI/MediaEditSheet.swift`

This task is UI-only with no headless logic to unit-test cleanly; the UI smoke test in Task 6 exercises it end-to-end.

- [ ] **Step 1: Create the view**

Create `OnlyCue/UI/MediaEditSheet.swift`:

```swift
import SwiftUI

/// Modal sheet for editing a single `MediaItem`'s user-facing metadata:
/// alternate display name, start-timecode offset, and per-clip LTC mute.
/// Save commits all three fields atomically through `CueCommands.updateMediaItem`
/// (single undo step). Cancel discards drafts.
///
/// The TC field uses the project framerate (`framerate`) for parsing and
/// display, matching `MediaTimecodeRow`. Per-media framerate is intentionally
/// out of scope (see spec).
struct MediaEditSheet: View {

    let item: MediaItem
    let framerate: SMPTEFramerate
    let onSave: (_ alternateName: String?, _ startFrames: Int, _ muted: Bool) -> Void
    let onCancel: () -> Void

    @State private var nameDraft: String = ""
    @State private var tcDraft: String = ""
    @State private var mutedDraft: Bool = false
    @State private var tcInvalid: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Media")
                .font(.headline)

            Form {
                LabeledContent("Name") {
                    TextField(item.media.displayName, text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("mediaEditNameField")
                }
                LabeledContent("Start timecode") {
                    TextField("HH:MM:SS:FF", text: $tcDraft)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(tcInvalid ? Color.red : Color.clear, lineWidth: 1)
                        )
                        .onChange(of: tcDraft) { _, _ in tcInvalid = false }
                        .accessibilityIdentifier("mediaEditStartTimecodeField")
                }
                Toggle("Mute LTC for this clip", isOn: $mutedDraft)
                    .accessibilityIdentifier("mediaEditMuteToggle")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("mediaEditCancel")
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mediaEditSave")
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .onAppear { syncDraftsFromItem() }
    }

    private func syncDraftsFromItem() {
        nameDraft = item.alternateName ?? ""
        tcDraft = Timecode(frameCount: item.startTimecodeFrames, rate: framerate).displayString
        mutedDraft = item.ltcMuted
        tcInvalid = false
    }

    private func commit() {
        guard let parsed = Timecode.parse(tcDraft, rate: framerate) else {
            tcInvalid = true
            return
        }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternate = trimmed.isEmpty ? nil : trimmed
        onSave(alternate, parsed.frameCount, mutedDraft)
    }
}
```

- [ ] **Step 2: Verify the view compiles**

Run: `xcodebuild build -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

If the SwiftUI `LabeledContent` API isn't available because the deployment target was lowered (it shouldn't be — ADR-001 keeps macOS 14+), fall back to `HStack { Text("Name"); TextField(...) }`. Otherwise keep `LabeledContent`.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/MediaEditSheet.swift
git commit -m "feat(ui): MediaEditSheet for per-clip name/TC/mute editing"
```

---

## Task 5: Wire context menu + sheet presentation in the sidebar

**Files:**
- Modify: `OnlyCue/UI/ItemListPane.swift`

- [ ] **Step 1: Add state, context menu, and `.sheet` modifier**

Edit `OnlyCue/UI/ItemListPane.swift`. Add an `@State` for the editing target near the existing properties:

```swift
    @State private var editingItemID: MediaItem.ID?
```

In the `itemList` computed property, attach a `.contextMenu` to the `ItemRowView` inside `ForEach`. Replace the existing `ForEach` body so it looks like:

```swift
            ForEach(document.model.items) { item in
                ItemRowView(
                    item: item,
                    framerate: document.model.timecodeSettings.framerate,
                    onSetStartTimecode: { frames in
                        CueCommands.setStartTimecode(
                            itemID: item.id,
                            frames: frames,
                            document: document,
                            undoManager: undoManager
                        )
                    }
                )
                .tag(Optional(item.id))
                .contextMenu {
                    Button("Edit Media…") {
                        editingItemID = item.id
                    }
                    .accessibilityIdentifier("contextMenuEditMedia")

                    Button(role: .destructive) {
                        CueCommands.removeItem(id: item.id, document: document, undoManager: undoManager)
                    } label: {
                        Text("Remove")
                    }
                }
            }
```

(If `CueCommands.removeItem` has a different name in this codebase — confirm against `ItemListPane.deleteAtOffsets` which already calls it — match that signature.)

Then attach a `.sheet(item:)` to the `List` (or the outer `Group`). Use a small `Identifiable` wrapper so the sheet can resolve the item lazily and survive list mutations:

```swift
            .sheet(item: editingItemBinding) { editing in
                MediaEditSheet(
                    item: editing.item,
                    framerate: document.model.timecodeSettings.framerate,
                    onSave: { alt, frames, muted in
                        CueCommands.updateMediaItem(
                            id: editing.item.id,
                            alternateName: alt,
                            startTimecodeFrames: frames,
                            ltcMuted: muted,
                            document: document,
                            undoManager: undoManager
                        )
                        editingItemID = nil
                    },
                    onCancel: { editingItemID = nil }
                )
            }
```

Add the binding helper as a private computed property on `ItemListPane`:

```swift
    private struct EditingTarget: Identifiable {
        let item: MediaItem
        var id: MediaItem.ID { item.id }
    }

    private var editingItemBinding: Binding<EditingTarget?> {
        Binding(
            get: {
                guard let id = editingItemID,
                      let item = document.model.items.first(where: { $0.id == id })
                else { return nil }
                return EditingTarget(item: item)
            },
            set: { newValue in editingItemID = newValue?.id }
        )
    }
```

- [ ] **Step 2: Verify the project builds**

Run: `xcodebuild build -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all unit tests to confirm no regressions**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/UI/ItemListPane.swift
git commit -m "feat(sidebar): right-click → Edit Media… opens MediaEditSheet"
```

---

## Task 6: Switch user-facing labels to `resolvedName`

**Files:**
- Modify: `OnlyCue/UI/ItemRowView.swift`
- Modify: `OnlyCue/UI/MediaTimecodeRow.swift`
- Modify: any export/title surface that prints `media.displayName` to a user (confirm by grep).

- [ ] **Step 1: Find every user-facing usage of `media.displayName`**

Run: `grep -rn "media\.displayName\|item\.media\.displayName" OnlyCue --include="*.swift"`

Classify each hit:
- **User-facing** (sidebar row, main-pane title, cue list grouping label, export columns) → switch to `resolvedName`.
- **Internal** (logging, error messages, bookmark/file-lookup, debug prints, audio engine wiring) → leave on `media.displayName`.

Known user-facing sites to update:
- `OnlyCue/UI/ItemRowView.swift` — the sidebar row label.
- `OnlyCue/UI/MediaTimecodeRow.swift` — the per-item label inside `TimecodeSettingsSheet`.

If `OnlyCue/Document/CueCSVExporter.swift` (or similar) prints the clip name into export rows, update it. Use `git grep` output to make sure no user-facing surface is missed.

- [ ] **Step 2: Apply the edits**

For each user-facing site, change `item.media.displayName` (or the local binding equivalent) to `item.resolvedName`. Example for `OnlyCue/UI/MediaTimecodeRow.swift` line 22:

```swift
            Text(item.resolvedName)
```

If a site only has access to a `MediaReference` (not the full `MediaItem`), leave it on `displayName` — the resolution requires the wrapping item. Note such sites in the commit message for future visibility.

- [ ] **Step 3: Verify the project builds**

Run: `xcodebuild build -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run all unit tests**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(ui): user-facing surfaces use MediaItem.resolvedName"
```

---

## Task 7: UI smoke test for the edit sheet

**Files:**
- Create: `OnlyCueUITests/MediaEditSheetUITests.swift`

- [ ] **Step 1: Write the UI test**

Create `OnlyCueUITests/MediaEditSheetUITests.swift`. The exact seeding mechanism depends on what's already in the UI-test target — there's a `UITestSeedHandler` per the recent test work; use the same pattern that existing tests use to launch the app with one seeded media item.

```swift
import XCTest

final class MediaEditSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_rightClickMediaRow_opensEditSheet_andSaveCommitsName() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-seed", "single-media-item"] // match existing seed name
        app.launch()

        let row = app.outlines.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()

        let edit = app.menuItems["contextMenuEditMedia"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.click()

        let nameField = app.textFields["mediaEditNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Opening Cue")

        let save = app.buttons["mediaEditSave"]
        save.click()

        // After save, the sidebar row label should reflect the new name.
        let renamed = app.staticTexts["Opening Cue"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 2))
    }

    func test_cancelDiscardsEdits() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-seed", "single-media-item"]
        app.launch()

        let row = app.outlines.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        app.menuItems["contextMenuEditMedia"].click()

        let nameField = app.textFields["mediaEditNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Should Not Stick")

        app.buttons["mediaEditCancel"].click()

        // Sheet should dismiss; label should still be the original seeded name.
        XCTAssertFalse(app.textFields["mediaEditNameField"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["Should Not Stick"].exists)
    }
}
```

Inspect `OnlyCueUITests/` for the exact existing seeding flag spelling (e.g. `-uitest-seed-fixture`, or an environment variable) and the seed name for a single-media-item fixture. If a single-item seed doesn't yet exist, add the smallest one needed by extending the existing `UITestSeedHandler` (single media item, no cues), keeping the change additive.

If the sidebar `List` doesn't render as `outlines.cells` in the AX tree, swap to whichever query the existing sidebar smoke tests use (e.g. `app.tables.cells` or by accessibility identifier on `ItemRowView`).

- [ ] **Step 2: Run the UI tests**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/MediaEditSheetUITests 2>&1 | tail -40`
Expected: 2 tests pass. If a step is fragile against XCUIElementQuery resolution, prefer adding an `accessibilityIdentifier` to the sidebar row in `ItemRowView` rather than overfitting the test query.

- [ ] **Step 3: Run the full UI test target to catch regressions**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests 2>&1 | tail -20`
Expected: All UI tests pass.

- [ ] **Step 4: Commit**

```bash
git add OnlyCueUITests/MediaEditSheetUITests.swift OnlyCueUITests/UITestSeedHandler.swift 2>/dev/null
git commit -m "test(media-edit-sheet): UI smoke for right-click → edit → save/cancel"
```

(Only stage `UITestSeedHandler.swift` if Step 1 actually modified it.)

---

## Task 8: Lint pass and final verification

**Files:** none (verification only)

- [ ] **Step 1: SwiftLint**

Run: `swiftlint lint --quiet 2>&1 | tail -30`
Expected: zero violations on touched files. Fix any reported issues inline and amend the relevant commit (or add a fixup commit).

- [ ] **Step 2: Full test suite**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -30`
Expected: all unit tests and UI tests pass.

- [ ] **Step 3: Manual smoke (golden path)**

`xcodegen generate && open OnlyCue.xcodeproj`, run the app, drop a media file in, right-click the sidebar row, choose "Edit Media…", type a name and a non-zero start timecode, toggle Mute, click Save. Confirm:
- Sidebar row label updates to the new name.
- Cmd-Z reverts all three fields in one undo.
- Reopening the same document round-trips the new fields.

If anything misbehaves, fix it before claiming done; UI/feature correctness is not implied by green tests alone.

- [ ] **Step 4: No commit needed** — verification only.

---

## Self-review (already applied)

- **Spec coverage:**
  - "Right-click sidebar row reveals Edit Media…" → Task 5.
  - "Modal sheet with three editable fields" → Tasks 4, 5.
  - "Atomic single-undo save" → Task 3 (+ test).
  - "Existing `TimecodeSettingsSheet` rows keep working" → unchanged code path, covered by Task 2 step 7 (full unit-test suite) and Task 6 step 4.
  - "`MediaItem.alternateName: String?`" → Task 1.
  - "`resolvedName` helper + display-name resolution rule" → Task 1, Task 6.
  - "Schema v11→v12 additive migration" → Task 2.
  - "Tests: model resolvedName, v12 migration, command atomic undo, UI smoke" → Tasks 1, 2, 3, 7.
  - Non-goal "per-media framerate" → explicitly excluded; framerate stays on `ProjectTimecodeSettings`.
  - Non-goal "rename on disk" → display-only override only.
  - Non-goal "bulk multi-select" → sheet edits one item; no plumbing for multi-selection.
- **Placeholder scan:** no TBD/TODO/"appropriate" placeholders; every code block is concrete.
- **Type consistency:** `updateMediaItem(id:alternateName:startTimecodeFrames:ltcMuted:document:undoManager:)` signature is identical in spec, command file, sheet wiring, and tests. `resolvedName`, `alternateName`, `LegacyV11`, `LegacyV11Item`, `MediaEditSheet`, and the accessibility identifiers (`mediaEditNameField`, `mediaEditStartTimecodeField`, `mediaEditMuteToggle`, `mediaEditSave`, `mediaEditCancel`, `contextMenuEditMedia`) are consistent across tasks.
