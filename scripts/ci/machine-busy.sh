#!/bin/bash
# Is someone else's OnlyCue test run happening on this machine right now?
#
# The self-hosted GitHub Actions runner lives on the same Mac mini as local
# development, and XCUITest does not survive CPU contention. The damage goes
# both ways (#816):
#
#   CI -> local   a running UI-test job makes the local unit suite fail on
#                 random unrelated tests that pass in isolation.
#   local -> CI   a local xcodebuild makes the CI UI-test step fail with
#                 repeated "Lost connection to the application" — the app
#                 process dying, not an assertion. Three consecutive dev runs
#                 went red this way on 2026-09-15 and looked like a code
#                 regression; the first run with the machine left alone passed
#                 first try.
#
# Both callers ask the same question, so they share this script:
#
#   scripts/dev/test.sh    --self <repo>             --include-runner --wait 1800
#   ci.yml                 --self $GITHUB_WORKSPACE                   --wait 900
#
# Usage:
#
#     machine-busy.sh --self <dir> [--include-runner] [--wait <sec>] [--interval <sec>]
#
# Exit 0  the machine is clear (immediately, or it cleared within --wait).
# Exit 1  still busy when the wait ran out. Offending processes go to stderr.
# Exit 2  usage error.
#
# There is deliberately no load-average gate. Process detection is the direct
# signal and load average is a lagging proxy for it, so gating on load would add
# a failure mode (an unrelated heavy process blocking tests indefinitely) to
# catch nothing the process check misses. The 1-minute load is printed for
# diagnostics only.
#
# MACHINE_BUSY_PS overrides how the process table is read. It exists so
# machine-busy.test.sh can feed canned tables: the subject under test is "what
# is running on this machine", and the suite runs on the contended machine.

set -uo pipefail

self=""
include_runner=0
wait_budget=0
interval=15

usage() {
  echo "usage: machine-busy.sh --self <dir> [--include-runner] [--wait <sec>] [--interval <sec>]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --self) [ $# -ge 2 ] || usage; self="$2"; shift 2 ;;
    --include-runner) include_runner=1; shift ;;
    --wait) [ $# -ge 2 ] || usage; wait_budget="$2"; shift 2 ;;
    --interval) [ $# -ge 2 ] || usage; interval="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# Required, never defaulted to $PWD: a wrong --self silently reclassifies every
# process as foreign, which would make the guard fire forever.
[ -n "$self" ] || usage

ps_command="${MACHINE_BUSY_PS:-ps -Ao pid=,command=}"

# One line per foreign process, "<pid> <command>". Empty means clear.
#
# `xcodebuild` alone is not enough: it hands off to the UI runner, so the app
# and XCTRunner can outlive it, and `Lost connection to the application` is the
# app dying. Runner.Worker carries no path on its command line and so cannot be
# classified — for the local caller every worker is foreign, but for CI the only
# worker is its own job, which is why it is opt-in rather than always counted.
#
# The *executable* decides whether a process is interesting; the *whole command
# line* decides whether it is mine. Matching the whole line for both flagged the
# shell that invoked this script, because the command being typed mentioned
# xcodebuild — every shell, editor or grep naming the binary would have held the
# guard busy forever.
foreign() {
  $ps_command 2>/dev/null | while IFS= read -r line; do
    [ -n "$line" ] || continue

    # shellcheck disable=SC2086 # deliberate word-split: "<pid> <exe> <args…>"
    set -- $line
    [ $# -ge 2 ] || continue
    exe="$2"

    case "$exe" in
      *Runner.Worker)
        [ "$include_runner" -eq 1 ] && printf '%s\n' "$line"
        continue
        ;;
      */xcodebuild|xcodebuild|*/OnlyCue.app/Contents/MacOS/OnlyCue|*/XCTRunner) ;;
      *) continue ;;
    esac

    # Mine if the command line mentions my checkout — the only classifier
    # available, since the runner runs as the same user as local development.
    case "$line" in
      *"$self"*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

report() { # the foreign lines
  echo "machine-busy: another OnlyCue test run is using this machine (#816):" >&2
  printf '%s\n' "$1" | sed 's/^/  /' >&2
  echo "  1-minute load: $(uptime | sed 's/.*load averages*: //')" >&2
}

deadline=$(( $(date +%s) + wait_budget ))
while :; do
  busy="$(foreign)"
  if [ -z "$busy" ]; then
    exit 0
  fi

  now="$(date +%s)"
  if [ "$now" -ge "$deadline" ]; then
    report "$busy"
    exit 1
  fi

  remaining=$(( deadline - now ))
  echo "machine-busy: waiting up to ${remaining}s for the machine to clear…" >&2
  sleep "$interval"
done
