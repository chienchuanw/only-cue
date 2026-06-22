# Start Page (Welcome Window) — Design

**Issue:** #591
**Status:** approved (brainstorming)
**Date:** 2026-06-22

## Goal

Give OnlyCue a dedicated "Welcome to OnlyCue" window that lists recent projects for quick reopen and offers to start a new project — shown at launch instead of the default blank document, and reopenable from the menu.

## Constraints

- Pure SwiftUI `DocumentGroup` app, macOS **14.0+** (ADR-001 — do not raise the floor). `DocumentGroupLaunchScene` (macOS 15) is therefore **not** available; the welcome window is a plain SwiftUI `Window` scene plus a thin AppKit boundary.
- No App Sandbox (ADR-007). Recents come from `NSDocumentController.shared.recentDocumentURLs`, which the existing `DocumentGroup` already populates on open/save.
- No `ProjectModel` / schema change (this is launch UI only).
- Dark-only chrome (ADR-029); reuse `DS` tokens and the `FirstLaunchSheet` visual language.

## Architecture

A thin AppKit boundary around a pure-SwiftUI view, with the recents logic factored into a testable pure type.

```
OnlyCueApp (Scene)
├── DocumentGroup            (unchanged — the editor)
├── Window("welcome")        (NEW — hosts StartView)
└── @NSApplicationDelegateAdaptor(AppDelegate)
        └── applicationShouldOpenUntitledFile = false   (suppress auto blank doc)

StartView (SwiftUI, DS-styled)
├── reads RecentProjectsModel.load()  → [RecentProject]
├── left pane:  brand hero + tagline + actions (New / New from Template… / Open Other…)
└── right pane: Recent Projects list (open / remove-missing)

RecentProjectsModel (pure, unit-tested)
└── recentDocumentURLs + FileManager → [RecentProject]
```

## Components

### `RecentProject` (value type)
`{ url: URL, name: String, folder: String, date: Date?, exists: Bool }`
- `name` = `url.deletingPathExtension().lastPathComponent`.
- `folder` = abbreviated parent path (`~`-relative via `(path as NSString).abbreviatingWithTildeInPath` on the parent).
- `date` = file content-modification date (`URLResourceValues.contentModificationDate`); `nil` if unavailable.
- `exists` = `FileManager.fileExists(atPath:)`.

### `RecentProjectsModel` (pure / testable)
- `static func recents(from urls: [URL], fileManager: FileManager = .default) -> [RecentProject]` — maps the URL list (already newest-first from `NSDocumentController`) to rows, preserving order. This is the unit-tested seam.
- `static func load() -> [RecentProject]` — thin wrapper calling `recents(from: NSDocumentController.shared.recentDocumentURLs)` (the impure read).
- `static func removing(_ url: URL, from urls: [URL]) -> [URL]` — pure: the newest-first URL list with `url` dropped. Unit-tested; used by the remove flow below.

### `StartView` (SwiftUI)
- Two-pane `HStack`, ~720×460, fixed-ish.
- **Left:** `BrandHero` (reuse the `FirstLaunchSheet` "BrandHero" asset), title "OnlyCue", tagline, then three actions:
  - **New Project** → `NSDocumentController.shared.newDocument(nil)` (or `@Environment(\.newDocument)` equivalent).
  - **New from Template…** → reuse existing `TemplateAction.newDocument()` flow.
  - **Open Other…** → `NSDocumentController.shared.openDocument(nil)` (standard open panel).
- **Right:** "RECENT PROJECTS" `dsSectionHeader` + a scrollable list of rows. Each row shows name (primary), folder (secondary), date (mono small, trailing). Click or ⏎ on a present row → open it (`openDocument`/`NSDocumentController.openDocument(withContentsOf:display:)`). A row whose `exists == false` is greyed/disabled with an inline ⨯ that calls a remove (see below). Empty state: "No recent projects" hint.
- Opening any project (recent / new / template / other) closes the Welcome window.

### Welcome window lifecycle (`AppDelegate` + `Window` scene)
- `Window("Welcome to OnlyCue", id: "welcome") { StartView() }` — single welcome window.
- `AppDelegate.applicationShouldOpenUntitledFile(_:) -> false` suppresses the default blank document at launch so the Welcome window is what the user sees.
- A `File → Welcome to OnlyCue` command (`AppCommands`) reopens it via `@Environment(\.openWindow) openWindow("welcome")`.
- Best-effort: when the app is reactivated with no visible windows (dock click), show the Welcome window (`applicationShouldHandleReopen`). State restoration of previously-open document windows takes precedence — if macOS restores a document, the Welcome window is not forced on top.

## Data Flow

1. Launch → `applicationShouldOpenUntitledFile` returns false → Welcome window shows.
2. `StartView.onAppear` / `.task` → `RecentProjectsModel.load()` → render rows.
3. User action:
   - Recent row → open that URL → document window opens → Welcome closes.
   - New / Template / Open Other → respective `NSDocumentController` flow → Welcome closes.
   - Remove (missing row) → `NSDocumentController` has no public single-URL removal, so: compute `survivors = RecentProjectsModel.removing(url, from: recentDocumentURLs)`, call `clearRecentDocuments(nil)`, then `noteNewRecentDocumentURL(_:)` for each survivor **oldest → newest** so the system rebuilds the list with the original newest-first order. The reordering is the pure, tested part; the clear/re-note is the thin impure apply.

## Error Handling

- `RecentProjectsModel` never throws: an unreadable URL yields `exists = false`, `date = nil`; it is still listed (greyed) so the user can remove it.
- Opening a recent that has gone missing between render and click falls back to the existing "Missing media"/open-failure handling already in the document layer; the Welcome flow does not need its own alert.
- If the `Window` scene fails to auto-open at launch on some macOS 14 point release (the fiddly area), the `File → Welcome to OnlyCue` menu command is the guaranteed manual entry point.

## Testing

- **Unit (pure):** `RecentProjectsModelTests` — name/folder/date derivation; `exists` true/false against real temp files; ordering preserved from input; empty input → empty output; a missing path → `exists == false` and still present; `removing(_:from:)` drops the target and keeps the rest in order.
- **Manual (impure boundary, daemon-wedged UI-test caveat):** launch shows Welcome (no blank doc); recents populate; clicking a recent opens it and closes Welcome; New / Template / Open Other work; missing row greyed + removable; `File → Welcome to OnlyCue` reopens it.

## Out of Scope (YAGNI)

- Thumbnails / previews, pinning, search/filter, a "show at startup" preference toggle, a global "Clear Recents" (only per-row remove for missing entries).
- Changing how documents are saved/opened beyond launch presentation.

## Risks / Notes

- The launch + reopen lifecycle of a `Window` scene alongside `DocumentGroup` on macOS 14 is the main unknown; the menu command is the fallback entry point and the behavior will be confirmed by manual run.
- `NSDocumentController` recents are app-wide and already maintained by `DocumentGroup`; no new persistence is introduced.
