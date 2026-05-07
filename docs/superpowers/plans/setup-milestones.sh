#!/usr/bin/env bash
# Idempotent: skips milestones that already exist by title match.
set -euo pipefail

REPO="chienchuanw/only-cue"

ensure_milestone() {
  local title="$1"
  local description="$2"
  if gh api "repos/${REPO}/milestones" --jq ".[] | select(.title == \"${title}\") | .number" | grep -q .; then
    echo "exists: ${title}"
  else
    gh api "repos/${REPO}/milestones" -f title="${title}" -f description="${description}" --jq '.title + " (#" + (.number|tostring) + ")"'
  fi
}

ensure_milestone "MVP" "Thin slice — import, mark, save, reopen"
ensure_milestone "Phase 2 — Pro handoff" "LTC, templates, export, custom shortcuts"
ensure_milestone "Phase 3 — Differentiator" "AI cueing | collaboration | console bridge (TBD)"
