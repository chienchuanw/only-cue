# Handoff — OnlyCue: resolve the 4 remaining open issues

**Repo:** `chienchuanw/only-cue` (local: `/Users/chienchuanw/Documents/only-cue`)
**Default branch:** `main` · **Working/integration branch:** `dev` (all PRs merge into `dev`)
**As of:** 2026-06-04 · `dev` is green.

## Goal of this session

Drive the **4 remaining open issues** to resolution. They were deliberately left open in the prior session because each needs a human decision or human-in-the-loop visual work — they are not blindly auto-implementable. Your job is to unblock and (where possible) implement them.

## The 4 issues (read the bodies + my prior comments on GitHub — don't re-derive)

| # | Title | Why it's blocked | What it needs |
|---|---|---|---|
| [#413](https://github.com/chienchuanw/only-cue/issues/413) | spec(ux): decide cue-list-vs-lyric-inspector for Lyric Mode right pane | `needs-spec` — product decision | A UX decision from the user, then `/feature` |
| [#412](https://github.com/chienchuanw/only-cue/issues/412) | spec(ux): clarify lyric-ribbon visibility policy across editor modes | `needs-spec` — product decision | A UX decision from the user, then `/feature` |
| [#417](https://github.com/chienchuanw/only-cue/issues/417) | chore(tests): add `video-project` UI test seed | Acceptance hinges on a Figma-matched visual baseline | Figma frame `318:1614` + capture golden on real display |
| [#416](https://github.com/chienchuanw/only-cue/issues/416) | chore(tests): add `set-list-act-i` UI test seed | Same — Figma-fidelity visual baseline | Figma populated frames (§7.1/§7.5/§8.4/§9.2) + capture |

Recommended order: resolve the two `needs-spec` issues first (they unblock implementation cleanly), then the two seed/visual issues (more involved, need Figma + capture).

## Hard constraints / gotchas (these bit the prior session — don't relearn them)

- **You cannot run UI tests (XCUITest) from the Claude Code bash environment.** It fails with `Timed out while enabling automation mode` / `XCTest is trying to Enable UI Automation` — the non-interactive shell can't approve the macOS TCC prompt. UI tests are validated only on the **push-to-dev CI run** (the self-hosted Mac mini, where UI Automation is enabled). PRs run build+unit only; UI tests run on push to dev/main. Plan validation around this.
- **Visual-baseline `*ScreenshotTests` are CI-skipped by design** (golden-image capture needs a real display + eyeball comparison to Figma). So #416/#417's "screenshot test matches Figma" criterion is **not autonomously verifiable** — it's a human-in-the-loop capture task. Don't merge a half-built visual baseline.
- CI runner details, Xcode-version-alignment rules, and the UI-Automation setup are recorded in memory: `/Users/chienchuanw/.claude/projects/-Users-chienchuanw-Documents-only-cue/memory/ci-runner-mac-mini.md`. Read it.
- Project conventions (enforced): branch `issues/<N>` via `gh issue develop`; **rebase-merge only** (squash/merge disabled); Conventional Commits, lowercase, **no `Co-Authored-By` trailer**; PRs use the **forked** templates in `.github/PULL_REQUEST_TEMPLATE/{type}.md` (incl. the OnlyCue verification footer); never push to `dev`/`main` directly. See `CLAUDE.md`.

## Useful starting points in the code

- UI-test seeds + launch-arg plumbing: `OnlyCueUITests/Support/` (look for the seed handler / `SeedKey` enum; `--ui-test-seed=` launch arg). `#416/#417` add new seed keys here.
- Lyric Mode panes (for #412/#413): `OnlyCue/UI/LyricsInspectorPane.swift`, and the editor-mode switching views under `OnlyCue/UI/`.
- Visual baseline tests: search `OnlyCueUITests/` for `*ScreenshotTests` / `visualBaseline`.
- Design tokens: `OnlyCue/UI/DesignSystem/DSColor.swift`, `DS.swift`.

## Prior session context (reference only — already done, do not redo)

- Today's bulk of work was standing up the new self-hosted CI runner (dedicated Mac mini, Xcode 26.5, UI Automation enabled, runner launched from Terminal via login-item not launchd). Merged: PR #454 (ci.yml comments), #456 (`Self` lint fix), #457 (#396 token rebind), #458 (#378 UI-test de-brittling). Issues #403/#404 closed as already-implemented. The Swift-6-warnings "issue" was a non-issue (Xcode alignment fixed it).
- Don't reopen those; they're settled and `dev` is green.

## Suggested skills (invoke as relevant)

- **`superpowers:brainstorming`** — for #412/#413, to explore the UX options with the user before any code. These are product decisions; start here.
- **`grill-with-docs`** (or `grill-me`) — to stress-test the chosen Lyric-Mode pane/ribbon design against the existing domain model and update `CONTEXT.md`/ADRs as decisions crystallise.
- **`figma:figma-use`** / `get_design_context` / `get_screenshot` — for #416/#417, to pull the reference frames (`318:1614` and the §7–9 populated frames) so the seeds match Figma fidelity.
- **`dev:feature`** — once a `needs-spec` issue has a decision, run the full issue→TDD→PR→CI→merge lifecycle. (This is the `/feature` command used last session.)
- **`verify`** / **`run`** — to launch the app / capture screenshots on a real display for the visual-baseline work (must be done interactively, not from the bash tool).
- **`AskUserQuestion`** — to get the two UX decisions efficiently if brainstorming converges fast.

## First move

Confirm `dev` is green and clean, then start with #413 (or #412): use brainstorming/AskUserQuestion to get the UX decision from the user, since neither can be implemented without it.
