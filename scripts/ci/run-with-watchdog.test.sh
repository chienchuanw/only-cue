#!/bin/bash
# Tests for run-with-watchdog.sh — see
# docs/superpowers/specs/2026-08-26-ci-ui-test-watchdog-design.md (#775).
#
# Plain bash with no test framework so this runs on the self-hosted runner's
# system bash (3.2) without extra tooling. Usage:
#
#     scripts/ci/run-with-watchdog.test.sh
#
# Exits non-zero if any case fails.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
watchdog="$script_dir/run-with-watchdog.sh"

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

if [ ! -x "$watchdog" ]; then
  echo "run-with-watchdog.test.sh: $watchdog is missing or not executable" >&2
  exit 1
fi

# --- 1. a fast, successful command ------------------------------------------
# The wrapper must be transparent: same exit status, same stdout, plus a log.

echo "forwards stdout and exits 0 when the command succeeds"
cat >"$tmp/hello.sh" <<'EOF'
#!/bin/bash
echo "alpha"
echo "beta"
EOF
chmod +x "$tmp/hello.sh"

out="$("$watchdog" --log "$tmp/hello.log" --poll-interval 1 -- "$tmp/hello.sh" 2>/dev/null)"
status=$?
expect_eq "exits 0" "0" "$status"
expect_contains "forwards stdout" "$out" "alpha"
expect_contains "writes the raw log" "$(cat "$tmp/hello.log")" "beta"

# --- 2. exit-status propagation ---------------------------------------------
# The `run_ui_tests || { reset; retry; }` fallback in ci.yml depends on the
# real xcodebuild status surviving the wrapper.

echo "propagates a non-zero exit status"
cat >"$tmp/boom.sh" <<'EOF'
#!/bin/bash
echo "boom"
exit 3
EOF
chmod +x "$tmp/boom.sh"

"$watchdog" --log "$tmp/boom.log" --poll-interval 1 -- "$tmp/boom.sh" >/dev/null 2>&1
expect_eq "exits 3" "3" "$?"

# --- 3. the stall detector (the #775 wedge) ---------------------------------
# Emits one test-start line, then goes silent forever — exactly the observed
# failure: xcodebuild alive, stdout dead, never exits.

echo "kills a stalled command and names the test in flight"
cat >"$tmp/stall.sh" <<'EOF'
#!/bin/bash
echo "Test Case '-[OnlyCueUITests.CueListPaneLayoutUITests test_playheadClockIsPresent]' started."
sleep 120
EOF
chmod +x "$tmp/stall.sh"

err="$("$watchdog" --log "$tmp/stall.log" --poll-interval 1 --stall-timeout 3 \
  -- "$tmp/stall.sh" 2>&1 >/dev/null)"
status=$?
expect_eq "exits 124 on stall" "124" "$status"
expect_contains "reports the in-flight test" "$err" "test_playheadClockIsPresent"

# --- 4. the hard cap, independent of the stall clock ------------------------
# Chatty forever: the stall clock never trips, so only the wall-clock cap can
# stop it. This is what proves the two limits are genuinely independent.

echo "kills an over-long command even while it keeps producing output"
cat >"$tmp/chatty.sh" <<'EOF'
#!/bin/bash
while :; do
  echo "still going"
  sleep 1
done
EOF
chmod +x "$tmp/chatty.sh"

"$watchdog" --log "$tmp/chatty.log" --poll-interval 1 --stall-timeout 600 \
  --hard-timeout 3 -- "$tmp/chatty.sh" >/dev/null 2>&1
expect_eq "exits 124 on the hard cap" "124" "$?"

# --- 5. process-group reaping ------------------------------------------------
# Killing only the direct child would orphan xcodebuild's helpers and leave the
# runner dirty for the retry — the whole point of the retry is a clean slate.

echo "reaps grandchildren, not just the direct child"
cat >"$tmp/spawner.sh" <<'EOF'
#!/bin/bash
sleep 120 &
echo "$!" >"$1"
echo "Test Case '-[OnlyCueUITests.FooTests test_bar]' started."
sleep 120
EOF
chmod +x "$tmp/spawner.sh"

"$watchdog" --log "$tmp/spawn.log" --poll-interval 1 --stall-timeout 3 \
  -- "$tmp/spawner.sh" "$tmp/grandchild.pid" >/dev/null 2>&1
sleep 1
grandchild="$(cat "$tmp/grandchild.pid" 2>/dev/null || echo "")"
if [ -z "$grandchild" ]; then
  nope "grandchild is dead" "the spawner never recorded a pid"
elif kill -0 "$grandchild" 2>/dev/null; then
  kill -9 "$grandchild" 2>/dev/null || true
  nope "grandchild is dead" "pid $grandchild survived the watchdog kill"
else
  ok "grandchild is dead"
fi

# --- summary -----------------------------------------------------------------

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
