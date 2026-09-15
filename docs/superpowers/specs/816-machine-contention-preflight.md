# 816 — Bidirectional pre-flight guard for the shared Mac mini

**Issue:** #816
**Status:** proposed

## Goal

Stop local `xcodebuild` runs and CI UI-test jobs from corrupting each other on the Mac mini
they share, and make any failure that happens anyway say so in its own output.

## Why this, and not "fix the flaky tests"

#816 was filed as "`OnlyCueTests` fails nondeterministically; different tests each run, all
pass in isolation". Two measurements on 2026-09-15 changed its shape:

- **CI → local.** Two local full-suite runs failed on two different unrelated tests. `ps`
  then showed `OnlyCue.app --ui-test-seed=…` at 220% CPU under a foreign DerivedData hash
  plus a live `Runner.Worker`: the runner was executing dev run 34967315810 through both.
  With the machine verified idle, the same suite passed — 1822 tests, first try.
- **local → CI.** `dev` failed three consecutive runs (34947557702, 34952854230,
  34967315810), every one on `UI tests (behavioral)`, every one with the same signature
  (6–10 × `Lost connection to the application` — the app process dying, not an assertion).
  Local `xcodebuild` / `dotnet test` was running during all three. Run 34969558846, the
  first where the machine was deliberately left alone, passed first try with no retry.

Neither is proof on its own (n=1 each), but together they say the failures are contention,
not code — and the three red dev runs invite exactly the wrong conclusion ("something in
#835 broke UI tests"; nothing did). The cost of *not* fixing this is that every future
flake costs a debugging session to re-derive.

The runner runs as `chuan`, the same user as local development, so a process cannot be
classified by uid. It can be classified by **path**: the runner's checkout lives under
`~/actions-runner/_work/` (or `~/github-runner/_work/`), local development under
`~/Projects/only-cue`.

## Input / Output

### `scripts/ci/machine-busy.sh` (new, shared by both sides)

```
machine-busy.sh [--runner] [--under <dir>]… [--wait <sec>] [--interval <sec>]
```

| Flag | Meaning |
|---|---|
| `--runner` | A live `Runner.Worker` counts as busy. Set by the local caller; **not** by CI, where the only worker is the caller's own job. |
| `--under <dir>` | Processes whose command line mentions `<dir>` count as busy. Repeatable. |
| `--wait <sec>` | Poll until clear, up to this many seconds. Default `0` (check once). |
| `--interval <sec>` | Poll interval. Default `15`. |

Busy if any enabled predicate matches. At least one of `--runner` / `--under` is required —
with neither, nothing can ever match and the guard would pass unconditionally.

**Watched executables**: `xcodebuild`, `OnlyCue.app/Contents/MacOS/OnlyCue`, `XCTRunner`, and
`Runner.Worker`. The *executable* decides whether a process is interesting; its *arguments*
decide whether it is under a watched root.

**Correction to the first draft.** This started as `--self <dir> [--include-runner]`: each
side passes its own checkout and everything else is foreign. Implementation exposed a flaw
that would have hurt CI on every run. DerivedData lives in
`~/Library/Developer/Xcode/DerivedData`, **not** under `$GITHUB_WORKSPACE`, so a stale
`OnlyCue.app` left by an interrupted previous job reads as foreign — and CI would burn its
entire 900 s budget waiting for a process the very next lines of `Reset stale test state`
were about to kill. Asking *positively* ("is anything running under this root?") cannot make
that mistake, and it lets the two sides ask the different questions they actually have:

| Side | Question | Flags |
|---|---|---|
| local | is a CI job running? | `--runner` (+ the runner work roots, a second signal for a worker that died leaving its `xcodebuild`) |
| CI | is anything running out of the maintainer's working copy? | `--under "$HOME/Projects"` |

`scripts/ci/machine-busy.test.sh` pins the stale-own-app case so the negative form cannot
come back.

**Known gap.** A local run's *app host* lives under DerivedData and so is not attributable to
`~/Projects`. CI catches the local `xcodebuild` instead, which is alive for the whole local
run — and because the guard runs before the `pkill`s, a live local run is waited out rather
than killed. Orphaned app processes with no live `xcodebuild` are what those `pkill`s are
for.

**Exit 0** machine clear (immediately, or it cleared within `--wait`).
**Exit 1** still busy when the wait ran out. Prints each offending pid + command line, and
the 1-minute load average, to stderr.

**No load-average gate.** I floated one in the #816 discussion; dropping it is a deliberate
reversal. Process detection is the direct signal and load average is a lagging proxy for it,
so gating on load adds a second failure mode (an unrelated heavy process blocks tests
indefinitely) to catch nothing the process check misses. Load is *reported* for diagnostics
only.

### `scripts/dev/test.sh` (new, local only)

```
scripts/dev/test.sh [extra xcodebuild args…]
```

1. `machine-busy.sh --runner --under <runner work roots> --wait 1800` — refuses to start if
   CI is mid-job, rather than racing it. Exit 1 with the offending processes named.
2. `killall -9 testmanagerd` (the #595 reset).
3. `xcodebuild test` with `-destination 'platform=macOS,arch=arm64'`, ad-hoc signing
   (`CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` — without it
   the runner is flagged "damaged" and hangs), and `-only-testing:OnlyCueTests` unless the
   caller passes their own `-only-testing:` selector.

Deliberately thin: a guard, the daemon reset, and the invocation. It is not a build system.

### `.github/workflows/ci.yml` (changed)

- `Reset stale test state` gains, as its **first** action:
  `scripts/ci/machine-busy.sh --under "$HOME/Projects" --wait 900 || echo "::warning::…"`.
  Bounded wait, then **warn and continue** — never fail. A red `dev` for a reason that has
  nothing to do with `dev` is the thing this is trying to stop, so the guard must not
  create one. Placed here, before `Unit tests`, so both test steps benefit from the one wait.
- `UI tests (behavioral)` gains a **zero-wait** re-check that only annotates. This is the
  diagnostic that was missing: when the step fails, its own log then says whether the
  machine was contaminated at that moment, instead of leaving it to be reconstructed from
  `ps` after the fact.
- `timeout-minutes: 90 → 105`. The existing worst case is ~82 min (two watchdog-capped
  UI attempts at 2400 s plus the earlier steps); a 900 s wait would push that to ~97.
  900 s is chosen to outlast a local full unit run (~6–8 min observed), which a shorter
  wait would usually fail to do, making it warn rather than wait. The extra 15 min of
  exposure on a wedged job is bounded — `run-with-watchdog.sh` already caps the real work.
- `CI script tests` runs `scripts/ci/machine-busy.test.sh` alongside the existing suite.

## Steps

1. `scripts/ci/machine-busy.test.sh` — failing first (TDD), per the repo's existing
   `*.test.sh` convention.
2. `scripts/ci/machine-busy.sh` to green.
3. `scripts/dev/test.sh`.
4. Wire both into `ci.yml`; extend the `CI script tests` step.

## Edge cases

- **Mid-job starts.** A local run that begins *after* the guard has passed is not caught.
  Only a mutual `flock` would catch it, and a fixed shared path is a known trap in this repo
  (#789) — a stale lock from a `kill -9`'d local run would hold CI to the job timeout. The
  local wrapper is the mitigation: it refuses while `Runner.Worker` is alive, which is the
  direction that actually caused the three red runs.
- **Two runner installs.** Both `~/github-runner` and `~/actions-runner` have a live
  `Runner.Listener`. The detector matches on the process name, so it does not care which.
- **Self-match.** `machine-busy.sh` must not see its own `ps` invocation, nor the
  `xcodebuild` that `scripts/dev/test.sh` is about to launch (it launches after the check).
  Found for real, not by a canned table: matching the whole command line flagged the *shell
  that invoked the detector*, because the command being typed mentioned `xcodebuild`. Any
  shell, editor or `grep` naming the binary would have held the guard busy forever. Hence
  classifying on the executable and matching roots on the arguments.
- **No foreign process, high load.** Not busy. See the no-load-gate note above.

## Acceptance

- `scripts/ci/machine-busy.test.sh` passes, covering: clear machine → 0; `xcodebuild` under a
  watched root → 1; `xcodebuild` outside every watched root → 0; a process that merely
  *mentions* `xcodebuild` → 0; a stale app from CI's own previous run → 0; `OnlyCue.app` /
  `XCTRunner` under a watched root → 1; `Runner.Worker` ignored without `--runner` and
  honoured with it; `--wait` returns 0 as soon as the process exits; `--wait` returns 1 on
  timeout; an invocation with no predicate → 2.
- Those cases are mutation-tested: inverting the root match, ungating `Runner.Worker`,
  classifying on the whole command line, dropping the no-predicate guard, and removing the
  app/`XCTRunner` arms must each turn the suite red.
- `scripts/dev/test.sh` exits non-zero without invoking `xcodebuild` while a `Runner.Worker`
  is alive.
- A dev run's log shows the guard's verdict in `Reset stale test state`, and again at
  `UI tests (behavioral)`.
