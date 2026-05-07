#!/usr/bin/env bash
# Idempotent: re-running updates existing labels in place.
set -euo pipefail

# kind (purple #6f42c1)
gh label create epic        --force --color "6f42c1" --description "Tracks an entire build-sequence step"
gh label create leaf        --force --color "6f42c1" --description "Single behavior under an epic"
gh label create chore       --force --color "6f42c1" --description "Infra / process / tooling work"
gh label create bug         --force --color "6f42c1" --description "Defect to fix"
gh label create spike       --force --color "6f42c1" --description "Time-boxed investigation"

# type (blue #1f6feb)
gh label create "type:feat"     --force --color "1f6feb" --description "User-visible feature"
gh label create "type:test"     --force --color "1f6feb" --description "Test-only change"
gh label create "type:docs"     --force --color "1f6feb" --description "Documentation"
gh label create "type:ci"       --force --color "1f6feb" --description "CI / GitHub Actions"
gh label create "type:build"    --force --color "1f6feb" --description "Build / tooling / packaging"
gh label create "type:refactor" --force --color "1f6feb" --description "No behavior change"

# area (green #2da44e) — mirrors architecture.md folders
gh label create "area:document" --force --color "2da44e" --description "ProjectModel, .cuelist, persistence"
gh label create "area:media"    --force --color "2da44e" --description "AVPlayer, asset loading"
gh label create "area:ui"       --force --color "2da44e" --description "SwiftUI views"
gh label create "area:commands" --force --color "2da44e" --description "Undoable mutations"
gh label create "area:waveform" --force --color "2da44e" --description "Peak generation, waveform rendering"
gh label create "area:dist"     --force --color "2da44e" --description "Signing, notarization, DMG"

# priority (red #d1242f)
gh label create p0-blocker --force --color "d1242f" --description "Blocks all other work"
gh label create p1         --force --color "d1242f" --description "Standard priority (default)"
gh label create p2         --force --color "d1242f" --description "Nice to have"

# status (yellow #d4a72c)
gh label create blocked          --force --color "d4a72c" --description "Waiting on something"
gh label create needs-spec       --force --color "d4a72c" --description "Spec section missing or unclear"
gh label create good-first-issue --force --color "d4a72c" --description "Good entry point"
