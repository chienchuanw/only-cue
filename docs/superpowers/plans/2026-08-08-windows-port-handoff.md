# Windows Port — Session Handoff (2026-08-08)

A self-contained resume point for the OnlyCue-on-Windows epic. Read this top to
bottom and you can pick up exactly where the last session stopped.

## TL;DR

The Windows epic is **scoped, designed, and tracked**; implementation has **not**
started. This session ran the full brainstorm → spec → epic issue → branch, then
did a complete Figma audit (Foundations are healthy) and produced a macOS-screens
gap list. The **only blocker** is a local **automation-mode wedge** that stops
XCUITest from running on this Mac — it needs one `sudo` command from the
maintainer. Once cleared, the next work is: capture app screenshots → close the
macOS Figma gaps → design the full Windows UI in Figma → then build the Windows
M0 foundation (C# scaffold + golden-vector bridge + CI).

## Canonical references

- **Epic issue:** #728 (`feat: OnlyCue on Windows (WinUI 3 + shared-contract core) — epic`)
- **Design spec:** `docs/superpowers/specs/2026-08-08-windows-port-design.md`
- **Branch:** `issues/728` (spec + this handoff committed here; not on `dev`)
- **Figma file:** "OnlyCue Design System", key `NhH2957iKQ8b581x3gI3Wk`
  - URL: https://www.figma.com/design/NhH2957iKQ8b581x3gI3Wk/OnlyCue-Design-System
  - MCP: `plugin:figma:figma`; authenticated as `frankwang16@gmail.com` (pro).
    If a new session isn't authed: `/mcp` → figma → Authenticate.

## Agreed architecture (14 decisions — see spec for rationale)

| # | Decision |
|---|---|
| 1 | **Do not touch macOS** — Swift/SwiftUI stays first-class, unchanged. |
| 2 | Windows UI = **WinUI 3 + C#/.NET**. |
| 3 | Core sharing = **C# re-implementation locked to macOS-generated golden vectors** (shared contract = `.cuelist` JSON schema + behavioural spec + vectors). Swift-for-Windows/FFI rejected. |
| 4 | Platform layers re-written on Windows: transport (sockets), media engine, audio LTC (WASAPI/ASIO), MIDI (WinRT). |
| 5 | **Unified brand visual** — WinUI is the substrate wearing an OnlyCue theme, not default Fluent. |
| 6 | **Both platforms dark-only** (Windows inherits ADR-029's spirit; write a parallel ADR). |
| 7 | Fonts: macOS keeps **SF Pro**; Windows embeds **Inter** (no macOS change). |
| 8 | Figma: single file, pages `Foundations` / `macOS Screens` / `Windows Screens`, shared tokens + component library, platform differences as variants. |
| 9 | UI is **design-first and complete** — the whole two-platform UI is finalized in Figma before any Windows code. Agent produces it; maintainer reviews/finalizes. |
| 10 | **`.cuelist` is fully cross-platform** (portable paths; bookmark = macOS-only optimization; relink covers cross-machine). |
| 11 | **Monorepo** — Windows C# solution in a `windows/` subtree; independent Swift + .NET builds. |
| 12 | Maintainer is **not fluent in C#/.NET/WinUI** → agent leads the Windows side (scaffold, examples, golden-vector bridge, CI); maintainer reviews. |
| 13 | Drift between the two cores contained by the **golden-vector gate** (macOS emits, Windows CI verifies). |
| 14 | Highest technical risk = Windows audio/timecode fidelity (WASAPI/ASIO) → deferred to M3. |

## What this session completed

- Full grill/brainstorm (in zh-Hant) → 14-decision consensus.
- Wrote the design spec (committed on `issues/728`).
- Opened epic **#728**; created branch `issues/728` off `dev`.
- **Figma audit (important — corrects earlier mis-reads):** the file is healthy,
  NOT stale. It has 5 pages (`Cover`, `Foundations`, `Components`, `Screens`,
  `Website`) and complete variable collections.
  - `Primitives` (26): `neutral/light/*`, `neutral/dark/*`, `cue/*` (8-colour).
  - `Color` (13, **Light + Dark** modes, aliased to Primitives).
  - `Spacing` (6), `Radius` (3), `Motion` (2).
- **Foundations verified against app `DS.*`:** all 9 `neutral/dark/*` match exactly
  (surface `#232220`, panel `#2B2926`, border `#423F3A`, text-primary `#EBE9E3`,
  …); Spacing 4/8/12/16/24/32 match; `accent #5B5BD6`, `text-on-accent #FFFFFF`
  match. **Small diffs only:** `Radius` missing `xl=12`; `cue/*` palette differs
  from app type-bar (`cue/green #6BCB77` vs teal `#4ECDC4`; `cue/indigo #6155F5`
  vs accent `#5B5BD6`); text styles (type ramp) not yet audited.
- **macOS Screens gap list produced** (below).

## macOS Screens — gap list (Figma vs app现况)

Figma already has (Dark): main window in every mode (Cue/Lyric/Show/Empty/Video/
Populated), Notes/Lyrics overlays, sheets (Export Cue List, Manage Types, Edit
Media, First Launch, OSC Monitor, Timecode Settings, Note Overlay), popovers (Cue
Notes/Tempo), a #714 workspace exploration section.

Figma is **missing / behind** (app has, needs drawing):

1. **Settings tabs** — Figma has only "Settings — Audio"; app has **General
   (language picker, new), Keyboard, OSC, MIDI, grandMA2**.
2. **MA2 Push sheet** ("Send to grandMA2") + MA2 plugin export sheet — absent.
3. **Split Channels waveform / per-channel lanes / LTC channel badge** (v0.22) —
   not reflected in the PreviewPane screens.
4. **zh-Hant** — Figma is all English; decide whether to show bilingual variants
   or keep English as the design source of truth.
5. **Workspace management (#714)** — Figma has only a "phase A" exploration;
   confirm the app's shipped state.

Pixel-level comparison needs **app screenshots**, which are blocked by the wedge
below. The maintainer chose "fix the wedge first."

## BLOCKER — automation-mode wedge (fix first)

XCUITest cannot run on this Mac. Root cause was pinned this session:

- `/usr/bin/automationmodetool` (no args) prints: *"Automation Mode is disabled.
  This device requires user authentication to enable Automation Mode."* — that is
  exactly why runner init logs `Timed out while enabling automation mode` (~60s).
- Developer mode IS enabled; `testmanagerd` and `CoreSimulatorService` are
  user-owned (`chuan`). CoreSimulator on disk = 1051.55 (a running 1051.54 is a
  stale-daemon mismatch, clearable without sudo).

**Fix (maintainer must run — agent cannot sudo):**
```
sudo automationmodetool enable-automationmode-without-authentication
```
This should be more durable than the previously-tried `sudo xcodebuild
-runFirstLaunch` (whose relief lasted ~10 min; see the
`onlycue-automation-mode-wedge` memory). **This command was requested at the end
of the session but not yet confirmed run.**

**After it runs, the agent should:**
1. `killall com.apple.CoreSimulator.CoreSimulatorService testmanagerd` (no sudo —
   clears the 1051.54↔1051.55 mismatch, lets them respawn on 1051.55).
2. Verify `automationmodetool` now reports enabled.
3. Run one minimal XCUITest (e.g. `-only-testing:OnlyCueUITests/TraditionalChineseLocalizationUITests`)
   to confirm the wedge is gone. Batch UI work into few runs — the wedge is
   load/time-dependent and can recur.

## Next steps (ordered)

1. **Unblock:** maintainer runs the sudo command; agent verifies (above).
2. **macOS calibration:** capture app screenshots (XCUITest, once unblocked) for
   the gap-list screens; update the Figma `macOS Screens` page. Also close the
   Foundations small diffs (`radius/xl`, cue palette, type-ramp audit).
3. **Windows Screens:** design the complete Windows UI in Figma (all milestones'
   screens) using the shared dark tokens + platform variants (window chrome, menu
   bar, context menus, file dialogs). Maintainer reviews/finalizes. **This is the
   biggest remaining UI task.**
4. **M0 (only after Figma is finalized):** create the `.NET`/WinUI solution
   scaffold under `windows/`, the golden-vector export (from macOS) + verification
   mechanism, and Windows CI. Then M1 → M4 per the spec.

## Milestones (from spec)

- **M0** Windows foundation: C#/.NET scaffold, golden-vector bridge, Windows CI.
- **M1** planning + MA2 (shared logic + sockets): `.cuelist` r/w + migrations,
  cue list/grid/inspector, tempo/beat grid, MA2 telnet timecode push, MA2 plugin
  export, OSC.
- **M2** media: video/audio preview + waveform + timecode alignment (engine選型 open).
- **M3** hardware: LTC audio out (WASAPI/ASIO), MIDI in/out.
- **M4** polish: Windows update, MSIX packaging + signing, i18n (String Catalog →
  .NET resources, incl. zh-Hant).

## Working notes / gotchas for the next session

- **Figma reads** (`get_metadata`/`get_screenshot`/`get_variable_defs`) don't need
  a skill; **`use_figma` writes** require loading the `figma-use` skill first (and
  `figma-generate-library` for components/variables, `figma-generate-design` for
  full screens). `get_metadata` can exceed the token limit on big pages — it saves
  to a file; use `jq` to slice it (that's how the `Screens` list was extracted).
- **Branch/commit discipline:** specs/plans/design files commit to the issue
  branch (`issues/728`), never to `dev` (project CLAUDE.md rule).
- **XCUITest wedge** is the gating environment issue — see the
  `onlycue-automation-mode-wedge` memory (updated this session with the direct
  root cause).
- The `windows/` subtree does not exist yet — created in M0.
- ADRs to write (deferred): Windows dark-only; no-sandbox/portable-path media;
  C#-core + golden-vector contract; Inter as Windows brand font.

## Progress update — 2026-08-11 (macOS calibration session)

**Wedge UNBLOCKED (confirmed):** `sudo automationmodetool enable-automationmode-without-authentication`
cleared it permanently (see the `onlycue-automation-mode-wedge` memory). XCUITest
runs locally again — screenshot capture is no longer blocked.

**Figma scope correction:** the file was NOT stale. `get_metadata` with no nodeId
lists only *loaded* pages, which misread it as near-empty. The file actually has 5
pages incl. a healthy `Foundations` and a `Screens` page with ~23 frames. Full
token system present. See the new `onlycue-figma-calibration` memory.

**Done this session:**
- Foundations diffs closed: added `radius/xl`=12 + text styles `Small` / `Mono/Label`
  / `Mono/Micro` (match `DSText`/`DS`).
- 4 new dark-mode screenshot tests — General / MIDI / grandMA2 settings + MA2 Push
  sheet → **PR #745 / issue #744**. (Split-channel capture deferred: needs a
  stereo-with-content audio fixture; current fixtures are mono or silent.)
- Built 4 Figma screens (General / grandMA2 / MIDI settings + MA2 Push sheet) on the
  `Screens` page, grouped in section "Settings & Sheets — calibration (#728)", all
  validated dark via `get_screenshot`. Fixed the stale tab bar on the existing Audio
  frame (4-tab Audio/Keyboard/Timecode/OSC → the real 6-tab set).
- GOTCHA banked: new auto-layout/frame nodes default to a white fill (clear it);
  validate dark frames with `get_screenshot`, not the plugin `node.screenshot()`.

**Remaining macOS calibration:** split-channel waveform screen (blocked on fixture);
decide whether the 4 new frames should move next to the existing Screens content.

## Task list snapshot

- [x] Figma: Foundations — dark tokens (audited healthy; `radius/xl` + 3 text styles DONE)
- [x] Figma: 重建元件庫到 dark tokens (moot — already dark)
- [~] Figma: macOS Screens (settings tabs + MA2 push built & dark; split-channel waveform pending)
- [ ] Figma: Windows Screens (M1–M4) — the big remaining UI task
- [ ] M0: Windows C# scaffold + golden-vector bridge + CI
