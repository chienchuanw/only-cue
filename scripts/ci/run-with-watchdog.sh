#!/bin/bash
# Run a command under a stall watchdog and a wall-clock cap.
#
# Why this exists (#775): the CI `UI tests (behavioral)` step wedges — xcodebuild
# stays alive with its stdout dead and never exits, so `run_ui_tests || retry`
# never fires and the job burns its full 90-minute budget for no result. A
# process that never exits needs an *external* killer.
#
# This deliberately does NOT wrap, re-exec, or re-parent the command, and does
# not touch its argv, environment or controlling terminal. #603/#605 established
# that wrapping the UI xcodebuild (with `caffeinate`) deterministically broke
# automation-mode init. The watchdog only stats a file and, on timeout, sends a
# signal.
#
# Usage:
#   run-with-watchdog.sh --log PATH [--stall-timeout SEC] [--hard-timeout SEC]
#                        [--heartbeat SEC] [--poll-interval SEC] -- CMD [ARGS...]
#
# Exit status: the command's own, or 124 (the timeout(1) convention) if killed.
# All diagnostics go to stderr, which is unbuffered and therefore visible live
# in the Actions log even when stdout is block-buffered through xcbeautify.
#
# Targets bash 3.2 (macOS system bash) — no `wait -n`, no associative arrays.
# Tests: scripts/ci/run-with-watchdog.test.sh

set -uo pipefail

log=""
stall_timeout=600
hard_timeout=2400
heartbeat=120
poll_interval=5

usage() {
  echo "usage: $0 --log PATH [--stall-timeout SEC] [--hard-timeout SEC]" >&2
  echo "          [--heartbeat SEC] [--poll-interval SEC] -- CMD [ARGS...]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --)              shift; break ;;
    -h|--help)       usage; exit 0 ;;
    --log)           log="$2";           shift 2 ;;
    --stall-timeout) stall_timeout="$2"; shift 2 ;;
    --hard-timeout)  hard_timeout="$2";  shift 2 ;;
    --heartbeat)     heartbeat="$2";     shift 2 ;;
    --poll-interval) poll_interval="$2"; shift 2 ;;
    *)
      echo "$0: unknown option '$1'" >&2
      usage
      exit 2
      ;;
  esac
done

if [ -z "$log" ]; then
  echo "$0: --log is required" >&2
  usage
  exit 2
fi

if [ $# -eq 0 ]; then
  echo "$0: no command given after --" >&2
  usage
  exit 2
fi

# The last test xcodebuild announced. This is the answer to "which test was in
# flight when it wedged" — the question the #775 forensics had to reconstruct by
# hand from DerivedData.
in_flight() {
  local line
  line="$(grep -E "Test [Cc]ase '.*' started" "$log" 2>/dev/null | tail -1)"
  if [ -n "$line" ]; then
    printf '%s' "$line"
  else
    printf 'unknown (no test-start line in the log yet)'
  fi
}

own_pgid="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"

# Kill the command's whole process group: `kill "$job"` alone would leave the
# pipeline's other members (xcodebuild itself, `tee`) running.
#
# This deliberately does not try to reach XCTRunner or the app under test —
# those are spawned by testmanagerd, not inside this process group, so no
# signal sent here can touch them. ci.yml's `reset_ui_daemons` owns that
# cleanup and runs right after a 124.
kill_command_tree() {
  local pgid
  pgid="$(ps -o pgid= -p "$job" 2>/dev/null | tr -d ' ')"
  if [ -n "$pgid" ] && [ "$pgid" != "$own_pgid" ]; then
    kill -9 -"$pgid" 2>/dev/null || true
  fi
  kill -9 "$job" 2>/dev/null || true
}

: >"$log"

# Completion is signalled by a sentinel file rather than `kill -0 "$job"`: a
# finished-but-unreaped child is a zombie, and `kill -0` still succeeds on a
# zombie, which would spin this loop forever.
state_dir="$(mktemp -d -t onlycue-watchdog)"
trap 'rm -rf "$state_dir"' EXIT
status_file="$state_dir/status"

# `set -m` puts the job in its own process group so kill_command_tree can signal
# the group without also killing this script.
set -m
{ "$@" 2>&1 | tee -a "$log"; echo "${PIPESTATUS[0]}" >"$status_file"; } &
job=$!
set +m

start="$(date +%s)"
last_beat="$start"
# The log's mtime *is* the stall clock — the filesystem already records when the
# command last wrote, so tracking a byte count alongside it would just be a
# second copy of the same fact. `: >"$log"` above seeded it to now.
# `stat -f` is BSD; the runner and this whole project are macOS-only (ADR-001).
last_out="$start"
reason=""

while :; do
  sleep "$poll_interval"

  # Completion is checked before the clocks: a command that exited during the
  # sleep has not wedged, however quiet it was beforehand. Checking the other
  # way round kills a finishing command and reports a green run as a wedge.
  if [ -f "$status_file" ]; then
    break
  fi

  now="$(date +%s)"
  last_out="$(stat -f %m "$log" 2>/dev/null || echo "$last_out")"

  if [ $((now - last_out)) -ge "$stall_timeout" ]; then
    reason="produced no output for ${stall_timeout}s"
  elif [ $((now - start)) -ge "$hard_timeout" ]; then
    reason="exceeded the ${hard_timeout}s cap"
  fi

  if [ -n "$reason" ]; then
    # It may have exited while we were deciding. Re-check rather than kill a
    # command that already finished.
    if [ -f "$status_file" ]; then
      reason=""
    fi
    break
  fi

  if [ "$heartbeat" -gt 0 ] && [ $((now - last_beat)) -ge "$heartbeat" ]; then
    last_beat="$now"
    printf '[watchdog] %ss elapsed, %ss since last output — in flight: %s\n' \
      "$((now - start))" "$((now - last_out))" "$(in_flight)" >&2
  fi
done

if [ -n "$reason" ]; then
  {
    echo "::error::Watchdog: the command $reason — killing it. In flight: $(in_flight)"
    echo "----- last 40 lines of raw output -----"
    tail -40 "$log" 2>/dev/null
    echo "----- end of raw output ---------------"
  } >&2
  kill_command_tree
  wait "$job" 2>/dev/null || true
  exit 124
fi

wait "$job" 2>/dev/null || true
exit "$(cat "$status_file" 2>/dev/null || echo 1)"
