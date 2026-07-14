# Handoff — 2026-07-15 (post repo move to ~/Projects)

**Repo:** `chienchuanw/only-cue` (local: `/Users/chuan/Projects/only-cue` — **moved from `~/Documents/only-cue` on 2026-07-15**, issue #634)
**Branch state:** `dev` and `main` both at v0.7.4; working tree clean; no open PRs.
**Latest release:** v0.7.4 (RMS waveform) — https://github.com/chienchuanw/only-cue/releases/tag/v0.7.4

## What just happened (context for the new session)

1. **Repo moved** `~/Documents/only-cue` → `~/Projects/only-cue` to stop the recurring
   Documents TCC prompt from wedging CI (issue #634, closed). Key finding: the self-hosted
   runner (`~/github-runner`, checkout in `~/github-runner/_work/only-cue/`) was never under
   Documents — the trigger was the *dev checkout* on the same machine. Details in the closing
   comment on #634 and the new Troubleshooting entry in `docs/release.md` (PR #635, merged).
2. After the move: `xcodegen generate` re-run, full unit suite green at the new path.
   One known-flaky test: `LTCRoutingStoreTests.test_update_persistsAndSurvivesReload`
   (failed once in a full run, passed in isolation and on rerun — unrelated to the move).
3. Claude Code memory was copied to the new project dir
   (`~/.claude/projects/-Users-chuan-Projects-only-cue/memory/`). The old
   `-Users-chuan-Documents-only-cue` dir still exists; it is stale — do not update it.
4. Recent shipped work (all merged, released): #622 vertical-zoom removal, #624 Welcome
   menu item removal, #626 Gatekeeper install docs (macOS 15 Open Anyway), #628 waveform
   vertical headroom (0.85 fill), #630 test-fixture bundling fix, #632 **RMS waveform**
   (the fix the user confirmed correct; `WaveformCache.formatVersion` bumped to 3).

## Post-move CI validation

- The first dev-push CI run after the move (run 29357357605, full suite incl. UI tests)
  completed **green** on 2026-07-15 — the runner is confirmed healthy at the new setup.
  If a later run wedges, see the CI-recovery notes below.

## Open / dormant items (no active task)

- **ADR-024 waveform fill color** — app uses `#B3AFA5`, Figma mock uses `#5A564F`;
  user never decided. Dormant until user raises it.
- **#611 audio↔visual alignment** — instrumentation tests exist and pass; a human
  listening check was suggested but never done.
- **v0.7.4 smoke test on a clean Mac** — user's manual task, not ours.
- **Developer ID signing** — declined for now (no paid Apple account). The unsigned
  path and its Gatekeeper/TCC consequences are documented in `docs/release.md`.

## CI environment notes (self-hosted mac-mini, same machine as dev box)

- Runner: `~/github-runner`, launchd agent present; workspace `~/github-runner/_work`.
- UI tests only run on **push** events (ci.yml `if: github.event_name == 'push'`);
  PR runs are lint/build/unit only (~30 s).
- Wedge playbook (also in Claude memory):
  - testmanagerd timeout → `killall -9 testmanagerd` (no sudo; CI self-heals via #595).
  - "Timed out while enabling automation mode" → have the user run
    `sudo xcodebuild -runFirstLaunch`; reboot alone did NOT clear it (2026-07-14).
  - CoreSimulator 1051.54 < 1051.55 warning (Xcode 26.6) is benign on macOS-only runs.
- Local UI-test runs need ad-hoc signing: `CODE_SIGN_IDENTITY="-"`.

## Standing conventions (user-established, non-negotiable)

- Conversation in **zh-TW**; code/commits/issues/PRs in **English**.
- Conventional Commits, lowercase imperative. **No Co-Authored-By / attribution anywhere**
  (commits, PRs, issues, review comments — subagent prompts must explicitly forbid it).
- Branch `issues/<N>` off dev: `gh issue develop N --base dev --name issues/N --checkout`.
- PRs into dev using forked templates `.github/PULL_REQUEST_TEMPLATE/{type}.md` +
  OnlyCue verification block + `## Understanding` section (4 answers).
- TDD mandatory: failing test committed separately (red) before the fix (green).
- **Subagent review before merge; merge only on APPROVE.** Then
  `gh pr merge N --rebase --delete-branch`.
- Never push dev/main directly except repo-metadata (version bumps via PlistBuddy —
  the Edit tool fails on Info.plist tabs — and README release pointers).
- Hard rules: no App Sandbox (ADR-007), no media in `.cuelist`, no ProjectModel schema
  change without version bump, macOS 14.0 floor.
- Release runbook: `docs/release.md` — bump plist → push dev →
  `bash scripts/build-release.sh` → `bash scripts/make-dmg.sh` → verify DMG
  (expect ~2.7 MB; a 50 MB DMG means a fixture leaked into Resources, see #630) →
  FF main → annotated tag → `gh release create` → README pointer → FF main again.
