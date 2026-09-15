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

# The four places an OnlyCue process can live on this machine. Note that neither
# DerivedData path sits under its own checkout — that asymmetry is what the
# --under design is built around, and case 3c pins it.
local_checkout="/Users/chuan/Projects/only-cue"
runner_checkout="/Users/chuan/actions-runner/_work/only-cue/only-cue"
local_derived="/Users/chuan/Library/Developer/Xcode/DerivedData/OnlyCue-aaaalocal"
ci_derived="/Users/chuan/Library/Developer/Xcode/DerivedData/OnlyCue-zzzzzzci"

# --- 1. a machine with nothing of ours on it --------------------------------

echo "reports clear when no test process is running"
ps_cmd="$(fixture clear <<EOF
  501 /usr/sbin/cfprefsd agent
  777 /Applications/Safari.app/Contents/MacOS/Safari
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --runner --under "$local_checkout" >/dev/null 2>&1
expect_eq "exits 0" "0" "$?"

# --- 2. CI sees a local xcodebuild ------------------------------------------
# The CI-side question: is anything running out of the maintainer's working
# copy? A local `xcodebuild test -project ~/Projects/…` names it directly, and
# xcodebuild stays alive for the whole local run.

echo "reports busy for an xcodebuild under a watched root"
ps_cmd="$(fixture local-xcodebuild <<EOF
  501 /usr/sbin/cfprefsd agent
  4242 /usr/bin/xcodebuild test -project $local_checkout/OnlyCue.xcodeproj -scheme OnlyCue
EOF
)"
err="$(MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_checkout" 2>&1 >/dev/null)"
status=$?
expect_eq "exits 1" "1" "$status"
expect_contains "names the offending pid" "$err" "4242"

# --- 3. CI's own xcodebuild is not "busy" -----------------------------------
# Only watched roots count. CI's own build runs out of the runner's checkout,
# which nobody asked about.

echo "ignores an xcodebuild outside every watched root"
ps_cmd="$(fixture ci-xcodebuild <<EOF
  4242 /usr/bin/xcodebuild test -project $runner_checkout/OnlyCue.xcodeproj
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_checkout" >/dev/null 2>&1
expect_eq "exits 0" "0" "$?"

# --- 3b. only the executable counts, not the arguments ----------------------
# Caught by running the detector for real, not by a canned table: the very shell
# invoking it matched, because the command I had typed *mentioned* xcodebuild.
# Any shell, editor, grep or CI step that names the binary would trip the guard
# forever, and the guard's whole job is to not produce phantom failures.

echo "ignores a process that merely mentions xcodebuild in its arguments"
ps_cmd="$(fixture mentions <<EOF
  4242 /bin/zsh -c eval 'killall testmanagerd; xcodebuild test -project $local_checkout/X.xcodeproj'
  4243 /usr/bin/grep xcodebuild $local_checkout/ci.yml
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_checkout" >/dev/null 2>&1
expect_eq "exits 0" "0" "$?"

# --- 3c. CI must not wait on its own leftovers ------------------------------
# The case that killed the first design, which had each side pass its own
# checkout and treat everything else as foreign. DerivedData lives in
# ~/Library/Developer/Xcode/DerivedData, *not* under $GITHUB_WORKSPACE, so a
# stale OnlyCue.app from an interrupted previous job read as foreign and CI
# burned its entire 900s budget waiting for a process the very next lines of
# `Reset stale test state` were about to kill. Asking positively cannot make
# that mistake — and this pins it so nobody reintroduces the negative form.

echo "ignores a stale app from CI's own previous run"
ps_cmd="$(fixture stale-ci-app <<EOF
  5150 $ci_derived/Build/Products/Debug/OnlyCue.app/Contents/MacOS/OnlyCue --ui-test-seed=digit
  5151 $ci_derived/Build/Products/Debug/OnlyCueUITests-Runner.app/Contents/MacOS/XCTRunner
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_checkout" >/dev/null 2>&1
expect_eq "exits 0" "0" "$?"

# --- 4. the app and the UI runner, not just xcodebuild ----------------------
# `Lost connection to the application` is the *app* dying, and an xcodebuild
# that has handed off to the UI runner may already have exited. Both live under
# DerivedData, so catching them means watching that root rather than a checkout.

echo "reports busy for an OnlyCue.app under a watched root"
ps_cmd="$(fixture watched-app <<EOF
  5150 $local_derived/Build/Products/Debug/OnlyCue.app/Contents/MacOS/OnlyCue --ui-test-seed=digit
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_derived" >/dev/null 2>&1
expect_eq "exits 1" "1" "$?"

echo "reports busy for an XCTRunner under a watched root"
ps_cmd="$(fixture watched-xctrunner <<EOF
  5151 $local_derived/Build/Products/Debug/OnlyCueUITests-Runner.app/Contents/MacOS/XCTRunner
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_derived" >/dev/null 2>&1
expect_eq "exits 1" "1" "$?"

# --- 5. Runner.Worker is opt-in ---------------------------------------------
# It carries no path on its command line, so it can never be attributed to a
# root — it is a yes/no question, and the two sides want opposite answers. For
# the local caller any worker means CI is mid-job; for CI the only worker is its
# own, so counting it there would make the guard fire on every single run.

echo "answers Runner.Worker only when asked"
ps_cmd="$(fixture worker <<'EOF'
  6001 /Users/chuan/github-runner/bin.2.337.0/Runner.Worker spawnclient 157 160
EOF
)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_checkout" >/dev/null 2>&1
expect_eq "exits 0 without --runner" "0" "$?"

err="$(MACHINE_BUSY_PS="$ps_cmd" "$detector" --runner 2>&1 >/dev/null)"
status=$?
expect_eq "exits 1 with --runner" "1" "$status"
expect_contains "names the worker" "$err" "6001"

# --- 6. --wait polls until clear --------------------------------------------
# A table that reports one watched xcodebuild for the first two calls and
# nothing after, so the wait has to actually re-read it rather than cache.

echo "waits for a busy machine to clear"
cat >"$tmp/draining.sh" <<EOF
#!/bin/bash
count_file="$tmp/drain.count"
n=\$(cat "\$count_file" 2>/dev/null || echo 0)
echo \$((n + 1)) >"\$count_file"
if [ "\$n" -lt 2 ]; then
  echo "  4242 /usr/bin/xcodebuild test -project $local_checkout/OnlyCue.xcodeproj"
fi
EOF
chmod +x "$tmp/draining.sh"

MACHINE_BUSY_PS="$tmp/draining.sh" "$detector" --under "$local_checkout" --wait 30 --interval 1 \
  >/dev/null 2>&1
expect_eq "exits 0 once it clears" "0" "$?"
expect_contains "re-read the table" "polled $(cat "$tmp/drain.count")" "polled 3"

# --- 7. --wait gives up ------------------------------------------------------
# The CI caller warns and continues on this; it must not hang past its budget.

echo "gives up when the machine never clears"
ps_cmd="$(fixture stuck <<EOF
  4242 /usr/bin/xcodebuild test -project $local_checkout/OnlyCue.xcodeproj
EOF
)"
start="$(date +%s)"
MACHINE_BUSY_PS="$ps_cmd" "$detector" --under "$local_checkout" --wait 3 --interval 1 \
  >/dev/null 2>&1
status=$?
elapsed=$(( $(date +%s) - start ))
expect_eq "exits 1 on timeout" "1" "$status"
if [ "$elapsed" -le 10 ]; then
  ok "respects the wait budget"
else
  nope "respects the wait budget" "waited ${elapsed}s for a 3s budget"
fi

# --- 8. usage ----------------------------------------------------------------
# With no predicate enabled nothing can ever match, so the detector would report
# "clear" unconditionally — a guard that always passes is worse than no guard.

echo "rejects an invocation that can never match"
"$detector" >/dev/null 2>&1
expect_eq "exits 2 with no predicate" "2" "$?"

"$detector" --under >/dev/null 2>&1
expect_eq "exits 2 for --under without a value" "2" "$?"

# --- summary -----------------------------------------------------------------

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
