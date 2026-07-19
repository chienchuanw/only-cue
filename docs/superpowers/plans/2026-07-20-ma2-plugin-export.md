# grandMA2 plugin export (Approach C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Export grandMA2 plugin…" action that writes a self-contained grandMA2 plugin (`.lua` + `.xml` wrapper). When the user imports and runs it on any console, it writes the sequence + timecode-pool XML into the console's *local* `importexport` folder and imports them — no FTP, no live network connection. This restores the "real Timecode-pool object" outcome that Approach A (live telnet) cannot produce, and reuses the existing, rig-confirmed XML generators verbatim.

**Architecture:** A pure `MA2PluginGenerator` wraps the existing `MA2PushPlan` (two XML payloads + the Import command list produced by `MA2PushPlanner`) into a Lua plugin that, on the console, `io.open`-writes each XML into `<show path>/importexport/`, runs the plan's `gma.cmd` import commands, then `os.remove`s the temp files — the pattern the shared CuePoints `CuePoints_PLUGIN.lua` uses. `MA2PushRequestBuilder.pluginOutcome` reuses the existing `outcome(...)` (which already builds the plan). A File-menu / context-menu action saves the two files via `NSSavePanel`.

**Tech Stack:** Swift 6, SwiftUI, XCTest, AppKit `NSSavePanel`, xcodegen. Generated artifact is grandMA2 Lua (v3.9).

**Prerequisite:** Approach A (`docs/superpowers/plans/2026-07-20-ma2-telnet-command-push.md`) is merged/green. `MA2PushPlanner` / `MA2SequenceXMLGenerator` / `MA2TimecodeXMLGenerator` / `MA2PushPlan` / `MA2FTPUploader` are all retained (annotated Approach-C-only) — this plan is their consumer.

## Global Constraints

- Swift 6, macOS deployment target ≥ 14.0 (ADR-001).
- `swiftlint lint --strict` clean; multi-line calls one-arg-per-line; no `force_unwrapping` in tests.
- No direct `ProjectModel` mutations — go through `Commands/CueCommands.swift` (reuse `setMA2PushTarget`).
- Conventional Commits, no `Co-Authored-By` / attribution.
- No schema change: `MA2PushTarget` (v17) is reused in full (Approach C uses `timecodeSlot` and `timecodeCommand`, unlike A).
- No test contacts a console or filesystem outside a temp dir; the generator is a pure string builder.

## Reference types (already in the codebase)

- `MA2PushPlan`: `sequenceUpload: Upload`, `timecodeUpload: Upload`, `commands: [String]`. `Upload`: `filename: String` (e.g. `onlycue_seq_900.xml`), `xml: String`.
- `MA2PushPlanner.plan(cues:target:sequenceName:timecodeName:startTimecodeFrames:lengthFrames:framerate:showfile:datetime:) -> MA2PushPlan`. Its `commands` are the import sequence: `Delete Sequence <s> /nc`, `Delete Timecode <t> /nc`, `cd Sequences`, `cd Global`, `Import "<seqbase>" At <s> /nc`, `cd /`, `Import "<tcbase>" At Timecode <t> /nc`, `Assign Sequence <s> At Exec <p>.<e>`, `Label Sequence <s> "…"`, `Label Timecode <t> "…"`.
- `MA2PushRequestBuilder.outcome(item:target:framerate:showfile:datetime:) -> Outcome` (`.blocked([Issue])` / `.ready(MA2PushPlan)`) — already builds the plan; reuse it.
- Reference artifacts the owner shared: `~/Downloads/test 2/gma2/plugins/CuePoints_PLUGIN.lua` (local-write + `CMD('Import … At Timecode N')` + `os.remove`) and `cuepoints.xml` (the `<Plugin luafile=…/>` manifest shape).

---

### Task 1: `MA2PluginGenerator.lua` — the Lua script

**Files:**

- Create: `OnlyCue/MA2/MA2PluginGenerator.swift`
- Test: `OnlyCueTests/MA2PluginGeneratorTests.swift`

**Interfaces:**

- Consumes: `MA2PushPlan`.
- Produces: `enum MA2PluginGenerator { static func lua(plan: MA2PushPlan) -> String }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MA2PluginGeneratorTests: XCTestCase {
    private func plan() -> MA2PushPlan {
        MA2PushPlan(
            sequenceUpload: .init(filename: "onlycue_seq_900.xml", xml: "<seq/>"),
            timecodeUpload: .init(filename: "onlycue_tc_9.xml", xml: "<tc/>"),
            commands: ["Delete Sequence 900 /nc", "Import \"onlycue_seq_900\" At 900 /nc"]
        )
    }

    func test_lua_writesBothFilesLocally_runsCommands_thenRemoves() {
        let lua = MA2PluginGenerator.lua(plan: plan())
        // Resolves the console's local importexport folder + OS path separator.
        XCTAssertTrue(lua.contains("gma.show.getvar('PATH')"))
        XCTAssertTrue(lua.contains("package.config:sub(1,1)"))
        // Writes each payload with a long-bracket literal so XML quotes survive.
        XCTAssertTrue(lua.contains("'onlycue_seq_900.xml'"))
        XCTAssertTrue(lua.contains("[==[<seq/>]==]"))
        XCTAssertTrue(lua.contains("'onlycue_tc_9.xml'"))
        XCTAssertTrue(lua.contains("[==[<tc/>]==]"))
        // Runs each plan command via gma.cmd.
        XCTAssertTrue(lua.contains("CMD('Delete Sequence 900 /nc')"))
        XCTAssertTrue(lua.contains("CMD('Import \"onlycue_seq_900\" At 900 /nc')"))
        // Cleans up both temp files.
        XCTAssertTrue(lua.contains("os.remove(path..'onlycue_seq_900.xml')"))
        XCTAssertTrue(lua.contains("os.remove(path..'onlycue_tc_9.xml')"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests/MA2PluginGeneratorTests`
Expected: FAIL — `MA2PluginGenerator` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Wraps an `MA2PushPlan` (#683, Approach C) into a grandMA2 Lua plugin that,
/// when run on the console, writes the two XML payloads into the console's own
/// `importexport` folder, imports them via `gma.cmd`, then deletes the temp
/// files — the CuePoints "TC object" pattern, which needs no FTP because the
/// plugin runs on the console. The Lua runtime wrapper (how MA2 invokes the
/// plugin) is modeled on the shared `CuePoints_PLUGIN.lua`; verify plugin
/// invocation on a real console during Phase C validation.
enum MA2PluginGenerator {

    static func lua(plan: MA2PushPlan) -> String {
        var lines: [String] = [
            "-- OnlyCue grandMA2 plugin (generated). Imports a sequence + timecode object.",
            "local function onlycue_import()",
            "  local CMD = gma.cmd",
            "  local slash = package.config:sub(1,1)",
            "  local path = gma.show.getvar('PATH')..slash..'importexport'..slash"
        ]
        lines.append(contentsOf: writeFile(plan.sequenceUpload))
        lines.append(contentsOf: writeFile(plan.timecodeUpload))
        for command in plan.commands {
            // Plan commands never contain single quotes; wrap in a Lua single-quoted string.
            lines.append("  CMD('\(command)')")
        }
        lines.append("  gma.sleep(0.5)")
        lines.append("  os.remove(path..'\(plan.sequenceUpload.filename)')")
        lines.append("  os.remove(path..'\(plan.timecodeUpload.filename)')")
        lines.append("end")
        lines.append("return onlycue_import")
        return lines.joined(separator: "\n")
    }

    private static func writeFile(_ upload: MA2PushPlan.Upload) -> [String] {
        // Long-bracket literal [==[ … ]==] keeps the XML's double quotes intact.
        [
            "  local f = io.open(path..'\(upload.filename)', 'w')",
            "  f:write([==[\(upload.xml)]==])",
            "  f:close()"
        ]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PluginGeneratorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PluginGenerator.swift OnlyCueTests/MA2PluginGeneratorTests.swift
git commit -m "feat(ma2): generate grandMA2 lua plugin from push plan"
```

---

### Task 2: `MA2PluginGenerator.bundle` — manifest XML + file set

**Files:**

- Modify: `OnlyCue/MA2/MA2PluginGenerator.swift`
- Test: `OnlyCueTests/MA2PluginGeneratorTests.swift` (add cases)

**Interfaces:**

- Produces: `struct MA2PluginBundle: Equatable { var luaFilename: String; var lua: String; var manifestFilename: String; var manifestXML: String }`; `MA2PluginGenerator.bundle(plan: MA2PushPlan, pluginName: String, datetime: String) -> MA2PluginBundle`.

- [ ] **Step 1: Write the failing test**

```swift
func test_bundle_pairsLuaWithManifestPointingToIt() {
    let bundle = MA2PluginGenerator.bundle(plan: plan(), pluginName: "Opening", datetime: "2026-07-20T00:00:00")
    XCTAssertEqual(bundle.luaFilename, "OnlyCue_Opening_PLUGIN.lua")
    XCTAssertEqual(bundle.manifestFilename, "OnlyCue_Opening.xml")
    XCTAssertTrue(bundle.manifestXML.contains("<Plugin"))
    XCTAssertTrue(bundle.manifestXML.contains("luafile=\"OnlyCue_Opening_PLUGIN.lua\""))
    XCTAssertTrue(bundle.manifestXML.contains("datetime=\"2026-07-20T00:00:00\""))
    XCTAssertEqual(bundle.lua, MA2PluginGenerator.lua(plan: plan()))
}

func test_bundle_sanitizesPluginNameForFilenames() {
    let bundle = MA2PluginGenerator.bundle(plan: plan(), pluginName: "A / B: c", datetime: "d")
    XCTAssertFalse(bundle.luaFilename.contains("/"))
    XCTAssertFalse(bundle.luaFilename.contains(":"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PluginGeneratorTests`
Expected: FAIL — `bundle` / `MA2PluginBundle` undefined.

- [ ] **Step 3: Write minimal implementation** — add to `MA2PluginGenerator.swift`:

```swift
struct MA2PluginBundle: Equatable {
    var luaFilename: String
    var lua: String
    var manifestFilename: String
    var manifestXML: String
}

extension MA2PluginGenerator {

    static func bundle(plan: MA2PushPlan, pluginName: String, datetime: String) -> MA2PluginBundle {
        let base = "OnlyCue_" + sanitize(pluginName)
        let luaFilename = base + "_PLUGIN.lua"
        return MA2PluginBundle(
            luaFilename: luaFilename,
            lua: lua(plan: plan),
            manifestFilename: base + ".xml",
            manifestXML: manifestXML(pluginName: pluginName, luaFilename: luaFilename, datetime: datetime)
        )
    }

    static func manifestXML(pluginName: String, luaFilename: String, datetime: String) -> String {
        let escaped = MA2SequenceXMLGenerator.escape
        return [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<MA xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
                + "xmlns=\"http://schemas.malighting.de/grandma2/xml/MA\" "
                + "major_vers=\"3\" minor_vers=\"9\" stream_vers=\"60\">",
            "\t<Info datetime=\"\(escaped(datetime))\" showfile=\"OnlyCue\" />",
            "\t<Plugin index=\"0\" name=\"\(escaped(pluginName))\" luafile=\"\(escaped(luaFilename))\" />",
            "</MA>"
        ].joined(separator: "\n")
    }

    /// Filesystem-safe base: strip path separators and colons.
    private static func sanitize(_ name: String) -> String {
        String(name.map { "/\\:".contains($0) ? "_" : $0 })
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PluginGeneratorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PluginGenerator.swift OnlyCueTests/MA2PluginGeneratorTests.swift
git commit -m "feat(ma2): pair generated lua with its plugin manifest xml"
```

---

### Task 3: `MA2PushRequestBuilder.pluginOutcome` — plan → bundle

**Files:**

- Modify: `OnlyCue/MA2/MA2PushRequestBuilder.swift`
- Test: `OnlyCueTests/MA2PushRequestBuilderTests.swift` (add cases; reuse existing `item`/`cue`/`target` helpers)

**Interfaces:**

- Consumes: existing `outcome(...)` (→ `MA2PushPlan`), `MA2PluginGenerator.bundle(...)`.
- Produces: `MA2PushRequestBuilder.pluginOutcome(item:target:framerate:datetime:) -> PluginOutcome` where `enum PluginOutcome: Equatable { case blocked([MA2PushPreflight.Issue]); case ready(MA2PluginBundle) }`.

- [ ] **Step 1: Write the failing test**

```swift
func test_pluginOutcome_ready_wrapsPlanInBundle() {
    let item = item(cues: [cue(number: 1, typeID: typeA, time: 2)])
    let outcome = MA2PushRequestBuilder.pluginOutcome(
        item: item,
        target: target(),
        framerate: .fps30,
        datetime: "2026-07-20T00:00:00"
    )
    guard case .ready(let bundle) = outcome else {
        return XCTFail("expected ready, got \(outcome)")
    }
    // Plugin name = clip's resolved name.
    XCTAssertTrue(bundle.manifestXML.contains("name=\"Opening\""))
    XCTAssertTrue(bundle.lua.contains("CMD('Label Sequence 18 \"Opening\"')"))
}

func test_pluginOutcome_blocked_onUnnumberedCue() {
    let item = item(cues: [cue(number: nil, typeID: typeA)])
    let outcome = MA2PushRequestBuilder.pluginOutcome(
        item: item,
        target: target(),
        framerate: .fps30,
        datetime: "d"
    )
    guard case .blocked = outcome else {
        return XCTFail("expected blocked")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PushRequestBuilderTests`
Expected: FAIL — `pluginOutcome` undefined.

- [ ] **Step 3: Write minimal implementation** — add to `MA2PushRequestBuilder.swift`:

```swift
    enum PluginOutcome: Equatable {
        case blocked([MA2PushPreflight.Issue])
        case ready(MA2PluginBundle)
    }

    /// Approach C (#683): reuse the FTP-era plan builder, then wrap it into a
    /// downloadable Lua plugin instead of pushing over FTP.
    static func pluginOutcome(
        item: MediaItem,
        target: MA2PushTarget,
        framerate: SMPTEFramerate,
        datetime: String
    ) -> PluginOutcome {
        switch outcome(item: item, target: target, framerate: framerate, showfile: "OnlyCue", datetime: datetime) {
        case .blocked(let issues):
            return .blocked(issues)
        case .ready(let plan):
            return .ready(MA2PluginGenerator.bundle(plan: plan, pluginName: item.resolvedName, datetime: datetime))
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PushRequestBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PushRequestBuilder.swift OnlyCueTests/MA2PushRequestBuilderTests.swift
git commit -m "feat(ma2): build plugin bundle from a media item"
```

---

### Task 4: Save the bundle to disk (pure writer)

**Files:**

- Create: `OnlyCue/MA2/MA2PluginWriter.swift`
- Test: `OnlyCueTests/MA2PluginWriterTests.swift`

**Interfaces:**

- Produces: `enum MA2PluginWriter { static func write(_ bundle: MA2PluginBundle, toDirectory directory: URL) throws -> [URL] }` (writes both files, returns their URLs).

- [ ] **Step 1: Write the failing test**

```swift
func test_write_createsBothFilesWithContents() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ma2plugin-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let bundle = MA2PluginBundle(
        luaFilename: "OnlyCue_X_PLUGIN.lua",
        lua: "-- lua",
        manifestFilename: "OnlyCue_X.xml",
        manifestXML: "<MA/>"
    )
    let urls = try MA2PluginWriter.write(bundle, toDirectory: dir)

    XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["OnlyCue_X_PLUGIN.lua", "OnlyCue_X.xml"])
    let lua = try String(contentsOf: dir.appendingPathComponent("OnlyCue_X_PLUGIN.lua"), encoding: .utf8)
    let xml = try String(contentsOf: dir.appendingPathComponent("OnlyCue_X.xml"), encoding: .utf8)
    XCTAssertEqual(lua, "-- lua")
    XCTAssertEqual(xml, "<MA/>")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PluginWriterTests`
Expected: FAIL — `MA2PluginWriter` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Writes an `MA2PluginBundle`'s two files into a user-chosen directory
/// (#683, Approach C). Pure filesystem — the `NSSavePanel` picks the directory.
enum MA2PluginWriter {
    @discardableResult
    static func write(_ bundle: MA2PluginBundle, toDirectory directory: URL) throws -> [URL] {
        let luaURL = directory.appendingPathComponent(bundle.luaFilename)
        let xmlURL = directory.appendingPathComponent(bundle.manifestFilename)
        try bundle.lua.write(to: luaURL, atomically: true, encoding: .utf8)
        try bundle.manifestXML.write(to: xmlURL, atomically: true, encoding: .utf8)
        return [luaURL, xmlURL]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test … -only-testing:OnlyCueTests/MA2PluginWriterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/MA2/MA2PluginWriter.swift OnlyCueTests/MA2PluginWriterTests.swift
git commit -m "feat(ma2): write plugin bundle files to a directory"
```

---

### Task 5: UI — "Export grandMA2 plugin…" action

**Files:**

- Modify: `OnlyCue/App/AppCommands.swift` (File-menu item next to "Send to grandMA2…")
- Modify: `OnlyCue/UI/ItemListPane.swift` (context-menu item)
- Create: `OnlyCue/UI/MA2PluginExportPresenter.swift` (listens for the request, resolves the item, runs the pre-flight, shows an `NSSavePanel`, writes via `MA2PluginWriter`, persists the target via `CueCommands.setMA2PushTarget`, surfaces pre-flight blocks)
- Modify: `OnlyCue/App/OnlyCueApp.swift` (attach the presenter modifier, mirroring `ma2PushSheet`)
- Test: reuse Tasks 1–4 (pure logic is covered). Add a UI smoke check only if the project already has an equivalent XCUITest pattern for "Send to grandMA2…"; otherwise assert the wiring compiles and the app builds.

**Interfaces:**

- Consumes: `MA2PushRequestBuilder.pluginOutcome(...)`, `MA2PluginWriter.write(...)`, a new `Notification.Name.exportMA2PluginRequested` (mirror `.sendToMA2Requested`).

- [ ] **Step 1: Read the existing "Send to grandMA2…" wiring** to copy its shape exactly.

Run: `grep -rn "sendToMA2Requested\|Send to grandMA2" OnlyCue/App/AppCommands.swift OnlyCue/UI/ItemListPane.swift OnlyCue/App/OnlyCueApp.swift`

- [ ] **Step 2: Add the notification + menu/context entries**

In the notification-names file that defines `.sendToMA2Requested`, add:

```swift
static let exportMA2PluginRequested = Notification.Name("exportMA2PluginRequested")
```

In `AppCommands.swift`, directly after the "Send to grandMA2…" button, add:

```swift
Button {
    NotificationCenter.default.post(name: .exportMA2PluginRequested, object: nil)
} label: {
    Label("Export grandMA2 plugin…", systemImage: "square.and.arrow.down")
}
```

In `ItemListPane.swift`, after the "Send to grandMA2…" context button, add the sibling posting `.exportMA2PluginRequested` with the item's ID as `object`.

- [ ] **Step 3: Create the presenter** — `OnlyCue/UI/MA2PluginExportPresenter.swift`, modeled on `MA2PushSheetPresenter`:

```swift
import SwiftUI
import AppKit

/// Listens for `.exportMA2PluginRequested` (#683, Approach C): resolves the
/// item, builds the plugin bundle, and — on a clean pre-flight — saves it via
/// an `NSSavePanel`. Blocks are surfaced through the same alert channel as the
/// push sheet.
struct MA2PluginExportPresenter: ViewModifier {
    let document: CueListDocument
    let undoManager: UndoManager?
    @State private var blockedIssues: [MA2PushPreflight.Issue] = []
    @State private var showingBlock = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportMA2PluginRequested)) { note in
                export(requestedID: note.object as? MediaItem.ID)
            }
            .alert("Cannot export plugin", isPresented: $showingBlock) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(MA2PushPreflight.summary(blockedIssues))   // reuse the sheet's issue-formatting helper
            }
    }

    private func export(requestedID: MediaItem.ID?) {
        let itemID = requestedID ?? document.model.activeItemID
        guard let item = document.model.items.first(where: { $0.id == itemID }) else { return }
        let target = item.ma2PushTarget ?? MA2PushTarget(   // same default the sheet seeds
            sequenceSlot: 1, timecodeSlot: 1, executorPage: 1, executorNumber: 1,
            timecodeCommand: .goto, includedTypeIDs: []
        )
        let datetime = ISO8601DateFormatter().string(from: Date())
        switch MA2PushRequestBuilder.pluginOutcome(
            item: item, target: target, framerate: document.model.timecodeSettings.framerate, datetime: datetime
        ) {
        case .blocked(let issues):
            blockedIssues = issues
            showingBlock = true
        case .ready(let bundle):
            CueCommands.setMA2PushTarget(target, itemID: item.id, document: document, undoManager: undoManager)
            save(bundle)
        }
    }

    private func save(_ bundle: MA2PluginBundle) {
        let panel = NSSavePanel()
        panel.title = "Export grandMA2 plugin"
        panel.nameFieldStringValue = bundle.manifestFilename
        panel.prompt = "Export"
        panel.message = "Both the .xml and its _PLUGIN.lua are written next to each other."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? MA2PluginWriter.write(bundle, toDirectory: url.deletingLastPathComponent())
    }
}

extension View {
    func ma2PluginExport(document: CueListDocument, undoManager: UndoManager?) -> some View {
        modifier(MA2PluginExportPresenter(document: document, undoManager: undoManager))
    }
}
```

> Two lookups to confirm against real code before writing: the default `MA2PushTarget` the sheet seeds (copy `MA2PushSheet.init`'s `saved` fallback), and whether a `MA2PushPreflight.summary(_:)`-style formatter exists — if not, inline the same issue-to-text mapping the sheet's `preflightCard` uses.

- [ ] **Step 4: Attach the presenter** in `OnlyCueApp.swift` right after `.ma2PushSheet(...)`:

```swift
.ma2PluginExport(document: document, undoManager: undoManager)
```

- [ ] **Step 5: Regenerate, build, full test, lint**

Run:

```bash
xcodegen generate
xcodebuild build -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-"
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" -only-testing:OnlyCueTests
swiftlint lint --strict
```

Expected: BUILD SUCCEEDED; all tests pass; lint clean.

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/App/AppCommands.swift OnlyCue/UI/ItemListPane.swift OnlyCue/UI/MA2PluginExportPresenter.swift OnlyCue/App/OnlyCueApp.swift OnlyCue/App/*Notification*.swift
git commit -m "feat(ma2): add export grandMA2 plugin action"
```

---

## Self-Review

- **Spec coverage (Approach C):** Lua generation (local write + import + remove) → Task 1; manifest pairing → Task 2; plan→bundle reuse of `outcome(...)` → Task 3; file writing → Task 4; UI action + save panel → Task 5. Reuses `MA2PushPlanner` / both XML generators / `MA2PushPlan` verbatim (no changes to them). No schema change.
- **No real-console dependency in tests:** Tasks 1–4 are pure / temp-dir; Task 5 is UI wiring behind the pure logic.
- **Type consistency:** `MA2PluginGenerator.lua(plan:)`, `MA2PluginBundle`, `MA2PluginGenerator.bundle(plan:pluginName:datetime:)`, `MA2PushRequestBuilder.pluginOutcome(item:target:framerate:datetime:) → PluginOutcome`, `MA2PluginWriter.write(_:toDirectory:)` — used identically across tasks.
- **Placeholder scan:** Task 5 flags the two real-code lookups (seed target default, pre-flight summary helper) to confirm before writing — the rest ships complete code.

## Real-console validation (before this can be called done)

The Lua runtime wrapper and `Import … At Timecode` on a **locally-written** file cannot be exercised without placing files on the console. When a console (or onPC with local file access) is available:

1. Export a plugin, drop both files into that console's `gma2/plugins`, import + run the plugin.
2. Confirm the sequence + a real Timecode-pool object (slot `timecodeSlot`) appear, the executor is assigned, labels are set, and the temp XML files are removed.
3. Confirm frame times land correctly (this is also where the 29.97DF case gets its real-LTC check).

Log the result on PR #684 (or Phase C's PR). Do not flip to ready / merge without the owner's go-ahead.

```
