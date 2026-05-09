# Import Media in File Menu — Design

**Date:** 2026-05-09
**Status:** Approved (brainstorming)
**Spec section:** `docs/mvp.md` — media import; menu-bar surface.

## Goal

Expose "Import Media…" as a first-class entry in the macOS menu bar under **File**, so users can import media via the standard menu-bar path in addition to the existing in-app button and drag-and-drop.

## Non-goals

- Changing import semantics, supported types, or the importer pipeline.
- Adding "Open Recent" or other File-menu entries (future work).
- Touching `.cuelist` open/save flows.

## Architecture

- **`OnlyCue/App/AppCommands.swift`**
  - Add `CommandGroup(after: .newItem)` with a single button:
    - Title: `Import Media…`
    - Shortcut: `⌘O` (canonical owner of the shortcut after this change)
    - Action: `NotificationCenter.default.post(name: .importMediaRequested, object: nil)`
  - Pattern matches the existing View-menu entries (`waveformZoomIn`, etc.) so `Commands` stays decoupled from view state.

- **Notification name**
  - Define `Notification.Name.importMediaRequested = Notification.Name("OnlyCue.importMediaRequested")` in an `extension Notification.Name` at the bottom of `DocumentView.swift` (the receiver). Mirrors the pattern in `WaveformContainer.swift:279-280` where the receiver owns its notification names.

- **`OnlyCue/UI/DocumentView.swift`**
  - Add `.onReceive(NotificationCenter.default.publisher(for: .importMediaRequested))` on `mainPane` (or the root view) that sets `showImporter = true`.
  - Keep the in-app `Button("Import Media…")` at line 55 as a visible affordance.
  - **Remove** the `.keyboardShortcut("o", modifiers: .command)` from that button — the File-menu item now owns ⌘O. This avoids duplicate-shortcut ambiguity.

No other layers (`MediaImporter`, `.fileImporter`, importer pipeline) change.

## Data flow

1. User selects File → Import Media… (or presses ⌘O).
2. `AppCommands` posts `.importMediaRequested`.
3. `DocumentView` receives notification → sets `showImporter = true`.
4. Existing `.fileImporter` modifier presents the open panel.
5. On selection, existing `handlePickerResult` → `importURLs` → `MediaImporter.importMedia` flow runs unchanged.

## Error handling

Unchanged. Existing `pendingAlert` flow handles unsupported files and import errors.

## Testing

**Unit (TDD, write failing first):**

- `OnlyCueTests/`: assert `Notification.Name.importMediaRequested.rawValue` equals the expected string (mirrors existing notification-name tests for waveform commands).

**UI / BDD (`OnlyCueUITests/`):**

- Given the app is launched with no media imported,
- When the user activates **File → Import Media…** from the menu bar,
- Then the system file-open panel appears (assert presence of the open panel; cancel to dismiss).

## Risks / Notes

- **Duplicate shortcut:** mitigated by removing ⌘O from the in-app button; the menu item is the sole owner.
- **Discoverability:** in-app button stays for users who haven't found the menu yet.
- **Future:** a follow-up could add "Open Recent" and/or move the in-app button to a less prominent spot once the menu is the established entry point.

## Out of scope (deferred)

- Open Recent submenu.
- Reorganizing other File-menu entries.
- Changes to drag-and-drop or sidebar drop targets.
