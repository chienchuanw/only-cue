#!/bin/bash
# Tests for machine-busy.sh — see
# docs/superpowers/specs/816-machine-contention-preflight.md (#816).
#
# Plain bash with no test framework so this runs on the self-hosted runner's
# system bash (3.2) without extra tooling. Usage:
#
#     scripts/ci/machine-busy.test.sh
#
# Every case feeds the detector a canned process table through
# MACHINE_BUSY_PS. That seam is the whole reason these tests can exist: the
# subject under test is "what is running on this machine", and this suite runs
# *on the contended machine* — in CI, with a live Runner.Worker and possibly a
# foreign xcodebuild. A test that consulted the real process table would be
# exactly the environment-dependent flake #816 is about.
#
# Exits non-zero if any case fails.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
detector="$script_dir/machine-busy.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

passed=0
failed=0

ok() {
  printf '  ok    %s\n' "$1"
  passed=$((passed + 1))
}

nope() {
  printf '  FAIL  %s\n' "$1"
  printf '        %s\n' "$2"
  failed=$((failed + 1))
}

expect_eq() { # label expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else nope "$1" "expected '$2', got '$3'"; fi
}

expect_contains() { # label haystack needle
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) nope "$1" "expected output to contain '$3', got: $2" ;;
  esac
}

if [ ! -x "$detector" ]; then
  echo "machine-busy.test.sh: $detector is missing or not executable" >&2
  exit 1
fi

# A canned `ps -Ao pid=,command=` table. `fixture <name>` writes one and echoes
# the command that replays it.
fixture() { # name, then lines on stdin
  cat >"$tmp/$1.ps"
  printf 'cat %s\n' "$tmp/$1.ps"
}

mine="/Users/chuan/Projects/only-cue"
theirs="/Users/chuan/actions-runner/_work/only-cue/only-cue"

# --- 1. a machine with nothing of ours on it --------------------------------

echo "reports clear when no test process is running"
ps_cmd="$(fixture clear <<EOF
  501 /usr/sbin/cfprefsd agent
  777 /Applications/Safari.app/Contents/MacOS/Safari
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" >/dev/null 2>&1
expect_eq "exits 0" "0" "$?"

# --- 2. a foreign xcodebuild -------------------------------------------------
# The local-side case: CI is mid-build while I am about to start a local run.

echo "reports busy for an xcodebuild outside my checkout"
ps_cmd="$(fixture foreign-xcodebuild <<EOF
  501 /usr/sbin/cfprefsd agent
  4242 /usr/bin/xcodebuild test-without-building -project $theirs/OnlyCue.xcodeproj
EOF
)"
err="$(MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" 2>&1 >/dev/null)"
status=$?
expect_eq "exits 1" "1" "$status"
expect_contains "names the offending pid" "$err" "4242"

# --- 3. my own xcodebuild is not "busy" -------------------------------------
# Without this, the guard would refuse to let a second selector-scoped run
# start while the first was finishing, and CI would flag its own build.

echo "ignores an xcodebuild inside my own checkout"
ps_cmd="$(fixture own-xcodebuild <<EOF
  4242 /usr/bin/xcodebuild test-without-building -project $mine/OnlyCue.xcodeproj
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" >/dev/null 2>&1
expect_eq "exits 0" "0" "$?"

# --- 4. the app and the UI runner, not just xcodebuild ----------------------
# `Lost connection to the application` is the *app* dying, and an xcodebuild
# that has handed off to the UI runner may already have exited.

echo "reports busy for a foreign OnlyCue.app"
ps_cmd="$(fixture foreign-app <<EOF
  5150 $theirs/Build/Products/Debug/OnlyCue.app/Contents/MacOS/OnlyCue --ui-test-seed=digit
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" >/dev/null 2>&1
expect_eq "exits 1" "1" "$?"

echo "reports busy for a foreign XCTRunner"
ps_cmd="$(fixture foreign-xctrunner <<EOF
  5151 $theirs/Build/Products/Debug/OnlyCueUITests-Runner.app/Contents/MacOS/XCTRunner
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" >/dev/null 2>&1
expect_eq "exits 1" "1" "$?"

# --- 5. Runner.Worker is opt-in ---------------------------------------------
# It carries no path on its command line, so it cannot be classified as mine or
# foreign. For the local caller any worker is foreign; for CI the only worker is
# its own job, so flagging it would make the guard fire on every single run.

echo "ignores Runner.Worker by default"
ps_cmd="$(fixture worker <<'EOF'
  6001 /Users/chuan/github-runner/bin.2.337.0/Runner.Worker spawnclient 157 160
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" >/dev/null 2>&1
expect_eq "exits 0 without --include-runner" "0" "$?"

err="$(MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" --include-runner 2>&1 >/dev/null)"
status=$?
expect_eq "exits 1 with --include-runner" "1" "$status"
expect_contains "names the worker" "$err" "6001"

# --- 6. --wait polls until clear --------------------------------------------
# A table that reports one foreign xcodebuild for the first two calls and
# nothing after, so the wait has to actually re-read it rather than cache.

echo "waits for a busy machine to clear"
cat >"$tmp/draining.sh" <<EOF
#!/bin/bash
count_file="$tmp/drain.count"
n=\$(cat "\$count_file" 2>/dev/null || echo 0)
echo \$((n + 1)) >"\$count_file"
if [ "\$n" -lt 2 ]; then
  echo "  4242 /usr/bin/xcodebuild test -project $theirs/OnlyCue.xcodeproj"
fi
EOF
chmod +x "$tmp/draining.sh"

MACHINE_BUSY_PS="$tmp/draining.sh" "$detector" --self "$mine" --wait 30 --interval 1 \
  >/dev/null 2>&1
expect_eq "exits 0 once it clears" "0" "$?"
expect_contains "re-read the table" "polled $(cat "$tmp/drain.count")" "polled 3"

# --- 7. --wait gives up ------------------------------------------------------
# The CI caller warns and continues on this; it must not hang past its budget.

echo "gives up when the machine never clears"
ps_cmd="$(fixture stuck <<EOF
  4242 /usr/bin/xcodebuild test -project $theirs/OnlyCue.xcodeproj
EOF
)"
start="$(date +%s)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --self "$mine" --wait 3 --interval 1 >/dev/null 2>&1
status=$?
elapsed=$(( $(date +%s) - start ))
expect_eq "exits 1 on timeout" "1" "$status"
if [ "$elapsed" -le 10 ]; then
  ok "respects the wait budget"
else
  nope "respects the wait budget" "waited ${elapsed}s for a 3s budget"
fi

# --- 8. usage ----------------------------------------------------------------
# --self is required: defaulting it to $PWD would silently classify every
# process as foreign when the script is invoked from elsewhere.

echo "rejects a missing --self"
"$detector" >/dev/null 2>&1
expect_eq "exits 2" "2" "$?"

# --- summary -----------------------------------------------------------------

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
