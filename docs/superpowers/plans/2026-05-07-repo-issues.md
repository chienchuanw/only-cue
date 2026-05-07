# Repo Issues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up the OnlyCue GitHub repo with linked remote, 17 labels, 3 milestones, and 13 issues (10 MVP epics + 3 chores) per spec `docs/superpowers/specs/2026-05-07-repo-issues-design.md`.

**Architecture:** Pure repo-metadata work via `git` and `gh` CLI. Issue body markdown files are committed to `docs/superpowers/plans/issue-bodies/` so the setup is reproducible. No source code, no Xcode project (chore C1 owns that work — we only create the issue describing it).

**Tech Stack:** `git`, `gh` CLI (already authenticated), bash. macOS shell.

---

## File structure

Files this plan creates and commits to the repo:

```
docs/superpowers/plans/
├── 2026-05-07-repo-issues.md            # this plan
├── setup-labels.sh                       # idempotent script: 17 labels via gh label create
├── setup-milestones.sh                   # idempotent script: 3 milestones via gh api
└── issue-bodies/
    ├── C1-bootstrap.md
    ├── C2-ci.md
    ├── C3-release.md
    ├── E1-skeleton.md
    ├── E2-player-core.md
    ├── E3-media-import.md
    ├── E4-video-preview.md
    ├── E5-waveform.md
    ├── E6-cue-list-pane.md
    ├── E7-add-edit-delete-cues.md
    ├── E8-cue-markers.md
    ├── E9-polish.md
    └── E10-distribution.md
```

Files that exist on GitHub only (not in repo):
- 13 issues (created via `gh issue create --body-file <path>`)
- 17 labels
- 3 milestones
- The `origin` remote pointer

---

## Task 1: Link the GitHub remote

**Files:**
- Modify: local git config (no file in repo)

- [ ] **Step 1: Verify no remote exists yet**

Run: `git remote -v`
Expected output: empty (no `origin`)

- [ ] **Step 2: Add the remote**

Run:
```bash
git remote add origin git@github.com:chienchuanw/only-cue.git
```

- [ ] **Step 3: Push the existing main branch**

Run:
```bash
git push -u origin main
```
Expected: push succeeds, `main` is now tracking `origin/main`.

- [ ] **Step 4: Verify**

Run: `git remote -v && git branch -vv | head -2`
Expected: `origin git@github.com:chienchuanw/only-cue.git (fetch)` and `(push)` lines, plus main showing `[origin/main]`.

- [ ] **Step 5: Verify GitHub repo is reachable**

Run: `gh repo view chienchuanw/only-cue --json name,defaultBranchRef -q '.name + " / " + .defaultBranchRef.name'`
Expected: `only-cue / main`

No commit needed (this task only touches local git config and the remote).

---

## Task 2: Author the label setup script

**Files:**
- Create: `docs/superpowers/plans/setup-labels.sh`

- [ ] **Step 1: Write the script**

Create `docs/superpowers/plans/setup-labels.sh` with exactly this content:

```bash
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x docs/superpowers/plans/setup-labels.sh`

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/setup-labels.sh
git commit -m "chore: add idempotent label setup script (17 labels)"
```

---

## Task 3: Run the label setup script

**Files:** none (executes against GitHub)

- [ ] **Step 1: Run the script**

Run: `bash docs/superpowers/plans/setup-labels.sh`
Expected: 23 lines of output, each like `https://github.com/chienchuanw/only-cue/labels/<name>`. (Total = 5 kind + 6 type + 6 area + 3 priority + 3 status = 23 labels — see Task 2 script.)

> Correction note: spec says 17 — that was the kind/type/area/priority subset. The status group adds 3 optional helpers + spike rounds kind to 5 + type stays 6 = actual total **23**. Both totals are referenced; 23 is the authoritative number from the script.

- [ ] **Step 2: Verify**

Run: `gh label list --limit 100 | wc -l`
Expected: `23` (or higher if GitHub has any default labels we didn't override).

Run: `gh label list --limit 100 --json name -q '.[].name' | sort | grep -E '^(epic|leaf|chore|bug|spike|type:|area:|p0-blocker|p1|p2|blocked|needs-spec|good-first-issue)$' | wc -l`
Expected: `23`

No commit needed.

---

## Task 4: Author the milestone setup script

**Files:**
- Create: `docs/superpowers/plans/setup-milestones.sh`

- [ ] **Step 1: Write the script**

Create `docs/superpowers/plans/setup-milestones.sh` with exactly this content:

```bash
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x docs/superpowers/plans/setup-milestones.sh`

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/setup-milestones.sh
git commit -m "chore: add idempotent milestone setup script (MVP, Phase 2, Phase 3)"
```

---

## Task 5: Run the milestone setup script

**Files:** none

- [ ] **Step 1: Run**

Run: `bash docs/superpowers/plans/setup-milestones.sh`
Expected: three lines naming the milestones (or `exists: ...` lines on re-runs).

- [ ] **Step 2: Verify**

Run: `gh api repos/chienchuanw/only-cue/milestones --jq 'length'`
Expected: `3`

Run: `gh api repos/chienchuanw/only-cue/milestones --jq '.[].title' | sort`
Expected:
```
MVP
Phase 2 — Pro handoff
Phase 3 — Differentiator
```

No commit needed.

---

## Task 6: Author chore C1 body (bootstrap)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/C1-bootstrap.md`

- [ ] **Step 1: Write the body**

Create `docs/superpowers/plans/issue-bodies/C1-bootstrap.md` with exactly this content:

```markdown
## What
Scaffold the project so all subsequent epics can land. No feature code.

## Spec source
`docs/architecture.md`, `docs/decisions.md` (ADR-001, ADR-002, ADR-007), `docs/superpowers/specs/2026-05-07-repo-issues-design.md`

## Tasks
- [ ] Create Xcode project `OnlyCue.xcodeproj` (macOS app, Swift, SwiftUI lifecycle)
- [ ] Set deployment target macOS 14.0
- [ ] Folder layout per `docs/architecture.md#folder-layout` (App/, Document/, Media/, UI/, Commands/, Utilities/, OnlyCueTests/, OnlyCueUITests/)
- [ ] `.gitignore` (Xcode build dirs, DerivedData, .DS_Store, *.xcuserdata, .build/)
- [ ] `.editorconfig` (Swift: 4-space indent, LF, UTF-8, trim trailing ws)
- [ ] SwiftLint config `.swiftlint.yml` + run as Xcode build phase
- [ ] `.github/ISSUE_TEMPLATE/{epic,leaf,chore,bug}.md` matching templates in spec
- [ ] `.github/ISSUE_TEMPLATE/config.yml` (`blank_issues_enabled: false`)
- [ ] `.github/PULL_REQUEST_TEMPLATE/{feat,bug,refactor,doc,perf,security}.md` — fork from gh-pr skill at `~/.claude/plugins/cache/chuan-skills/gh/*/skills/gh-pr/templates/` and append the OnlyCue verification footer to every file
- [ ] `CLAUDE.md` at repo root with the "Pull requests" override rule (verbatim text in spec)
- [ ] Confirm 23 labels exist (`bash docs/superpowers/plans/setup-labels.sh` is idempotent)
- [ ] Confirm 3 milestones exist (`bash docs/superpowers/plans/setup-milestones.sh` is idempotent)

## Done when
- Repo opens cleanly in Xcode 15+
- `xcodebuild -project OnlyCue.xcodeproj -scheme OnlyCue build` succeeds locally
- `gh label list --limit 100` shows all 23 labels
- A test PR opened via `gh-pr` uses the forked template (verify body contains the OnlyCue verification block)

## Out of scope
- Any feature code (E1+)
- CI workflow (C2)
- Release pipeline (C3)
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/C1-bootstrap.md
git commit -m "docs: add C1 bootstrap issue body"
```

---

## Task 7: Author chore C2 body (CI)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/C2-ci.md`

- [ ] **Step 1: Write the body**

Create with exactly this content:

```markdown
## What
GitHub Actions workflow that builds the app and runs unit + UI tests on every PR and on pushes to `main`.

## Spec source
`docs/superpowers/specs/2026-05-07-repo-issues-design.md`, `docs/verification.md`

## Tasks
- [ ] `.github/workflows/ci.yml`:
  - Runs on `pull_request` (any branch) and `push` to `main`
  - Runner: `macos-latest`
  - Caches DerivedData and SwiftPM artifacts
  - Steps: checkout → select Xcode → `xcodebuild build` → `xcodebuild test -scheme OnlyCue -destination 'platform=macOS'`
  - Surfaces test results with `xcpretty` or equivalent
- [ ] Branch protection on `main`: require CI green + 1 review (configured via repo Settings, not committed)

## Done when
- A test PR triggers the workflow
- All checks pass on a no-op PR (after C1 lands the Xcode project)
- A deliberately-failing test causes the workflow to fail

## Out of scope
- Code signing in CI (C3)
- Release builds in CI (C3)
- Notarization in CI (C3)
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/C2-ci.md
git commit -m "docs: add C2 CI issue body"
```

---

## Task 8: Author chore C3 body (release pipeline)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/C3-release.md`

- [ ] **Step 1: Write the body**

Create with exactly this content:

```markdown
## What
Set up signing, notarization, and DMG packaging so MVP can ship.

## Spec source
`docs/decisions.md` (ADR-007), `docs/verification.md` (Distribution sanity check)

## Tasks
- [ ] Developer ID Application certificate imported into login keychain
- [ ] App-specific password for notarization stored in keychain via `xcrun notarytool store-credentials`
- [ ] Build script `scripts/build-release.sh` — archive, export with Developer ID, notarize, staple
- [ ] DMG script `scripts/make-dmg.sh` — uses `create-dmg` (Homebrew); produces `OnlyCue-<version>.dmg`
- [ ] Document the release flow in `docs/release.md` (new file)

## Done when
- `bash scripts/build-release.sh` produces a notarized `OnlyCue.app`
- `codesign --verify --deep --strict --verbose=2 OnlyCue.app` clean
- `spctl --assess --type execute OnlyCue.app` accepts
- `bash scripts/make-dmg.sh` produces a DMG that opens, drag-installs, and launches without Gatekeeper warning on a Mac that has never seen the app

## Blocks
Epic E10 — distribution.

## Out of scope
- Sparkle / auto-update
- App Store distribution (ADR-007)
- CI integration of release builds (a follow-up after C3 lands)
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/C3-release.md
git commit -m "docs: add C3 release pipeline issue body"
```

---

## Task 9: Author epic E1 body (skeleton)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E1-skeleton.md`

- [ ] **Step 1: Write the body**

Create with exactly this content:

```markdown
## Spec source
Build-sequence step 1 — `docs/build-sequence.md` ("Skeleton")
Architecture — `docs/architecture.md#folder-layout`
Data model — `docs/data-model.md`

## Done when
Xcode project compiles. `DocumentGroup` opens an empty document. `.cuelist` UTType registered in `Info.plist`. `ProjectModel` Codable round-trip test passes.

## Leaves (expand JIT when MVP becomes active)
- [ ] Leaf: Define `ProjectModel`, `Cue`, `MediaReference`, `MediaKind` Codable types
- [ ] Leaf: `ProjectModelTests.test_jsonRoundTrip_preservesAllFields`
- [ ] Leaf: Register UTType `com.onlycue.cuelist` (Info.plist + UTExportedTypeDeclarations)
- [ ] Leaf: `CueListDocument` conforming to `ReferenceFileDocument`
- [ ] Leaf: `OnlyCueApp` with `DocumentGroup` opens an empty new doc

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: New document opens
  Given the app is launched fresh
  When the user creates a new document
  Then a window appears titled "Untitled"
  And the cue list is empty
  And the preview pane shows the empty-state message

Scenario: ProjectModel round-trips through JSON
  Given a ProjectModel with media reference and 3 cues
  When the model is encoded to JSON and decoded back
  Then the decoded model equals the original
```

## Out of scope
- Player engine (E2)
- Media import (E3)
- Any UI beyond an empty document window
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E1-skeleton.md
git commit -m "docs: add E1 skeleton epic body"
```

---

## Task 10: Author epic E2 body (player core)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E2-player-core.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 2 — `docs/build-sequence.md` ("Player core")
Architecture — `docs/architecture.md#layer-responsibilities` (Media layer)

## Done when
`PlayerEngine` plays/pauses/seeks a hardcoded asset. `TransportBar` UI hooked up. `currentTime` updates drive a label.

## Leaves
- [ ] Leaf: `PlayerEngine` (`@Observable`, wraps `AVPlayer`, exposes `currentTime`, `rate`, `status`)
- [ ] Leaf: `PlayerEngine.play() / pause() / seek(to:)` with unit tests
- [ ] Leaf: `TransportBar` SwiftUI view (play/pause button, scrubber, time readout)
- [ ] Leaf: `Time+Format.swift` — `HH:MM:SS.mmm` formatter + tests

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Play and pause
  Given a PlayerEngine loaded with a 30-second audio asset
  When play() is called
  Then rate transitions from 0 to 1
  When pause() is called
  Then rate transitions from 1 to 0

Scenario: Seek
  Given a PlayerEngine loaded with a 30-second audio asset
  When seek(to: 12.5) is called
  Then currentTime is within 0.05s of 12.5

Scenario: Time readout updates
  Given the TransportBar is visible and PlayerEngine is playing
  Then the time readout updates at least once per second
  And the format matches HH:MM:SS.mmm
```

## Out of scope
- Loading user-imported media (E3)
- Video preview pane (E4)
- Waveform (E5)
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E2-player-core.md
git commit -m "docs: add E2 player-core epic body"
```

---

## Task 11: Author epic E3 body (media import)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E3-media-import.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 3 — `docs/build-sequence.md` ("Media import")
Data model — `docs/data-model.md` (`MediaReference`, bookmark behavior)

## Done when
`⌘O` and drag-drop accept supported audio + video. Bookmark created and stored in `MediaReference`. Player loads the imported asset.

## Leaves
- [ ] Leaf: `Bookmarks.swift` — create/resolve security-scoped bookmarks, `staleness` handling
- [ ] Leaf: `BookmarksTests` — round-trip create → encode → decode → resolve on a temp file
- [ ] Leaf: File importer (`fileImporter` modifier) accepting `.audio` + `.movie` content types
- [ ] Leaf: Drag-drop onto `DocumentView` accepts the same types
- [ ] Leaf: Reject unsupported file types with an inline alert
- [ ] Leaf: On import success, populate `ProjectModel.media` and call `PlayerEngine.load(asset:)`

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Import audio via file picker
  Given a new document is open
  When the user picks sample.mp3 via ⌘O
  Then ProjectModel.media is populated
  And the player loads the asset within 250ms
  And subsequent save round-trips include the bookmark

Scenario: Import video via drag-drop
  Given a new document is open
  When the user drops clip.mp4 onto the window
  Then ProjectModel.media.kind == .video
  And the preview pane is video (per E4)

Scenario: Reject unsupported file
  Given a new document is open
  When the user drops doc.pdf onto the window
  Then an alert appears explaining only audio/video are supported
  And ProjectModel.media remains nil
```

## Out of scope
- Re-link UX for missing media (E9)
- Multi-media-per-document (out of MVP per data-model.md)
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E3-media-import.md
git commit -m "docs: add E3 media-import epic body"
```

---

## Task 12: Author epic E4 body (video preview)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E4-video-preview.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 4 — `docs/build-sequence.md` ("Video preview pane")
Architecture — `docs/architecture.md` (PreviewPane, PlayerEngine binding)

## Done when
`AVPlayerLayer` wrapped via `NSViewRepresentable`. `.mp4` and `.mov` show picture; transport drives video.

## Leaves
- [ ] Leaf: `AVPlayerLayerView: NSViewRepresentable` wrapping `AVPlayerLayer`
- [ ] Leaf: `PreviewPane` switches between video view and (placeholder for now) audio view based on `MediaReference.kind`
- [ ] Leaf: Aspect-fit sizing; preserves aspect ratio across window resizes
- [ ] Leaf: Visual smoke test — load `clip.mp4`, press play, confirm picture renders

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Video imports show picture
  Given a document with clip.mp4 imported
  Then the PreviewPane shows the first video frame
  When play() is called via TransportBar
  Then the video plays in sync with audio

Scenario: Audio imports show audio placeholder
  Given a document with sample.mp3 imported
  Then the PreviewPane shows an audio placeholder (waveform comes in E5)
```

## Out of scope
- Waveform rendering for audio (E5)
- Cue marker overlay (E8)
- Full-screen video
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E4-video-preview.md
git commit -m "docs: add E4 video-preview epic body"
```

---

## Task 13: Author epic E5 body (waveform)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E5-waveform.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 5 — `docs/build-sequence.md` ("Waveform")
Architecture — `docs/architecture.md` (Media/, WaveformGenerator, WaveformCache)

## Done when
`WaveformGenerator` produces peak arrays asynchronously. `WaveformView` renders peaks via `Canvas`. Peak cache hits on second open of the same asset.

## Leaves
- [ ] Leaf: `WaveformGenerator` — `AVAssetReader` → `[Float]` peaks, async, cancellable
- [ ] Leaf: `WaveformGeneratorTests` — peak count == requested resolution, deterministic
- [ ] Leaf: `WaveformCache` — on-disk cache keyed by `(assetSHA, resolution)`
- [ ] Leaf: `WaveformView` — `Canvas` renderer, mono, no zoom for v1
- [ ] Leaf: Wire `WaveformView` into `PreviewPane` for `.audio` assets
- [ ] Leaf: Performance — 5-min audio renders in < 1s on cache miss; instant on hit

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Waveform appears for imported audio
  Given the user has just imported sample.mp3
  Then a waveform is rendered in the preview pane within 1 second
  And the waveform width spans the full preview area

Scenario: Peak cache hits on reopen
  Given a document was previously saved with sample.mp3
  When the document is reopened
  Then the waveform appears within 250ms (no regeneration)
```

## Out of scope
- Cue markers on waveform (E8)
- Zoom / horizontal scroll
- Stereo / multi-channel display
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E5-waveform.md
git commit -m "docs: add E5 waveform epic body"
```

---

## Task 14: Author epic E6 body (cue list pane)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E6-cue-list-pane.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 6 — `docs/build-sequence.md` ("Cue list pane")
Data model — `docs/data-model.md` (Cue)

## Done when
Right-side pane shows cues from `ProjectModel.cues`. Empty state when none. Read-only at this stage.

## Leaves
- [ ] Leaf: `CueListPane` view in a `NavigationSplitView` inspector slot
- [ ] Leaf: `CueRowView` — `#`, name, time (formatted), color swatch
- [ ] Leaf: Empty-state view ("No cues yet — press M to add one at the playhead")
- [ ] Leaf: Click-to-seek wiring (selecting a row calls `PlayerEngine.seek(to:)`)

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Empty cue list
  Given a document with no cues
  Then the cue list shows the empty state with the M-key hint

Scenario: List renders cues
  Given a document with 3 cues at times 4.25, 12.0, 18.5
  Then the cue list shows 3 rows in that order
  And each row shows the formatted time HH:MM:SS.mmm
  And each row shows its colorHex as a swatch

Scenario: Click row to seek
  Given a document with 3 cues
  When the user clicks the second row
  Then the player seeks to that cue's time within 50ms
```

## Out of scope
- Adding/editing/deleting cues (E7)
- Drag-to-reorder
- Inline edit
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E6-cue-list-pane.md
git commit -m "docs: add E6 cue-list-pane epic body"
```

---

## Task 15: Author epic E7 body (add/edit/delete cues)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E7-add-edit-delete-cues.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 7 — `docs/build-sequence.md` ("Add / edit / delete cues")
Architecture — `docs/architecture.md#layer-responsibilities` (Commands layer rule: UI never mutates ProjectModel directly)

## Done when
`M` key adds at playhead. Inline rename, color picker, time edit, delete. All routed through `CueCommands` with `UndoManager`.

## Leaves
- [ ] Leaf: `CueCommands.addCueAtPlayhead(player:document:)` with undo registration
- [ ] Leaf: `CueCommands.delete(cueId:document:)` with undo
- [ ] Leaf: `CueCommands.rename(cueId:to:document:)` with undo
- [ ] Leaf: `CueCommands.recolor(cueId:to:document:)` with undo
- [ ] Leaf: `CueCommands.retime(cueId:to:document:)` with undo
- [ ] Leaf: `M` keyboard shortcut bound in `AppCommands`
- [ ] Leaf: Inline rename on row double-click
- [ ] Leaf: Color picker popover from row swatch
- [ ] Leaf: Delete via row swipe action and `⌫` key
- [ ] Leaf: `CueCommandsTests` covers each command's add + undo + redo path

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Drop a cue at the playhead
  Given a document with sample.mp3 loaded
  And the playhead is at 00:00:12.500
  When the user presses M
  Then a new cue appears in the cue list at index 0
  And the cue time equals 12.500 seconds
  And the action is undoable

Scenario: Undo restores prior state
  Given the previous scenario completed
  When the user presses ⌘Z
  Then the cue list is empty

Scenario: Rename
  Given a cue at index 0
  When the user double-clicks the name and types "Chorus"
  Then the cue's name is "Chorus"
  And ⌘Z restores the prior name

Scenario: Delete
  Given a cue at index 0
  When the user presses ⌫
  Then the cue is removed
  And ⌘Z restores it with the same id and time
```

## Out of scope
- Cue markers on waveform (E8)
- Drag-to-reorder
- Multi-select operations
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E7-add-edit-delete-cues.md
git commit -m "docs: add E7 add-edit-delete-cues epic body"
```

---

## Task 16: Author epic E8 body (cue markers)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E8-cue-markers.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 8 — `docs/build-sequence.md` ("Cue markers on waveform")
Architecture — `docs/architecture.md` (WaveformView)

## Done when
Markers drawn at correct x-positions over the waveform. Drag retimes the cue. Click seeks the player.

## Leaves
- [ ] Leaf: `WaveformView` overlay layer drawing one marker per cue
- [ ] Leaf: Marker hit-testing for click/drag
- [ ] Leaf: Drag gesture mutates time via `CueCommands.retime` (single undo step per drag)
- [ ] Leaf: Click on marker calls `PlayerEngine.seek(to: cue.time)`
- [ ] Leaf: Marker color reflects `cue.colorHex`
- [ ] Leaf: Snap-to-frame behavior is OFF for v1 (free-form retime)

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Markers render
  Given a document with 3 cues at 4.25, 12.0, 18.5 and a 30s waveform
  Then 3 markers appear at the corresponding x-positions
  And each marker uses its cue's color

Scenario: Drag retimes
  Given a marker at 12.0s
  When the user drags it +50px (= +5s on the current zoom)
  Then the cue's time is approximately 17.0
  And ⌘Z restores 12.0 in a single undo step

Scenario: Click seeks
  Given a marker at 18.5
  When the user clicks the marker
  Then the player seeks to 18.5 within 50ms
```

## Out of scope
- Hover preview / tooltip (E9 polish)
- Keyboard nudge ("←" / "→" to retime)
- Snap to grid
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E8-cue-markers.md
git commit -m "docs: add E8 cue-markers epic body"
```

---

## Task 17: Author epic E9 body (polish)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E9-polish.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 9 — `docs/build-sequence.md` ("Polish")
Data model — `docs/data-model.md` (bookmark stale handling)
Verification — `docs/verification.md`

## Done when
Empty states. Missing-media relink alert. App icon. Default keyboard shortcuts wired. About box. Standard macOS feel.

## Leaves
- [ ] Leaf: Empty document state ("Drop a file or press ⌘O")
- [ ] Leaf: Bookmark-stale alert with "Relink media…" button on document open
- [ ] Leaf: Replace `Untitled` window title with `<filename> — OnlyCue` once saved
- [ ] Leaf: Standard shortcuts wired: ⌘N, ⌘O, ⌘S, ⌘Z, ⌘⇧Z, Space (play/pause), M (add cue), ⌫ (delete cue), ←/→ (jump 1s)
- [ ] Leaf: App icon (1024px → all required sizes via `iconutil`)
- [ ] Leaf: About box with version and credits
- [ ] Leaf: First-launch nudge with link to docs (one-time, dismissible)

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Missing media on reopen
  Given Show.cuelist references sample.mp3
  And sample.mp3 has been moved to a new folder
  When the user opens Show.cuelist
  Then an alert appears with "Relink media…"
  And the cue list is still rendered (cues survive missing media)
  When the user clicks "Relink media…" and picks the new path
  Then the bookmark is updated, document is silently re-saved
  And playback works
```

## Out of scope
- Auto-update / Sparkle (post-MVP)
- Settings/preferences UI (post-MVP)
- Theme / accent customization
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E9-polish.md
git commit -m "docs: add E9 polish epic body"
```

---

## Task 18: Author epic E10 body (distribution)

**Files:**
- Create: `docs/superpowers/plans/issue-bodies/E10-distribution.md`

- [ ] **Step 1: Write the body**

```markdown
## Spec source
Build-sequence step 10 — `docs/build-sequence.md` ("Distribution")
Decisions — `docs/decisions.md` (ADR-007)
Verification — `docs/verification.md` (Distribution sanity check)

## Blocked by
Chore C3 (release pipeline must exist first).

## Done when
A signed, notarized DMG built via the C3 pipeline installs cleanly on a Mac that has never seen the app, with no Gatekeeper warning, and the app launches and runs the manual end-to-end script in `docs/verification.md`.

## Leaves
- [ ] Leaf: Tag `v0.1.0` on the merge commit that completes E9
- [ ] Leaf: Run `bash scripts/build-release.sh` against the tag → notarized `OnlyCue.app`
- [ ] Leaf: `codesign --verify --deep --strict --verbose=2 OnlyCue.app` clean
- [ ] Leaf: `spctl --assess --type execute OnlyCue.app` accepts
- [ ] Leaf: Run `bash scripts/make-dmg.sh` → `OnlyCue-0.1.0.dmg`
- [ ] Leaf: Manual install on a clean Mac account (or VM); run full `docs/verification.md` script
- [ ] Leaf: Create GitHub Release with the DMG attached

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: First-launch on a clean Mac
  Given OnlyCue-0.1.0.dmg downloaded on a Mac that has never seen the app
  When the user mounts the DMG and drags OnlyCue.app to /Applications
  And launches OnlyCue from /Applications
  Then no Gatekeeper warning appears
  And the app reaches the empty-document window within 3 seconds

Scenario: End-to-end manual script passes
  Given OnlyCue is installed per the previous scenario
  Then every step of docs/verification.md ("Manual end-to-end script") passes
```

## Out of scope
- Sparkle auto-update
- Mac App Store
- Crash reporting
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/issue-bodies/E10-distribution.md
git commit -m "docs: add E10 distribution epic body"
```

---

## Task 19: Create C1 issue (bootstrap)

**Files:** none (creates issue on GitHub)

- [ ] **Step 1: Create the issue**

Run:
```bash
gh issue create \
  --title "chore: bootstrap — Xcode project, SwiftLint, issue & PR templates, CLAUDE.md, labels" \
  --body-file docs/superpowers/plans/issue-bodies/C1-bootstrap.md \
  --label "chore,type:build,p0-blocker"
```
Expected: prints a URL like `https://github.com/chienchuanw/only-cue/issues/1`. **Note the issue number** (will be 1 if first issue).

- [ ] **Step 2: Verify**

Run: `gh issue view 1 --json title,labels,body --jq '.title + " | labels=" + (.labels | map(.name) | join(","))'`
Expected: title matches, labels include `chore`, `type:build`, `p0-blocker`.

No commit needed.

---

## Task 20: Create C2 issue (CI)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "chore: CI — GitHub Actions, build + XCTest + XCUITest on macos-latest" \
  --body-file docs/superpowers/plans/issue-bodies/C2-ci.md \
  --label "chore,type:ci,p1"
```

- [ ] **Step 2: Verify**

Run: `gh issue list --label "chore" --json number,title`
Expected: shows C1 and C2 with `chore` label.

---

## Task 21: Create epic E1 (skeleton)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: skeleton — Xcode project, .cuelist UTType, ProjectModel round-trip" \
  --body-file docs/superpowers/plans/issue-bodies/E1-skeleton.md \
  --label "epic,type:build,area:document,p1" \
  --milestone "MVP"
```

- [ ] **Step 2: Verify**

Run: `gh issue view <issue-number> --json milestone --jq '.milestone.title'`
Expected: `MVP`.

---

## Task 22: Create epic E2 (player core)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: player core — AVPlayer wrapper, transport bar, time publisher" \
  --body-file docs/superpowers/plans/issue-bodies/E2-player-core.md \
  --label "epic,type:feat,area:media,p1" \
  --milestone "MVP"
```

---

## Task 23: Create epic E3 (media import)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: media import — file picker, drag-drop, security-scoped bookmarks" \
  --body-file docs/superpowers/plans/issue-bodies/E3-media-import.md \
  --label "epic,type:feat,area:media,p1" \
  --milestone "MVP"
```

---

## Task 24: Create epic E4 (video preview)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: video preview — AVPlayerLayer pane for .mp4/.mov" \
  --body-file docs/superpowers/plans/issue-bodies/E4-video-preview.md \
  --label "epic,type:feat,area:ui,p1" \
  --milestone "MVP"
```

---

## Task 25: Create epic E5 (waveform)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: waveform — async peak generator, Canvas renderer, peak cache" \
  --body-file docs/superpowers/plans/issue-bodies/E5-waveform.md \
  --label "epic,type:feat,area:waveform,p1" \
  --milestone "MVP"
```

---

## Task 26: Create epic E6 (cue list pane)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: cue list pane — read-only table bound to ProjectModel.cues" \
  --body-file docs/superpowers/plans/issue-bodies/E6-cue-list-pane.md \
  --label "epic,type:feat,area:ui,p1" \
  --milestone "MVP"
```

---

## Task 27: Create epic E7 (add/edit/delete cues)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: add/edit/delete cues — undoable commands, M shortcut, color picker" \
  --body-file docs/superpowers/plans/issue-bodies/E7-add-edit-delete-cues.md \
  --label "epic,type:feat,area:commands,p1" \
  --milestone "MVP"
```

---

## Task 28: Create epic E8 (cue markers)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: cue markers — draw on waveform, drag-to-retime, click-to-seek" \
  --body-file docs/superpowers/plans/issue-bodies/E8-cue-markers.md \
  --label "epic,type:feat,area:waveform,p1" \
  --milestone "MVP"
```

---

## Task 29: Create epic E9 (polish)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: polish — empty states, missing-media relink, app icon, shortcuts" \
  --body-file docs/superpowers/plans/issue-bodies/E9-polish.md \
  --label "epic,type:feat,area:ui,p2" \
  --milestone "MVP"
```

---

## Task 30: Create epic E10 (distribution)

- [ ] **Step 1: Create**

```bash
gh issue create \
  --title "epic: distribution — Developer ID signing, notarization, DMG" \
  --body-file docs/superpowers/plans/issue-bodies/E10-distribution.md \
  --label "epic,type:build,area:dist,p1" \
  --milestone "MVP"
```

- [ ] **Step 2: Note the issue number** for use in Task 31.

Run: `gh issue list --label "epic" --json number,title --jq '.[] | select(.title | contains("distribution")) | .number'`
Save as `E10_NUMBER`.

---

## Task 31: Create chore C3 (release pipeline) and link to E10

- [ ] **Step 1: Append a `Blocks #<E10>` line to the C3 body file**

First read `E10_NUMBER` from Task 30 step 2.

Append to `docs/superpowers/plans/issue-bodies/C3-release.md`:

```markdown

---
**Blocks:** #<E10_NUMBER>
```

(replace `<E10_NUMBER>` with the actual integer).

- [ ] **Step 2: Commit the body update**

```bash
git add docs/superpowers/plans/issue-bodies/C3-release.md
git commit -m "docs: link C3 to E10"
```

- [ ] **Step 3: Create the issue**

```bash
gh issue create \
  --title "chore: release pipeline — signing keychain, notarization, DMG script" \
  --body-file docs/superpowers/plans/issue-bodies/C3-release.md \
  --label "chore,type:build,area:dist,p2" \
  --milestone "MVP"
```

- [ ] **Step 4: Push the body-update commit**

```bash
git push
```

---

## Task 32: Final verification

**Files:** none

- [ ] **Step 1: Issue count**

Run: `gh issue list --state open --json number | jq length`
Expected: `13`

- [ ] **Step 2: Epic count in MVP**

Run: `gh issue list --label "epic" --milestone "MVP" --json number | jq length`
Expected: `10`

- [ ] **Step 3: Chore count**

Run: `gh issue list --label "chore" --json number | jq length`
Expected: `3`

- [ ] **Step 4: Every epic cites build-sequence**

Run:
```bash
for n in $(gh issue list --label epic --json number --jq '.[].number'); do
  body=$(gh issue view "$n" --json body --jq '.body')
  if ! echo "$body" | grep -q 'docs/build-sequence.md'; then
    echo "FAIL: epic #$n missing build-sequence reference"
  fi
done
echo "epic spec-link check complete"
```
Expected: only the final `epic spec-link check complete` line printed (no `FAIL`).

- [ ] **Step 5: Milestones**

Run: `gh api repos/chienchuanw/only-cue/milestones --jq '.[] | .title + " — " + (.open_issues|tostring) + " open"'`
Expected:
```
MVP — 11 open
Phase 2 — Pro handoff — 0 open
Phase 3 — Differentiator — 0 open
```
(11 in MVP = 10 epics + C3.)

- [ ] **Step 6: Labels**

Run: `gh label list --limit 100 --json name -q '.[].name' | wc -l`
Expected: `23` or higher.

- [ ] **Step 7: Push final state**

Run: `git status && git push`
Expected: working tree clean, push reports up-to-date.

- [ ] **Step 8: Report**

Print the issue board URL: `https://github.com/chienchuanw/only-cue/issues`

---

## Notes for the executing engineer

- **`gh` is already authenticated** as `chienchuanw` via SSH keyring. No re-auth needed.
- **All commits in this plan are docs-only** (issue body markdown + setup scripts). Each task that commits should pass any future pre-commit hooks trivially.
- **If a `gh issue create` fails** (network, rate limit, auth), simply re-run the same command. `gh issue create` is NOT idempotent — re-running creates a duplicate. To recover from a partial failure, delete the duplicate via `gh issue delete <n> --yes` and retry.
- **`gh label create --force`** is idempotent (updates existing labels). `gh api .../milestones` is gated by the script's existence check.
- **Issue numbering is determined by GitHub** in creation order. The plan doesn't hardcode numbers; only Task 31 needs a specific number (E10's), which is captured at the end of Task 30.
- **No source code is created by this plan.** That's the work of issues C1–C3 and E1–E10 once they're picked up.
