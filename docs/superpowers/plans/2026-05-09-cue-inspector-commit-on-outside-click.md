# Cue Inspector — Commit Drafts on Outside-Click Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking on any non-focusable surface in the OnlyCue document window (waveform, sidebar, inspector empty space) commits the active inspector text-field draft (Number / Name / Fade / Notes) through `CueCommands` before the click's other side-effects take effect.

**Architecture:** Install a window-scoped `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` via a SwiftUI `ViewModifier` applied at `DocumentView`'s body root. On every left-mouse-down, if the window's `firstResponder` is an `NSText` and the click lands outside its frame, call `window.makeFirstResponder(nil)` — that propagates to SwiftUI's `@FocusState focused` in `CueInspectorView`, fires the existing `.onChange(of: focused)`, and triggers `commitOnFocusLeave` which writes through `CueCommands.setNotes` / `setName` / `setCueNumber` / `setFadeTime`. No changes to `CueInspectorView`'s commit machinery — we're only patching the missing focus-leave trigger.

**Tech Stack:** Swift 5.10+, SwiftUI on macOS 14+, AppKit (`NSEvent`, `NSWindow`, `NSText`), XCTest. Spec at `docs/superpowers/specs/2026-05-09-cue-inspector-commit-on-outside-click-design.md`.

---

## File Structure

| File | Responsibility | New / Modified |
|---|---|---|
| `OnlyCue/UI/FirstResponderResign.swift` | (1) `enum FirstResponderResign` — pure-logic predicate `shouldResign(...)`; (2) `FirstResponderResignOnOutsideClick` ViewModifier with `MonitorInstaller` NSViewRepresentable + `Coordinator` for monitor lifecycle; (3) `View.resignFirstResponderOnOutsideClick()` convenience extension | New (~70 lines) |
| `OnlyCue/UI/DocumentView.swift` | Apply `.resignFirstResponderOnOutsideClick()` at `body`'s outermost view (after `.task(id:)`) | Modified (1 line added) |
| `OnlyCueTests/FirstResponderResignTests.swift` | 4 unit tests for the pure helper: inside-frame, outside-frame, non-text first responder, edge boundary | New (~50 lines) |

The pure helper and the SwiftUI/AppKit plumbing live in the same file because they're tightly coupled (the predicate exists only so the view modifier's monitor closure has unit-testable logic). One file, one responsibility surface ("when does the document window resign first responder on a left-click?"). Below 100 lines, well within the codebase's file-length convention.

---

### Task 1: Add the pure-logic helper with TDD

**Files:**
- Create: `OnlyCue/UI/FirstResponderResign.swift`
- Test: `OnlyCueTests/FirstResponderResignTests.swift`

This task ships only the pure predicate `FirstResponderResign.shouldResign(...)` and its tests. The view modifier comes in Task 2 once the predicate is locked in green.

- [ ] **Step 1.1: Write the failing test file**

Create `OnlyCueTests/FirstResponderResignTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class FirstResponderResignTests: XCTestCase {

    private let textFieldFrame = NSRect(x: 10, y: 10, width: 100, height: 30)

    func test_clickInsideTextFieldFrame_doesNotResign() {
        let click = NSPoint(x: 50, y: 25)
        XCTAssertFalse(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: textFieldFrame,
                firstResponderIsText: true
            ),
            "clicks inside the text field's frame must not resign — let the user move the cursor without committing"
        )
    }

    func test_clickOutsideTextFieldFrame_resigns() {
        let click = NSPoint(x: 200, y: 200)
        XCTAssertTrue(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: textFieldFrame,
                firstResponderIsText: true
            ),
            "clicks outside the text field's frame must resign — that's the whole point of this fix"
        )
    }

    func test_clickWhenFirstResponderIsNotText_doesNotResign() {
        let click = NSPoint(x: 200, y: 200)
        XCTAssertFalse(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: textFieldFrame,
                firstResponderIsText: false
            ),
            "must not yank focus from buttons / segmented controls / other non-text focusable views"
        )
    }

    func test_clickOnFirstResponderEdge_doesNotResign() {
        let click = NSPoint(x: 10, y: 10)
        XCTAssertFalse(
            FirstResponderResign.shouldResign(
                clickLocationInWindow: click,
                firstResponderFrameInWindow: textFieldFrame,
                firstResponderIsText: true
            ),
            "NSRect.contains is inclusive on the edge — boundary click must not resign"
        )
    }
}
```

- [ ] **Step 1.2: Regenerate the Xcode project (xcodegen folder rules pick up new files)**

Run: `make generate`
Expected: `Created project at /Users/chienchuanw/Documents/only-cue/OnlyCue.xcodeproj`

If `make` is unavailable, run `xcodegen generate` directly.

- [ ] **Step 1.3: Run the test class to confirm RED**

Run:
```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/FirstResponderResignTests \
  2>&1 | grep -E "error:|TEST FAILED|TEST SUCCEEDED" | head -8
```

Expected: compile error `cannot find 'FirstResponderResign' in scope` (4 instances, one per test). This confirms the test exercises the right symbol and the symbol is missing — true RED, not a typo or import error.

- [ ] **Step 1.4: Create `FirstResponderResign.swift` with only the pure helper (Task 2 adds the view modifier)**

Create `OnlyCue/UI/FirstResponderResign.swift`:

```swift
import AppKit

/// Pure-logic predicate for the document window's outside-click resign behavior.
/// Extracted from `FirstResponderResignOnOutsideClick`'s monitor closure so the
/// hit-test decision is unit-testable without spinning up an `NSWindow`.
enum FirstResponderResign {

    /// Should the document window resign first responder when a left-mouse-down
    /// fires at `clickLocationInWindow`?
    ///
    /// - Parameters:
    ///   - clickLocationInWindow: event coordinates in the window's coordinate space
    ///   - firstResponderFrameInWindow: the first responder's frame, converted to
    ///     window coordinates via `firstResponder.convert(firstResponder.bounds, to: nil)`
    ///   - firstResponderIsText: whether `window.firstResponder is NSText` — guards
    ///     against yanking focus from buttons, segmented controls, etc.
    /// - Returns: `true` to call `window.makeFirstResponder(nil)`, `false` otherwise.
    static func shouldResign(
        clickLocationInWindow: NSPoint,
        firstResponderFrameInWindow: NSRect,
        firstResponderIsText: Bool
    ) -> Bool {
        guard firstResponderIsText else { return false }
        return !firstResponderFrameInWindow.contains(clickLocationInWindow)
    }
}
```

- [ ] **Step 1.5: Run the test class to confirm GREEN**

Run:
```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/FirstResponderResignTests \
  2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -3
```

Expected: `Executed 4 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 1.6: Commit**

```bash
git add OnlyCue/UI/FirstResponderResign.swift OnlyCueTests/FirstResponderResignTests.swift
git commit -m "feat(ui): add FirstResponderResign predicate for outside-click commit"
```

(No Co-Authored-By trailer per `CLAUDE.md`.)

---

### Task 2: Add the SwiftUI view modifier and AppKit monitor installer

**Files:**
- Modify: `OnlyCue/UI/FirstResponderResign.swift` (append the view modifier and `View` extension)

This task adds the SwiftUI plumbing on top of the green pure helper. The `MonitorInstaller` lifecycle (install / remove) is not unit-testable without a real `NSWindow`; manual verification in Task 4 covers it.

- [ ] **Step 2.1: Append the view modifier, `MonitorInstaller`, `Coordinator`, and `View` extension to `FirstResponderResign.swift`**

Append to the existing file:

```swift
import SwiftUI

/// SwiftUI view modifier that installs a window-scoped local `NSEvent` monitor
/// for `.leftMouseDown` events. On every event:
///   1. resolve the host `NSWindow` from the event
///   2. ask `FirstResponderResign.shouldResign(...)`
///   3. if yes, call `window.makeFirstResponder(nil)` so SwiftUI's `@FocusState`
///      observers see the focus change and run their commit-on-focus-leave path
/// Returns the event unchanged so normal click handling proceeds afterward.
struct FirstResponderResignOnOutsideClick: ViewModifier {
    func body(content: Content) -> some View {
        content.background(MonitorInstaller())
    }

    private struct MonitorInstaller: NSViewRepresentable {

        final class Coordinator {
            var monitor: Any?
            deinit {
                if let monitor { NSEvent.removeMonitor(monitor) }
            }
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard context.coordinator.monitor == nil else { return }
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(
                matching: .leftMouseDown
            ) { event in
                guard
                    let window = event.window,
                    let firstResponder = window.firstResponder as? NSText
                else { return event }

                // NSText is-a NSView, so .convert is available without a re-cast.
                let frame = firstResponder.convert(firstResponder.bounds, to: nil)
                let shouldResign = FirstResponderResign.shouldResign(
                    clickLocationInWindow: event.locationInWindow,
                    firstResponderFrameInWindow: frame,
                    firstResponderIsText: true
                )
                if shouldResign {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }
}

extension View {
    /// Installs a window-scoped left-mouse-down monitor that resigns the
    /// active first responder when the user clicks outside its frame.
    /// Apply once at the document window's root.
    func resignFirstResponderOnOutsideClick() -> some View {
        modifier(FirstResponderResignOnOutsideClick())
    }
}
```

- [ ] **Step 2.2: Build to confirm the file compiles**

Run:
```bash
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. Ignore SourceKit-LSP "Cannot find type X in scope" diagnostics — they're indexing-lag false positives in this project (consistent across PRs #60 / #61 / #63 / #65 / #67 / #69 / #72).

- [ ] **Step 2.3: Re-run the existing test class to confirm the predicate tests still pass**

Run:
```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests/FirstResponderResignTests \
  2>&1 | grep -E "Executed|TEST SUCCEEDED|TEST FAILED" | tail -3
```

Expected: `Executed 4 tests, with 0 failures` — the predicate is unaffected by adding the view modifier.

- [ ] **Step 2.4: Commit**

```bash
git add OnlyCue/UI/FirstResponderResign.swift
git commit -m "feat(ui): add FirstResponderResignOnOutsideClick view modifier"
```

---

### Task 3: Apply the modifier at `DocumentView`'s body root

**Files:**
- Modify: `OnlyCue/UI/DocumentView.swift` (append `.resignFirstResponderOnOutsideClick()` after `.task(id:)`)

- [ ] **Step 3.1: Read the current `DocumentView.body` to find the correct anchor**

Run: `grep -n '.task(id: document.model.activeItemID)' OnlyCue/UI/DocumentView.swift`
Expected: one match around line 32 in the format `.task(id: document.model.activeItemID) { await reloadActive() }`.

If the file has changed and the anchor isn't there, locate the outermost view modifiers chain at the end of `body` and append `.resignFirstResponderOnOutsideClick()` as the **last** modifier.

- [ ] **Step 3.2: Apply the modifier**

Use the Edit tool with the matching context. The expected current shape ends with:

```swift
        .task(id: document.model.activeItemID) { await reloadActive() }
    }
```

Edit to:

```swift
        .task(id: document.model.activeItemID) { await reloadActive() }
        .resignFirstResponderOnOutsideClick()
    }
```

If `DocumentView` already has additional trailing modifiers (e.g., the `.sheet` for `FirstLaunchSheet` is between `.task` and the closing brace), append `.resignFirstResponderOnOutsideClick()` after them — it must be the outermost modifier on `body` so the monitor sees clicks from the entire window's hosted view tree.

- [ ] **Step 3.3: Build to confirm DocumentView still compiles**

Run:
```bash
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3.4: Commit**

```bash
git add OnlyCue/UI/DocumentView.swift
git commit -m "feat(ui): apply outside-click first-responder resign at document root"
```

---

### Task 4: Run all gates and manual verification

**Files:** none (verification only)

- [ ] **Step 4.1: Run the full unit test suite**

Run:
```bash
xcodebuild test \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -destination 'platform=macOS' \
  -only-testing:OnlyCueTests \
  2>&1 | grep -E "Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED|error:" | tail -3
```

Expected: `Executed N tests, with 0 failures` (where N = baseline + 4) and `** TEST SUCCEEDED **`. If any pre-existing test fails, stop and investigate — Task 1–3 should not affect any other test.

- [ ] **Step 4.2: Run SwiftLint --strict**

Run: `swiftlint --strict 2>&1 | tail -3`
Expected: `Done linting! Found 0 violations, 0 serious in N files.`

If a `multiline_arguments` or other violation surfaces in the new files, fix it inline before continuing. The most likely candidate is the long `firstResponderFrameInWindow:` argument label across a multi-line call site — match the project's established pattern (each argument on its own line if any are wrapped).

- [ ] **Step 4.3: Release build with warnings as errors**

Run:
```bash
xcodebuild build \
  -project OnlyCue.xcodeproj \
  -scheme OnlyCue \
  -configuration Release \
  -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  2>&1 | grep -E "warning:|error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
```

Expected: `** BUILD SUCCEEDED **` with no `warning:` lines (other than the harmless `appintentsmetadataprocessor` Metadata extraction warning, which is pre-existing across all recent builds).

- [ ] **Step 4.4: Manual verification — end-to-end UI test**

Launch the app:
```bash
open -a OnlyCue.app
# or if running from Xcode build dir:
open ~/Library/Developer/Xcode/DerivedData/OnlyCue-*/Build/Products/Debug/OnlyCue.app
```

Run through every check below. Each check matches a Manual verification bullet in the spec:

1. **Type into Notes, click on the waveform**
   - Open a `.cuelist` document (or create one with imported audio). Click a cue. Click into the inspector's Notes textarea. Type `GO Wash`.
   - Click anywhere on the waveform / video preview area.
   - Switch to a different cue, then back to the original. Verify the Notes field now reads `GO Wash` (commit went through).

2. **Type into Notes, click on the inspector divider area**
   - Same setup. Type `Stage Left` into Notes.
   - Click on the inspector's empty area between rows or on the divider above the "Manage Types…" button.
   - Switch cues and back. Verify `Stage Left` persisted.

3. **Type into Notes, click on the sidebar empty area**
   - Same setup. Type into Notes.
   - Click on the sidebar (item list) below the last item, in empty space.
   - Switch cues and back. Verify the typed value persisted.

4. **Regression check — Number field**
   - Click the inspector's Number field. Type `1.5` (replacing whatever was there).
   - Click on the waveform.
   - Verify the Number field shows `1.5` and the cue list row's number column reflects it.

5. **Inside-frame guard — clicking within Notes**
   - Click into Notes and type `Wash`. Click again **inside the textarea** (e.g., to reposition the cursor between letters).
   - Verify the cursor moves to the click location, the textarea retains focus, and no spurious commit fires (best observed by the cursor staying in place / no sudden re-render of the cue list row).

6. **Existing focus-change path still works**
   - Click into Number, type `2.5`. Click the Play button (or press Space).
   - Verify the existing path still commits — Number shows `2.5` after the focus change to the button.

7. **Right-click does not trigger resign**
   - Type into Notes. Right-click on the waveform.
   - Verify the Notes field still has focus and the typed text is **not** committed (it remains in the draft until the user clicks elsewhere with the primary mouse button or presses Tab / Enter).

8. **Cmd+Z restores prior value**
   - Type into Notes (different from the cue's existing notes). Click on the waveform to commit. Press `⌘Z`.
   - Verify the Notes field reverts to the prior value — confirms the commit went through `CueCommands.setNotes` and registered an undo entry.

If any check fails, stop and diagnose. Most likely failure modes:
- `@FocusState` doesn't update after `makeFirstResponder(nil)` → SwiftUI version skew; verify `OnlyCue/UI/CueInspectorView.swift` has the existing `.onChange(of: focused)` block (line 91 in the spec snapshot).
- Click on waveform commits but click on sidebar doesn't → the modifier may not be at the outermost `body` modifier position; re-check Task 3 placement.

- [ ] **Step 4.5: Commit if any lint / WAE fixes were needed**

If Step 4.2 or 4.3 required edits, commit them as a separate fix:

```bash
git add OnlyCue/UI/FirstResponderResign.swift  # or whichever file changed
git commit -m "fix(ui): satisfy SwiftLint multiline_arguments in FirstResponderResign"
```

If no fixes were needed, skip this step.

---

## Self-review checklist

The plan author has verified:

- **Spec coverage:** every section of the spec is addressed.
  - Problem & root cause → captured in plan header.
  - Approach (4-step monitor algorithm) → Task 2 implements verbatim.
  - Components (`FirstResponderResign`, `FirstResponderResignOnOutsideClick`, `View` extension) → Task 1 + Task 2 + Task 3.
  - Tests (4 cases) → Task 1 Steps 1.1–1.5.
  - Manual verification checklist → Task 4 Step 4.4 (8 checks, 1:1 with spec).
  - Out of scope items → not implemented (correctly).

- **Placeholder scan:** no `TBD`, `TODO`, or `similar to Task N` left behind.

- **Type consistency:**
  - `FirstResponderResign.shouldResign(clickLocationInWindow:firstResponderFrameInWindow:firstResponderIsText:)` — same parameter names in tests (Task 1 Step 1.1), pure helper definition (Task 1 Step 1.4), and view modifier monitor closure (Task 2 Step 2.1).
  - `FirstResponderResignOnOutsideClick` ViewModifier name matches the file name's content and the `View.resignFirstResponderOnOutsideClick()` extension's modifier call.
  - `MonitorInstaller.Coordinator.monitor: Any?` — `addLocalMonitorForEvents` returns `Any?`; `removeMonitor(_:)` takes `Any` — matches.

- **Branch convention:** the plan does not assume a specific branch name. Issue creation (via `gh-issue` after this plan completes) and branching (via `gh-dev`) are out of scope for the plan itself.
