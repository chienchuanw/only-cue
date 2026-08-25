# CI — UI-test stall watchdog (#775) and single-run fast-forward (#776)

**Status:** draft (awaiting approval 2026-08-26)
**Issues:** #775 (`bug`, `p0-blocker`, `type:ci`), #776 (`chore`, `p2`, `type:ci`)
**Touches:** `.github/workflows/ci.yml`, new `scripts/ci/`
**Prior art:** #471, #595 (testmanagerd control-session reset), #603/#605
(`caffeinate` + `-test-timeouts-enabled` tried and reverted — both broke
automation-mode init)

## Problem

`UI tests (behavioral)` wedges and `xcodebuild` never exits, so the job burns its
full `timeout-minutes: 90` and produces no result. The existing self-heal is
`run_ui_tests || { reset_ui_daemons; run_ui_tests; }` — it only fires on a
*non-zero exit*, which a wedge never produces. The 90-minute cap is the only
backstop.

### How bad it actually is

Measured across `ci.yml` runs 2026-08-16 → 2026-08-25:

| push runs to `dev`/`main` | wedged at the 90-min cap |
| ------------------------- | ------------------------ |
| ~14                       | ~10                      |

This is not an occasional flake. It is the normal outcome of a push.

### Healthy baseline (drives the timeout numbers)

Commit `3fa5ea9` ran twice — once per branch — and both were healthy:

| run        | branch | UI step duration |
| ---------- | ------ | ---------------- |
| 32879198538 | dev    | **28m44s**       |
| 32882261391 | main   | **7m04s**        |

Same commit, same suite, 4× spread. The difference is `-test-iterations 2
-retry-tests-on-failure` — a flaky run re-runs tests and takes far longer. So
**"healthy" is a wide band (7–29 min), and a wall-clock cap alone is a blunt
instrument**: to be safe it must sit around 40 min, which means a wedge starting
at minute 2 still costs 40 minutes.

That is why the stall detector is the primary signal and the cap is only a
backstop.

## Confirmed decisions

Decided with the maintainer on 2026-08-26.

1. **Stall detector primary, hard cap as backstop.** Kill when `xcodebuild`
   produces no output for 10 minutes, *or* when a single attempt exceeds 40
   minutes — whichever comes first.
2. **Connection-loss signal is warn-only.** Count
   `Lost connection to the application` occurrences and surface a `::warning::`
   with the tally. Do **not** abort on it. We have no baseline for a sane
   threshold, and shipping a new abort path alongside a new kill path doubles
   the ways this change can itself break CI. A follow-up issue tunes it once we
   have clean data.
3. **#776: skip UI tests on `main` pushes.** `main` keeps lint + build + unit
   (~60s) as a "did the fast-forward land a buildable tree" check; the release
   commit inherits `dev`'s UI green.

## Why a stall detector is sound here

From the #775 forensics, during the wedge `xcodebuild`'s **stdout** goes silent —
the 500 KB/min of `Checking status using token 15` goes to the XCTest *session
log* inside DerivedData, not to stdout. The live CI log showed only occasional
unbuffered stderr.

A healthy run emits test events at roughly 2/min. A 10-minute stdout silence is
therefore ~20× the healthy inter-event gap and cannot happen on a healthy run.

## Design

### `scripts/ci/run-with-watchdog.sh`

A single-purpose, project-agnostic wrapper. Splitting it out of `ci.yml` is what
makes it *testable* — YAML `run:` blocks cannot be unit-tested, and this logic
must not itself become a new way for CI to hang.

```
run-with-watchdog.sh --log PATH [--stall-timeout SEC] [--hard-timeout SEC]
                     [--heartbeat SEC] -- COMMAND [ARGS...]
```

Behaviour:

- Runs `COMMAND` with stdout+stderr tee'd to `--log` **and** forwarded to the
  script's stdout, so the caller can still pipe into `xcbeautify`.
- Polls the log every 5s. Tracks byte count; resets the stall clock on growth.
- Emits a heartbeat line to **stderr** every `--heartbeat` seconds (default 120)
  with elapsed time and the last observed `Test Case '...' started`. stderr is
  unbuffered, so this is visible live in the Actions log — fixing the
  "reads as nothing is happening" complaint in the #775 Notes.
- On stall or hard-cap: prints `::error::` naming **which test was in flight**,
  dumps the last 40 raw lines, kills the whole process group, exits `124`.
- Otherwise exits with `COMMAND`'s status.

Implementation notes that matter:

- The command runs as a background job under `set -m`, so it gets its own
  process group and `kill -9 -$pgid` reaps `xcodebuild` *and* `tee` together.
  Killing only the `xcodebuild` pid would leave helpers orphaned.
- Completion is detected via a sentinel status file, not `kill -0` — a finished
  child is a zombie until reaped and `kill -0` still succeeds on it, which would
  spin the monitor loop forever.
- Targets **bash 3.2** (macOS system bash). No `wait -n`, no associative arrays.
- Exit `124` follows the `timeout(1)` convention.

### `ci.yml` wiring

```
run_ui_tests() {
  scripts/ci/run-with-watchdog.sh --log "$RAW_LOG" \
    --stall-timeout 600 --hard-timeout 2400 \
    -- xcodebuild test-without-building ...existing flags unchanged... \
    | xcbeautify --renderer github-actions
}
```

The `xcodebuild` invocation itself is **byte-for-byte unchanged**. Given #605 —
where wrapping it in `caffeinate` deterministically broke automation-mode init —
the watchdog deliberately does not alter argv, environment, or the process's
controlling terminal. It only observes a file and, on timeout, sends a signal.

After each attempt, `ci.yml` counts connection losses from `$RAW_LOG` and emits
the `::warning::`. That stays in `ci.yml` rather than the script so the script
holds no OnlyCue-specific knowledge.

`$RAW_LOG` lives under `$RUNNER_TEMP` and is uploaded via `actions/upload-artifact`
on failure, so a wedge is post-mortem-able without SSHing to the Mac mini.

### Timeout budget

| | |
| --- | --- |
| stall timeout | 600s (10 min) — 20× the healthy inter-event gap |
| hard cap / attempt | 2400s (40 min) — 11 min over the worst healthy run |
| worst case, both attempts | 40 + 40 + ~2 = **82 min** < the 90-min job cap |

If a genuinely healthy run ever exceeds 40 min, the watchdog fires *and its
diagnostic shows steady progress* — self-diagnosing, and the fix is one number.

### #776

Add one condition to the UI step, with the trade-off recorded as a `ci.yml`
comment (which AC bullet 2 explicitly permits, so no ADR):

```yaml
if: github.event_name == 'push' && github.ref != 'refs/heads/main'
```

## Test plan (TDD)

`scripts/ci/run-with-watchdog.test.sh` — plain bash, runs in seconds, written
first and seen red:

1. Fast success → exit 0, stdout forwarded verbatim, log written.
2. Non-zero command → exit code propagates unchanged.
3. Emits one line then sleeps, `--stall-timeout 3` → exit 124; stderr names the
   in-flight test.
4. Chatty but endless, `--hard-timeout 3` → exit 124 *despite* continuous output
   (proves the cap is independent of the stall clock).
5. After a kill, the grandchild pid is gone (proves process-group reaping).

This step also runs in CI, before `Build`.

## Known gap

`ci.yml` runs the UI step only on `push`, never on `pull_request`. So the PR for
#775 will **not** exercise the watchdog against a real `xcodebuild` — its first
live run is the merge push to `dev`. The bash tests are the real safety net; the
first post-merge `dev` run is the acceptance check.

## Acceptance mapping

| #775 AC | Covered by |
| --- | --- |
| Wedge fails within N min, not 90 | stall 600s / cap 2400s |
| One-shot retry demonstrably fires | watchdog exits 124 → `\|\|` branch reachable; test 3/4 prove non-zero exit |
| Reports which test was in flight | `::error::` + heartbeat, from the raw log |
| Re-run suite, classify the 3 suspect classes | post-merge follow-up, not code |

| #776 AC | Covered by |
| --- | --- |
| FF consumes the runner once | `github.ref != 'refs/heads/main'` |
| Decision recorded | `ci.yml` comment |

## Sequencing

#775 first (p0-blocker), merge to `dev`, then #776 rebased on top. Both edit the
same few lines of the UI-test step, so parallel branches would conflict.

## Out of scope

- Aborting on connection-loss threshold (decision 2 — follow-up issue).
- Re-enabling UI tests on PRs (long-standing separate decision, see the `ci.yml`
  comment block at the UI step).
- Re-litigating `-test-timeouts-enabled` (reverted in #605).
- Whether the 3 suspect test classes are real regressions — needs a stable runner
  first, which is what this change buys.
