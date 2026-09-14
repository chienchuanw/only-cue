# Windows Port — Session Handoff (2026-09-14)

Self-contained resume point for the **OnlyCue-on-Windows epic (#728)**. Supersedes
the 2026-08-15 handoff for current status; the 2026-08-08 doc still holds the
original scoping/audit narrative.

**Spec:** `docs/superpowers/specs/2026-08-08-windows-port-design.md` (approved).

## TL;DR

The spec's gate — *"Design is finalized before any Windows code is written"* — is
now **met**:

- **Figma UI — ✅ COMPLETE.** Both platform pages are at full parity: 26 Windows
  frames covering every macOS screen, plus two panes that were missing on *both*
  platforms.
- **M0 (Windows foundation) — ✅ CODE COMPLETE**, PR #809. `.NET 10` solution,
  `OnlyCue.Core` `Timecode`, xUnit golden-vector verifier, Windows CI job.
- **M1 — NOT STARTED.** Needs a scope decision first (see "Open decisions").

Environment: `dotnet` is installed (the 2026-08-15 blocker is cleared). The
XCUITest automation-mode wedge recurred in a **new** form and is fixed — see
"CI".

## Status by phase

### 1. Figma UI — ✅ COMPLETE

File `NhH2957iKQ8b581x3gI3Wk`. Pages: `macOS Screens` (13:4),
`Windows Screens` (573:3020).

**Windows Screens now holds 26 frames**, one per macOS screen:

| Group | Count | Chrome treatment |
|---|---|---|
| Main windows (Cue / Empty / Lyric / Show / Video) | 5 | macOS `TitleBar` (52px) → Windows Chrome (Title bar 32 + Menu bar 20) |
| Settings (General / Audio / Keyboard / OSC / MIDI / grandMA2) | 6 | Title bar 32 inserted above the tab bar; children shifted +32, frame grown +32 |
| Dialogs | 10 | **No title bar** — WinUI `ContentDialog`; verbatim clones |
| Flyouts (Cue Notes / Cue Tempo) | 2 | **No title bar** — WinUI `Flyout`; verbatim clones |
| Mini Player (Cue / Show / Empty) | 3 | macOS traffic-light bar (28px) → Windows title bar instance at 28px, title = `<document> — OnlyCue` |

Reusable component: **`Windows / Title Bar` `576:257`** (app dot + `Title` text +
min/restore/close). Instance it and resize — the caption buttons stay pinned right.

**Two content exceptions** (everything else is chrome-only, and the page legend
records this):

1. `Settings → Keyboard` uses `Ctrl` / `Shift` / `Alt` instead of `⌘` / `⇧` / `⌥`.
2. `Settings → OSC` names *Windows Defender Firewall* instead of *macOS*, and
   *this PC's IP* instead of *this Mac's IP*.

The projected Notes/Lyrics overlays are full-screen output with no chrome, so they
are identical on both platforms and are deliberately **not** duplicated.

#### Gaps closed on the macOS page this session

- **`Settings → Keyboard` and `Settings → OSC` did not exist in Figma on *either*
  platform** — 4 of 6 settings tabs were designed. Both were built from ground
  truth (Keyboard from a real app screenshot; OSC from
  `OnlyCue/UI/OSCSettingsView.swift` + `OSCCommand.supportedAddresses`) and then
  ported to Windows. Node IDs: macOS `656:3468` (Keyboard), `658:3468` (OSC);
  Windows `658:4747`, `658:4900`.
- **Fixed a rendering defect in `Window · Settings — General · Dark` (`553:3018`)**:
  its five inactive tabs and the `Popup · System` control carried opaque
  *unbound white* fills, so they rendered as white boxes. The working convention
  (MIDI/Audio/grandMA2 frames) is `fills: []`. The Windows General clone
  (`576:5674`) had inherited the same defect; both are fixed.

#### Figma working notes

- `get_metadata` with no nodeId lists only *loaded* pages — enumerate via
  `use_figma` (`figma.root.children`), never `get_metadata`.
- **Always verify a mutation with `get_screenshot`** (the app-render). This caught
  three real bugs this session that the return value reported as success: a
  variant set stacked at one position, four clone titles left unset, and the
  white-fill defect above.
- Right after `clone()` + `insertChild`, `findOne(...)` on instance sublayers can
  return `null` before they materialise — `clone.query('TEXT[name=Title]').first()`
  worked where `findOne` did not.
- Colour variables (dark mode): `517:6` = `color/accent` = `#5B5BD6` (this is what
  `DS.Color.cueIndigo` maps to — **not** `cue/indigo` `6:29` = `#6155F5`, despite
  the comment in `DSColor.swift`); `336:2` = `color/text-on-accent`;
  `7:4` panel, `7:6` surface-sunken, `7:8` border, `7:12/14/16` text
  tertiary/secondary/primary, `7:22` selection.

### 2. M0 — Windows foundation — ✅ CODE COMPLETE (PR #809)

```
golden/timecode-v1.json          74 cases, macOS is the source of truth
OnlyCueTests/TimecodeGoldenVectorTests.swift   generates + drift-guards
windows/OnlyCue.sln
windows/OnlyCue.Core/            Timecode.cs, SmpteFramerate.cs   (net10.0)
windows/OnlyCue.Core.Tests/      xUnit; asserts parity with the JSON
```

CI job **"Golden vectors (Windows, C# core)"** runs `dotnet test` on a
GitHub-hosted `windows-latest` runner and is green. `bin/`/`obj/` are correctly
untracked.

### 3. M1 — NOT STARTED

Spec scope: `.cuelist` read/write + migrations, cue list/grid/inspector planning
UI, tempo/beat grid, MA2 telnet timecode push, MA2 plugin (lua/xml) export, OSC.
No audio hardware.

## Open decisions (blocking M1)

### D1 — Sequencing: contract-first, or vertical slice?

The golden-vector gate makes **contract-first** the natural order, and every step
of it is verifiable from the Mac:

1. **Extend the vectors** (macOS emits, Windows CI verifies) across the M1
   domains — `.cuelist` round-trip, cue-numbering rules, MA2 telnet command
   output, MA2 lua/xml export output, OSC address→command mapping, tempo/beat-grid
   math.
2. **Implement the C# core** against them.
3. **Then** the WinUI layer.

A vertical slice (one domain end-to-end including UI) would surface WinUI
integration risk earlier, at the cost of a partial contract.

### D2 — How is the WinUI layer verified, given there is no Windows machine here?

**WinUI 3 cannot be built or run on macOS.** Practical consequence: the agent can
develop and test *platform-neutral* C# locally (`dotnet test` works on macOS for
plain `net10.0` class libraries) but cannot build, run, or look at the WinUI app.

Recommended shape, which maximises what is verifiable:

- `OnlyCue.Core` — domain + logic. Locked by golden vectors.
- `OnlyCue.App.ViewModels` — a plain `net10.0` library (no WinUI reference), unit
  tested on macOS.
- `OnlyCue.App` — WinUI 3 XAML, kept as thin as possible; **CI-built only**, on
  the GitHub `windows-latest` runner. Visual verification is a maintainer step on
  a real Windows box.

The alternative is to defer all WinUI work until a Windows machine (or VM) is
available to the maintainer for iteration.

## Known drift / follow-ups

- **The spec says `.cuelist` schema `v19`; it is now `v23`** (`ProjectModel.swift:5`,
  migrations through `ProjectModel+MigrationV22.swift`). The `.cuelist` round-trip
  vectors must pin v23 *and* the full v1→v23 migration ladder.
- **#812** — six XCUITest suites (`MiniPlayerUITests`, `GeneralSettings`,
  `MA2PushSheet`, `MA2Settings`, `MIDISettings`, `SplitChannelWaveform` screenshot
  tests) are skipped in the behavioral step **and** absent from the baseline step,
  so they run in no CI job at all.
- Stale source comments referencing a `TIME/#/NAME/FADE` column set:
  `OnlyCue/UI/CueListLayout.swift:33`, `OnlyCue/UI/CueListInspectorMetrics.swift:15`.

## CI

**The `automationmodetool` self-heal from #799 was itself wedging the runner.**
Calling `sudo -n automationmodetool enable-automationmode-without-authentication`
unconditionally hangs forever as a **root** process; the runner user's NOPASSWD
entry covers the tool but **not** `pkill`/`killall`, so the job can never reap it.
Three separate runs each left an orphan (found at 8:17 / 9:47 / 19:56 elapsed).
`< /dev/null` does **not** prevent this — the previous note claiming it does is wrong.

Fixed in `ci.yml` (#810/#811): probe the no-arg read first — it returns instantly
and already reported `DOES NOT REQUIRE user authentication`, so the call was also
*unnecessary* — and only re-assert on drift, bounded by a watchdog + blocking
`wait`. Use `wait`, not a `kill -0` poll loop: without reaping, `kill -0` keeps
succeeding on the zombie and a fast normal exit is misreported as a hang.
Verified green in ~3 min.

**Maintainer action still outstanding:** reap the surviving root orphans with
`sudo killall -9 automationmodetool`.

## How to resume

1. Read this doc + the spec. Figma node IDs are above; the
   `onlycue-figma-calibration` memory is stale on the "what's pending" section.
2. Get D1/D2 decided.
3. Merge #809 (M0) if it has not landed, then start M1 step 1 (vector extension).
4. Specs/plans commit to `issues/728` — never `dev`.
