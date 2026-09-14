#!/bin/bash
# Tests for check-ui-test-coverage.sh (#812).
#
# A guard that silently stops guarding is worse than no guard, and this one is
# all string parsing — so each case builds a throwaway workflow + suite tree and
# checks the guard reaches the right verdict on it.
#
# Plain bash with no test framework so this runs on the self-hosted runner's
# system bash (3.2) without extra tooling. Usage:
#
#     scripts/ci/check-ui-test-coverage.test.sh
#
# Exits non-zero if any case fails.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
check="$script_dir/check-ui-test-coverage.sh"

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

expect_lacks() { # label haystack needle
  case "$2" in
    *"$3"*) nope "$1" "expected output NOT to contain '$3', got: $2" ;;
    *) ok "$1" ;;
  esac
}

if [ ! -x "$check" ]; then
  echo "check-ui-test-coverage.test.sh: $check is missing or not executable" >&2
  exit 1
fi

# --- fixture builders -------------------------------------------------------

# make_suite <case-dir> <SuiteName>
make_suite() {
  mkdir -p "$1/suites"
  cat >"$1/suites/$2.swift" <<EOF
import XCTest

final class $2: OnlyCueUITestCase {
    func test_something() throws {}
}
EOF
}

# make_workflow <case-dir> <skipped…> -- <baselined…>
make_workflow() {
  dir="$1"; shift
  mkdir -p "$dir"
  {
    echo "      - name: UI tests (behavioral)"
    echo "        run: |"
    echo "          xcodebuild test-without-building \\"
    echo "            -only-testing:OnlyCueUITests \\"
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
      echo "            -skip-testing:OnlyCueUITests/$1 \\"
      shift
    done
    [ "${1:-}" = "--" ] && shift
    echo "            -parallel-testing-enabled NO"
    echo "      - name: UI baseline screenshots"
    echo "        run: |"
    echo "          xcodebuild test-without-building \\"
    for name in "$@"; do
      echo "            -only-testing:OnlyCueUITests/$name \\"
    done
    echo "            -parallel-testing-enabled NO"
  } >"$dir/ci.yml"
}

# run_check <case-dir> -> sets $out and $status
run_check() {
  out="$("$check" --workflow "$1/ci.yml" --suite-dir "$1/suites" 2>&1)"
  status=$?
}

# --- 1. the happy path ------------------------------------------------------
# Every skipped suite is picked up by the baseline step; everything else runs
# behaviorally by falling through `-only-testing:OnlyCueUITests`.

echo "passes when the two lists are the same set"
c="$tmp/agree"
make_suite "$c" AlphaUITests
make_suite "$c" BravoScreenshotTests
make_suite "$c" CharlieScreenshotTests
make_workflow "$c" BravoScreenshotTests CharlieScreenshotTests -- BravoScreenshotTests CharlieScreenshotTests
run_check "$c"
expect_eq "exits 0" "0" "$status"
expect_contains "counts the suites" "$out" "3 suites, 1 behavioral, 2 baseline"

# --- 2. the bug this guard exists for ---------------------------------------
# #812 exactly: skipped behaviorally, absent from the baseline list, so the
# suite executes in no job at all.

echo "fails when a skipped suite is missing from the baseline list"
c="$tmp/orphan"
make_suite "$c" AlphaUITests
make_suite "$c" BravoScreenshotTests
make_suite "$c" OrphanScreenshotTests
make_workflow "$c" BravoScreenshotTests OrphanScreenshotTests -- BravoScreenshotTests
run_check "$c"
expect_eq "exits 1" "1" "$status"
expect_contains "names the orphan" "$out" "OrphanScreenshotTests"
expect_contains "says why it matters" "$out" "NEITHER"
expect_lacks "does not accuse the covered suite" "$out" "BravoScreenshotTests"

# --- 3. the inverse ---------------------------------------------------------
# Listed as a baseline generator but not skipped behaviorally, so it runs twice.
# Cheap to detect and it means the two lists disagree, which is the thing.

echo "fails when a baselined suite is not skipped behaviorally"
c="$tmp/doubled"
make_suite "$c" AlphaUITests
make_suite "$c" DoubledScreenshotTests
make_workflow "$c" -- DoubledScreenshotTests
run_check "$c"
expect_eq "exits 1" "1" "$status"
expect_contains "names it" "$out" "DoubledScreenshotTests"
expect_contains "says it runs in both" "$out" "BOTH"

# --- 4. a stale name --------------------------------------------------------
# xcodebuild accepts a -skip-testing for a suite that no longer exists without
# complaint, so a rename leaves an entry that quietly stops doing anything.

echo "fails when ci.yml names a suite that does not exist"
c="$tmp/stale"
make_suite "$c" AlphaUITests
make_workflow "$c" RenamedAwayScreenshotTests -- RenamedAwayScreenshotTests
run_check "$c"
expect_eq "exits 1" "1" "$status"
expect_contains "names the ghost" "$out" "RenamedAwayScreenshotTests"
expect_contains "says it is stale" "$out" "do not exist"

# --- 5. duplicates ----------------------------------------------------------
# Harmless to xcodebuild, but it pads the list so a by-eye count of "18 skips"
# no longer means 18 suites — which is how the gap went unnoticed.

echo "fails when a name is repeated inside one list"
c="$tmp/dupe"
make_suite "$c" AlphaUITests
make_suite "$c" BravoScreenshotTests
make_workflow "$c" BravoScreenshotTests BravoScreenshotTests -- BravoScreenshotTests
run_check "$c"
expect_eq "exits 1" "1" "$status"
expect_contains "says which list" "$out" "Duplicate entries in the behavioral"

# --- 6. the whole-target selection is not a suite ---------------------------
# The behavioral step's own `-only-testing:OnlyCueUITests` must not be read as
# a baseline entry for a suite named "OnlyCueUITests".

echo "does not mistake -only-testing:OnlyCueUITests for a suite"
c="$tmp/target"
make_suite "$c" AlphaUITests
make_workflow "$c" --
run_check "$c"
expect_eq "exits 0" "0" "$status"
expect_lacks "no phantom suite" "$out" "do not exist"

# --- 7. helpers are not suites ----------------------------------------------
# Support/ carries classes with no test methods. Counting them would produce a
# permanent false failure, and the reflex fix for a guard that cries wolf is to
# delete the guard.

echo "ignores support classes that declare no test methods"
c="$tmp/support"
make_suite "$c" AlphaUITests
mkdir -p "$c/suites/Support"
cat >"$c/suites/Support/OnlyCueUITestCase.swift" <<'EOF'
import XCTest

class OnlyCueUITestCase: XCTestCase {
    func launchApp() -> XCUIApplication { XCUIApplication() }
}
EOF
make_workflow "$c" --
run_check "$c"
expect_eq "exits 0" "0" "$status"
expect_contains "counts only the real suite" "$out" "1 suites"

# --- 8. a broken parse must fail loudly -------------------------------------
# If the class-declaration parse ever stops matching, every suite reads as
# "not declared" — which would make the guard pass vacuously if it treated an
# empty set as agreement.

echo "fails loudly when it finds no suites at all"
c="$tmp/empty"
mkdir -p "$c/suites"
make_workflow "$c" --
run_check "$c"
expect_eq "exits 2" "2" "$status"
expect_contains "blames the parser" "$out" "parser is probably broken"

# --- 9. the real repo -------------------------------------------------------
# The point of all the above is this one line.

echo "agrees with the committed ci.yml"
out="$("$check" 2>&1)"
status=$?
expect_eq "exits 0" "0" "$status"

# --- summary ----------------------------------------------------------------

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
