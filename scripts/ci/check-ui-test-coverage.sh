#!/bin/bash
# Fails when an XCUITest suite is selected by neither UI job in ci.yml (#812).
#
# ci.yml runs the UI layer in two steps whose suite lists are maintained by hand
# and independently of each other:
#
#   "UI tests (behavioral)"    -only-testing:OnlyCueUITests  minus  -skip-testing:<suite>…
#   "UI baseline screenshots"  -only-testing:<suite>…        (workflow_dispatch only)
#
# So the behavioral step runs *everything except* the skip list, and the baseline
# step is supposed to pick the skip list back up. The invariant is therefore
# simply: the two lists are the same set. Nothing enforced it, and six suites had
# fallen into the gap — compiled into the target, selected by no job, so a
# regression in any of them landed on dev fully green. This check is what keeps
# the two lists in step.
#
# Usage:
#
#     scripts/ci/check-ui-test-coverage.sh [--workflow <ci.yml>] [--suite-dir <dir>]
#
# Exits 0 when the lists agree, 1 when they do not (and prints how), 2 on a
# usage or parse error.
#
# Plain bash with no test framework or yaml parser, so this runs on the
# self-hosted runner's system bash (3.2) with no extra tooling. The grep is
# deliberately literal: the flags it looks for are the flags xcodebuild is
# actually handed, so a rename that breaks the parse breaks the build too.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
workflow="$repo_root/.github/workflows/ci.yml"
suite_dir="$repo_root/OnlyCueUITests"

while [ $# -gt 0 ]; do
  case "$1" in
    --workflow) workflow="$2"; shift 2 ;;
    --suite-dir) suite_dir="$2"; shift 2 ;;
    *) echo "check-ui-test-coverage.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

for required in "$workflow" "$suite_dir"; do
  if [ ! -e "$required" ]; then
    echo "check-ui-test-coverage.sh: $required does not exist" >&2
    exit 2
  fi
done

# --- what exists ------------------------------------------------------------
# A suite is a class in a file that declares at least one `func test` — the same
# thing xcodebuild selects. Keying off the test methods rather than a `*Tests`
# name convention means a suite that breaks the convention is still caught, and
# the Support/ helpers (OnlyCueUITestCase and friends, no test methods) drop out
# without a path exclusion that could later go stale.
declared=""
for file in $(find "$suite_dir" -name '*.swift' | sort); do
  grep -q 'func test' "$file" || continue
  classes="$(sed -n 's/^[[:space:]]*\(final \)\{0,1\}\(public \|open \|internal \)\{0,1\}class \([A-Za-z0-9_]*\).*/\3/p' "$file")"
  for class in $classes; do
    declared="$declared$class
"
  done
done
declared="$(printf '%s' "$declared" | sort)"

if [ -z "$declared" ]; then
  echo "check-ui-test-coverage.sh: found no test suites under $suite_dir — the parser is probably broken" >&2
  exit 2
fi

# --- what ci.yml selects ----------------------------------------------------
# A bare `-only-testing:OnlyCueUITests` (the whole target, in the behavioral
# step) is not a suite selection — the trailing `/` in the pattern excludes it.
skipped="$(grep -o -- '-skip-testing:OnlyCueUITests/[A-Za-z0-9_]*' "$workflow" | sed 's|.*/||' | sort)"
baselined="$(grep -o -- '-only-testing:OnlyCueUITests/[A-Za-z0-9_]*' "$workflow" | sed 's|.*/||' | sort)"

status=0

report() { # heading  newline-separated-names  remedy…
  status=1
  echo "$1" >&2
  printf '%s\n' "$2" | sed 's/^/  /' >&2
  shift 2
  for line in "$@"; do echo "  $line" >&2; done
}

# --- 1. the bug this check exists for ---------------------------------------
orphans="$(comm -23 <(printf '%s\n' "$skipped" | sort -u) <(printf '%s\n' "$baselined" | sort -u))"
if [ -n "$orphans" ]; then
  report "Suites selected by NEITHER UI job — a regression in these lands on dev green:" "$orphans" \
    "They are skipped by the behavioral step but absent from the baseline step." \
    "Fix: add each to the baseline step's -only-testing list (screenshot generator)," \
    "     or drop it from the behavioral step's -skip-testing list (behavioral suite)."
fi

# --- 2. the inverse: run twice rather than never -----------------------------
doubled="$(comm -13 <(printf '%s\n' "$skipped" | sort -u) <(printf '%s\n' "$baselined" | sort -u))"
if [ -n "$doubled" ]; then
  report "Suites selected by BOTH UI jobs — the behavioral step does not skip them:" "$doubled" \
    "Fix: add each to the behavioral step's -skip-testing list, or drop it from the baseline step."
fi

# --- 3. a name repeated inside one list -------------------------------------
# Harmless to xcodebuild, but it makes the lists look longer than they are and
# hides a missing entry from a by-eye count.
dupes="$(printf '%s\n' "$skipped" | uniq -d)"
if [ -n "$dupes" ]; then
  report "Duplicate entries in the behavioral step's -skip-testing list:" "$dupes"
fi

dupes="$(printf '%s\n' "$baselined" | uniq -d)"
if [ -n "$dupes" ]; then
  report "Duplicate entries in the baseline step's -only-testing list:" "$dupes"
fi

# --- 4. a name that no longer resolves --------------------------------------
# xcodebuild does not complain about a -skip-testing for a suite that no longer
# exists, so a rename leaves an entry that silently stops doing anything.
unknown="$(comm -13 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$skipped" "$baselined" | grep -v '^$' | sort -u))"
if [ -n "$unknown" ]; then
  report "Suites named in ci.yml that do not exist — stale after a rename or deletion:" "$unknown"
fi

if [ "$status" -eq 0 ]; then
  total="$(printf '%s\n' "$declared" | sort -u | wc -l | tr -d ' ')"
  held="$(printf '%s\n' "$skipped" | sort -u | wc -l | tr -d ' ')"
  echo "check-ui-test-coverage.sh: ok — $total suites, $((total - held)) behavioral, $held baseline."
fi

exit "$status"
