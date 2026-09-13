# Spec — #792: delete CIRuntime, gate CI-only skips at the xcodebuild invocation

## Unblock status

Blocked-on #789 is **CLOSED (COMPLETED, 2026-09-01)**; the #791 instrumentation
PR is **MERGED**. The investigation concluded (cause: `isSelfHostedRunner` read
`true` throughout a single job — not a cross-run race). The evidence path has
served its purpose, so the marker mechanism can now be removed. **Unblocked.**

## Problem (from the issue)

`CIRuntime.isSelfHostedRunner` decides "am I on CI" by `fileExists("/tmp/.onlycue-ci-active")`.
The runner Mac is also the dev machine, so the shared fixed-path marker leaks
both ways (CI job in flight → local runs silently skip; clear it locally → a live
CI job's guards break). It also **fails open**: a missing marker means `XCTSkipIf`
silently does not fire, so a broken guard looks like a test meant to run — exactly
how #785's two red tests stayed invisible.

## Current-state facts (verified this session)

- **Marker lifecycle:** `Mark CI active` (`ci.yml:148`, unconditional) touches it;
  `Clear CI marker` (`ci.yml:402`, `if: always()`) removes it. Present for the
  whole job body.
- **Two mutually-exclusive UI steps:** `UI tests (behavioral)` runs on
  `push && ref==dev`; `UI baseline screenshots` runs on `workflow_dispatch`.
- **10 suites carry an executable `XCTSkipIf(CIRuntime.isGitHubActions, …)`**
  (11 call sites — `Phase3` ×4, `MiniPlayer` ×2, plus 8 single-site suites).
  `MediaEditSheetUITests` / `EmptyStateRedesignUITests` only mention it in
  comments.
- **`-skip-testing:` (behavioral step) already lists 4 of them** (Export,
  Keyboard, OSCSettings, Phase3). The **6 load-bearing** ones are not:
  GeneralSettings, MA2PushSheet, MA2Settings, MIDISettings, MiniPlayer,
  SplitChannelWaveform.
- **Argument-less-launch audit (step-4 risk):** `launchApp(...)` always adds
  `--ui-test-reset` + `--ui-test-first-launch=suppress`, so every behavioral test
  is safe. Of the manual `app.launch()` screenshot tests, **only
  `TempoGridOverlayScreenshotTests` carries no `--ui-test*` argument** — it relies
  on the marker for the #603 defaults-reset. (`ExportSheet` always passes
  `--ui-test-appearance=dark`; all others pass a `--ui-test*` arg.)
- **Three launch handlers** consult the marker as an "is this a UI-test launch?"
  OR-branch: `UITestLTCHandler`, `UITestMTCHandler`, `UITestDefaultsResetHandler`
  (the issue named only two — MTC is a third). Each triggers on
  `arguments.contains { $0.hasPrefix("--ui-test") } || fileExists(marker)`.

## Plan (ordered — step 4 before step 3, per the issue)

### 1. Make the one arg-less launch explicit (step 4)
`TempoGridOverlayScreenshotTests`: add `--ui-test-reset` to its `launchArguments`
so it keeps the #603 defaults-reset (and #599 in-memory LTC) without the marker.
No other launch needs a change (audit above).

### 2. Drop the marker branch from the three handlers (step 3)
`UITestLTCHandler`, `UITestMTCHandler`, `UITestDefaultsResetHandler`: trigger
purely on `arguments.contains { $0.hasPrefix("--ui-test") }`; delete the
`ciMarkerPath` constant and the `fileExists` OR-branch.
`UITestDefaultsResetHandler.isResetRequested(arguments:ciMarkerPresent:)` loses
its `ciMarkerPresent` parameter — **update its unit tests first (TDD)**.

### 3. Move exclusion to the xcodebuild invocation (step 1)
Add the 6 load-bearing suites to the behavioral step's `-skip-testing:` list in
`ci.yml`, kept alphabetized. (The baseline `-only-testing:` step is unchanged;
after guard removal it will actually capture the 4 formerly-skipped suites, which
is its intent.)

### 4. Delete CIRuntime and all guards (step 2)
- Remove all 11 `XCTSkipIf(CIRuntime.isGitHubActions, …)` call sites.
- Delete the `CIRuntime` enum + `logMarkerRead` + `markerDateFormatter` from
  `Foregrounding.swift`, leaving it a single-purpose file.
- Refresh the stale CIRuntime comments in `Phase3`, `EmptyStateRedesignUITests`,
  `MediaEditSheetUITests`.

### 5. Remove the dead marker plumbing from ci.yml
Delete `Mark CI active`, `Clear CI marker`, and the `log_marker_state`
instrumentation (#791, now dead) from `ci.yml`.

## Acceptance / verification

- `grep -r CIRuntime OnlyCue OnlyCueUITests` → nothing.
- `/tmp/.onlycue-ci-active` appears nowhere in the repo.
- The 6 load-bearing suites are in `-skip-testing:` and absent from the executed
  list.
- Handler unit tests updated and green; full unit suite green; SwiftLint strict
  clean.
- **Local hermeticity check:** run `TempoGridOverlayScreenshotTests` and a couple
  of behavioral suites locally (no marker) and confirm they behave as before.
- **Skip-count baseline (needs a dev push):** UI tests only run on push-to-`dev`,
  so the "nothing silently started running" check can only be confirmed after
  merge, by comparing the `dev` push run's skip counts to the pre-change
  baseline. This is called out as a post-merge verification, not a PR gate.

## Risk

Medium — touches CI infra and 13 files, but each step is mechanical and the audit
bounded the one behavioural risk (TempoGrid) to a single line. The only check
that cannot run pre-merge is the dev-push skip-count comparison.

Refs #789, #785, #791. Spec anchor: `docs/verification.md#ui-smoke-xcuitest`.
