#!/bin/bash
# Run the local test suite without fighting the CI runner for the machine.
#
#     scripts/dev/test.sh                                  # OnlyCueTests
#     scripts/dev/test.sh -only-testing:OnlyCueTests/OSCParserTests
#     scripts/dev/test.sh --no-wait                        # fail fast if busy
#
# Three things that are easy to forget and expensive to forget, in one place:
#
#   1. The self-hosted runner shares this Mac mini, and XCUITest does not
#      survive CPU contention. Racing it corrupts both sides — the local suite
#      fails on random unrelated tests, and the CI UI-test step fails with
#      "Lost connection to the application" (#816). So: wait for it.
#   2. `testmanagerd` left over from an interrupted run makes the next
#      `xcodebuild test` time out initiating its control session (#471, #595).
#   3. Without ad-hoc signing the locally built runner is flagged "damaged" and
#      the run hangs.
#
# Anything after the flags is passed straight to `xcodebuild`.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
wait_budget=1800

args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-wait) wait_budget=0; shift ;;
    --wait) wait_budget="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done

# Unit tests unless the caller scoped the run themselves. Running the UI suite
# locally is the rarer, deliberate act, and it is the expensive one.
case "${args[*]:-}" in
  *-only-testing:*) ;;
  *) args+=("-only-testing:OnlyCueTests") ;;
esac

if ! "$repo_root/scripts/ci/machine-busy.sh" \
      --self "$repo_root" --include-runner --wait "$wait_budget"; then
  echo "scripts/dev/test.sh: refusing to start — see above (#816)." >&2
  echo "  Results from a contended run are not evidence about the code." >&2
  exit 1
fi

killall -9 testmanagerd 2>/dev/null || true

exec xcodebuild test \
  -project "$repo_root/OnlyCue.xcodeproj" \
  -scheme OnlyCue \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  "${args[@]}"
