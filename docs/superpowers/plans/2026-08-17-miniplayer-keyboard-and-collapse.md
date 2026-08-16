# Mini Player Keyboard + Collapse-to-Mini Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let playback keyboard shortcuts work while the Mini Player is the active surface, and make the main window's close button collapse the app into the Mini Player (hide, not destroy) so playback continues.

**Architecture:** Three pure decision units (`MiniPlaybackKeymap`, `MiniPlaybackGate`, `MiniPlayerCollapse`) carry the logic and are unit-tested. A shared `MiniPlaybackActions` seam performs the playback actions for both the Mini Player's buttons and a new `NSEvent` key-down monitor. `DocumentView` owns the monitor (it holds `engine`/`document`/`context` and its own `NSWindow`), intercepts window close to collapse, and restores on demand. `MiniPlayerController` detects the panel's own close and signals a restore.

**Tech Stack:** Swift, SwiftUI (`DocumentGroup`), AppKit (`NSPanel`, `NSEvent` local monitor, `NSWindowDelegate`), XCTest. Spec: `docs/superpowers/specs/2026-08-17-miniplayer-keyboard-and-collapse-design.md`.

## Global Constraints

- macOS deployment target ≥ 14.0 (ADR-001); do not lower.
- No direct `ProjectModel` mutation from UI — go through `CueCommands` (song stepping already does).
- Main-window views use `DS.*` design tokens, not raw color/spacing/font literals (ADR-024/029).
- Conventional Commits, lowercase after prefix, imperative; no `Co-Authored-By` trailers.
- No new App Sandbox entitlements (ADR-007). Local `NSEvent` monitor only (no global monitor / Accessibility).
- Whitelisted playback actions only: `playPause, jumpBack, jumpForward, stepPrevCue, stepNextCue, go, playbackRateUp, playbackRateDown, playbackRateReset`. Never `addCue` or cue-type digits.
- New source files under `OnlyCue/` are picked up by the existing xcodegen folder rules; run `xcodegen generate` after adding files before building.

## Existing seams (verbatim, for reference)

- `KeymapStore.shared.keymap` → `Keymap`; `keymap.chord(for: KeymapAction) -> KeyChord` (`OnlyCue/App/Keymap.swift:25`).
- `KeyChord(key: String, modifiers: Set<KeyChord.Modifier>)`; special-key names include `"leftArrow" "rightArrow" "upArrow" "downArrow" "space" "return"` (`OnlyCue/App/KeyChord.swift`).
- `engine.toggle()`, `engine.seek(to:) async`, `engine.currentTime`, `engine.nudgePlaybackRate(by:)`, `engine.resetPlaybackRate()`, `engine.playbackRate` (`PlayerEngine`).
- `PlaybackRateController.apply(_ change:engine:ltcEnabled:)` — LTC-interlocked rate change with beep (`OnlyCue/UI/PlaybackRateShortcuts.swift:110`).
- `DocumentView.jump(by:)` = `max(0, engine.currentTime + seconds)` then `engine.seek(to:)` (`OnlyCue/UI/DocumentView.swift:373`).
- `MiniPlayerHostView` already has `step(_:)` (cue seek) and `performGo()` (`OnlyCue/UI/MiniPlayerHostView.swift`).
- `MiniPlayerController` (`OnlyCue/UI/MiniPlayerController.swift`): `panel: NSPanel?`, `isVisible`, `show/hide/close`, `makePanel`.
- `WindowScope.shouldHandle(isFrontmost:openWindowCount:)`, `view.isMiniFrontmost`, `view.miniHandlesNotifications` (`OnlyCue/UI/DocumentView+MiniPlayer.swift`).
- `View` menu items live in `AppCommands.swift` `CommandGroup(after: .sidebar)`; "Mini Player" at line 162; notifications in `OnlyCue/UI/AppNotifications.swift`.
- `LTCRoutingStore.shared.settings.isEnabled` — LTC output on/off (already read by `TransportControls`).

---

### Task 1: `MiniPlaybackKeymap` — chord → whitelisted action (pure)

**Files:**
- Create: `OnlyCue/UI/MiniPlaybackKeymap.swift`
- Test: `OnlyCueTests/MiniPlaybackKeymapTests.swift`

**Interfaces:**
- Produces: `enum MiniPlaybackAction { case playPause, jumpBack, jumpForward, stepPrevCue, stepNextCue, go, rateUp, rateDown, rateReset }`
- Produces: `enum MiniPlaybackKeymap { static func action(for chord: KeyChord, keymap: Keymap) -> MiniPlaybackAction? }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

@MainActor
final class MiniPlaybackKeymapTests: XCTestCase {

    func test_defaultSpaceMapsToPlayPause() {
        let chord = Keymap.default.chord(for: .playPause)
        XCTAssertEqual(MiniPlaybackKeymap.action(for: chord, keymap: .default), .playPause)
    }

    func test_defaultArrowsMapToJumpAndStep() {
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .jumpBack), keymap: .default), .jumpBack)
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .stepNextCue), keymap: .default), .stepNextCue)
    }

    func test_rateKeysMap() {
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .playbackRateUp), keymap: .default), .rateUp)
    }

    func test_goMaps() {
        XCTAssertEqual(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .go), keymap: .default), .go)
    }

    func test_excludedActionsAreIgnored() {
        // addCue is NOT a playback action — its chord must not resolve.
        XCTAssertNil(MiniPlaybackKeymap.action(for: Keymap.default.chord(for: .addCue), keymap: .default))
    }

    func test_unknownChordIsIgnored() {
        XCTAssertNil(MiniPlaybackKeymap.action(for: KeyChord(key: "q"), keymap: .default))
    }

    func test_customRebindResolves() {
        var keymap = Keymap.default
        keymap.rebind(.playPause, to: KeyChord(key: "p"))
        XCTAssertEqual(MiniPlaybackKeymap.action(for: KeyChord(key: "p"), keymap: keymap), .playPause)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet`
Expected: FAIL — `MiniPlaybackKeymap` / `MiniPlaybackAction` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// The playback/navigation commands the Mini Player accepts from the keyboard
/// (#743). A deliberate whitelist — editing actions (`addCue`, cue-type digits)
/// are never keyboard-driven from the Mini Player.
enum MiniPlaybackAction: Equatable {
    case playPause, jumpBack, jumpForward, stepPrevCue, stepNextCue, go, rateUp, rateDown, rateReset
}

/// Resolves a key chord to a Mini Player playback action, honoring the user's
/// live `KeymapStore` bindings. Pure — the `NSEvent` glue converts an event to a
/// `KeyChord` and calls this.
enum MiniPlaybackKeymap {

    /// The `KeymapAction`s the Mini Player honors, paired with the action they map to.
    private static let whitelist: [(KeymapAction, MiniPlaybackAction)] = [
        (.playPause, .playPause),
        (.jumpBack, .jumpBack),
        (.jumpForward, .jumpForward),
        (.stepPrevCue, .stepPrevCue),
        (.stepNextCue, .stepNextCue),
        (.go, .go),
        (.playbackRateUp, .rateUp),
        (.playbackRateDown, .rateDown),
        (.playbackRateReset, .rateReset)
    ]

    static func action(for chord: KeyChord, keymap: Keymap) -> MiniPlaybackAction? {
        whitelist.first { keymap.chord(for: $0.0) == chord }?.1
    }
}
```

- [ ] **Step 4: Regenerate project, run tests to verify they pass**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MiniPlaybackKeymapTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/MiniPlaybackKeymap.swift OnlyCueTests/MiniPlaybackKeymapTests.swift
git commit -m "feat(miniplayer): resolve key chords to whitelisted playback actions"
```

---

### Task 2: `MiniPlaybackGate` — handle-vs-yield decision (pure)

**Files:**
- Create: `OnlyCue/UI/MiniPlaybackGate.swift`
- Test: `OnlyCueTests/MiniPlaybackGateTests.swift`

**Interfaces:**
- Produces: `enum MiniPlaybackGate { static func shouldHandle(panelVisible: Bool, isFrontmostMini: Bool, mainWindowIsKey: Bool) -> Bool }`

Approach A: handle only when the Mini Player is the visible frontmost surface AND the main document window is not currently key (minimized / hidden / behind). Otherwise yield to the main window's existing SwiftUI shortcuts.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MiniPlaybackGateTests: XCTestCase {

    func test_handlesWhenMiniFrontmostAndMainNotKey() {
        XCTAssertTrue(MiniPlaybackGate.shouldHandle(panelVisible: true, isFrontmostMini: true, mainWindowIsKey: false))
    }

    func test_yieldsWhenMainWindowIsKey() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(panelVisible: true, isFrontmostMini: true, mainWindowIsKey: true))
    }

    func test_yieldsWhenPanelHidden() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(panelVisible: false, isFrontmostMini: true, mainWindowIsKey: false))
    }

    func test_yieldsWhenNotFrontmostMini() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(panelVisible: true, isFrontmostMini: false, mainWindowIsKey: false))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet`
Expected: FAIL — `MiniPlaybackGate` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Decides whether the Mini Player's key monitor should handle a playback key or
/// yield it to the main window (#743, Approach A). Handle only when the Mini
/// Player is the visible frontmost surface and no document window is key —
/// otherwise the main window's own SwiftUI shortcuts (which already yield to
/// inline text fields) take the key.
enum MiniPlaybackGate {
    static func shouldHandle(panelVisible: Bool, isFrontmostMini: Bool, mainWindowIsKey: Bool) -> Bool {
        panelVisible && isFrontmostMini && !mainWindowIsKey
    }
}
```

- [ ] **Step 4: Regenerate, run tests to verify they pass**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MiniPlaybackGateTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/MiniPlaybackGate.swift OnlyCueTests/MiniPlaybackGateTests.swift
git commit -m "feat(miniplayer): gate playback key handling to yield to the main window"
```

---

### Task 3: `MiniPlayerCollapse` — close/restore decisions (pure)

**Files:**
- Create: `OnlyCue/UI/MiniPlayerCollapse.swift`
- Test: `OnlyCueTests/MiniPlayerCollapseTests.swift`

**Interfaces:**
- Produces: `enum MiniPlayerCollapse`
  - `static func onMainWindowClose(miniVisible: Bool) -> CloseOutcome` where `enum CloseOutcome { case collapseToMini, closeDocument }`
  - `static func onMiniClose(mainWindowHidden: Bool) -> MiniCloseOutcome` where `enum MiniCloseOutcome { case restoreMainWindow, justCloseMini }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import OnlyCue

final class MiniPlayerCollapseTests: XCTestCase {

    func test_close_collapsesWhenMiniVisible() {
        XCTAssertEqual(MiniPlayerCollapse.onMainWindowClose(miniVisible: true), .collapseToMini)
    }

    func test_close_closesDocumentWhenMiniHidden() {
        XCTAssertEqual(MiniPlayerCollapse.onMainWindowClose(miniVisible: false), .closeDocument)
    }

    func test_miniClose_restoresMainWhenHidden() {
        XCTAssertEqual(MiniPlayerCollapse.onMiniClose(mainWindowHidden: true), .restoreMainWindow)
    }

    func test_miniClose_justClosesWhenMainVisible() {
        XCTAssertEqual(MiniPlayerCollapse.onMiniClose(mainWindowHidden: false), .justCloseMini)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet`
Expected: FAIL — `MiniPlayerCollapse` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Collapse-to-Mini decisions (#743). Invariant: while a document is open it
/// never has zero visible surfaces, and an unsaved document is never silently
/// discarded — so the main window's close button collapses to the Mini Player
/// (hide) whenever the Mini Player is visible, and closing the Mini Player
/// restores a hidden main window instead of leaving nothing.
enum MiniPlayerCollapse {

    enum CloseOutcome { case collapseToMini, closeDocument }
    enum MiniCloseOutcome { case restoreMainWindow, justCloseMini }

    static func onMainWindowClose(miniVisible: Bool) -> CloseOutcome {
        miniVisible ? .collapseToMini : .closeDocument
    }

    static func onMiniClose(mainWindowHidden: Bool) -> MiniCloseOutcome {
        mainWindowHidden ? .restoreMainWindow : .justCloseMini
    }
}
```

- [ ] **Step 4: Regenerate, run tests to verify they pass**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MiniPlayerCollapseTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/MiniPlayerCollapse.swift OnlyCueTests/MiniPlayerCollapseTests.swift
git commit -m "feat(miniplayer): collapse/restore decision helpers"
```

---

### Task 4: `MiniPlaybackActions` seam + route the Mini Player buttons through it

**Files:**
- Create: `OnlyCue/UI/MiniPlaybackActions.swift`
- Modify: `OnlyCue/UI/MiniPlayerHostView.swift`
- Test: `OnlyCueTests/MiniPlaybackActionsTests.swift`

**Interfaces:**
- Consumes: `MiniPlaybackAction` (Task 1).
- Produces: `@MainActor struct MiniPlaybackActions` holding `engine: PlayerEngine`, `document: CueListDocument`, `context: MiniPlayerContext`, `ltcEnabled: Bool`, with:
  - `func perform(_ action: MiniPlaybackAction)`
  - `func playPause()`, `func jump(by: TimeInterval)`, `func stepCue(_ direction: MediaItem.PlayheadStep)`, `func go()`, `func rate(_ change: PlaybackRateShortcuts.Change)`
- Produces: a pure `static func rateChange(for action: MiniPlaybackAction) -> PlaybackRateShortcuts.Change?` used by tests and `perform`.

The action bodies mirror the existing seams exactly: `jump` = `max(0, engine.currentTime + seconds)` then `engine.seek(to:)`; `stepCue` reuses `MediaItem.cue(steppingFrom:direction:typeID:)` with `context.showGoTypeID`; `go` reuses `MediaItem.showGoDecision`; `rate` reuses `PlaybackRateController.apply`.

- [ ] **Step 1: Write the failing test** (pure mapping only — engine side effects are covered by existing engine/CueCommands tests)

```swift
import XCTest
@testable import OnlyCue

final class MiniPlaybackActionsTests: XCTestCase {

    func test_rateChangeMapping() {
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateUp), .up)
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateDown), .down)
        XCTAssertEqual(MiniPlaybackActions.rateChange(for: .rateReset), .reset)
        XCTAssertNil(MiniPlaybackActions.rateChange(for: .playPause))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet`
Expected: FAIL — `MiniPlaybackActions` not defined.

- [ ] **Step 3: Write the seam**

```swift
import AppKit
import SwiftUI

/// The single Mini Player playback-action seam (#743). Both the Mini Player's
/// on-screen buttons and its keyboard monitor route through this, so button and
/// keyboard behavior cannot drift. Every body reuses an existing seam.
@MainActor
struct MiniPlaybackActions {

    let engine: PlayerEngine
    let document: CueListDocument
    let context: MiniPlayerContext
    let ltcEnabled: Bool

    private var seekTaskBox: SeekTaskBox

    init(engine: PlayerEngine, document: CueListDocument, context: MiniPlayerContext, ltcEnabled: Bool, seekTaskBox: SeekTaskBox) {
        self.engine = engine
        self.document = document
        self.context = context
        self.ltcEnabled = ltcEnabled
        self.seekTaskBox = seekTaskBox
    }

    func perform(_ action: MiniPlaybackAction) {
        switch action {
        case .playPause: playPause()
        case .jumpBack: jump(by: -1)
        case .jumpForward: jump(by: 1)
        case .stepPrevCue: stepCue(.previous)
        case .stepNextCue: stepCue(.next)
        case .go: go()
        case .rateUp, .rateDown, .rateReset:
            if let change = Self.rateChange(for: action) { rate(change) }
        }
    }

    func playPause() { engine.toggle() }

    func jump(by seconds: TimeInterval) {
        let target = max(0, engine.currentTime + seconds)   // mirrors DocumentView.jump
        seekTaskBox.task?.cancel()
        seekTaskBox.task = Task { await engine.seek(to: target) }
    }

    func stepCue(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction, typeID: context.showGoTypeID)
        else { return }
        seekTaskBox.task?.cancel()
        seekTaskBox.task = Task { await engine.seek(to: target.time) }
    }

    func go() {
        guard let item = document.model.activeItem,
              case .seekAndPlay(let time) = item.showGoDecision(from: engine.currentTime, typeID: context.showGoTypeID)
        else { return }
        seekTaskBox.task?.cancel()
        seekTaskBox.task = Task { await engine.seek(to: time); engine.play() }
    }

    func rate(_ change: PlaybackRateShortcuts.Change) {
        PlaybackRateController.apply(change, engine: engine, ltcEnabled: ltcEnabled)
    }

    static func rateChange(for action: MiniPlaybackAction) -> PlaybackRateShortcuts.Change? {
        switch action {
        case .rateUp: return .up
        case .rateDown: return .down
        case .rateReset: return .reset
        default: return nil
        }
    }
}

/// Reference box so a cancellable seek task survives across the struct's copies
/// (host view rebuilds a fresh `MiniPlaybackActions` each render).
@MainActor
final class SeekTaskBox {
    var task: Task<Void, Never>?
}
```

- [ ] **Step 4: Route `MiniPlayerHostView` buttons through the seam**

In `MiniPlayerHostView.swift`, add `@State private var seekBox = SeekTaskBox()` and build `let actions = MiniPlaybackActions(engine: engine, document: document, context: context, ltcEnabled: LTCRoutingStore.shared.settings.isEnabled, seekTaskBox: seekBox)` at the top of `body`. Replace the closures:

```swift
onPlayPause: { actions.playPause() },
onPrevCue: { actions.stepCue(.previous) },
onNextCue: { actions.stepCue(.next) },
onPrevSong: { stepSong(.previous) },   // unchanged — CueCommands path stays
onNextSong: { stepSong(.next) },
onGo: { actions.go() },
```

Delete the now-unused private `step(_:)` and `performGo()` from `MiniPlayerHostView` (their logic now lives in `MiniPlaybackActions`); keep `stepSong` and the `canStepSong`/`hasCue` helpers. Verify `hasCue` still compiles (it calls `document.model.activeItem?.cue(...)` directly — unaffected).

- [ ] **Step 5: Regenerate, build, run tests**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MiniPlaybackActionsTests`
Expected: PASS. Build clean (no unused-symbol warnings for removed `step`/`performGo`).

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/MiniPlaybackActions.swift OnlyCue/UI/MiniPlayerHostView.swift OnlyCueTests/MiniPlaybackActionsTests.swift
git commit -m "feat(miniplayer): shared playback-action seam for buttons and keyboard"
```

---

### Task 5: NSEvent key monitor in `DocumentView` (glue) + NSEvent→KeyChord conversion

**Files:**
- Create: `OnlyCue/UI/MiniKeyChord.swift` (pure NSEvent-characters → `KeyChord`)
- Create: `OnlyCue/UI/DocumentView+MiniKeyMonitor.swift`
- Modify: `OnlyCue/UI/DocumentView.swift` (add `@State` monitor token + collapse state; call install/remove)
- Modify: `OnlyCue/UI/DocumentView+MiniPlayer.swift` (start/stop monitor on visibility change)
- Test: `OnlyCueTests/MiniKeyChordTests.swift`

**Interfaces:**
- Consumes: `MiniPlaybackKeymap`, `MiniPlaybackGate`, `MiniPlaybackActions`.
- Produces: `enum MiniKeyChord { static func from(charactersIgnoringModifiers: String?, flags: NSEvent.ModifierFlags) -> KeyChord? }`
- Produces on `DocumentView`: `func startMiniKeyMonitor()`, `func stopMiniKeyMonitor()`, `@State var miniKeyMonitor: Any?`, `@State var isMainWindowCollapsed: Bool`, `@State var seekBox = SeekTaskBox()`.

- [ ] **Step 1: Write the failing test for the pure converter**

```swift
import AppKit
import XCTest
@testable import OnlyCue

final class MiniKeyChordTests: XCTestCase {

    func test_space() {
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: " ", flags: []), KeyChord(key: "space"))
    }

    func test_leftArrow() {
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: left, flags: []), KeyChord(key: "leftArrow"))
    }

    func test_return() {
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: "\r", flags: []), KeyChord(key: "return"))
    }

    func test_bracketWithNoModifiers() {
        XCTAssertEqual(MiniKeyChord.from(charactersIgnoringModifiers: "]", flags: []), KeyChord(key: "]"))
    }

    func test_letterLowercasedAndModifierCaptured() {
        XCTAssertEqual(
            MiniKeyChord.from(charactersIgnoringModifiers: "P", flags: [.command]),
            KeyChord(key: "p", modifiers: [.command])
        )
    }

    func test_nilCharactersYieldNil() {
        XCTAssertNil(MiniKeyChord.from(charactersIgnoringModifiers: nil, flags: []))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet`
Expected: FAIL — `MiniKeyChord` not defined.

- [ ] **Step 3: Implement the converter**

```swift
import AppKit

/// Converts an `NSEvent` key-down's characters + modifier flags into a `KeyChord`
/// so the pure `MiniPlaybackKeymap` can resolve it (#743). Mirrors
/// `KeyChord.from(keyEquivalent:modifiers:)` but works from AppKit's event data.
enum MiniKeyChord {

    private static let specialByScalar: [Int: String] = [
        NSLeftArrowFunctionKey: "leftArrow",
        NSRightArrowFunctionKey: "rightArrow",
        NSUpArrowFunctionKey: "upArrow",
        NSDownArrowFunctionKey: "downArrow"
    ]

    static func from(charactersIgnoringModifiers chars: String?, flags: NSEvent.ModifierFlags) -> KeyChord? {
        guard let chars, let first = chars.unicodeScalars.first else { return nil }

        var mods: Set<KeyChord.Modifier> = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }

        if let name = specialByScalar[Int(first.value)] { return KeyChord(key: name, modifiers: mods) }
        switch first {
        case " ": return KeyChord(key: "space", modifiers: mods)
        case "\r", "\u{3}": return KeyChord(key: "return", modifiers: mods)
        default: break
        }
        guard chars.count == 1 else { return nil }
        return KeyChord(key: chars.lowercased(), modifiers: mods)
    }
}
```

- [ ] **Step 4: Run converter tests to verify they pass**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MiniKeyChordTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Add monitor state to `DocumentView`**

In `DocumentView.swift`, near the other `@State`s (around line 34), add:

```swift
@State var miniKeyMonitor: Any?
@State var isMainWindowCollapsed = false
@State var seekBox = SeekTaskBox()
```

- [ ] **Step 6: Implement the monitor install/remove**

Create `OnlyCue/UI/DocumentView+MiniKeyMonitor.swift`:

```swift
import AppKit
import SwiftUI

extension DocumentView {

    /// Installs the app-local key-down monitor that lets the Mini Player receive
    /// playback shortcuts when it is the frontmost surface (#743). Idempotent.
    func startMiniKeyMonitor() {
        guard miniKeyMonitor == nil else { return }
        miniKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleMiniKey(event) ? nil : event
        }
    }

    func stopMiniKeyMonitor() {
        if let token = miniKeyMonitor { NSEvent.removeMonitor(token) }
        miniKeyMonitor = nil
    }

    /// Returns true when the event was handled (and should be swallowed).
    private func handleMiniKey(_ event: NSEvent) -> Bool {
        let mainKey = NSApp.keyWindow?.canBecomeMain == true
        guard MiniPlaybackGate.shouldHandle(
            panelVisible: miniController.isVisible,
            isFrontmostMini: isMiniFrontmost,
            mainWindowIsKey: mainKey
        ) else { return false }

        guard let chord = MiniKeyChord.from(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            flags: event.modifierFlags
        ), let action = MiniPlaybackKeymap.action(for: chord, keymap: KeymapStore.shared.keymap) else {
            return false
        }

        MiniPlaybackActions(
            engine: engine,
            document: document,
            context: miniContext,
            ltcEnabled: ltcRoutingStore.settings.isEnabled,
            seekTaskBox: seekBox
        ).perform(action)
        return true
    }
}
```

- [ ] **Step 7: Start/stop the monitor with Mini Player visibility**

In `DocumentView+MiniPlayer.swift`, in `miniPlayerHosted(for:)`, add visibility-driven monitor control and teardown. After the existing `.onChange(of: view.document.model.activeItemID)` line add:

```swift
.onChange(of: view.miniPlayerVisible) { _, visible in
    if visible { view.startMiniKeyMonitor() } else { view.stopMiniKeyMonitor() }
}
```

And in the existing `.onDisappear { view.miniController.close() }`, also stop the monitor:

```swift
.onDisappear {
    view.stopMiniKeyMonitor()
    view.miniController.close()
}
```

- [ ] **Step 8: Regenerate, build, run the full unit suite**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests`
Expected: PASS. Build + SwiftLint clean.

- [ ] **Step 9: Commit**

```bash
git add OnlyCue/UI/MiniKeyChord.swift OnlyCue/UI/DocumentView+MiniKeyMonitor.swift OnlyCue/UI/DocumentView.swift OnlyCue/UI/DocumentView+MiniPlayer.swift OnlyCueTests/MiniKeyChordTests.swift
git commit -m "feat(miniplayer): route playback shortcuts to the mini player via a key monitor"
```

---

### Task 6: Collapse the main window on close (window delegate) instead of destroying it

**Files:**
- Create: `OnlyCue/UI/DocumentWindowAccessor.swift` (SwiftUI → NSWindow bridge + close-intercept delegate)
- Modify: `OnlyCue/UI/DocumentView.swift` (host the accessor in `.background`; store the window; restore/collapse methods)
- Test: covered by `MiniPlayerCollapseTests` (Task 3) for the decision; the AppKit wiring is thin glue.

**Interfaces:**
- Consumes: `MiniPlayerCollapse` (Task 3), `miniController.isVisible`.
- Produces on `DocumentView`: `func collapseMainWindow()`, `func restoreMainWindow()`, `@State var documentWindow: NSWindow?`.

- [ ] **Step 1: Implement the window accessor + close-intercepting delegate**

```swift
import AppKit
import SwiftUI

/// Bridges the SwiftUI document view to its host `NSWindow` and intercepts the
/// window's close button so it collapses to the Mini Player instead of tearing
/// the document down while the Mini Player is visible (#743).
struct DocumentWindowAccessor: NSViewRepresentable {

    let onResolve: (NSWindow) -> Void
    let shouldCollapseOnClose: () -> Bool
    let onCollapse: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolve(window)
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldCollapse: shouldCollapseOnClose, onCollapse: onCollapse)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let shouldCollapse: () -> Bool
        private let onCollapse: () -> Void
        init(shouldCollapse: @escaping () -> Bool, onCollapse: @escaping () -> Void) {
            self.shouldCollapse = shouldCollapse
            self.onCollapse = onCollapse
        }
        func attach(to window: NSWindow) { window.delegate = self }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldCollapse() else { return true }   // default close (document teardown)
            onCollapse()                                   // hide instead
            return false
        }
    }
}
```

Note for the implementer: if a `WindowAccessor` already exists in the codebase, reuse it and add only the `windowShouldClose` delegate behavior. Grep `NSViewRepresentable` under `OnlyCue/UI/` before creating a duplicate.

- [ ] **Step 2: Add window state + collapse/restore to `DocumentView`**

In `DocumentView.swift` add:

```swift
@State var documentWindow: NSWindow?
```

and methods (in `DocumentView+MiniKeyMonitor.swift` or a small `DocumentView+Collapse.swift`):

```swift
func collapseMainWindow() {
    documentWindow?.orderOut(nil)
    isMainWindowCollapsed = true
}

func restoreMainWindow() {
    documentWindow?.makeKeyAndOrderFront(nil)
    isMainWindowCollapsed = false
}
```

- [ ] **Step 3: Host the accessor in `DocumentView`'s `.background`**

In `DocumentView.swift`, alongside the existing invisible shortcut hosts in `.background`, add:

```swift
DocumentWindowAccessor(
    onResolve: { documentWindow = $0 },
    shouldCollapseOnClose: {
        MiniPlayerCollapse.onMainWindowClose(miniVisible: miniController.isVisible) == .collapseToMini
    },
    onCollapse: { collapseMainWindow() }
)
.frame(width: 0, height: 0)
```

- [ ] **Step 4: Regenerate, build, run unit suite**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests`
Expected: PASS, clean build.

- [ ] **Step 5: Manual smoke check (documented, run by maintainer)**

Open a document, load media, ⌘⌥M to show the Mini Player, click the main window's red X → main window hides, audio keeps playing, Space/arrows control playback via the Mini Player. Without the Mini Player visible, red X closes the document normally (save prompt if dirty).

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/DocumentWindowAccessor.swift OnlyCue/UI/DocumentView.swift OnlyCue/UI/DocumentView+Collapse.swift
git commit -m "feat(miniplayer): collapse main window to the mini player on close"
```

---

### Task 7: Restore on Mini Player close + ⌘⌥M restore semantics

**Files:**
- Modify: `OnlyCue/UI/MiniPlayerController.swift` (detect the panel's own close via a delegate; report via callback)
- Modify: `OnlyCue/UI/DocumentView+MiniPlayer.swift` (wire the callback; adjust `toggleMiniPlayer`)
- Modify: `OnlyCue/UI/DocumentView.swift` if needed for state.

**Interfaces:**
- Consumes: `MiniPlayerCollapse.onMiniClose(mainWindowHidden:)` (Task 3), `restoreMainWindow()` (Task 6).
- Produces on `MiniPlayerController`: `var onUserClosedPanel: (() -> Void)?` invoked when the user closes the panel via its close button.

- [ ] **Step 1: Detect the panel's own close in `MiniPlayerController`**

Add a private `NSWindowDelegate` coordinator to the controller and set it as the panel's delegate in `makePanel`; on `windowWillClose`, invoke `onUserClosedPanel?()`. Add:

```swift
var onUserClosedPanel: (() -> Void)?

private lazy var panelDelegate = PanelDelegate { [weak self] in self?.onUserClosedPanel?() }

private final class PanelDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
```

In `makePanel`, before returning: `panel.delegate = panelDelegate`. Ensure `hide()` (orderOut) does NOT trigger `windowWillClose` — it does not (orderOut ≠ close), so the toggle/hide path is unaffected; only the user clicking the panel's X closes it.

- [ ] **Step 2: Wire the restore callback in `DocumentView`**

In `DocumentView+MiniPlayer.swift`, when creating/first showing the panel (in `openMiniPlayer`/`toggleMiniPlayer`), set the callback once:

```swift
miniController.onUserClosedPanel = {
    miniPlayerVisible = false
    stopMiniKeyMonitor()
    if MiniPlayerCollapse.onMiniClose(mainWindowHidden: isMainWindowCollapsed) == .restoreMainWindow {
        restoreMainWindow()
    }
}
```

(Set it in `syncMiniPlayerContext()` or a one-time setup guarded by a flag so it isn't reassigned every render.)

- [ ] **Step 3: ⌘⌥M restore semantics**

In `toggleMiniPlayer()`, when the Mini Player is currently visible AND `isMainWindowCollapsed`, treat the toggle as "restore main + hide mini":

```swift
func toggleMiniPlayer() {
    if miniController.isVisible && isMainWindowCollapsed {
        miniController.hide()
        miniPlayerVisible = false
        stopMiniKeyMonitor()
        restoreMainWindow()
        return
    }
    syncMiniPlayerContext()
    miniController.toggle(rootView: miniPlayerRoot, title: miniPlayerTitle, autosaveName: Self.miniAutosaveName)
    miniPlayerVisible = miniController.isVisible
    if miniPlayerVisible { startMiniKeyMonitor() } else { stopMiniKeyMonitor() }
}
```

- [ ] **Step 4: Regenerate, build, run unit suite**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests`
Expected: PASS, clean build.

- [ ] **Step 5: Manual smoke check (documented)**

With the main window collapsed and Mini Player visible: closing the Mini Player (its X) restores the main window. ⌘⌥M also restores the main window and hides the Mini Player. With the main window visible, closing the Mini Player just hides it (no change to the main window).

- [ ] **Step 6: Commit**

```bash
git add OnlyCue/UI/MiniPlayerController.swift OnlyCue/UI/DocumentView+MiniPlayer.swift OnlyCue/UI/DocumentView.swift
git commit -m "feat(miniplayer): restore the main window when the mini player closes"
```

---

### Task 8: `View → Show Main Window` menu command

**Files:**
- Modify: `OnlyCue/UI/AppNotifications.swift` (add `.showMainWindowRequested`)
- Modify: `OnlyCue/App/AppCommands.swift` (add the menu item after "Mini Player")
- Modify: `OnlyCue/UI/DocumentView+MiniPlayer.swift` (receive the notification, gated to the frontmost mini)

**Interfaces:**
- Consumes: `restoreMainWindow()` (Task 6), `miniHandlesNotifications`.

- [ ] **Step 1: Add the notification name**

In `OnlyCue/UI/AppNotifications.swift`:

```swift
static let showMainWindowRequested = Notification.Name("OnlyCue.showMainWindowRequested")
```

- [ ] **Step 2: Add the menu item**

In `AppCommands.swift`, immediately after the "Mini Player" button (line ~166):

```swift
Button("Show Main Window") {
    NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
}
.accessibilityIdentifier("showMainWindowMenuItem")
```

(No default key equivalent — it is a rarely-used recovery command; the operator normally uses ⌘⌥M or the Mini Player's close button.)

- [ ] **Step 3: Receive it in `DocumentView+MiniPlayer.swift`**

In `miniPlayerHosted(for:)` add:

```swift
.onReceive(NotificationCenter.default.publisher(for: .showMainWindowRequested)) { _ in
    guard view.miniHandlesNotifications, view.isMainWindowCollapsed else { return }
    view.restoreMainWindow()
    view.miniController.hide()
    view.miniPlayerVisible = false
    view.stopMiniKeyMonitor()
}
```

- [ ] **Step 4: Regenerate, build, run unit suite**

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests`
Expected: PASS, clean build.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/AppNotifications.swift OnlyCue/App/AppCommands.swift OnlyCue/UI/DocumentView+MiniPlayer.swift
git commit -m "feat(miniplayer): add View > Show Main Window command"
```

---

### Task 9: Simplify pass + spec footnote

- [ ] **Step 1: Run the `simplify` skill** over the branch diff (`git diff dev...HEAD`). Apply reuse/dedup findings (e.g. if `stepCue`/`go`/`jump` now duplicate `DocumentView`'s versions, consider whether `DocumentView` should also route through `MiniPlaybackActions` — only if it stays surgical). Commit any cleanup separately as `refactor: ...`.

- [ ] **Step 2:** Confirm the mini spec footnote — the design doc already records that the 2026-08-16 mini spec's "closes with its window" line is relaxed; no code change needed. If `docs/superpowers/specs/2026-08-16-miniplay-design.md` should carry a back-reference, add a one-line note pointing to the 2026-08-17 spec and commit as `docs(spec): ...`.

- [ ] **Step 3:** Full unit suite + build green before PR:

Run: `xcodegen generate && xcodebuild build-for-testing -scheme OnlyCue -destination 'platform=macOS' -quiet && xcodebuild test-without-building -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests`

---

## Self-review

- **Spec coverage:** Feature 1 whitelist → Task 1; Approach-A gate → Task 2; shared action seam → Task 4; NSEvent monitor + conversion → Task 5. Feature 2 collapse decision → Task 3; window-close intercept/collapse → Task 6; restore on mini close + ⌘⌥M → Task 7; `Show Main Window` → Task 8. Non-goals honored (no global monitor; no new song keys; no editing keys; panel stays non-activating). Invariant "never zero visible surfaces / never silently discard" → Tasks 6–8 decisions + default-close path.
- **Placeholder scan:** none — every code step carries real code; manual smoke checks are explicitly maintainer-run, not substitutes for the unit tests on the pure units.
- **Type consistency:** `MiniPlaybackAction` (Task 1) consumed by `MiniPlaybackKeymap` (Task 1) and `MiniPlaybackActions.perform`/`rateChange` (Task 4) and the monitor (Task 5). `MiniPlayerCollapse.CloseOutcome`/`MiniCloseOutcome` (Task 3) consumed in Tasks 6–8. `SeekTaskBox` defined in Task 4, reused in Task 5's `DocumentView.seekBox`. `documentWindow`/`isMainWindowCollapsed`/`miniKeyMonitor` all declared in Tasks 5–6.
- **Risk watch:** Task 6's `windowShouldClose`-returns-false leaves a hidden-but-open document in the Window menu — acceptable and reversible via Tasks 7–8; verified by the maintainer smoke checks. Multi-document is scoped by `isFrontmostMini`/`miniHandlesNotifications` throughout.
