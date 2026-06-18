# Check for Updates — design

**Date:** 2026-06-18
**Issue:** #565
**Status:** Approved (brainstorm)

## Goal

A **Check for Updates…** menu item that compares the running app against the
latest GitHub release of `chienchuanw/only-cue` and, if a newer release exists,
lets the user open the download. Manual-only.

## Decisions (locked with the user)

- **Update scope:** notify + open download. OnlyCue ships as an unsigned/ad-hoc
  DMG (no Developer ID, no Sparkle), so in-app auto-install is fragile
  (Gatekeeper "damaged", quarantine, no secure-update signature). "Update" =
  show what's available and open the `.dmg` (or release page); the user installs
  via the existing drag-to-Applications flow.
- **Manual only:** no auto-check on launch, no Settings toggle. Add later if
  wanted.
- **Up-to-date UX:** a manual check always gives feedback — an explicit
  "you're up to date" dialog, and a distinct "running a newer build" case when
  the running version is ahead of the latest release (dev builds); never offer a
  downgrade.

## Architecture

Mirrors the project's pure-core + thin-impure-boundary pattern (`Timecode`, the
OSC parser, the exporters): the version math and the decision are pure and
unit-tested; the one network call is the impure boundary, verified by running
the app.

### Components (`OnlyCue/Update/`)

- **`SemanticVersion`** — pure value type. Parses `"v0.6.0"`, `"0.6.0"`,
  `"0.6"` (missing patch → 0); leading `v` tolerated. `Comparable` + `Equatable`
  by (major, minor, patch). Returns `nil` for unparseable input.
- **`GitHubRelease`** — `Codable` decode of the GitHub `releases/latest` JSON:
  `tag_name`, `name`, `body` (release notes), `html_url`, `assets[]`
  (`name`, `browser_download_url`). Computed `downloadURL`: the first asset whose
  name ends in `.dmg`, else `html_url` (release page).
- **`UpdateChecker`** — performs one `URLSession` GET to
  `https://api.github.com/repos/chienchuanw/only-cue/releases/latest` with an
  `Accept: application/vnd.github+json` and a `User-Agent` header (GitHub rejects
  UA-less requests with 403). `/latest` already excludes drafts and prereleases.
  Decodes to `GitHubRelease`, then calls the **pure** `UpdateChecker.evaluate(current:latest:)`.
  The fetch is injectable (a `() async throws -> GitHubRelease` closure /
  protocol) so tests drive `evaluate` with a stubbed release and never hit the
  network.
- **`UpdateCheckResult`** enum:
  - `.updateAvailable(GitHubRelease)`
  - `.upToDate(current: SemanticVersion)`
  - `.runningNewerBuild(current: SemanticVersion, latest: SemanticVersion)`
  - `.failed(message: String)`
- **`UpdateCheckPresenter`** — `@MainActor`. Runs the check (with a busy state
  guard so double-clicks don't stack) and shows the matching `NSAlert`.

### Wiring

The action is app-global and stateless, so the menu `Button` triggers the
presenter directly (`Task { await UpdateCheckPresenter.shared.run() }`) — no
per-document `NotificationCenter` plumbing. The item lives in `AppCommands`'s
`CommandGroup(replacing: .appInfo)`, immediately after **About OnlyCue** (the
macOS-standard placement).

### Version source

`Bundle.main` `CFBundleShortVersionString` (currently `0.5.0`) → `SemanticVersion`.
Latest = `tag_name` with the leading `v` stripped → `SemanticVersion`.

## Data flow

1. User clicks **Check for Updates…**.
2. `UpdateCheckPresenter.run()` → `UpdateChecker.checkForUpdate()`:
   - fetch `releases/latest` → decode `GitHubRelease`;
   - `evaluate(current: appVersion, latest: release.version)`.
3. Present `NSAlert` per the result:
   - **updateAvailable:** message "OnlyCue `<latest>` is available — you have
     `<current>`."; informative = a truncated release-notes excerpt (≈500 chars).
     Buttons: **Download** (default → `NSWorkspace.shared.open(release.downloadURL)`),
     **Release Notes…** (→ `release.html_url`), **Later** (cancel).
   - **upToDate:** "You're up to date." / "OnlyCue `<current>` is the latest
     release." [OK].
   - **runningNewerBuild:** "You're running a newer build (`<current>`) than the
     latest release (`<latest>`)." [OK].
   - **failed:** "Couldn't check for updates." / short reason. [OK].

## Error handling

- No network / timeout / non-200 / 403 rate-limit / decode failure →
  `.failed(message:)` with a friendly one-liner; never crash, never hang the UI
  (the check is `async`; the alert shows on completion).
- Unparseable running version or tag → treat as `.failed` (shouldn't happen with
  a valid build/release).

## Testing

- **`SemanticVersionTests`** — parse (`v1.2.3`, `1.2.3`, `1.2` → patch 0,
  invalid → nil); ordering (`1.2.0 < 1.10.0`, patch/minor/major precedence);
  equality.
- **`UpdateCheckEvaluateTests`** — `evaluate` returns `.updateAvailable` /
  `.upToDate` / `.runningNewerBuild` for the three current-vs-latest orderings,
  from a stubbed `GitHubRelease`.
- **`GitHubReleaseDecodeTests`** — decode a committed golden GitHub
  `releases/latest` JSON fixture → `GitHubRelease`; assert `downloadURL` picks
  the `.dmg` asset, and falls back to `html_url` when no `.dmg` is present
  (a second fixture / asset-less case).
- The live `URLSession` call is verified by running the app (consistent with the
  LTC/OSC live paths).

## Out of scope

Auto-check on launch, a Settings "check automatically" toggle, in-app
download/mount/install, delta updates, signature verification of the download.
No `ProjectModel`/schema change; no new entitlements (ADR-007 unchanged).
