# Rearrangeable Workspace (phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the document window's three panes resizable and collapsible per editor mode, and let the designer save those arrangements as named workspace presets — without reintroducing an `NSSplitView` in the detail column (#617).

**Architecture:** A pure value type (`PaneLayout`) describes one mode's arrangement and owns the clamping rule. `WorkspaceLayout` bundles one `PaneLayout` per `EditorMode` under a name. `WorkspaceLayoutStore` is an app-level `ObservableObject` singleton persisting presets + the most-recent live layout to `UserDefaults` under `"workspaceLayout.v1"`, following the `LTCRoutingStore` pattern exactly. The live per-window layout is `@SceneStorage` JSON inside `DocumentView`. The inspector divider is a plain SwiftUI `Divider()` carrying a `DragGesture`; the sidebar width is read via `GeometryReader` and written via a one-way `NSViewRepresentable` probe that calls `NSSplitView.setPosition(_:ofDividerAt:)`.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit interop, XCTest / XCUITest, SwiftLint (`--strict`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-31-rearrangeable-workspace.md` (approved 2026-07-31). **Issue:** #714. **Branch:** `issues/714`.

## Global Constraints

- **No `NSSplitView`-backed split may be added to the detail column.** No `.inspector`, no `HSplitView`, no `NSSplitViewController`. The divider is a plain `Divider()` with a gesture. (#617; spec §"The obstacle this spec has to work around")
- **`OnlyCueUITests/DocumentWindowMinWidthUITests.swift` must stay green** — a populated window is ≤ 1280pt wide.
- **`ProjectModel.currentSchemaVersion` stays 18.** No migration. No layout value may reach `ProjectModel`, the undo stack, or mark the document dirty.
- **All `ProjectModel` mutation goes through `Commands/CueCommands.swift`** — this feature must not mutate it at all, so it adds no commands.
- **Width bounds are unchanged:** sidebar 240–320 (min–max, ideal 240), inspector 340–400 (min–max, ideal 360). Center pane minimum 560.
- **macOS deployment target stays 14.0.** No API newer than macOS 14.
- **No App Sandbox entitlements.**
- **Design tokens:** `DocumentView.swift` and `DocumentView+*.swift` are scanned by `OnlyCueTests/DesignSystem/TokenConformanceTests.swift` — raw `Color` literals, `.font(.system(size:))` and `.padding(<number>)` fail the build there. Use `DS.Space` / `DS.Radius` / `DS.Motion`, or a trailing `// semantic:` / `// off-grid:` comment where a raw value is genuinely required. New files under `OnlyCue/UI/Workspace/` are **not** in the scanned list.
- **The 8pt sidebar inset is measured at runtime, never hardcoded.** The SwiftUI-reported sidebar width runs consistently 8pt under the `NSSplitView` divider position; derive the offset from the live pair. (spec §"Two caveats carried into the plan")
- **Commits:** Conventional Commits, lowercase after the prefix, imperative. No `Co-Authored-By` trailers, no attribution. Never bundle spec/plan files into implementation commits.
- **After adding any new source folder, re-run `xcodegen generate`.** `project.yml` uses folder-based `sources`, so new files are picked up automatically — but the `.xcodeproj` is not committed and must be regenerated.

---

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `OnlyCue/UI/Workspace/SidebarMetrics.swift` | The sidebar's 240/240/320 width contract, extracted from the literals at `DocumentView.swift:61`. Mirrors `CueListInspectorMetrics`. |
| `OnlyCue/UI/Workspace/PaneLayout.swift` | One mode's arrangement + the pure `clamped(toAvailableWidth:)` rule. |
| `OnlyCue/UI/Workspace/WorkspaceLayout.swift` | A named snapshot of all three modes' `PaneLayout`s. |
| `OnlyCue/App/WorkspaceLayoutStore.swift` | Presets, selected preset name, most-recent live layout; `UserDefaults` persistence under `"workspaceLayout.v1"`. |
| `OnlyCue/UI/Workspace/InspectorDivider.swift` | The draggable divider view. |
| `OnlyCue/UI/Workspace/SidebarWidthBridge.swift` | `NSViewRepresentable` probe: reads the live sidebar width and applies a target width via `NSSplitView.setPosition(_:ofDividerAt:)`. |
| `OnlyCue/UI/Workspace/WorkspaceNameSheet.swift` | The small name-prompt sheet reused by Save As… and Rename. |
| `OnlyCue/UI/Workspace/ManageWorkspacesSheet.swift` | Rename / delete list. |
| `OnlyCue/UI/Workspace/FrontmostWindowGate.swift` | Restricts broadcast menu notifications to the frontmost document window. |
| `OnlyCue/UI/DocumentView+Workspace.swift` | Notification receivers, sheet hosts, and the apply/save wiring that keeps `DocumentView.body` under the SwiftLint type-length cap. |
| `OnlyCueTests/PaneLayoutTests.swift` | Clamping + codability + the sidebar-inset arithmetic. |
| `OnlyCueTests/WorkspaceLayoutStoreTests.swift` | Persistence lifecycle. |
| `OnlyCueTests/WorkspaceLayoutTests.swift` | Per-mode subscript + JSON shape. |
| `OnlyCueTests/WorkspaceNameValidationTests.swift` | Empty / reserved / duplicate name rules. |
| `OnlyCueTests/FrontmostWindowGateTests.swift` | The window-scoping rule. |
| `OnlyCueUITests/WorkspaceLayoutUITests.swift` | Inspector collapse via `⌥⌘I`; the Workspace menu renders. |

**Modify:**

| File | Change |
|---|---|
| `OnlyCue/UI/DocumentView.swift:58-86` | Replace the fixed `HStack` with the width-driven one; add the `@SceneStorage` live layout and the `GeometryReader` that supplies available width. |
| `OnlyCue/UI/AppNotifications.swift` | Six new `Notification.Name`s. |
| `OnlyCue/App/AppCommands.swift:133+` | The `View ▸ Workspace` submenu and the `Hide/Show Inspector` item. |

**Why this shape:** everything workspace-specific lives under `OnlyCue/UI/Workspace/` except the store, which joins its siblings (`KeymapStore`, `MIDIMapStore`) in `OnlyCue/App/`. The `DocumentView+Workspace.swift` extension exists because `DocumentView` is already close to SwiftLint's `type_body_length` cap and every other sheet host in this codebase (`DocumentView+ManageTypes.swift`) uses the same split.

---

## Task 1: `SidebarMetrics` + `PaneLayout` + clamping

The pure value layer. No SwiftUI, no persistence — so decision 8 (clamp on apply, never rewrite) is testable without a window.

**Files:**
- Create: `OnlyCue/UI/Workspace/SidebarMetrics.swift`
- Create: `OnlyCue/UI/Workspace/PaneLayout.swift`
- Test: `OnlyCueTests/PaneLayoutTests.swift`

**Interfaces:**
- Consumes: `CueListInspectorMetrics.minWidth` (340), `.idealWidth` (360), `.maxWidth` (400) from `OnlyCue/UI/CueListInspectorMetrics.swift`.
- Produces:
  - `enum SidebarMetrics { static let minWidth: CGFloat; static let idealWidth: CGFloat; static let maxWidth: CGFloat }`
  - `struct PaneLayout: Codable, Equatable` with `var sidebarWidth: CGFloat`, `var isSidebarCollapsed: Bool`, `var inspectorWidth: CGFloat`, `var isInspectorCollapsed: Bool`, `static let default: PaneLayout`
  - `static let PaneLayout.centerMinimumWidth: CGFloat`
  - `func PaneLayout.clamped(toAvailableWidth available: CGFloat) -> PaneLayout`

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/PaneLayoutTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class PaneLayoutTests: XCTestCase {

    // MARK: - Defaults

    func test_default_matchesTheShippingWidths() {
        let layout = PaneLayout.default
        XCTAssertEqual(layout.sidebarWidth, SidebarMetrics.idealWidth)
        XCTAssertFalse(layout.isSidebarCollapsed)
        XCTAssertEqual(layout.inspectorWidth, CueListInspectorMetrics.idealWidth)
        XCTAssertFalse(layout.isInspectorCollapsed)
    }

    // MARK: - Clamping

    func test_clamped_atDesignWidth_isUnchanged() {
        // 240 sidebar + 680 center + 360 inspector = 1280 (Figma 318:1311).
        let layout = PaneLayout.default
        XCTAssertEqual(layout.clamped(toAvailableWidth: 1280), layout)
    }

    func test_clamped_justInsideTheCentreFloor_isUnchanged() {
        // 1180 available: 240 sidebar + 360 inspector leaves 580 for the
        // centre, above its 560 floor — so nothing gives.
        XCTAssertEqual(
            PaneLayout.default.clamped(toAvailableWidth: 1180),
            PaneLayout.default
        )
    }

    func test_clamped_slightlyNarrow_shrinksTheInspectorFirst() {
        // 1140 available: 240 + 360 leaves 540, 20pt short of the 560 floor,
        // so the inspector gives up exactly 20 (360 -> 340) and the sidebar
        // stays put.
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 1140)
        XCTAssertEqual(clamped.inspectorWidth, 340)
        XCTAssertFalse(clamped.isInspectorCollapsed)
        XCTAssertEqual(clamped.sidebarWidth, SidebarMetrics.idealWidth)
    }

    func test_clamped_belowTheInspectorMinimum_collapsesTheInspector() {
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 1100)
        XCTAssertTrue(clamped.isInspectorCollapsed)
        // The width is retained so re-showing restores the saved value.
        XCTAssertEqual(clamped.inspectorWidth, 340)
        XCTAssertFalse(clamped.isSidebarCollapsed)
    }

    func test_clamped_veryNarrow_thenShrinksTheSidebar() {
        // 760 available: inspector collapsed leaves 760 - 240 = 520 < 560,
        // so the sidebar gives up 40pt but stays above its 240 minimum only
        // by collapsing — 240 is already the floor, so it collapses.
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 760)
        XCTAssertTrue(clamped.isInspectorCollapsed)
        XCTAssertTrue(clamped.isSidebarCollapsed)
    }

    func test_clamped_neverGrowsAPane() {
        var wide = PaneLayout.default
        wide.inspectorWidth = 340
        XCTAssertEqual(wide.clamped(toAvailableWidth: 3000).inspectorWidth, 340)
    }

    func test_clamped_isIdempotent() {
        let once = PaneLayout.default.clamped(toAvailableWidth: 1100)
        XCTAssertEqual(once.clamped(toAvailableWidth: 1100), once)
    }

    func test_clamped_zeroAvailableWidth_doesNotProduceNegativeWidths() {
        let clamped = PaneLayout.default.clamped(toAvailableWidth: 0)
        XCTAssertGreaterThanOrEqual(clamped.sidebarWidth, 0)
        XCTAssertGreaterThanOrEqual(clamped.inspectorWidth, 0)
    }

    // MARK: - Codable

    func test_roundTrip_preservesEveryField() throws {
        var layout = PaneLayout.default
        layout.sidebarWidth = 300
        layout.isInspectorCollapsed = true
        let data = try JSONEncoder().encode(layout)
        XCTAssertEqual(try JSONDecoder().decode(PaneLayout.self, from: data), layout)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL to compile — `cannot find 'PaneLayout' in scope`, `cannot find 'SidebarMetrics' in scope`.

- [ ] **Step 3: Write `SidebarMetrics`**

Create `OnlyCue/UI/Workspace/SidebarMetrics.swift`:

```swift
import SwiftUI

/// Single source of truth for the item-list sidebar's width contract, extracted
/// from the literals that used to sit inline at `DocumentView.swift:61`. The
/// mirror of `CueListInspectorMetrics` on the other side of the window: with
/// workspace presets storing sidebar widths (#714), two places declaring the
/// bounds could disagree and let a stored preset clamp against a range the
/// window does not actually honour.
enum SidebarMetrics {
    /// 240 — the Figma 318:1311 sidebar width and the native ideal.
    static let minWidth: CGFloat = 240
    static let idealWidth: CGFloat = 240
    /// 320 — beyond this the 1280pt design width cannot seat a 560pt centre
    /// pane plus a 340pt inspector.
    static let maxWidth: CGFloat = 320
}
```

- [ ] **Step 4: Write `PaneLayout`**

Create `OnlyCue/UI/Workspace/PaneLayout.swift`:

```swift
import SwiftUI

/// One editor mode's pane arrangement. A pure value: no window, no AppKit, no
/// persistence — so the clamping rule (spec decision 8) is unit-testable.
///
/// Collapsed panes keep their width. Collapsing is a visibility flag, never a
/// width of zero, so `⌥⌘I` twice returns the inspector to the width it had and
/// clamping on a narrow window does not destroy the value the user chose on a
/// wide one.
struct PaneLayout: Codable, Equatable {

    var sidebarWidth: CGFloat
    var isSidebarCollapsed: Bool
    var inspectorWidth: CGFloat
    var isInspectorCollapsed: Bool

    static let `default` = PaneLayout(
        sidebarWidth: SidebarMetrics.idealWidth,
        isSidebarCollapsed: false,
        inspectorWidth: CueListInspectorMetrics.idealWidth,
        isInspectorCollapsed: false
    )
}

extension PaneLayout {

    /// The centre pane's floor, mirroring `DocumentView.mainPane`'s
    /// `.frame(minWidth: 560)`. Below this the waveform well and transport bar
    /// start clipping.
    static let centerMinimumWidth: CGFloat = 560

    /// The width each pane actually occupies right now.
    var effectiveSidebarWidth: CGFloat { isSidebarCollapsed ? 0 : sidebarWidth }
    var effectiveInspectorWidth: CGFloat { isInspectorCollapsed ? 0 : inspectorWidth }

    /// Fits this layout into `available` points of window width, shedding in a
    /// fixed order: shrink the inspector to its minimum, collapse the
    /// inspector, shrink the sidebar to its minimum, collapse the sidebar.
    ///
    /// Never widens a pane, and never mutates the stored preset — callers clamp
    /// a *copy* on apply (spec decision 8: "clamped on apply, never rewritten";
    /// rewriting would silently shrink the user's workspace forever the moment
    /// they undocked from an external display).
    func clamped(toAvailableWidth available: CGFloat) -> PaneLayout {
        var result = self

        func deficit() -> CGFloat {
            let used = result.effectiveSidebarWidth + result.effectiveInspectorWidth
            return Self.centerMinimumWidth - (available - used)
        }

        guard deficit() > 0 else { return result }

        if !result.isInspectorCollapsed {
            result.inspectorWidth = max(
                CueListInspectorMetrics.minWidth,
                result.inspectorWidth - deficit()
            )
            guard deficit() > 0 else { return result }
            result.isInspectorCollapsed = true
            guard deficit() > 0 else { return result }
        }

        if !result.isSidebarCollapsed {
            result.sidebarWidth = max(SidebarMetrics.minWidth, result.sidebarWidth - deficit())
            guard deficit() > 0 else { return result }
            result.isSidebarCollapsed = true
        }

        return result
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PaneLayoutTests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 9 tests passing.

- [ ] **Step 6: Lint**

```bash
swiftlint lint --strict
```
Expected: no violations. (`PaneLayout.swift` is not in the `TokenConformanceTests` scanned list, but SwiftLint's own rules still apply.)

- [ ] **Step 7: Commit**

```bash
git add OnlyCue/UI/Workspace/SidebarMetrics.swift OnlyCue/UI/Workspace/PaneLayout.swift \
        OnlyCueTests/PaneLayoutTests.swift
git commit -m "feat(workspace): add PaneLayout with pure clamping rule"
```

---

## Task 2: `WorkspaceLayout` + `WorkspaceLayoutStore`

The persistence layer. Follows `LTCRoutingStore` exactly.

**Files:**
- Create: `OnlyCue/UI/Workspace/WorkspaceLayout.swift`
- Create: `OnlyCue/App/WorkspaceLayoutStore.swift`
- Test: `OnlyCueTests/WorkspaceLayoutTests.swift`
- Test: `OnlyCueTests/WorkspaceLayoutStoreTests.swift`

**Interfaces:**
- Consumes: `PaneLayout` and `PaneLayout.default` (Task 1); `EditorMode` (`OnlyCue/UI/EditorMode.swift`, a `String`-raw-valued `CaseIterable, Codable` enum with cases `cue`, `lyric`, `show`).
- Produces:
  - `struct WorkspaceLayout: Codable, Equatable, Identifiable` with `var name: String`, `var id: String { name }`, `subscript(mode: EditorMode) -> PaneLayout { get set }`, `static let defaultName = "Default"`, `static let `default`: WorkspaceLayout`, `static func uniform(name:layout:) -> WorkspaceLayout`
  - `@MainActor final class WorkspaceLayoutStore: ObservableObject` with `static let shared`, `static let storageKey = "workspaceLayout.v1"`, `init(defaults: UserDefaults = .standard)`, `@Published private(set) var state: WorkspaceState`, and methods `save(_ layout: WorkspaceLayout)`, `overwrite(name:with:)`, `rename(_:to:)`, `delete(_:)`, `select(_:)`, `recordLiveLayout(_:)`, `resetToDefault()`, `reload()`
  - `struct WorkspaceState: Codable, Equatable` with `var presets: [WorkspaceLayout]`, `var selectedName: String?`, `var mostRecentLayout: WorkspaceLayout`

- [ ] **Step 1: Write the failing `WorkspaceLayout` test**

Create `OnlyCueTests/WorkspaceLayoutTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class WorkspaceLayoutTests: XCTestCase {

    func test_default_givesEveryModeTheDefaultPaneLayout() {
        let workspace = WorkspaceLayout.default
        XCTAssertEqual(workspace.name, WorkspaceLayout.defaultName)
        for mode in EditorMode.allCases {
            XCTAssertEqual(workspace[mode], .default, "mode \(mode.rawValue)")
        }
    }

    func test_subscript_storesPerMode() {
        var workspace = WorkspaceLayout.default
        var lyric = PaneLayout.default
        lyric.inspectorWidth = 400
        workspace[.lyric] = lyric

        XCTAssertEqual(workspace[.lyric].inspectorWidth, 400)
        XCTAssertEqual(workspace[.cue].inspectorWidth, CueListInspectorMetrics.idealWidth)
    }

    func test_subscript_unsetMode_fallsBackToTheDefaultPaneLayout() throws {
        // A preset persisted by an older build that only knew two modes must
        // not crash or return garbage for the third.
        let json = #"{"name":"Legacy","layoutsByMode":{}}"#
        let workspace = try JSONDecoder().decode(
            WorkspaceLayout.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(workspace[.show], .default)
    }

    func test_encodesLayoutsAsAJSONObject_notAnArray() throws {
        // `[EditorMode: PaneLayout]` would encode as a flat ARRAY, because the
        // key is neither String nor Int as far as JSONEncoder is concerned.
        // Keying by `EditorMode.rawValue` keeps the on-disk shape a readable
        // object — which matters because decision 4 keeps file export cheap
        // to add later.
        let data = try JSONEncoder().encode(WorkspaceLayout.default)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let byMode = try XCTUnwrap(object?["layoutsByMode"] as? [String: Any])
        XCTAssertEqual(Set(byMode.keys), Set(EditorMode.allCases.map(\.rawValue)))
    }

    func test_roundTrip() throws {
        var workspace = WorkspaceLayout.default
        workspace.name = "Focus"
        workspace[.show] = PaneLayout(
            sidebarWidth: 300,
            isSidebarCollapsed: true,
            inspectorWidth: 400,
            isInspectorCollapsed: false
        )
        let data = try JSONEncoder().encode(workspace)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceLayout.self, from: data), workspace)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate && xcodebuild build-for-testing -project OnlyCue.xcodeproj \
  -scheme OnlyCue -configuration Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL to compile — `cannot find 'WorkspaceLayout' in scope`.

- [ ] **Step 3: Write `WorkspaceLayout`**

Create `OnlyCue/UI/Workspace/WorkspaceLayout.swift`:

```swift
import SwiftUI

/// A named snapshot of the pane arrangement for every editor mode.
///
/// A preset is a snapshot, not a live binding (spec scope item 6): dragging a
/// divider after selecting "Focus" changes the window, never "Focus".
struct WorkspaceLayout: Codable, Equatable, Identifiable {

    var name: String

    /// Keyed by `EditorMode.rawValue`, not by `EditorMode`. `JSONEncoder`
    /// encodes a dictionary whose key is neither `String` nor `Int` as a flat
    /// ARRAY of alternating keys and values — legal JSON, but an opaque shape
    /// to anything that later reads these files.
    private var layoutsByMode: [String: PaneLayout]

    var id: String { name }

    static let defaultName = "Default"

    subscript(mode: EditorMode) -> PaneLayout {
        get { layoutsByMode[mode.rawValue] ?? .default }
        set { layoutsByMode[mode.rawValue] = newValue }
    }

    init(name: String, layoutsByMode: [String: PaneLayout]) {
        self.name = name
        self.layoutsByMode = layoutsByMode
    }

    /// A workspace giving every mode the same `layout`.
    static func uniform(name: String, layout: PaneLayout) -> WorkspaceLayout {
        WorkspaceLayout(
            name: name,
            layoutsByMode: Dictionary(
                uniqueKeysWithValues: EditorMode.allCases.map { ($0.rawValue, layout) }
            )
        )
    }

    /// The built-in preset. It can be neither renamed, overwritten nor deleted.
    static let `default` = WorkspaceLayout.uniform(name: defaultName, layout: .default)

    var isBuiltIn: Bool { name == Self.defaultName }
}
```

- [ ] **Step 4: Run the `WorkspaceLayout` tests**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/WorkspaceLayoutTests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 5 tests passing.

- [ ] **Step 5: Write the failing store test**

Create `OnlyCueTests/WorkspaceLayoutStoreTests.swift`:

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class WorkspaceLayoutStoreTests: XCTestCase {

    private let suiteName = "com.chienchuanw.OnlyCue.workspaceLayoutStoreTests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try super.tearDownWithError()
    }

    private func makeStore() -> WorkspaceLayoutStore {
        WorkspaceLayoutStore(defaults: defaults)
    }

    // MARK: - Fresh state

    func test_freshLaunch_holdsOnlyTheBuiltInDefault() {
        let store = makeStore()
        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
        XCTAssertEqual(store.state.mostRecentLayout, .default)
    }

    func test_corruptData_fallsBackToDefaultWithNoError() {
        defaults.set(Data("not json".utf8), forKey: WorkspaceLayoutStore.storageKey)
        let store = makeStore()
        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
    }

    // MARK: - Save / select

    func test_save_addsThePresetAndSelectsIt() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        focus[.lyric] = PaneLayout(
            sidebarWidth: 300,
            isSidebarCollapsed: false,
            inspectorWidth: 400,
            isInspectorCollapsed: false
        )
        store.save(focus)

        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Focus"])
        XCTAssertEqual(store.state.selectedName, "Focus")
    }

    func test_save_persistsAcrossStoreInstances() {
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        focus[.show] = PaneLayout(
            sidebarWidth: 320,
            isSidebarCollapsed: false,
            inspectorWidth: 340,
            isInspectorCollapsed: true
        )
        makeStore().save(focus)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.state.presets.count, 2)
        XCTAssertEqual(reloaded.state.presets[1][.show].inspectorWidth, 340)
        XCTAssertTrue(reloaded.state.presets[1][.show].isInspectorCollapsed)
        XCTAssertEqual(reloaded.state.selectedName, "Focus")
    }

    func test_save_withAnExistingName_replacesRatherThanDuplicates() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        focus[.cue].inspectorWidth = 400
        store.save(focus)

        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Focus"])
        XCTAssertEqual(store.state.presets[1][.cue].inspectorWidth, 400)
    }

    // MARK: - The built-in preset is protected

    func test_delete_refusesTheBuiltInDefault() {
        let store = makeStore()
        store.delete(WorkspaceLayout.defaultName)
        XCTAssertEqual(store.state.presets, [.default])
    }

    func test_overwrite_refusesTheBuiltInDefault() {
        let store = makeStore()
        var mutated = PaneLayout.default
        mutated.inspectorWidth = 400
        store.overwrite(name: WorkspaceLayout.defaultName,
                        with: .uniform(name: WorkspaceLayout.defaultName, layout: mutated))
        XCTAssertEqual(store.state.presets, [.default])
    }

    func test_rename_refusesTheBuiltInDefault() {
        let store = makeStore()
        store.rename(WorkspaceLayout.defaultName, to: "Mine")
        XCTAssertEqual(store.state.presets.map(\.name), ["Default"])
    }

    // MARK: - Rename / delete

    func test_rename_movesThePresetAndFollowsTheSelection() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        store.rename("Focus", to: "Tight")

        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Tight"])
        XCTAssertEqual(store.state.selectedName, "Tight")
    }

    func test_rename_toAnExistingName_isRefused() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        var wide = WorkspaceLayout.default
        wide.name = "Wide"
        store.save(wide)

        store.rename("Focus", to: "Wide")
        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Focus", "Wide"])
    }

    func test_delete_removesThePresetAndClearsTheSelection() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        store.delete("Focus")

        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
    }

    // MARK: - Live layout

    func test_recordLiveLayout_doesNotTouchTheSelectedPreset() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)

        var dragged = focus
        dragged[.cue].inspectorWidth = 400
        store.recordLiveLayout(dragged)

        XCTAssertEqual(store.state.mostRecentLayout[.cue].inspectorWidth, 400)
        XCTAssertEqual(store.state.presets[1][.cue].inspectorWidth,
                       CueListInspectorMetrics.idealWidth,
                       "a drag must never rewrite the selected preset (spec scenario: snapshot, not live binding)")
        XCTAssertEqual(store.state.selectedName, "Focus")
    }

    func test_recordLiveLayout_survivesRelaunchSoNewWindowsInheritIt() {
        var dragged = WorkspaceLayout.default
        dragged[.cue].isInspectorCollapsed = true
        makeStore().recordLiveLayout(dragged)

        XCTAssertTrue(makeStore().state.mostRecentLayout[.cue].isInspectorCollapsed)
    }

    func test_recordLiveLayout_withNoChange_doesNotRepersist() {
        let store = makeStore()
        store.recordLiveLayout(.default)
        let before = defaults.data(forKey: WorkspaceLayoutStore.storageKey)
        store.recordLiveLayout(.default)
        XCTAssertEqual(defaults.data(forKey: WorkspaceLayoutStore.storageKey), before)
    }

    // MARK: - Reset

    func test_resetToDefault_clearsPresetsAndSelection() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        store.resetToDefault()

        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
        XCTAssertEqual(store.state.mostRecentLayout, .default)
    }
}
```

- [ ] **Step 6: Run it to verify it fails**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL to compile — `cannot find 'WorkspaceLayoutStore' in scope`.

- [ ] **Step 7: Write `WorkspaceLayoutStore`**

Create `OnlyCue/App/WorkspaceLayoutStore.swift`:

```swift
import Foundation

/// Everything persisted under `"workspaceLayout.v1"`.
struct WorkspaceState: Codable, Equatable {
    var presets: [WorkspaceLayout]
    var selectedName: String?
    /// The arrangement the frontmost window last had, so a brand-new window
    /// inherits it rather than the factory default (spec scope item 7).
    var mostRecentLayout: WorkspaceLayout

    static let `default` = WorkspaceState(
        presets: [.default],
        selectedName: nil,
        mostRecentLayout: .default
    )
}

/// App-level workspace preset storage. Layout is the person's habit, not the
/// work's content, so it lives in `UserDefaults` and never in `ProjectModel` —
/// storing it in the document would dirty the file, enter the undo stack and
/// require a schema bump (spec decision 3).
///
/// Mirrors `LTCRoutingStore` / `KeymapStore` / `MIDIMapStore`: `shared`
/// singleton, injectable `UserDefaults` for tests, versioned JSON under one
/// key, `.default` on any decode failure.
@MainActor
final class WorkspaceLayoutStore: ObservableObject {

    static let storageKey = "workspaceLayout.v1"
    static let shared = WorkspaceLayoutStore()

    @Published private(set) var state: WorkspaceState

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    /// The preset currently selected, or nil when the live layout has diverged
    /// from every preset (or none was ever chosen).
    var selectedPreset: WorkspaceLayout? {
        guard let name = state.selectedName else { return nil }
        return state.presets.first { $0.name == name }
    }

    // MARK: - Mutations

    /// Adds `layout` (replacing any preset of the same name) and selects it.
    func save(_ layout: WorkspaceLayout) {
        var next = state
        if let index = next.presets.firstIndex(where: { $0.name == layout.name }) {
            next.presets[index] = layout
        } else {
            next.presets.append(layout)
        }
        next.selectedName = layout.name
        next.mostRecentLayout = layout
        apply(next)
    }

    /// Replaces an existing preset's contents in place, keeping its position.
    /// Refused for the built-in `Default`.
    func overwrite(name: String, with layout: WorkspaceLayout) {
        guard name != WorkspaceLayout.defaultName else { return }
        guard let index = state.presets.firstIndex(where: { $0.name == name }) else { return }
        var next = state
        var replacement = layout
        replacement.name = name
        next.presets[index] = replacement
        next.selectedName = name
        next.mostRecentLayout = replacement
        apply(next)
    }

    /// Refused for the built-in `Default` and for a name already in use.
    func rename(_ name: String, to newName: String) {
        guard name != WorkspaceLayout.defaultName else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != WorkspaceLayout.defaultName else { return }
        guard !state.presets.contains(where: { $0.name == trimmed }) else { return }
        guard let index = state.presets.firstIndex(where: { $0.name == name }) else { return }

        var next = state
        next.presets[index].name = trimmed
        if next.selectedName == name { next.selectedName = trimmed }
        apply(next)
    }

    /// Refused for the built-in `Default`.
    func delete(_ name: String) {
        guard name != WorkspaceLayout.defaultName else { return }
        var next = state
        next.presets.removeAll { $0.name == name }
        if next.selectedName == name { next.selectedName = nil }
        apply(next)
    }

    func select(_ name: String?) {
        var next = state
        next.selectedName = name
        apply(next)
    }

    /// Records the frontmost window's current arrangement. Deliberately does
    /// NOT touch `presets` — a preset is a snapshot, so dragging a divider
    /// after selecting one must leave that preset byte-identical.
    func recordLiveLayout(_ layout: WorkspaceLayout) {
        var next = state
        next.mostRecentLayout = layout
        apply(next)
    }

    func resetToDefault() {
        apply(.default)
    }

    func reload() {
        state = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    // MARK: - Persistence

    private func apply(_ newState: WorkspaceState) {
        guard newState != state else { return }
        state = newState
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func decode(_ data: Data?) -> WorkspaceState {
        guard let data else { return .default }
        guard var decoded = try? JSONDecoder().decode(WorkspaceState.self, from: data) else {
            return .default
        }
        // The built-in Default is guaranteed present and first, even if an
        // older build or hand-edited defaults dropped it.
        decoded.presets.removeAll { $0.name == WorkspaceLayout.defaultName }
        decoded.presets.insert(.default, at: 0)
        return decoded
    }
}
```

- [ ] **Step 8: Run the store tests to verify they pass**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/WorkspaceLayoutStoreTests \
  -only-testing:OnlyCueTests/WorkspaceLayoutTests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 20 tests passing.

- [ ] **Step 9: Lint and commit**

```bash
swiftlint lint --strict
git add OnlyCue/UI/Workspace/WorkspaceLayout.swift OnlyCue/App/WorkspaceLayoutStore.swift \
        OnlyCueTests/WorkspaceLayoutTests.swift OnlyCueTests/WorkspaceLayoutStoreTests.swift
git commit -m "feat(workspace): persist named layout presets in UserDefaults"
```

---

## Task 3: Draggable inspector divider + collapse, wired into `DocumentView`

The first user-visible deliverable, and the one that has to clear the #617 wall. After this task the inspector resizes by drag and hides with `⌥⌘I`, but nothing is saved yet beyond the per-window `@SceneStorage`.

**Files:**
- Create: `OnlyCue/UI/Workspace/InspectorDivider.swift`
- Modify: `OnlyCue/UI/DocumentView.swift:58-86` (the `body`'s `NavigationSplitView`) and the `@SceneStorage` block around line 26
- Modify: `OnlyCue/UI/AppNotifications.swift`
- Modify: `OnlyCue/App/AppCommands.swift` (the `CommandGroup(after: .sidebar)` starting line 133)
- Test: `OnlyCueUITests/WorkspaceLayoutUITests.swift`

**Interfaces:**
- Consumes: `PaneLayout`, `SidebarMetrics`, `CueListInspectorMetrics`, `DS.Space`.
- Produces:
  - `struct InspectorDivider: View { init(width: Binding<CGFloat>) }`
  - `Notification.Name.toggleInspectorRequested`
  - On `DocumentView`: `var liveLayout: WorkspaceLayout { get }` and `func updateLiveLayout(_ transform: (inout PaneLayout) -> Void)`, both backed by `@SceneStorage("onlycue.workspaceLayout")`.

- [ ] **Step 1: Write the failing UI test**

Create `OnlyCueUITests/WorkspaceLayoutUITests.swift`:

```swift
import XCTest

/// Phase-A workspace behaviour that is only observable through the running
/// window: the inspector's collapse toggle and the View ▸ Workspace submenu.
/// Divider *dragging* is exercised by hand (the spec's outstanding manual
/// check) — a synthetic drag on a 1pt hit area is flaky enough to be worse
/// than no coverage.
final class WorkspaceLayoutUITests: OnlyCueUITestCase {

    /// Scenario: Hiding the inspector
    ///   Given the inspector is visible
    ///   When the designer presses ⌥⌘I
    ///   Then the inspector is removed from the layout
    ///   And pressing ⌥⌘I again restores it
    func test_optionCommandI_togglesTheInspector() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)

        let inspector = app.otherElements["cueListInspector"]
        XCTAssertTrue(
            inspector.waitForExistence(timeout: 10),
            "the inspector should be visible on a seeded document"
        )

        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(
            waitForDisappearance(of: inspector, timeout: 5),
            "⌥⌘I should hide the inspector"
        )

        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(
            inspector.waitForExistence(timeout: 5),
            "⌥⌘I should restore the inspector"
        )
    }

    /// The divider is present and exposes its width to accessibility, so a
    /// VoiceOver user can tell how wide the inspector is.
    func test_inspectorDivider_isExposedToAccessibility() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        let divider = app.otherElements["inspectorDivider"]
        XCTAssertTrue(divider.waitForExistence(timeout: 10))
        XCTAssertFalse(divider.label.isEmpty, "the divider needs an accessibility label")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
```

**Before writing it, verify the identifiers exist.** `cueListInspector` is assumed here; run

```bash
grep -rn "accessibilityIdentifier(\"cueListInspector" OnlyCue/UI/
```

If it returns nothing, add `.accessibilityIdentifier("cueListInspector")` to the root of `ModeAwareInspector`'s body in `OnlyCue/UI/ModeAwareInspector.swift` as part of Step 5. Do **not** invent a different name — the UI test and the view must agree.

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/WorkspaceLayoutUITests -parallel-testing-enabled NO 2>&1 | tail -30
```
Expected: FAIL — `⌥⌘I should hide the inspector` (no such menu item yet), and `inspectorDivider` never exists.

**If instead you see `Timed out while enabling automation mode` (~64s in):** that is a known machine-level wedge on this Mac, not your change. Retry once; if it recurs, note it, proceed on the unit tests alone, and flag it to the maintainer — `sudo xcodebuild -runFirstLaunch` is the untried remedy and needs their sudo. UI tests do not run on PRs in this repo (only on `dev`/`main` pushes), so a wedged local runner means this task's UI coverage is genuinely unverified until it lands.

- [ ] **Step 3: Add the notification names**

In `OnlyCue/UI/AppNotifications.swift`, after the existing `exportMA2PluginRequested` line, add:

```swift
    // MARK: - Workspace (#714)

    static let toggleInspectorRequested = Notification.Name("OnlyCue.toggleInspectorRequested")
    static let workspaceSelected = Notification.Name("OnlyCue.workspaceSelected")
    static let workspaceSaveAsRequested = Notification.Name("OnlyCue.workspaceSaveAsRequested")
    static let workspaceOverwriteRequested = Notification.Name("OnlyCue.workspaceOverwriteRequested")
    static let manageWorkspacesRequested = Notification.Name("OnlyCue.manageWorkspacesRequested")
    static let workspaceResetRequested = Notification.Name("OnlyCue.workspaceResetRequested")
```

Only `toggleInspectorRequested` is consumed in this task; the rest land in Task 5. They are declared together so the file has one workspace section rather than two.

- [ ] **Step 4: Write `InspectorDivider`**

Create `OnlyCue/UI/Workspace/InspectorDivider.swift`:

```swift
import AppKit
import SwiftUI

/// The draggable divider between the centre pane and the inspector.
///
/// Deliberately a plain SwiftUI `Divider()` with a gesture, NOT an
/// `HSplitView` or `.inspector`: any `NSSplitView`-backed split in the detail
/// column double-counts the sidebar into the window's minimum width and pins
/// the populated window at 1416pt, past the 1280pt design width (#617). The
/// gesture writes a width into state, which feeds the existing frame contract
/// — no AppKit split view is involved, so that mechanism cannot re-engage.
struct InspectorDivider: View {

    @Binding var width: CGFloat

    /// The width when the current drag began. `DragGesture.translation` is
    /// cumulative from the drag's start, so adding it to the *live* width each
    /// frame would compound and make the divider run away from the cursor.
    @State private var dragStartWidth: CGFloat?

    /// A 1pt line is far too small a target. The hit area is widened to
    /// `DS.Space.md` (12pt) around it — the standard macOS splitter tolerance
    /// — without changing the layout, because the overlay does not participate
    /// in sizing.
    private var hitArea: some View {
        Color.clear
            .frame(width: DS.Space.md)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(dragGesture)
    }

    /// `minimumDistance: 1`, not 0: a 0pt minimum makes the divider swallow
    /// plain clicks that land in the widened hit area, which overlaps the
    /// waveform's click-to-seek target (project CLAUDE.md's SwiftUI gesture
    /// caution). 1pt still feels instant while letting a click through.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStartWidth ?? width
                if dragStartWidth == nil { dragStartWidth = start }
                // Dragging LEFT (negative translation) widens the inspector,
                // because the inspector is the right-hand pane.
                width = min(
                    max(start - value.translation.width, CueListInspectorMetrics.minWidth),
                    CueListInspectorMetrics.maxWidth
                )
            }
            .onEnded { _ in dragStartWidth = nil }
    }

    var body: some View {
        Divider()
            .overlay(hitArea)
            .accessibilityElement()
            .accessibilityIdentifier("inspectorDivider")
            .accessibilityLabel("Inspector width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAddTraits(.isButton)
    }
}
```

- [ ] **Step 5: Wire it into `DocumentView`**

In `OnlyCue/UI/DocumentView.swift`, add the live-layout storage next to the existing `@SceneStorage` declarations (after line 27's `showGoTypeIDRaw`):

```swift
    /// The window's live pane arrangement, per editor mode. `@SceneStorage`
    /// (not `@AppStorage`): layout is a window-level property, so two open
    /// documents keep independent arrangements and macOS restores each window's
    /// own across relaunch (spec decision 9).
    @SceneStorage("onlycue.workspaceLayout") private var liveLayoutData = ""
```

Then add to the `extension DocumentView` block at the bottom of the file:

```swift
extension DocumentView {

    /// The window's live arrangement, decoded from scene storage. Falls back to
    /// the store's most-recent layout so a brand-new window inherits how the
    /// last one looked rather than the factory default (spec scope item 7).
    var liveLayout: WorkspaceLayout {
        guard let data = liveLayoutData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WorkspaceLayout.self, from: data)
        else { return WorkspaceLayoutStore.shared.state.mostRecentLayout }
        return decoded
    }

    /// The current mode's pane widths.
    var currentPaneLayout: PaneLayout { liveLayout[editorMode] }

    /// Mutates the current mode's arrangement and records it as the most recent
    /// layout. Records — never writes back into the selected preset: a preset
    /// is a snapshot, so dragging a divider must leave it byte-identical.
    func updateLiveLayout(_ transform: (inout PaneLayout) -> Void) {
        var workspace = liveLayout
        var pane = workspace[editorMode]
        transform(&pane)
        workspace[editorMode] = pane
        setLiveLayout(workspace)
    }

    func setLiveLayout(_ workspace: WorkspaceLayout) {
        guard let data = try? JSONEncoder().encode(workspace),
              let json = String(data: data, encoding: .utf8)
        else { return }
        liveLayoutData = json
        WorkspaceLayoutStore.shared.recordLiveLayout(workspace)
    }

    /// A binding the divider can drive directly.
    var inspectorWidthBinding: Binding<CGFloat> {
        Binding(
            get: { currentPaneLayout.inspectorWidth },
            set: { newValue in updateLiveLayout { $0.inspectorWidth = newValue } }
        )
    }
}
```

Replace the `detail:` closure at `DocumentView.swift:62-86` with:

```swift
        } detail: {
            // Plain HStack, NOT `.inspector` or `HSplitView` (#617): any
            // NSSplitView-backed split inside the detail column double-counts
            // the sidebar into the window's minimum width (~+249pt) and holds
            // the inspector at its ideal/max instead of its minimum, pinning
            // the populated window at 1416pt — past the 1280pt design width.
            // Verified empirically by bisecting all pane content to
            // `Color.clear`. The divider below restores the drag that comment
            // named as the only casualty, WITHOUT restoring the split view:
            // the gesture writes a width into scene storage, which feeds the
            // same frame contract that was already here (#714).
            HStack(spacing: 0) {
                mainPane
                if !currentPaneLayout.isInspectorCollapsed {
                    InspectorDivider(width: inspectorWidthBinding)
                    ModeAwareInspector(
                        document: document,
                        engine: engine,
                        editorMode: editorMode,
                        cueSelection: $cueSelection,
                        lyricsCursor: $lyricsCursor
                    )
                    .frame(width: currentPaneLayout.inspectorWidth)
                    .accessibilityIdentifier("cueListInspector")
                }
            }
            .animation(DS.Motion.quick, value: currentPaneLayout.isInspectorCollapsed)
        }
```

and add, next to the other `.onReceive` modifiers on `body`:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspectorRequested)) { _ in
            updateLiveLayout { $0.isInspectorCollapsed.toggle() }
        }
```

**Note the width change:** `.cueListInspectorPaneWidth()` (min/ideal/max) becomes a fixed `.frame(width:)`. That raises the window's `contentMinSize` from a measured 1149 to ~1209, and to ~1249 at a 400pt inspector — still under 1280, but with less headroom. Step 8 verifies it.

`cueListInspectorPaneWidth()` becomes unused by `DocumentView` but stays in the codebase: `CueListInspectorMetricsTests` covers it and `CueListPane.minPaneWidth` still resolves through the same enum. Do not delete it.

- [ ] **Step 6: Add the menu item**

In `OnlyCue/App/AppCommands.swift`, inside `CommandGroup(after: .sidebar)`, after the `Show Mode` button and its following `Divider()` (around line 168):

```swift
            Button("Hide Inspector") {
                NotificationCenter.default.post(name: .toggleInspectorRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .accessibilityIdentifier("toggleInspectorMenuItem")

            Divider()
```

The title stays "Hide Inspector" rather than flipping to "Show Inspector": the collapse state lives in the frontmost window's scene storage, which `AppCommands` cannot read, and a title that lies half the time is worse than a static one that toggles. `⌥⌘I` matches Xcode's inspector shortcut.

- [ ] **Step 7: Run the UI test to verify it passes**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/WorkspaceLayoutUITests -parallel-testing-enabled NO 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **`, 2 tests passing.

- [ ] **Step 8: Verify the #617 guard is still green — this is the gate for the whole feature**

```bash
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/DocumentWindowMinWidthUITests -parallel-testing-enabled NO 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` — the populated window is ≤ 1280pt.

**If it fails, stop.** Do not widen the assertion and do not proceed to Task 4. The likely cause is the fixed-width inspector's higher `contentMinSize`; the fix is to keep a `minWidth:` floor on the inspector frame rather than pinning it:

```swift
                    .frame(
                        minWidth: CueListInspectorMetrics.minWidth,
                        idealWidth: currentPaneLayout.inspectorWidth,
                        maxWidth: currentPaneLayout.inspectorWidth
                    )
```

Re-run this step after any such change.

- [ ] **Step 9: Manually verify the drag, then lint and commit**

Launch the app (`open OnlyCue.xcodeproj`, ⌘R) and confirm by hand:
- the cursor becomes a left-right resize arrow over the divider;
- dragging widens/narrows the inspector and stops at 340 and 400;
- a single click on the waveform still seeks (the divider's hit area must not have swallowed it);
- ⌥⌘I hides and restores the inspector at the width it had.

```bash
swiftlint lint --strict
git add OnlyCue/UI/Workspace/InspectorDivider.swift OnlyCue/UI/DocumentView.swift \
        OnlyCue/UI/AppNotifications.swift OnlyCue/App/AppCommands.swift \
        OnlyCueUITests/WorkspaceLayoutUITests.swift
git commit -m "feat(workspace): make the inspector divider draggable and collapsible"
```

---

## Task 4: Sidebar width bridge — read the dragged width, apply a preset's width

`NavigationSplitView`'s sidebar is already draggable natively within 240–320. What SwiftUI offers no API for is (a) reading back the width the user dragged to, and (b) setting it imperatively when a preset is applied. The spike (spec §"Resolved risk") settled the approach: read via `GeometryReader`, write via `NSSplitView.setPosition(_:ofDividerAt:)` from an `NSViewRepresentable` probe.

**Before starting this task**, do the manual check the spec leaves outstanding: in the shipping app on `dev`, drag the sidebar divider, resize the window, drag it again. Confirm it works today. Without that baseline you cannot tell whether a later regression is yours.

**Files:**
- Create: `OnlyCue/UI/Workspace/SidebarWidthBridge.swift`
- Modify: `OnlyCue/UI/DocumentView.swift` (the `NavigationSplitView` sidebar closure, line 59-61)

**Interfaces:**
- Consumes: `SidebarMetrics`; `DocumentView.updateLiveLayout(_:)` and `.currentPaneLayout` (Task 3).
- Produces:
  - `struct SidebarWidthBridge: NSViewRepresentable { init(targetWidth: CGFloat?, onMeasure: @escaping (CGFloat) -> Void) }` — a zero-size view placed in the sidebar. When `targetWidth` is non-nil and differs from the measured width it applies it once; it reports the measured width through `onMeasure`.
  - `extension View { func sidebarWidthBridge(targetWidth: CGFloat?, onMeasure: @escaping (CGFloat) -> Void) -> some View }`

- [ ] **Step 1: Write the failing test**

The bridge's *AppKit* half cannot be unit-tested without a hosted window, but its arithmetic can. Add to `OnlyCueTests/PaneLayoutTests.swift`:

```swift
    // MARK: - Sidebar inset (#714, spike caveat)

    func test_dividerPosition_derivesTheInsetFromTheLivePair_ratherThanHardcodingIt() {
        // The SwiftUI-reported sidebar width runs consistently under the
        // NSSplitView divider position (240<->248, 292<->300, 257<->265 in the
        // spike). The offset is derived from whatever pair is observed live,
        // never assumed to be 8 — a future SwiftUI release may change it.
        let inset = SidebarWidthBridge.inset(measuredWidth: 292, dividerPosition: 300)
        XCTAssertEqual(inset, 8)
        XCTAssertEqual(
            SidebarWidthBridge.dividerPosition(forTargetWidth: 320, inset: inset),
            328
        )
    }

    func test_dividerPosition_withNoObservedPair_appliesTheTargetUnadjusted() {
        // Before the first measurement there is no pair to derive from.
        // Applying the raw target is off by the inset for one frame, then the
        // measurement arrives and it settles — better than baking in a guess.
        XCTAssertEqual(
            SidebarWidthBridge.dividerPosition(forTargetWidth: 300, inset: nil),
            300
        )
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate && xcodebuild build-for-testing -project OnlyCue.xcodeproj \
  -scheme OnlyCue -configuration Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL to compile — `cannot find 'SidebarWidthBridge' in scope`.

- [ ] **Step 3: Write `SidebarWidthBridge`**

Create `OnlyCue/UI/Workspace/SidebarWidthBridge.swift`:

```swift
import AppKit
import SwiftUI

/// Reads and writes the `NavigationSplitView` sidebar's width.
///
/// SwiftUI gives the sidebar a native drag within
/// `.navigationSplitViewColumnWidth(min:ideal:max:)` but no way to read the
/// dragged value back or to set it when a workspace preset is applied. This
/// probe closes both gaps: a zero-size `NSView` placed in the sidebar walks up
/// its superview chain to the hosting `NSSplitView` (seven levels up, delegate
/// `SwiftUI.NavigationSplitViewController`) and calls
/// `setPosition(_:ofDividerAt:)`.
///
/// It writes the divider position and **nothing else** — no delegate is
/// installed and no constraint participation changes — so the #617 mechanism
/// (an `NSSplitView` in the *detail* column inflating the window minimum) has
/// nothing to re-engage. The spike measured `contentMinSize` at 1149 with this
/// in place, well under the 1280pt design width.
struct SidebarWidthBridge: NSViewRepresentable {

    /// The width a preset wants applied, or nil when the user is in charge.
    var targetWidth: CGFloat?
    /// Reports the sidebar's live width after every layout pass.
    var onMeasure: (CGFloat) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onMeasure = onMeasure
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onMeasure = onMeasure
        view.apply(targetWidth: targetWidth)
    }

    // MARK: - Arithmetic (unit-tested)

    /// The constant gap between the SwiftUI-reported sidebar width and the
    /// `NSSplitView` divider position. Derived from an observed pair, never
    /// hardcoded — the spike saw 8pt consistently, but that is SwiftUI's
    /// internal inset and is not contractual.
    static func inset(measuredWidth: CGFloat, dividerPosition: CGFloat) -> CGFloat {
        dividerPosition - measuredWidth
    }

    /// The divider position that yields `targetWidth` of visible sidebar.
    static func dividerPosition(forTargetWidth targetWidth: CGFloat, inset: CGFloat?) -> CGFloat {
        targetWidth + (inset ?? 0)
    }

    // MARK: - Probe

    final class ProbeView: NSView {

        var onMeasure: ((CGFloat) -> Void)?

        /// The inset derived from the most recent (measured width, divider
        /// position) pair. nil until the first layout pass.
        private var observedInset: CGFloat?
        /// The last target actually applied, so a re-render does not fight the
        /// user's subsequent drag by re-applying the same value every frame.
        private var appliedTarget: CGFloat?

        /// The hosting split view, or nil if SwiftUI's view hierarchy changed
        /// shape. Everything here degrades to a no-op in that case — the
        /// sidebar keeps its native drag and only preset application is lost.
        private var hostingSplitView: NSSplitView? {
            var candidate: NSView? = superview
            while let view = candidate {
                if let split = view as? NSSplitView { return split }
                candidate = view.superview
            }
            return nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            measure()
        }

        override func layout() {
            super.layout()
            measure()
        }

        private func measure() {
            guard let split = hostingSplitView,
                  let sidebar = split.arrangedSubviews.first
            else { return }
            let position = sidebar.frame.width
            // The probe sits inside the sidebar, so its own enclosing scroll /
            // content view reports the *visible* width SwiftUI lays out to.
            let measured = enclosingContentWidth ?? position
            observedInset = SidebarWidthBridge.inset(
                measuredWidth: measured,
                dividerPosition: position
            )
            onMeasure?(measured)
        }

        private var enclosingContentWidth: CGFloat? {
            var candidate: NSView? = superview
            while let view = candidate {
                if view is NSSplitView { return nil }
                if view.frame.width > 0 { return view.frame.width }
                candidate = view.superview
            }
            return nil
        }

        func apply(targetWidth: CGFloat?) {
            guard let targetWidth, targetWidth != appliedTarget else {
                if targetWidth == nil { appliedTarget = nil }
                return
            }
            guard let split = hostingSplitView, !split.arrangedSubviews.isEmpty else { return }
            appliedTarget = targetWidth
            let position = SidebarWidthBridge.dividerPosition(
                forTargetWidth: targetWidth,
                inset: observedInset
            )
            split.setPosition(position, ofDividerAt: 0)
        }
    }
}

extension View {
    /// Attaches the sidebar width probe as a zero-size background. A background
    /// (not an overlay or a sibling) so it can never intercept a click or take
    /// part in layout.
    func sidebarWidthBridge(
        targetWidth: CGFloat?,
        onMeasure: @escaping (CGFloat) -> Void
    ) -> some View {
        background(
            SidebarWidthBridge(targetWidth: targetWidth, onMeasure: onMeasure)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
```

- [ ] **Step 4: Run the arithmetic tests to verify they pass**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/PaneLayoutTests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 11 tests passing.

- [ ] **Step 5: Wire the bridge into `DocumentView`'s sidebar**

Add to the `extension DocumentView` from Task 3:

```swift
    /// The sidebar width a preset wants applied, or nil while the user is in
    /// charge. Set for one apply cycle by `applyWorkspace(_:)` (Task 5) and
    /// cleared as soon as the measurement confirms it landed, so a later native
    /// drag is never fought.
    var pendingSidebarWidth: CGFloat? {
        get { pendingSidebarWidthValue < 0 ? nil : pendingSidebarWidthValue }
        nonmutating set { pendingSidebarWidthValue = newValue ?? -1 }
    }
```

with the backing state declared alongside the other `@State` properties near the top of `DocumentView`:

```swift
    /// -1 means "no pending apply". A sentinel rather than `CGFloat?` because
    /// `@State` of an optional here reads worse at every call site than one
    /// impossible width does.
    @State private var pendingSidebarWidthValue: CGFloat = -1
```

Then replace `DocumentView.swift:59-61`'s sidebar closure with:

```swift
        NavigationSplitView {
            ItemListPane(document: document, onDropURLs: importURLs)
                .navigationSplitViewColumnWidth(
                    min: SidebarMetrics.minWidth,
                    ideal: SidebarMetrics.idealWidth,
                    max: SidebarMetrics.maxWidth
                )
                .sidebarWidthBridge(targetWidth: pendingSidebarWidth) { measured in
                    if let pending = pendingSidebarWidth,
                       abs(measured - pending) < 1 {
                        pendingSidebarWidth = nil
                    }
                    updateLiveLayout { $0.sidebarWidth = measured }
                }
        } detail: {
```

Note the literal `240 / 240 / 320` at line 61 are now `SidebarMetrics` constants — that extraction is the whole reason `SidebarMetrics` exists.

- [ ] **Step 6: Build and run the full unit suite**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` — the whole existing suite (1298+ tests) plus the new ones.

- [ ] **Step 7: Verify the #617 guard again**

```bash
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/DocumentWindowMinWidthUITests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Manual verification — the check the spike could not automate**

Launch the app and confirm:
- the sidebar still drags natively between 240 and 320;
- after resizing the window, dragging the sidebar still works and behaves identically;
- the dragged width is remembered when you switch editor modes and switch back;
- reopening the app restores the sidebar width.

If native dragging has stopped working, the probe is the only new thing in that view — check that `apply(targetWidth:)` is not being called on every layout pass with a stale value (`appliedTarget` guards this) before changing anything else.

- [ ] **Step 9: Lint and commit**

```bash
swiftlint lint --strict
git add OnlyCue/UI/Workspace/SidebarWidthBridge.swift OnlyCue/UI/DocumentView.swift \
        OnlyCueTests/PaneLayoutTests.swift
git commit -m "feat(workspace): capture and restore the sidebar width"
```

---

## Task 5: `View ▸ Workspace` menu + apply / save wiring

The menu, and the code that applies a preset to the frontmost window with clamping.

**Files:**
- Create: `OnlyCue/UI/DocumentView+Workspace.swift`
- Modify: `OnlyCue/App/AppCommands.swift`
- Test: extend `OnlyCueUITests/WorkspaceLayoutUITests.swift`

**Interfaces:**
- Consumes: `WorkspaceLayoutStore.shared`, `WorkspaceLayout`, `PaneLayout.clamped(toAvailableWidth:)`, `DocumentView.setLiveLayout(_:)` / `.liveLayout` / `.pendingSidebarWidth` (Tasks 2–4), and the notification names added in Task 3.
- Produces:
  - `extension View { func workspaceMenuReceiver(...) -> some View }` — hosts every workspace notification receiver.
  - On `DocumentView`: `func applyWorkspace(_ workspace: WorkspaceLayout, availableWidth: CGFloat)`, `func captureCurrentWorkspace(named:) -> WorkspaceLayout`.
  - `@State private var availableDetailWidth: CGFloat` on `DocumentView`, fed by a `GeometryReader`.

- [ ] **Step 1: Write the failing UI test**

Append to `OnlyCueUITests/WorkspaceLayoutUITests.swift`:

```swift
extension WorkspaceLayoutUITests {

    /// Scenario: the Workspace submenu is reachable and lists the built-in
    /// Default preset with the lifecycle commands.
    func test_viewMenu_exposesTheWorkspaceSubmenu() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        XCTAssertTrue(app.staticTexts["currentTimeReadout"].waitForExistence(timeout: 10))

        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 5))
        viewMenu.click()

        let workspace = app.menuBars.menuItems["Workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5), "View ▸ Workspace should exist")
        workspace.hover()

        XCTAssertTrue(app.menuBars.menuItems["Default"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuBars.menuItems["Save Current Layout As…"].exists)
        XCTAssertTrue(app.menuBars.menuItems["Manage Workspaces…"].exists)
        XCTAssertTrue(app.menuBars.menuItems["Reset to Default"].exists)

        // Close the menu so the app terminates cleanly.
        app.typeKey(.escape, modifierFlags: [])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/WorkspaceLayoutUITests/test_viewMenu_exposesTheWorkspaceSubmenu \
  -parallel-testing-enabled NO 2>&1 | tail -30
```
Expected: FAIL — `View ▸ Workspace should exist`.

- [ ] **Step 3: Add the submenu to `AppCommands`**

`AppCommands` must observe the store so the preset list and the checkmark stay current. Add near the other `@ObservedObject` / `@AppStorage` properties at the top of the `Commands` type:

```swift
    @ObservedObject private var workspaceStore = WorkspaceLayoutStore.shared
```

Then, inside `CommandGroup(after: .sidebar)`, immediately after the `Hide Inspector` button and its `Divider()` added in Task 3:

```swift
            Menu("Workspace") {
                ForEach(workspaceStore.state.presets) { preset in
                    Button {
                        NotificationCenter.default.post(
                            name: .workspaceSelected,
                            object: preset.name
                        )
                    } label: {
                        // The leading-checkmark pattern used by Auto-Scroll
                        // Waveform (#532) — the macOS-standard affordance for
                        // "this one is active". Note XCUITest cannot read the
                        // checkmark, so the UI test only asserts presence.
                        if workspaceStore.state.selectedName == preset.name {
                            Label(preset.name, systemImage: "checkmark")
                        } else {
                            Text(preset.name)
                        }
                    }
                }

                Divider()

                Button("Save Current Layout As…") {
                    NotificationCenter.default.post(name: .workspaceSaveAsRequested, object: nil)
                }

                Button(overwriteTitle) {
                    NotificationCenter.default.post(name: .workspaceOverwriteRequested, object: nil)
                }
                .disabled(!canOverwriteSelectedWorkspace)

                Button("Manage Workspaces…") {
                    NotificationCenter.default.post(name: .manageWorkspacesRequested, object: nil)
                }

                Divider()

                Button("Reset to Default") {
                    NotificationCenter.default.post(name: .workspaceResetRequested, object: nil)
                }
            }
            .accessibilityIdentifier("workspaceMenu")
```

and the two helpers alongside the existing private helpers in `AppCommands.swift` (the file already extracts helpers this way to satisfy SwiftLint's strict body-length rules):

```swift
    /// `Overwrite "Focus"` when a user preset is selected; a static title
    /// otherwise, since a disabled item with a dangling quote reads as a bug.
    private var overwriteTitle: String {
        guard let name = workspaceStore.state.selectedName,
              name != WorkspaceLayout.defaultName
        else { return "Overwrite Workspace" }
        return "Overwrite “\(name)”"
    }

    /// The built-in Default can never be overwritten (spec scope item 6).
    private var canOverwriteSelectedWorkspace: Bool {
        guard let name = workspaceStore.state.selectedName else { return false }
        return name != WorkspaceLayout.defaultName
    }
```

- [ ] **Step 4: Write the apply / capture wiring**

Create `OnlyCue/UI/DocumentView+Workspace.swift`:

```swift
import SwiftUI

/// Workspace preset application for one document window. Kept out of
/// `DocumentView.swift` so its body stays under SwiftLint's type-length cap,
/// matching `DocumentView+ManageTypes.swift`.
extension DocumentView {

    /// Applies `workspace` to this window, clamping each mode's layout to the
    /// width actually available.
    ///
    /// Clamps a **copy**: the stored preset is never rewritten (spec decision
    /// 8). Rewriting would mean a designer who applies a 400pt-inspector
    /// workspace on a laptop finds it permanently shrunk when they dock again.
    func applyWorkspace(_ workspace: WorkspaceLayout, availableWidth: CGFloat) {
        guard availableWidth > 0 else { return }
        var applied = workspace
        for mode in EditorMode.allCases {
            applied[mode] = workspace[mode].clamped(toAvailableWidth: availableWidth)
        }
        setLiveLayout(applied)
        // The sidebar is an AppKit split view: setting the value in state is
        // not enough, it has to be pushed through the bridge (Task 4).
        let pane = applied[editorMode]
        pendingSidebarWidth = pane.isSidebarCollapsed ? 0 : pane.sidebarWidth
    }

    /// Snapshots this window's current arrangement under `name`.
    func captureCurrentWorkspace(named name: String) -> WorkspaceLayout {
        var snapshot = liveLayout
        snapshot.name = name
        return snapshot
    }
}

/// Hosts every workspace notification receiver plus the two sheets, so
/// `DocumentView.body` gains one modifier rather than eight.
private struct WorkspaceMenuReceiver: ViewModifier {

    let applyWorkspace: (WorkspaceLayout) -> Void
    let captureCurrentWorkspace: (String) -> WorkspaceLayout
    let selectedWorkspaceName: () -> String?

    @ObservedObject private var store = WorkspaceLayoutStore.shared
    @State private var namePrompt: WorkspaceNamePrompt?
    @State private var isManaging = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .workspaceSelected)) { note in
                guard let name = note.object as? String,
                      let preset = store.state.presets.first(where: { $0.name == name })
                else { return }
                store.select(name)
                applyWorkspace(preset)
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceSaveAsRequested)) { _ in
                namePrompt = WorkspaceNamePrompt(kind: .saveAs, initialName: "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceOverwriteRequested)) { _ in
                guard let name = selectedWorkspaceName(), name != WorkspaceLayout.defaultName
                else { return }
                store.overwrite(name: name, with: captureCurrentWorkspace(name))
            }
            .onReceive(NotificationCenter.default.publisher(for: .manageWorkspacesRequested)) { _ in
                isManaging = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceResetRequested)) { _ in
                store.resetToDefault()
                applyWorkspace(.default)
            }
            .sheet(item: $namePrompt) { prompt in
                WorkspaceNameSheet(prompt: prompt) { name in
                    store.save(captureCurrentWorkspace(name))
                }
            }
            .sheet(isPresented: $isManaging) {
                ManageWorkspacesSheet()
            }
    }
}

extension View {
    func workspaceMenuReceiver(
        applyWorkspace: @escaping (WorkspaceLayout) -> Void,
        captureCurrentWorkspace: @escaping (String) -> WorkspaceLayout,
        selectedWorkspaceName: @escaping () -> String?
    ) -> some View {
        modifier(
            WorkspaceMenuReceiver(
                applyWorkspace: applyWorkspace,
                captureCurrentWorkspace: captureCurrentWorkspace,
                selectedWorkspaceName: selectedWorkspaceName
            )
        )
    }
}
```

`WorkspaceNamePrompt`, `WorkspaceNameSheet` and `ManageWorkspacesSheet` are Task 6 — **this task will not compile until Task 6 lands.** Either land Tasks 5 and 6 as one commit, or stub the three types in this task and fill them in the next. Prefer stubbing: it keeps each commit buildable, which the `git bisect`-ability of `dev` depends on. Minimal stubs to add at the bottom of `DocumentView+Workspace.swift` and delete in Task 6:

```swift
// MARK: - Task 6 placeholders

struct WorkspaceNamePrompt: Identifiable {
    enum Kind { case saveAs, rename(String) }
    let id = UUID()
    let kind: Kind
    let initialName: String
}

struct WorkspaceNameSheet: View {
    let prompt: WorkspaceNamePrompt
    let onCommit: (String) -> Void
    var body: some View { EmptyView() }
}

struct ManageWorkspacesSheet: View {
    var body: some View { EmptyView() }
}
```

- [ ] **Step 5: Feed the available width and attach the receiver in `DocumentView`**

Add near the other `@State` properties:

```swift
    /// The window's content width, measured live so preset application can
    /// clamp against what is actually there (spec decision 8).
    @State private var availableWindowWidth: CGFloat = 0
```

Wrap the `NavigationSplitView` in a `GeometryReader` and attach the receiver, so `body` becomes:

```swift
    var body: some View {
        GeometryReader { proxy in
            navigationSplit
                .onChange(of: proxy.size.width, initial: true) { _, newValue in
                    availableWindowWidth = newValue
                }
        }
        // ... every existing modifier from line 90 onward, unchanged ...
        .workspaceMenuReceiver(
            applyWorkspace: { applyWorkspace($0, availableWidth: availableWindowWidth) },
            captureCurrentWorkspace: { captureCurrentWorkspace(named: $0) },
            selectedWorkspaceName: { WorkspaceLayoutStore.shared.state.selectedName }
        )
    }

    /// Extracted so `body` stays inside SwiftLint's function-body-length cap
    /// now that a `GeometryReader` wraps it.
    private var navigationSplit: some View {
        NavigationSplitView {
            // ... the sidebar closure from Task 4 ...
        } detail: {
            // ... the detail closure from Task 3 ...
        }
    }
```

**Watch the `GeometryReader`.** It is greedy and does not propagate its child's ideal size, which can change how the window sizes itself — exactly the class of thing #617 is about. Step 6 is the gate. If `DocumentWindowMinWidthUITests` regresses, replace the `GeometryReader` with a background-based measurement, which does not affect layout at all:

```swift
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, newValue in
                        availableWindowWidth = newValue
                    }
            }
        }
```

Prefer this second form from the start if you have any doubt — it is strictly safer and costs nothing.

- [ ] **Step 6: Verify the #617 guard — mandatory gate**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/DocumentWindowMinWidthUITests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`. If not, switch to the background-based measurement above and re-run.

- [ ] **Step 7: Run the workspace UI tests**

```bash
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/WorkspaceLayoutUITests -parallel-testing-enabled NO 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **`, 3 tests passing.

- [ ] **Step 8: Lint and commit**

```bash
swiftlint lint --strict
git add OnlyCue/UI/DocumentView+Workspace.swift OnlyCue/UI/DocumentView.swift \
        OnlyCue/App/AppCommands.swift OnlyCueUITests/WorkspaceLayoutUITests.swift
git commit -m "feat(workspace): add the View menu workspace submenu and preset apply"
```

---

## Task 6: The name prompt and Manage Workspaces sheets

Replaces Task 5's stubs with the real sheets.

**Mockup gap — read before starting.** The Figma set for #714 (`Sheet · Manage Workspaces · Dark`, node `493:3017`, 420×293) covers the Manage sheet only. **No name-prompt sheet was drawn** for Save Current Layout As… or Rename. The design below is derived from the Manage sheet's own chrome so the two are visually consistent; if the maintainer wants a different treatment, get that decided before implementing rather than after.

**Sheet chrome, from the existing `Sheet · Manage Cue Types · Dark` (Figma `320:2225`) that the Manage Workspaces mockup was cloned from:** corner radius 12; header padding `[18, 20, 4, 20]` with 2pt gap, title Inter Semi Bold 15 on `color/text-primary`; body padding `[18, 20, 20, 20]`; rows 30pt tall, padding `[7, 8, 7, 8]`, 10pt gap, radius 6, label Inter Regular 13; footer padding `[16, 20, 16, 20]` with 8pt gap; hint captions Inter Regular 11 on `color/text-tertiary`. In code these map onto `DS.Space` (`sm` 8 / `md` 12 / `lg` 16 / `xl` 24) and `DS.Radius` (`sm` 6 / `xl` 12) — round to the nearest token rather than hardcoding the Figma pixel value, and match `TypeManagementSheet`'s structure (`VStack(spacing: 0) { header; Divider(); list; Divider(); footer }`).

**Files:**
- Create: `OnlyCue/UI/Workspace/WorkspaceNameSheet.swift`
- Create: `OnlyCue/UI/Workspace/ManageWorkspacesSheet.swift`
- Modify: `OnlyCue/UI/DocumentView+Workspace.swift` (delete the placeholders)
- Test: `OnlyCueTests/WorkspaceNameValidationTests.swift`

**Interfaces:**
- Consumes: `WorkspaceLayoutStore.shared`, `WorkspaceLayout.defaultName`, `DS.Space`, `DS.Radius`.
- Produces:
  - `struct WorkspaceNamePrompt: Identifiable` with `enum Kind { case saveAs, rename(String) }`, `let kind: Kind`, `let initialName: String`
  - `enum WorkspaceNameValidator { static func validate(_ candidate: String, existingNames: [String], allowing currentName: String?) -> WorkspaceNameProblem? }`
  - `enum WorkspaceNameProblem: Equatable { case empty, reserved, duplicate }` with `var message: String`
  - `struct WorkspaceNameSheet: View { init(prompt: WorkspaceNamePrompt, onCommit: @escaping (String) -> Void) }`
  - `struct ManageWorkspacesSheet: View { init() }`

- [ ] **Step 1: Write the failing validation test**

Name validation is where the real rules live (empty, reserved, duplicate), and it is pure — so it gets unit tests rather than being buried in a view.

Create `OnlyCueTests/WorkspaceNameValidationTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class WorkspaceNameValidationTests: XCTestCase {

    private let existing = ["Default", "Focus", "Wide"]

    func test_validName_isAccepted() {
        XCTAssertNil(WorkspaceNameValidator.validate("Tight", existingNames: existing, allowing: nil))
    }

    func test_emptyName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("", existingNames: existing, allowing: nil),
            .empty
        )
    }

    func test_whitespaceOnlyName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("   \n", existingNames: existing, allowing: nil),
            .empty
        )
    }

    func test_theReservedDefaultName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("Default", existingNames: existing, allowing: nil),
            .reserved
        )
    }

    func test_duplicateName_isRejected() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("Focus", existingNames: existing, allowing: nil),
            .duplicate
        )
    }

    func test_renamingAPresetToItsOwnName_isAccepted() {
        // Opening Rename and pressing Save without editing must not error.
        XCTAssertNil(
            WorkspaceNameValidator.validate("Focus", existingNames: existing, allowing: "Focus")
        )
    }

    func test_surroundingWhitespace_isTrimmedBeforeComparison() {
        XCTAssertEqual(
            WorkspaceNameValidator.validate("  Focus  ", existingNames: existing, allowing: nil),
            .duplicate
        )
    }

    func test_everyProblem_hasANonEmptyMessage() {
        for problem in [WorkspaceNameProblem.empty, .reserved, .duplicate] {
            XCTAssertFalse(problem.message.isEmpty, "\(problem) needs a message")
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate && xcodebuild build-for-testing -project OnlyCue.xcodeproj \
  -scheme OnlyCue -configuration Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL to compile — `cannot find 'WorkspaceNameValidator' in scope`.

- [ ] **Step 3: Write `WorkspaceNameSheet` (validator included)**

Create `OnlyCue/UI/Workspace/WorkspaceNameSheet.swift`:

```swift
import SwiftUI

/// Why a workspace name cannot be used.
enum WorkspaceNameProblem: Equatable {
    case empty
    case reserved
    case duplicate

    var message: String {
        switch self {
        case .empty: "Enter a name."
        case .reserved: "“\(WorkspaceLayout.defaultName)” is reserved for the built-in workspace."
        case .duplicate: "A workspace with that name already exists."
        }
    }
}

/// Pure name rules, so the sheet holds no logic worth testing.
enum WorkspaceNameValidator {

    /// - Parameter currentName: the name being renamed *from*, which is allowed
    ///   to collide with itself — otherwise opening Rename and pressing Save
    ///   without editing would report a duplicate.
    static func validate(
        _ candidate: String,
        existingNames: [String],
        allowing currentName: String?
    ) -> WorkspaceNameProblem? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed != WorkspaceLayout.defaultName else { return .reserved }
        if trimmed == currentName { return nil }
        guard !existingNames.contains(trimmed) else { return .duplicate }
        return nil
    }
}

/// What a `WorkspaceNameSheet` is being opened for.
struct WorkspaceNamePrompt: Identifiable {

    enum Kind: Equatable {
        case saveAs
        /// Renaming the preset currently called this.
        case rename(String)
    }

    let id = UUID()
    let kind: Kind
    let initialName: String

    var title: String {
        switch kind {
        case .saveAs: "Save Workspace"
        case .rename: "Rename Workspace"
        }
    }

    var confirmTitle: String {
        switch kind {
        case .saveAs: "Save"
        case .rename: "Rename"
        }
    }

    /// The name allowed to collide with itself.
    var currentName: String? {
        switch kind {
        case .saveAs: nil
        case .rename(let name): name
        }
    }
}

/// The small name prompt behind Save Current Layout As… and Rename.
///
/// NOTE: no Figma mockup exists for this sheet (#714's set covers Manage
/// Workspaces only). The chrome below is derived from `TypeManagementSheet`
/// and Figma 320:2225 so the two read as one family.
struct WorkspaceNameSheet: View {

    let prompt: WorkspaceNamePrompt
    let onCommit: (String) -> Void

    @ObservedObject private var store = WorkspaceLayoutStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    private var problem: WorkspaceNameProblem? {
        WorkspaceNameValidator.validate(
            name,
            existingNames: store.state.presets.map(\.name),
            allowing: prompt.currentName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(prompt.title)
                .font(.headline)

            TextField("Workspace name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("workspaceNameField")
                .onSubmit { commit() }

            // Reserve the row whether or not there is a problem, so the sheet
            // does not jump height as the user types.
            Text(problem?.message ?? " ")
                .font(.caption)
                .foregroundStyle(problem == nil ? .secondary : Color.red) // semantic: validation error
                .accessibilityIdentifier("workspaceNameProblem")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(prompt.confirmTitle) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
                    .accessibilityIdentifier("workspaceNameCommitButton")
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 360)
        .accessibilityIdentifier("workspaceNameSheet")
        .onAppear { name = prompt.initialName }
    }

    private func commit() {
        guard problem == nil else { return }
        onCommit(name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
```

- [ ] **Step 4: Run the validation tests to verify they pass**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/WorkspaceNameValidationTests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 8 tests passing.

- [ ] **Step 5: Write `ManageWorkspacesSheet`**

Create `OnlyCue/UI/Workspace/ManageWorkspacesSheet.swift`:

```swift
import SwiftUI

/// Rename and delete saved workspaces. Figma 493:3017 (420×293): a titled
/// header, a row per preset with a leading checkmark on the selected one and
/// trailing Rename / Delete actions, a hint line, and a Done footer.
///
/// The built-in Default is listed (so the user can see what they are returning
/// to) but its actions are disabled — it can be neither renamed nor deleted
/// (spec scope item 6).
struct ManageWorkspacesSheet: View {

    @ObservedObject private var store = WorkspaceLayoutStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var renamePrompt: WorkspaceNamePrompt?
    @State private var pendingDeletion: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 420, height: 293)
        .accessibilityIdentifier("manageWorkspacesSheet")
        .sheet(item: $renamePrompt) { prompt in
            WorkspaceNameSheet(prompt: prompt) { newName in
                guard case .rename(let oldName) = prompt.kind else { return }
                store.rename(oldName, to: newName)
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion ?? "")”?",
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let name = pendingDeletion { store.delete(name) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The workspace is removed. Windows keep their current arrangement.")
        }
    }

    private var header: some View {
        HStack {
            Text("Manage Workspaces")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.state.presets) { preset in
                    row(for: preset)
                    Divider()
                }
            }
        }
    }

    private func row(for preset: WorkspaceLayout) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark")
                .opacity(store.state.selectedName == preset.name ? 1 : 0)
                .accessibilityHidden(true)

            Text(preset.name)

            Spacer()

            Button("Rename") {
                renamePrompt = WorkspaceNamePrompt(
                    kind: .rename(preset.name),
                    initialName: preset.name
                )
            }
            .disabled(preset.isBuiltIn)

            Button("Delete", role: .destructive) { pendingDeletion = preset.name }
                .disabled(preset.isBuiltIn)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspaceRow.\(preset.name)")
    }

    private var footer: some View {
        HStack {
            Text("The built-in Default workspace can’t be renamed or deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}
```

- [ ] **Step 6: Delete the Task 5 placeholders**

Remove the `// MARK: - Task 6 placeholders` block and the three stub types from the bottom of `OnlyCue/UI/DocumentView+Workspace.swift`. Nothing else in that file changes.

- [ ] **Step 7: Build, run the whole unit suite, verify the #617 guard**

```bash
xcodegen generate
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests -parallel-testing-enabled NO 2>&1 | tail -20 && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/DocumentWindowMinWidthUITests \
  -only-testing:OnlyCueUITests/WorkspaceLayoutUITests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 8: Manual verification of the full lifecycle**

Launch the app and walk the spec's Gherkin scenarios by hand:
- arrange all three modes differently, `View ▸ Workspace ▸ Save Current Layout As…`, name it "Focus" → it appears checked in the menu;
- drag the divider → the window changes, then re-select "Focus" → the saved width returns (snapshot, not live binding);
- `Overwrite “Focus”` → the new width is now what "Focus" restores;
- `Manage Workspaces…` → rename to "Tight", the menu updates; Delete → it disappears and the checkmark clears;
- `Reset to Default` → only Default remains;
- Save a workspace with a 400pt inspector, then narrow the window and re-apply → the layout clamps and the inspector collapses before the centre pane becomes unusable; widen again and re-apply → 400pt returns.

- [ ] **Step 9: Lint and commit**

```bash
swiftlint lint --strict
git add OnlyCue/UI/Workspace/WorkspaceNameSheet.swift \
        OnlyCue/UI/Workspace/ManageWorkspacesSheet.swift \
        OnlyCue/UI/DocumentView+Workspace.swift \
        OnlyCueTests/WorkspaceNameValidationTests.swift
git commit -m "feat(workspace): add the name prompt and manage workspaces sheets"
```

---

## Task 7: Scope preset application to the frontmost window

**Why this is its own task.** `NotificationCenter.default.post` reaches **every** open `DocumentView`, so as written in Task 5 a preset applies to all windows at once. That directly violates spec decision 9 and the acceptance criterion "Applying a preset changes only the frontmost window". Every other notification in `AppNotifications.swift` has the same broadcast shape, but for sheets the consequence is a duplicate dialog rather than silently rearranging a window the user was not looking at.

**Files:**
- Create: `OnlyCue/UI/Workspace/FrontmostWindowGate.swift`
- Modify: `OnlyCue/UI/DocumentView+Workspace.swift`
- Test: `OnlyCueTests/FrontmostWindowGateTests.swift`

**Interfaces:**
- Produces:
  - `struct FrontmostWindowGate: ViewModifier` and `extension View { func frontmostWindowGate(isFrontmost: Binding<Bool>) -> some View }` — tracks whether the hosting window is key.
  - `enum WindowScope { static func shouldHandle(isFrontmost: Bool, openWindowCount: Int) -> Bool }` — the testable rule.

- [ ] **Step 1: Write the failing test**

Create `OnlyCueTests/FrontmostWindowGateTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class FrontmostWindowGateTests: XCTestCase {

    func test_singleWindow_alwaysHandles() {
        // With one window open, `isKeyWindow` can be false transiently (a sheet
        // or a panel has key). Refusing then would make the menu look broken.
        XCTAssertTrue(WindowScope.shouldHandle(isFrontmost: false, openWindowCount: 1))
        XCTAssertTrue(WindowScope.shouldHandle(isFrontmost: true, openWindowCount: 1))
    }

    func test_multipleWindows_onlyTheFrontmostHandles() {
        XCTAssertTrue(WindowScope.shouldHandle(isFrontmost: true, openWindowCount: 2))
        XCTAssertFalse(WindowScope.shouldHandle(isFrontmost: false, openWindowCount: 2))
    }

    func test_zeroWindows_doesNotHandle() {
        XCTAssertFalse(WindowScope.shouldHandle(isFrontmost: false, openWindowCount: 0))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate && xcodebuild build-for-testing -project OnlyCue.xcodeproj \
  -scheme OnlyCue -configuration Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL to compile — `cannot find 'WindowScope' in scope`.

- [ ] **Step 3: Write the gate**

Create `OnlyCue/UI/Workspace/FrontmostWindowGate.swift`:

```swift
import AppKit
import SwiftUI

/// Whether a broadcast menu notification belongs to this window.
///
/// `NotificationCenter.default.post` reaches every open `DocumentView`, so a
/// workspace preset would otherwise rearrange every window at once — against
/// spec decision 9, which makes layout a per-window property.
enum WindowScope {

    /// - Parameter openWindowCount: how many document windows exist. With
    ///   exactly one, key-window state is ignored: a sheet or an inspector
    ///   panel can hold key while the document window is plainly the target,
    ///   and refusing then would make the menu item look dead.
    static func shouldHandle(isFrontmost: Bool, openWindowCount: Int) -> Bool {
        guard openWindowCount > 0 else { return false }
        if openWindowCount == 1 { return true }
        return isFrontmost
    }
}

/// Publishes whether the hosting window is currently key.
struct FrontmostWindowGate: ViewModifier {

    @Binding var isFrontmost: Bool
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window = $0; refresh() })
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            ) { _ in refresh() }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            ) { _ in refresh() }
    }

    private func refresh() {
        isFrontmost = window?.isKeyWindow ?? false
    }

    /// Zero-size probe that hands back the hosting `NSWindow`. SwiftUI has no
    /// public accessor for it on macOS 14.
    private struct WindowReader: NSViewRepresentable {
        let onResolve: (NSWindow?) -> Void

        func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { onResolve(view.window) }
        }
    }
}

extension View {
    func frontmostWindowGate(isFrontmost: Binding<Bool>) -> some View {
        modifier(FrontmostWindowGate(isFrontmost: isFrontmost))
    }
}
```

- [ ] **Step 4: Apply the gate in `WorkspaceMenuReceiver`**

In `OnlyCue/UI/DocumentView+Workspace.swift`, add to `WorkspaceMenuReceiver`:

```swift
    @State private var isFrontmost = false

    /// Document windows currently open. `NSApp.windows` includes panels and
    /// the menu-bar window, so filter to those that can be a document.
    private var openDocumentWindowCount: Int {
        NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.count
    }

    private var handlesNotifications: Bool {
        WindowScope.shouldHandle(
            isFrontmost: isFrontmost,
            openWindowCount: openDocumentWindowCount
        )
    }
```

add `import AppKit` at the top of the file, add `.frontmostWindowGate(isFrontmost: $isFrontmost)` to the modifier chain in `body(content:)`, and guard **every** `.onReceive` handler in that chain with:

```swift
                guard handlesNotifications else { return }
```

as its first line. All five handlers — `workspaceSelected`, `workspaceSaveAsRequested`, `workspaceOverwriteRequested`, `manageWorkspacesRequested`, `workspaceResetRequested` — need it. Apply the same guard to the `toggleInspectorRequested` receiver added to `DocumentView.body` in Task 3, by moving that receiver into `WorkspaceMenuReceiver` alongside the others:

```swift
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspectorRequested)) { _ in
                guard handlesNotifications else { return }
                toggleInspector()
            }
```

with `let toggleInspector: () -> Void` added to `WorkspaceMenuReceiver`'s stored properties, to `workspaceMenuReceiver(...)`'s parameters, and passed from `DocumentView` as `{ updateLiveLayout { $0.isInspectorCollapsed.toggle() } }`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild build-for-testing -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' && \
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueTests -parallel-testing-enabled NO 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Manual verification — two windows**

Open two documents side by side. Apply a preset in the frontmost one. Confirm the other keeps its arrangement, and that `⌥⌘I` toggles only the frontmost window's inspector. Then close one and confirm the menu still works with a single window (the `openWindowCount == 1` branch).

- [ ] **Step 7: Full UI suite, lint, commit**

```bash
xcodebuild test-without-building -project OnlyCue.xcodeproj -scheme OnlyCue \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:OnlyCueUITests/DocumentWindowMinWidthUITests \
  -only-testing:OnlyCueUITests/WorkspaceLayoutUITests -parallel-testing-enabled NO 2>&1 | tail -20
swiftlint lint --strict
git add OnlyCue/UI/Workspace/FrontmostWindowGate.swift \
        OnlyCue/UI/DocumentView+Workspace.swift OnlyCue/UI/DocumentView.swift \
        OnlyCueTests/FrontmostWindowGateTests.swift
git commit -m "feat(workspace): apply presets to the frontmost window only"
```

---

## Acceptance criteria → task map

| Spec criterion | Covered by |
|---|---|
| `DocumentWindowMinWidthUITests` still passes | Tasks 3 §8, 4 §7, 5 §6, 6 §7 — a mandatory gate in each |
| No `NSSplitView`-backed split in the detail column | Task 3 (`InspectorDivider` is a plain `Divider()`); Global Constraints |
| Inspector resizes 340–400 by drag and collapses via `⌥⌘I` | Task 3 |
| Each `EditorMode` restores its own arrangement | Task 3 (`liveLayout[editorMode]`), Task 2 (`WorkspaceLayout` subscript) |
| Preset create / overwrite / rename / delete / re-apply; `Default` protected | Tasks 2, 5, 6 |
| Adjusting a divider does not modify the preset | Task 2 (`recordLiveLayout` touches only `mostRecentLayout`; unit-tested) |
| Clamp on apply, stored preset unchanged | Task 1 (`clamped(toAvailableWidth:)`), Task 5 (`applyWorkspace` clamps a copy) |
| Applying a preset changes only the frontmost window | Task 7 |
| Corrupt/absent `"workspaceLayout.v1"` → Default, silently | Task 2 (`decode` fallback; unit-tested) |
| Schema stays 18, no migration, no undo/dirty | Global Constraints — nothing in Tasks 1–7 touches `ProjectModel` or `CueCommands` |
| A new window opens with the most recent layout | Task 3 (`liveLayout` falls back to `store.state.mostRecentLayout`), Task 2 (persisted) |

## Outstanding before this ships

1. **No Figma mockup exists for the name-prompt sheet.** Task 6 derives one from the Manage sheet's chrome. Get it signed off, or drawn, before Task 6.
2. **The sidebar-drag manual check** (spec §"One manual check still outstanding") must be done on `dev` *before* Task 4 so a regression is attributable.
3. **`dev` CI is currently red** on "UI tests (behavioral)" from the automation-mode wedge, unrelated to this work. UI tests do not run on PRs in this repo, so this feature's UI coverage is only exercised locally and after merge. Do not read a red `dev` as this feature failing without checking which step failed.
