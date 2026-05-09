# Cue inspector — commit drafts on outside-click

**Status:** approved (2026-05-09)
**Brainstorm:** session `e36fc334-a717-4c7d-a091-0c0ed0d301bf` (branched from PR #72 thread)
**Scope:** bug fix on `OnlyCue/UI/CueInspectorView.swift`'s commit-on-focus-leave path
**Type:** `feat` (commit prefix `feat(ui):`) — net-new, but small

---

## Problem

`CueInspectorView` already wires commit-on-focus-leave for all four editable fields (Number, Name, Fade, Notes) via:

```swift
.onChange(of: focused) { old, _ in commitOnFocusLeave(field: old, cue: cue) }
```

When focus moves between two SwiftUI focusable views (`TextField` ↔ `TextField`, `TextField` → `Button`, etc.) this fires correctly and the active field's draft commits through `CueCommands.setNotes` / `setName` / `setCueNumber` / `setFadeTime`.

The bug: SwiftUI's `@FocusState` only updates when focus moves to **another focusable view**. When the user clicks on a non-focusable area — the inspector divider, the gap between rows, the waveform pane, the document title text, or the sidebar's background — `@FocusState focused` retains its previous value, `.onChange(of: focused)` never fires, and the user's typed draft is silently lost (typically when they switch cues, which clears the draft buffer via `syncDrafts` for any non-active field).

User confirmation of repro click targets (via `AskUserQuestion` during brainstorm):
1. ✅ Inside the inspector pane (divider, Manage Types button area, gaps between rows)
2. ✅ On the waveform or video preview
3. ✅ On the sidebar (media item list) or the document title area
4. ❌ On a different cue row in the cue list — this path commits correctly because the cue switch mechanism is independent

User confirmation of scope: same bug applies to all four inspector fields (Number / Name / Fade / Notes); fix should apply uniformly.

## Goal

Clicking anywhere outside the active inspector text field — on any non-focusable surface in the document window — must commit the active draft through `CueCommands` before the click's other side-effects (scrub, item-switch, etc.) take effect.

## Approach

Install a window-scoped `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` on the document window. When the monitor fires:

1. If `window.firstResponder` is `nil` → no-op, return event unchanged.
2. If `window.firstResponder` is **not** an `NSText` (i.e. not a `TextField` / `TextEditor` underlying view) → no-op, return event unchanged. We must not yank focus from buttons or other focusable controls.
3. Convert the event's `locationInWindow` to the first responder's coordinate space and hit-test:
   - If the click is **inside** the first responder's bounds → no-op. Lets the user click within their own text view to move the cursor without triggering a commit.
   - If the click is **outside** → call `window.makeFirstResponder(nil)`.
4. Always return the event unchanged so SwiftUI's normal click handling proceeds afterward — clicks on the waveform / sidebar / etc. still do whatever they would have done.

Resigning first responder propagates to SwiftUI's `@FocusState focused` (it observes the AppKit first-responder via the underlying `NSTextField` / `NSTextView`), which fires the existing `.onChange(of: focused)` and runs `commitOnFocusLeave` for whichever inspector field was active. The commit goes through `CueCommands.setNotes` / `setName` / `setCueNumber` / `setFadeTime` exactly as it does today on Tab or clicking another `TextField`.

**Why a single window-level hook (vs scattered SwiftUI tap gestures):** one place to maintain, automatically covers any future pane / surface added under the document window, no need to lift `@FocusState` up to `DocumentView` or thread bindings through three view layers. Approach B (SwiftUI tap gestures on every non-focusable surface) was considered and rejected — four hook points spread across views, fragile (preview pane's existing `MagnifyGesture` and drag handlers would swallow tap gestures in many cases), silently breaks when a future pane is added without the hook.

**Why not live-commit on every keystroke (Approach C):** would force a rewrite of `CueInspectorCommit.commitFadeTime` / `commitCueNumber` (mid-typed `1/` would partially-parse and revert), would bloat undo (one undo step per keystroke unless we add coalescing in `CueCommands` — separate work), and defers commits in a way that "click then close window before debounce fires" loses data. Approach A is a smaller, more conservative fix.

**Why AppKit (`NSEvent`):** `AppCommands.swift` already imports AppKit (`NSCursor`, `NSApplication`); `VerticalZoomDragHandle.swift` already uses `NSCursor.resizeUpDown.push() / .pop()`. The codebase has a precedent of reaching for AppKit when SwiftUI doesn't expose a needed primitive. SwiftUI macOS 14 has no first-class API for "all clicks anywhere in the window" — `NSEvent.addLocalMonitorForEvents` is the canonical fallback.

## Components

### `OnlyCue/UI/FirstResponderResign.swift` (new file)

Two pieces:

```swift
/// Pure-logic predicate. Given a left-mouse-down at `clickLocationInWindow`,
/// the first responder's frame in window coordinates, and whether the first
/// responder is an `NSText` subclass, decide whether to call
/// `window.makeFirstResponder(nil)`. Extracted so the hit-test logic can be
/// unit-tested without a real NSWindow.
enum FirstResponderResign {
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

```swift
/// SwiftUI view modifier that installs a window-scoped local NSEvent monitor
/// for `.leftMouseDown` events. On every event:
///   1. resolve the host NSWindow from the underlying NSView
///   2. ask `FirstResponderResign.shouldResign(...)`
///   3. if yes, call `window.makeFirstResponder(nil)`
/// Returns the event unchanged so normal click handling proceeds.
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
    /// first responder when the user clicks outside an active text field.
    /// Apply once at the document window's root.
    func resignFirstResponderOnOutsideClick() -> some View {
        modifier(FirstResponderResignOnOutsideClick())
    }
}
```

### `OnlyCue/UI/DocumentView.swift` (one-line change)

Apply the modifier at `body`'s outermost view (the `NavigationSplitView`):

```swift
NavigationSplitView { ... } detail: { ... }
    .navigationSubtitle(...)
    .sheet(...) { ... }
    .task(id: ...) { ... }
    .resignFirstResponderOnOutsideClick()  // <-- new
```

No changes to `CueInspectorView`. The existing `.onChange(of: focused)` and `commitOnFocusLeave` machinery remain unchanged — we're only patching the missing trigger.

## Tests

`OnlyCueTests/FirstResponderResignTests.swift` (new file, ~40 lines, 4 tests):

- `test_clickInsideTextFieldFrame_doesNotResign`
  - Frame `(10, 10, 100, 30)`, click at `(50, 25)` → `shouldResign = false`
- `test_clickOutsideTextFieldFrame_resigns`
  - Frame `(10, 10, 100, 30)`, click at `(200, 200)` → `shouldResign = true`
- `test_clickWhenFirstResponderIsNotText_doesNotResign`
  - Any click position with `firstResponderIsText = false` → `shouldResign = false`
- `test_clickOnFirstResponderEdge_doesNotResign`
  - Frame `(10, 10, 100, 30)`, click at `(10, 10)` (top-left corner) → `shouldResign = false` (boundary case; `NSRect.contains` is inclusive)

The `MonitorInstaller` install / remove lifecycle is not unit-testable without spinning up an `NSWindow`; it's covered by manual verification.

## Manual verification

- Type "GO Wash" into the Notes textarea of the active cue. Click on the waveform. Switch to a different cue, then back. Verify the notes are persisted.
- Type "Stage Left" into the Notes textarea. Click on the inspector's empty divider area between fields. Switch cues and back. Verify persisted.
- Type into the Notes textarea. Click on the sidebar's empty area below the last item. Verify the active draft commits.
- Type "1.5" into Number. Click on the waveform. Verify Number is now `1.5` (regression check — same fix path applies to all four fields).
- Type "Wash" into Notes. Click within the Notes textarea (move the cursor). Verify the cursor moves and the textarea retains focus and the draft is **not** committed yet (validates the inside-frame guard).
- Click the Play button while focused in Number. Verify the existing path still works (button takes focus → focused changes → commitOnFocusLeave fires).
- Right-click on the waveform while typing in Notes. Verify Notes does **not** commit (right-click is not in `.leftMouseDown`).
- Cmd+Z after committing via outside-click. Verify undo restores the prior value (validates the commit went through `CueCommands.setNotes`).

## Acceptance (Gherkin)

```gherkin
Scenario: Click on waveform commits Notes draft
  Given the user has typed "GO Wash" into the Notes textarea
  When the user clicks on the waveform area
  Then the Notes field's first responder is resigned
  And CueCommands.setNotes is called with "GO Wash"
  And switching to another cue and back shows "GO Wash" persisted

Scenario: Click inside Notes textarea does not commit
  Given the user has typed "Stage Left" into the Notes textarea
  When the user clicks within the textarea bounds (e.g. to reposition the cursor)
  Then the Notes field retains first-responder status
  And no commit fires
  And the cursor moves to the click location

Scenario: Click on a focusable button while in Number commits
  Given the user has typed "1.5" into the Number TextField
  When the user clicks the Play button
  Then the existing focus-change path commits via setCueNumber
  And the new value is "1.5"

Scenario: Right-click does not trigger resign
  Given the user is typing in Notes
  When the user right-clicks on the waveform
  Then the Notes field retains first-responder status
  And the typed draft is not committed
```

## Out of scope

- Changing `commitNotes` / `commitName` / `commitNumber` / `commitFade` — they keep their parse-or-revert / idempotency / undo-registration semantics.
- Lifting `@FocusState focused` out of `CueInspectorView`.
- Generalizing the modifier to other future text fields outside the document window — applied at `DocumentView`, so any text input added under the document window automatically benefits. Future panels / sheets with their own NSWindow would need to apply the modifier separately.
- Right-click / `.rightMouseDown` — only the primary click triggers resign. Right-click typically opens context menus and shouldn't commit a draft underneath.
- Coalescing undo entries from rapid commits (current per-commit undo is acceptable).
- Live-commit / debounced-commit / dropping the draft buffer — all rejected as Approach C in the brainstorm.

## Files touched

- `OnlyCue/UI/FirstResponderResign.swift` — new (~70 lines: `enum FirstResponderResign` pure helper + `FirstResponderResignOnOutsideClick` ViewModifier + `MonitorInstaller` NSViewRepresentable + `Coordinator` + `View` extension)
- `OnlyCue/UI/DocumentView.swift` — append `.resignFirstResponderOnOutsideClick()` at the outermost view (1 line)
- `OnlyCueTests/FirstResponderResignTests.swift` — new (~40 lines, 4 unit tests)

## Risk & rollback

- **Risk: yanking focus too aggressively.** Mitigated by the `firstResponderIsText` guard (don't yank focus from buttons / segmented controls) and the inside-frame guard (don't yank when click is inside the active text view).
- **Risk: monitor leak across document close / reopen.** Mitigated by `Coordinator.deinit` calling `NSEvent.removeMonitor(_:)`.
- **Risk: monitor double-install.** Mitigated by the `context.coordinator.monitor == nil` guard in `updateNSView`.
- **Rollback:** delete `FirstResponderResign.swift` and remove the modifier call from `DocumentView`. No data migration. No schema impact. Existing commit machinery falls back to the prior (incomplete) Tab / focusable-target-only behavior.
