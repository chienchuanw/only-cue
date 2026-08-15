# Windows Port — Session Handoff (2026-08-15)

Self-contained resume point for the **OnlyCue-on-Windows epic (#728)**. Supersedes
the 2026-08-08 handoff for current status; that doc still holds the original
scoping/audit narrative. **Work is paused here** to prioritise a new macOS
"miniplay" feature — resume from this document.

## TL;DR

The epic is **scoped, designed, and now partly executed**:

- **macOS calibration — DONE.** All gap screens captured as committable tests and
  built in Figma.
- **Windows Screens (Figma) — SCAFFOLD STARTED.** Page + reusable chrome component
  + 3 window archetypes proven; remaining screen variants are repetition of the
  pattern.
- **M0 (Windows foundation) — STARTED.** The golden-vector contract's macOS half is
  done and green; the C# half is blocked on a `.NET SDK` install.

Two environment facts: the old **XCUITest automation-mode wedge is RESOLVED**; the
new blocker is **`dotnet` is not installed** on the dev/CI Mac.

## Status by phase

### 1. macOS calibration (was handoff step 2) — ✅ DONE
- Foundations token diffs closed in Figma: `radius/xl`=12 + text styles `Small`
  (Inter 11), `Mono/Label` (Roboto Mono 10), `Mono/Micro` (Roboto Mono 9).
- **5 gap screens captured as XCUITest screenshot baselines** → **PR #745 (MERGED)**,
  **issue #744 (closed)**: General / MIDI / grandMA2 settings, MA2 Push sheet, and
  the split-channel waveform (added a stereo fixture `tone-stereo-60s.m4a` + a
  `split-channels` seed; all `#if DEBUG`, no release impact).
- **5 macOS Figma screens built** on the `Screens` page, grouped in section
  "Settings & Sheets — calibration (#728)"; the stale Audio-frame tab bar
  corrected to the real 6-tab set (General/Audio/Keyboard/OSC/MIDI/grandMA2).

### 2. Windows Screens (Figma) — 🟡 SCAFFOLD STARTED
Figma file key `NhH2957iKQ8b581x3gI3Wk`; new page **"Windows Screens" (573:3020)**.
Approach per spec: WinUI wearing the OnlyCue brand theme, **chrome-only platform
difference** (window controls right + menu bar; dialogs = ContentDialog).
- **"Windows / Title Bar" component** `576:257` (swappable `Title` text property;
  app dot + title + min/restore/close caption buttons). Reused by instance.
- **3 archetypes, validated dark:** Main Window `573:3021` (title-bar instance +
  menu bar + cloned macOS body), Settings window `576:5674`, MA2 ContentDialog
  `576:5730`.
- **Pattern:** clone the macOS frame across pages (clone + `winPage.appendChild`
  in one `use_figma` call), then swap the title bar for a component instance.
- **PENDING:** empty/lyric/show main-window modes, projected overlays, remaining
  sheets → ContentDialogs, popovers → flyouts; optional dimmed-backdrop modal
  treatment. All are repetition of the proven pattern.

### 3. M0 — Windows foundation — 🟡 STARTED (golden-vector macOS half)
- **`golden/timecode-v1.json`** (repo root, language-neutral): 74 cases for
  `Timecode` math across 24/25/30/30df — frame↔components, `totalSeconds`, `parse`,
  incl. drop-frame minute/tenth-minute boundaries + day wrap. macOS is the source
  of truth. → **PR #747 (OPEN, CI green)**, **issue #746**.
- `OnlyCueTests/TimecodeGoldenVectorTests.swift` generates + drift-guards it
  (bootstrap-on-missing = write+fail; strict-compare when present; regenerate by
  deleting the file). Independent hand-computed drop-frame correctness pins too.
- **BLOCKER: `dotnet` not installed.** Cannot create `windows/` .NET solution or
  run the C# verifier. After install, the ordered work is:
  1. `windows/OnlyCue.sln` + `OnlyCue.Core` (C#) — re-implement `Timecode`
     (drop-frame rule included).
  2. `OnlyCue.Core.Tests` (xUnit) — read `golden/timecode-v1.json`, assert
     byte-for-byte parity.
  3. Windows CI (GitHub Actions windows runner) running `dotnet test` — golden
     gate live.
  4. Extend the contract to the next domains (`.cuelist` round-trip, MA2/OSC
     command output, cue-numbering) per the spec.

## Blockers

| Blocker | Owner | Fix |
|---|---|---|
| `.NET SDK` not installed (M0 C# half) | maintainer | `brew install dotnet` or the official installer |
| ~~XCUITest automation-mode wedge~~ | — | **RESOLVED**: `sudo automationmodetool enable-automationmode-without-authentication` (persistent) |

## PRs & issues

- **#728** — epic (this port).  ·  **#730** — original resume-guide issue.
- **#744** — calibration screenshot tests — CLOSED (via PR **#745**, MERGED).
- **#746** — golden-vector Timecode contract — OPEN (via PR **#747**, OPEN + green).

## Environment / workflow gotchas (learned this run)

- **`get_metadata` with no nodeId lists only *loaded* Figma pages** — it misreported
  the file as near-empty. Enumerate pages via `use_figma`
  (`figma.root.children.map(p => p.name)`), not `get_metadata`.
- **`figma.createAutoLayout()`/`createFrame()` default to an opaque white fill** —
  clear child section fills (`= []`) or a dark frame renders white. **Validate
  dark-mode frames with `get_screenshot` (app-render), not the plugin
  `node.screenshot()`** — the latter rendered a white frame as dark.
- **This repo disallows squash AND merge commits — use `gh pr merge --rebase`.**
- **Shell env vars don't propagate into the `xcodebuild test` process** — the golden
  regenerator uses a file-bootstrap (write-on-missing) instead of an env gate.
- Local XCUITest runs need ad-hoc signing: `CODE_SIGN_IDENTITY="-"
  CODE_SIGNING_REQUIRED=NO`; reset daemons with `killall
  com.apple.CoreSimulator.CoreSimulatorService testmanagerd` before runs.

## How to resume

1. Read this doc, the spec (`docs/superpowers/specs/2026-08-08-windows-port-design.md`),
   and the `onlycue-figma-calibration` memory (has all Figma node IDs + the M0 state).
2. **M0 (recommended once dotnet is installed):** build `windows/OnlyCue.sln` +
   `OnlyCue.Core` + xUnit verifier against `golden/timecode-v1.json`, then Windows CI.
3. **Figma:** continue cloning macOS screen variants onto the Windows page via the
   title-bar-instance pattern.
4. Specs/plans commit to `issues/728` (never `dev`).
