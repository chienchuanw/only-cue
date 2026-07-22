# PotPlayer Bookmark Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a File-menu "Export PotPlayer Bookmarks…" action that copies every located video into a chosen folder and writes a paired `.pbf` beside each, so PotPlayer (Windows) can auto-load OnlyCue's cues as jump-to bookmarks.

**Architecture:** A pure formatter (`PBFExporter`) turns one video's cues into `.pbf` text; a writer (`PotPlayerBundleWriter`) reuses the existing `BundleLayout` planner (source dedupe + collision-safe names) to copy videos flat and write their paired `.pbf`; a thin AppKit action (`PotPlayerExportAction`) supplies the `NSSavePanel` shell, mirroring `BundleExportAction`. Menu → notification → presenter-modifier wiring follows the existing Export Bundle pattern.

**Tech Stack:** Swift, XCTest, AppKit (`NSSavePanel`/`NSAlert`), SwiftUI (menu + presenter modifier), XcodeGen.

## Global Constraints

- Conventional Commits, lowercase after prefix, imperative; **no `Co-Authored-By` trailers** (project CLAUDE.md).
- No `ProjectModel` schema change → **no `schemaVersion` bump / migration** (this feature is read-only over the model).
- No App Sandbox entitlements (ADR-007); no embedded media in `.cuelist` (ADR-006 — N/A, we don't write a `.cuelist`).
- macOS deployment target stays ≥ 14.0 (ADR-001).
- New source files live under existing folders (`OnlyCue/Document/`, `OnlyCue/Utilities/`, `OnlyCue/UI/`) and test files under `OnlyCueTests/`; run `xcodegen generate` after adding files so the (uncommitted) `.xcodeproj` picks them up.
- `.pbf` title format: `[Type] Number Name`, e.g. `[Lighting] 12 副歌`. Number dropped when unnumbered; `[Type]` dropped when type unknown. `*`, CR, LF replaced with a space in the `.pbf` only (never mutate stored cues).
- Time base: `ms = round(cue.time * 1000)`; **ignore `startTimecodeFrames`**.
- Cue filter: include a cue only if its Type's `isExportEnabled == true`. A video with no surviving cue still gets an empty `.pbf` (`[Bookmark]` header only). UTF-8, no BOM.

**Test command** (unit tests only — no simulator/UI runner, avoids the known UITest wedges):

```bash
xcodegen generate
xcodebuild test -scheme OnlyCue -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PBFExporterTests \
  -only-testing:OnlyCueTests/PotPlayerBundleWriterTests
```

---

### Task 1: `PBFExporter` — pure `.pbf` formatter

**Files:**
- Create: `OnlyCue/Document/PBFExporter.swift`
- Test: `OnlyCueTests/PBFExporterTests.swift`

**Interfaces:**
- Consumes: `Cue` (`OnlyCue/Document/Cue.swift` — `time: TimeInterval`, `cueNumber: Double?`, `name: String`, `typeID: UUID`), `FadeTime.formatNumber(_:)` (`OnlyCue/Document/FadeTime.swift:68` — drops trailing `.0`).
- Produces: `PBFExporter.pbf(cues: [Cue], typeNamesByID: [UUID: String]) -> String`. Callers pass **already-filtered** cues (filtering is Task 2's job). Output is the full `.pbf` file body.

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/PBFExporterTests.swift`:

```swift
import XCTest
@testable import OnlyCue

/// Pins the PotPlayer `.pbf` bookmark format: `[Bookmark]` header, 1-based
/// `index=ms*title*` lines, time-sorted, `[Type] Number Name` titles, and
/// title sanitization of the `*`/CR/LF format characters.
final class PBFExporterTests: XCTestCase {

    private func cue(
        type: UUID = UUID(),
        number: Double? = nil,
        name: String = "",
        time: TimeInterval
    ) -> Cue {
        Cue(id: UUID(), typeID: type, cueNumber: number, name: name,
            time: time, notes: "", fadeTime: FadeTime(fadeIn: 0, fadeOut: 0))
    }

    func test_emptyList_returnsHeaderOnly() {
        XCTAssertEqual(PBFExporter.pbf(cues: [], typeNamesByID: [:]), "[Bookmark]\n")
    }

    func test_singleCue_formatsTypeNumberName() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [cue(type: type, number: 12, name: "副歌", time: 12.5)],
            typeNamesByID: [type: "Lighting"]
        )
        XCTAssertEqual(out, "[Bookmark]\n1=12500*[Lighting] 12 副歌*\n")
    }

    func test_time_isRoundedToNearestMillisecond() {
        let out = PBFExporter.pbf(cues: [cue(name: "x", time: 3.4567)], typeNamesByID: [:])
        XCTAssertTrue(out.contains("=3457*"), out)
    }

    func test_cuesAreSortedByTime_withOneBasedIndex() {
        let out = PBFExporter.pbf(
            cues: [cue(name: "late", time: 9), cue(name: "early", time: 1)],
            typeNamesByID: [:]
        )
        XCTAssertEqual(out, "[Bookmark]\n1=1000*early*\n2=9000*late*\n")
    }

    func test_unnumberedCue_dropsNumber() {
        let type = UUID()
        let out = PBFExporter.pbf(cues: [cue(type: type, name: "副歌", time: 0)],
                                  typeNamesByID: [type: "Lighting"])
        XCTAssertEqual(out, "[Bookmark]\n1=0*[Lighting] 副歌*\n")
    }

    func test_unknownType_dropsBracket() {
        let out = PBFExporter.pbf(cues: [cue(number: 3, name: "hit", time: 0)],
                                  typeNamesByID: [:])
        XCTAssertEqual(out, "[Bookmark]\n1=0*3 hit*\n")
    }

    func test_titleSanitizesDelimiterAndNewlines() {
        let type = UUID()
        let out = PBFExporter.pbf(
            cues: [cue(type: type, number: 5, name: "hit*flash\nbig", time: 0)],
            typeNamesByID: [type: "FX"]
        )
        XCTAssertEqual(out, "[Bookmark]\n1=0*[FX] 5 hit flash big*\n")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/PBFExporterTests`
Expected: FAIL — `cannot find 'PBFExporter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `OnlyCue/Document/PBFExporter.swift`:

```swift
import Foundation

/// Exports one video's cues to a PotPlayer bookmark file (`.pbf`) body.
///
/// `.pbf` is an INI-style text file; each bookmark is a line under a
/// `[Bookmark]` header:
///
///     [Bookmark]
///     1=<milliseconds>*<title>*
///
/// The three `*`-separated fields are time (ms from the video's 0), title, and
/// thumbnail (left empty). Bookmarks are written in time order with a 1-based
/// index. Times are `round(cue.time * 1000)` — the same 0-based playback seconds
/// OnlyCue stores, so a bookmark lands on the identical frame; the SMPTE
/// `startTimecodeFrames` label offset is deliberately ignored.
///
/// Title is `[Type] Number Name`, e.g. `[Lighting] 12 副歌`; the number is
/// dropped when the cue is unnumbered and the `[Type]` bracket when the type is
/// unknown. `*`, CR, and LF are replaced with a space so a cue title can't break
/// the `*`-delimited / line-based format — only the `.pbf` output is sanitized,
/// never the stored cue.
///
/// Per-Type `isExportEnabled` filtering happens upstream in the writer; this
/// renders exactly the cues it is handed. An empty list yields just the
/// `[Bookmark]` header, matching PotPlayer's empty bookmark file.
enum PBFExporter {

    static func pbf(cues: [Cue], typeNamesByID: [UUID: String]) -> String {
        let sorted = cues.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return (lhs.cueNumber ?? .greatestFiniteMagnitude)
                 < (rhs.cueNumber ?? .greatestFiniteMagnitude)
        }
        var out = "[Bookmark]\n"
        for (index, cue) in sorted.enumerated() {
            let ms = Int((cue.time * 1000).rounded())
            out += "\(index + 1)=\(ms)*\(title(for: cue, typeNamesByID: typeNamesByID))*\n"
        }
        return out
    }

    private static func title(for cue: Cue, typeNamesByID: [UUID: String]) -> String {
        var parts: [String] = []
        if let typeName = typeNamesByID[cue.typeID], !typeName.isEmpty {
            parts.append("[\(typeName)]")
        }
        if let number = cue.cueNumber {
            parts.append(FadeTime.formatNumber(number))
        }
        if !cue.name.isEmpty {
            parts.append(cue.name)
        }
        return sanitize(parts.joined(separator: " "))
    }

    /// Replace the format's control characters — the `*` field delimiter and any
    /// line break — with spaces so a cue title can't corrupt the `.pbf`.
    private static func sanitize(_ title: String) -> String {
        var result = title
        for bad in ["*", "\r", "\n"] {
            result = result.replacingOccurrences(of: bad, with: " ")
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/PBFExporterTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Document/PBFExporter.swift OnlyCueTests/PBFExporterTests.swift
git commit -m "feat(export): add PotPlayer .pbf bookmark formatter"
```

---

### Task 2: `PotPlayerBundleWriter` — flat video + paired `.pbf` I/O

**Files:**
- Create: `OnlyCue/Utilities/PotPlayerBundleWriter.swift`
- Test: `OnlyCueTests/PotPlayerBundleWriterTests.swift`

**Interfaces:**
- Consumes: `BundleLayout` (`OnlyCue/Utilities/BundleLayout.swift` — `.plan(_:)`, `Entry(source: URL, destName: String, itemIDs: [MediaItem.ID])`), `PBFExporter.pbf(cues:typeNamesByID:)` (Task 1), `ProjectModel` (`items`, `cuePointTypes`), `CuePointType` (`isExportEnabled: Bool`, `name`, `id`), `MediaItem` (`cues`).
- Produces: `PotPlayerBundleWriter.write(layout: BundleLayout, model: ProjectModel, to: URL, fileManager: FileManager = .default) throws`. Writes flat `<destName>` videos + `<stem>.pbf` files into `destination` (which must not pre-exist). Consumed by Task 3's action.

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/PotPlayerBundleWriterTests.swift`:

```swift
import XCTest
@testable import OnlyCue

/// `PotPlayerBundleWriter` copies each located video flat into the destination
/// and writes a paired `<stem>.pbf` (cues filtered to `isExportEnabled` Types).
/// Integration-tested against a temp directory (no NSSavePanel / GUI).
final class PotPlayerBundleWriterTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pbfwriter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeSourceFile(_ name: String, bytes: [UInt8]) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func cue(type: UUID, number: Double, name: String, time: TimeInterval) -> Cue {
        Cue(id: UUID(), typeID: type, cueNumber: number, name: name,
            time: time, notes: "", fadeTime: FadeTime(fadeIn: 0, fadeOut: 0))
    }

    private func item(id: UUID, name: String, cues: [Cue], startTCFrames: Int = 0) -> MediaItem {
        MediaItem(
            id: id,
            media: MediaReference(displayName: name, kind: .video, duration: 60, bookmarkData: Data([9])),
            cues: cues,
            startTimecodeFrames: startTCFrames
        )
    }

    private func model(types: [CuePointType], items: [MediaItem]) -> ProjectModel {
        ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "Show",
            cuePointTypes: types,
            items: items,
            activeItemID: items.first?.id
        )
    }

    func test_write_copiesVideoFlatAndWritesPairedPBF() throws {
        let type = UUID()
        let itemID = UUID()
        let source = try makeSourceFile("intro.mp4", bytes: [1, 2, 3])
        let m = model(
            types: [CuePointType(id: type, name: "Lighting", colorHex: "#fff")],
            items: [item(id: itemID, name: "intro.mp4",
                         cues: [cue(type: type, number: 1, name: "開場", time: 5)])]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "intro.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("intro.mp4")), Data([1, 2, 3]))
        let pbf = try String(contentsOf: dest.appendingPathComponent("intro.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n1=5000*[Lighting] 1 開場*\n")
    }

    func test_write_excludesDisabledTypes() throws {
        let shown = UUID(), hidden = UUID(), itemID = UUID()
        let source = try makeSourceFile("song.mp4", bytes: [1])
        let m = model(
            types: [
                CuePointType(id: shown, name: "Lighting", colorHex: "#fff", isExportEnabled: true),
                CuePointType(id: hidden, name: "Video", colorHex: "#000", isExportEnabled: false)
            ],
            items: [item(id: itemID, name: "song.mp4", cues: [
                cue(type: shown, number: 1, name: "keep", time: 1),
                cue(type: hidden, number: 2, name: "drop", time: 2)
            ])]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "song.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let pbf = try String(contentsOf: dest.appendingPathComponent("song.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n1=1000*[Lighting] 1 keep*\n")
    }

    func test_write_emptyVideoStillGetsPBF() throws {
        let itemID = UUID()
        let source = try makeSourceFile("silent.mp4", bytes: [1])
        let m = model(types: [], items: [item(id: itemID, name: "silent.mp4", cues: [])])
        let layout = BundleLayout.plan([.init(id: itemID, name: "silent.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let pbf = try String(contentsOf: dest.appendingPathComponent("silent.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n")
    }

    func test_write_collisionRenamesVideoAndPBFTogether() throws {
        let type = UUID(), idA = UUID(), idB = UUID()
        let dirA = tempRoot.appendingPathComponent("a", isDirectory: true)
        let dirB = tempRoot.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let srcA = dirA.appendingPathComponent("intro.mp4"); try Data([1]).write(to: srcA)
        let srcB = dirB.appendingPathComponent("intro.mp4"); try Data([2]).write(to: srcB)
        let m = model(
            types: [CuePointType(id: type, name: "L", colorHex: "#fff")],
            items: [
                item(id: idA, name: "intro.mp4", cues: [cue(type: type, number: 1, name: "a", time: 0)]),
                item(id: idB, name: "intro.mp4", cues: [cue(type: type, number: 2, name: "b", time: 0)])
            ]
        )
        let layout = BundleLayout.plan([
            .init(id: idA, name: "intro.mp4", url: srcA),
            .init(id: idB, name: "intro.mp4", url: srcB)
        ])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro.mp4").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro.pbf").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro-2.mp4").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("intro-2.pbf").path))
    }

    func test_write_ignoresStartTimecodeFrames() throws {
        let type = UUID(), itemID = UUID()
        let source = try makeSourceFile("offset.mp4", bytes: [1])
        let m = model(
            types: [CuePointType(id: type, name: "L", colorHex: "#fff")],
            items: [item(id: itemID, name: "offset.mp4",
                         cues: [cue(type: type, number: 1, name: "x", time: 5)],
                         startTCFrames: 90_000)]
        )
        let layout = BundleLayout.plan([.init(id: itemID, name: "offset.mp4", url: source)])
        let dest = tempRoot.appendingPathComponent("out", isDirectory: true)

        try PotPlayerBundleWriter.write(layout: layout, model: m, to: dest)

        let pbf = try String(contentsOf: dest.appendingPathComponent("offset.pbf"), encoding: .utf8)
        XCTAssertEqual(pbf, "[Bookmark]\n1=5000*[L] 1 x*\n")
    }
}
```

> Verified: `MediaItem` (`OnlyCue/Document/MediaItem.swift`) uses the synthesized memberwise init, so `MediaItem(id:media:cues:)` and `...startTimecodeFrames:)` both compile (`startTimecodeFrames` and later fields have defaults).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/PotPlayerBundleWriterTests`
Expected: FAIL — `cannot find 'PotPlayerBundleWriter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `OnlyCue/Utilities/PotPlayerBundleWriter.swift`:

```swift
import Foundation

/// File I/O for the PotPlayer bookmark export: given a `BundleLayout` (reused
/// from Export Bundle for source dedupe + collision-safe names), copy each video
/// flat into `destination` and write a paired `<stem>.pbf` beside it.
///
/// Unlike `BundleWriter`, the layout is written flat (no `media/` subfolder) and
/// no `.cuelist` is produced — PotPlayer auto-loads a `.pbf` only when it sits
/// beside the video sharing its base name. Cues are filtered to Types whose
/// `isExportEnabled` is true; a video with no surviving cue still gets an empty
/// `.pbf`. `destination` must not already exist (the action clears any prior).
enum PotPlayerBundleWriter {

    static func write(
        layout: BundleLayout,
        model: ProjectModel,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let enabledTypeIDs = Set(
            model.cuePointTypes.filter { $0.isExportEnabled }.map { $0.id }
        )
        let typeNamesByID = Dictionary(
            uniqueKeysWithValues: model.cuePointTypes.map { ($0.id, $0.name) }
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: model.items.map { ($0.id, $0) })

        for entry in layout.entries {
            // The source may be a security-scoped bookmark URL; reading its bytes
            // (copyItem) needs scoped access started, like BundleWriter /
            // MediaImporter. A plain fallback URL returns false and needs no bracket.
            let scoped = entry.source.startAccessingSecurityScopedResource()
            defer { if scoped { entry.source.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(
                at: entry.source,
                to: destination.appendingPathComponent(entry.destName)
            )

            // A file shared by several items (BundleLayout dedupe) gets all their
            // enabled cues merged into its one `.pbf`.
            let cues = entry.itemIDs
                .compactMap { itemsByID[$0]?.cues }
                .flatMap { $0 }
                .filter { enabledTypeIDs.contains($0.typeID) }
            let body = PBFExporter.pbf(cues: cues, typeNamesByID: typeNamesByID)
            let pbfName = (entry.destName as NSString).deletingPathExtension + ".pbf"
            try body.write(
                to: destination.appendingPathComponent(pbfName),
                atomically: true,
                encoding: .utf8
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/PotPlayerBundleWriterTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Utilities/PotPlayerBundleWriter.swift OnlyCueTests/PotPlayerBundleWriterTests.swift
git commit -m "feat(export): write flat PotPlayer bookmark bundle"
```

---

### Task 3: Menu wiring + `PotPlayerExportAction` (AppKit shell)

**Files:**
- Modify: `OnlyCue/UI/AppNotifications.swift` (add one notification name)
- Create: `OnlyCue/UI/PotPlayerExportAction.swift`
- Create: `OnlyCue/UI/PotPlayerExportMenuReceiver.swift`
- Modify: `OnlyCue/UI/DocumentView.swift:251` (add presenter modifier after `.bundleExportMenuReceiver`)
- Modify: `OnlyCue/App/AppCommands.swift` (add menu button after "Export Bundle…")

**Interfaces:**
- Consumes: `PotPlayerBundleWriter.write(...)` (Task 2), `BundleLayout.plan(_:)` + `BundleLayout.Source` (existing), `MediaReveal.revealURL(for:)` (`OnlyCue/UI/MediaReveal.swift` — two-step file locator, `nil` when unlocatable), `CueListDocument` (`document.model`).
- Produces: `.exportPotPlayerRequested` notification + `PotPlayerExportAction.export(from:)`. No unit test — thin I/O, matching `BundleExportAction`'s "Not unit-tested (thin I/O); verified by running the app."

- [ ] **Step 1: Add the notification name**

In `OnlyCue/UI/AppNotifications.swift`, add after the `exportBundleRequested` line:

```swift
    static let exportPotPlayerRequested = Notification.Name("OnlyCue.exportPotPlayerRequested")
```

- [ ] **Step 2: Create the action**

Create `OnlyCue/UI/PotPlayerExportAction.swift`:

```swift
import AppKit

/// Wires the File menu's **Export PotPlayer Bookmarks…** action. Copies every
/// located video into a chosen folder and writes a paired `.pbf` beside each so
/// PotPlayer (Windows) can auto-load OnlyCue's cues as jump-to bookmarks.
///
/// Mirrors `BundleExportAction`: same source-location + option-C "some files
/// missing" warning + `NSSavePanel` shell, but delegates the write to
/// `PotPlayerBundleWriter` (flat videos + `.pbf`, no `.cuelist`). Not
/// unit-tested (thin I/O); verified by running the app.
enum PotPlayerExportAction {

    @MainActor
    static func export(from document: CueListDocument) {
        let model = document.model

        let sources = model.items.map { item in
            BundleLayout.Source(
                id: item.id,
                name: item.media.displayName,
                url: MediaReveal.revealURL(for: item.media)
            )
        }
        let layout = BundleLayout.plan(sources)

        if !layout.missing.isEmpty, !confirmMissing(count: layout.missing.count) {
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.name.isEmpty ? "Untitled" : model.name
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.nameFieldLabel = "Folder Name:"
        panel.message = "Choose where to save the PotPlayer bookmark folder."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try PotPlayerBundleWriter.write(layout: layout, model: model, to: destination)
        } catch {
            // Don't leave a half-written folder behind on a mid-copy failure.
            try? FileManager.default.removeItem(at: destination)
            presentError(message: "The PotPlayer bookmarks could not be exported.")
        }
    }

    /// Option-C confirmation. Returns true to export the rest anyway.
    @MainActor
    private static func confirmMissing(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1
            ? "1 media file can’t be included"
            : "\(count) media files can’t be included"
        alert.informativeText = """
        These files couldn’t be located on this Mac, so no bookmarks will be \
        written for them. Export the rest anyway?
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private static func presentError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PotPlayer Export Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

- [ ] **Step 3: Create the presenter modifier**

Create `OnlyCue/UI/PotPlayerExportMenuReceiver.swift`:

```swift
import SwiftUI

/// View modifier that listens for `.exportPotPlayerRequested` and routes it to
/// `PotPlayerExportAction`. Same pattern as `BundleExportMenuReceiver`.
struct PotPlayerExportMenuReceiver: ViewModifier {

    @ObservedObject var document: CueListDocument

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportPotPlayerRequested)) { _ in
                PotPlayerExportAction.export(from: document)
            }
    }
}

extension View {
    func potPlayerExportMenuReceiver(document: CueListDocument) -> some View {
        modifier(PotPlayerExportMenuReceiver(document: document))
    }
}
```

- [ ] **Step 4: Attach the modifier**

In `OnlyCue/UI/DocumentView.swift`, immediately after the existing `.bundleExportMenuReceiver(document: document)` (line ~251), add:

```swift
        .potPlayerExportMenuReceiver(document: document)
```

- [ ] **Step 5: Add the menu item**

In `OnlyCue/App/AppCommands.swift`, immediately after the "Export Bundle…" `Button { … }` block (the one with `.accessibilityIdentifier("exportBundleMenuItem")`), add:

```swift
            Button {
                NotificationCenter.default.post(name: .exportPotPlayerRequested, object: nil)
            } label: {
                Label("Export PotPlayer Bookmarks…", systemImage: "bookmark")
            }
            .accessibilityIdentifier("exportPotPlayerMenuItem")
```

- [ ] **Step 6: Regenerate, build, and run the full test suite**

Run:
```bash
xcodegen generate
xcodebuild build -scheme OnlyCue -destination 'platform=macOS'
xcodebuild test -scheme OnlyCue -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PBFExporterTests \
  -only-testing:OnlyCueTests/PotPlayerBundleWriterTests
```
Expected: build succeeds; both test classes PASS.

- [ ] **Step 7: SwiftLint**

Run: `swiftlint lint --quiet OnlyCue`
Expected: no new violations in the added files.

- [ ] **Step 8: Manual verification (record for the PR)**

1. Open a project with ≥1 video and cues of mixed Types (some Type `isExportEnabled` off).
2. File → **Export PotPlayer Bookmarks…** → choose a folder.
3. Confirm the folder holds each `<video>` + `<video>.pbf`, and the `.pbf` contents match `[Type] Number Name` with disabled Types absent.
4. (If a Windows/PotPlayer machine is available) copy the folder over, open a video, and confirm bookmarks appear and jump correctly with UTF-8 titles intact. Otherwise note this as PotPlayer-side verification pending (spec risk).

- [ ] **Step 9: Commit**

```bash
git add OnlyCue/UI/AppNotifications.swift OnlyCue/UI/PotPlayerExportAction.swift \
        OnlyCue/UI/PotPlayerExportMenuReceiver.swift OnlyCue/UI/DocumentView.swift \
        OnlyCue/App/AppCommands.swift
git commit -m "feat(export): add Export PotPlayer Bookmarks menu action"
```

---

## Self-Review

**Spec coverage:**
- Independent export (not bundled `.cuelist`) → Task 3 action + Task 2 writer (no `.cuelist`). ✓
- Jump-point preview via `.pbf` bookmarks → Task 1 format (`ms*title*`). ✓
- Title `[Type] Number Name` → Task 1 `title(for:)` + tests. ✓
- Time base `round(time*1000)`, ignore `startTimecodeFrames` → Task 1 + Task 2 `test_write_ignoresStartTimecodeFrames`. ✓
- `isExportEnabled` filter → Task 2 `enabledTypeIDs` + `test_write_excludesDisabledTypes`. ✓
- All-videos bundle-style export → Task 2 iterates `layout.entries`; Task 3 builds sources from all `model.items`. ✓
- Filename collision `-2`/`-3`, video+`.pbf` paired → reuse `BundleLayout` + Task 2 `test_write_collisionRenamesVideoAndPBFTogether`. ✓
- Empty video → empty `.pbf` → Task 1 `test_emptyList` + Task 2 `test_write_emptyVideoStillGetsPBF`. ✓
- `*`/newline sanitization → Task 1 `test_titleSanitizesDelimiterAndNewlines`. ✓
- UTF-8 → Task 2 `.write(...encoding: .utf8)`. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. One flagged assumption (Task 2 note on `MediaItem` init label) with a concrete resolution instruction.

**Type consistency:** `PBFExporter.pbf(cues:typeNamesByID:)` and `PotPlayerBundleWriter.write(layout:model:to:fileManager:)` referenced identically across tasks. `.exportPotPlayerRequested`, `potPlayerExportMenuReceiver`, and `exportPotPlayerMenuItem` used consistently in Task 3.

**Risks (from spec):** PotPlayer `.pbf` encoding/BOM tolerance and same-stem/different-extension collisions (e.g. `intro.mp4` vs `intro.mov` → both want `intro.pbf`) are accepted PotPlayer-side limitations, not built around (YAGNI). Confirmed at Step 8.
