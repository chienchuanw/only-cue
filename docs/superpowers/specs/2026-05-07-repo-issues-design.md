# Spec: Repo Issues & TDD/SDD/BDD Workflow

**Date**: 2026-05-07
**Status**: Approved
**Owner**: chienchuanw
**Related docs**: [`docs/architecture.md`](../../architecture.md), [`docs/build-sequence.md`](../../build-sequence.md), [`docs/decisions.md`](../../decisions.md), [`docs/roadmap.md`](../../roadmap.md)

## Context

OnlyCue planning is complete (vision, MVP scope, architecture, data model, build sequence, verification, roadmap, ADRs). The local repo has one commit on `main` and an unlinked remote at `git@github.com:chienchuanw/only-cue.git`.

Before any code is written we want a shaped issue tracker that:

1. Maps 1:1 to the build sequence so progress is legible at a glance.
2. Wires in **TDD, SDD (Spec-Driven), and BDD** at the issue level — not as a parallel doc, but as the structure of every issue body and PR.
3. Forks the `gh-pr` skill's PR templates into the repo so every PR (skill-produced or otherwise) carries the OnlyCue verification footer.

This spec is the contract for that setup. Implementation creates repo metadata and 13 issues; no source code.

## Goals

- A GitHub repo state where any contributor (human or agent) can pick the next leaf issue, write the failing test, implement, and open a compliant PR with no further onboarding.
- Spec ↔ issue ↔ PR traceability: every issue cites a `docs/` section; every PR cites the issue and the spec section.
- Just-in-time leaves (approach C "backbone first") so the board never holds stale fine-grained scope.

## Non-goals

- Creating leaf issues for epics now. Leaves are expanded only when the parent epic's milestone becomes active.
- Writing any Swift code or scaffolding the Xcode project (that's the work of chore C1 once it's an issue).
- Defining the Phase 3 differentiator. Roadmap leaves it open.

## Locked decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Issue tracker | GitHub Issues at `chienchuanw/only-cue` |
| SDD interpretation | **Spec-Driven** — every issue cites `docs/` section it implements |
| Granularity | Two-tier: 10 Epics (one per build-sequence step) + leaves underneath via task lists |
| BDD format | Gherkin (Given/When/Then) acceptance + plain XCTest unit + XCUITest UI. No Quick/Nimble. |
| Infra issues to create | Bootstrap+lint, CI, Release pipeline. (Repo-hygiene minimums folded into bootstrap.) |
| Rollout | **Approach C**: backbone-first, leaves JIT |
| PR templates | **Fork** the gh-pr skill's templates into `.github/PULL_REQUEST_TEMPLATE/` with the OnlyCue verification footer baked in. CLAUDE.md redirects the skill to read locally. |

## Hierarchy

```
Milestone: MVP
├── Epic E1   Skeleton                  (build-sequence #1)
├── Epic E2   Player core               (#2)
├── Epic E3   Media import              (#3)
├── Epic E4   Video preview             (#4)
├── Epic E5   Waveform                  (#5)
├── Epic E6   Cue list pane             (#6)
├── Epic E7   Add/edit/delete cues      (#7)
├── Epic E8   Cue markers               (#8)
├── Epic E9   Polish                    (#9)
├── Epic E10  Distribution              (#10)
└── Chore C3  Release pipeline (blocks E10)

Milestone: Phase 2 — Pro handoff   (epics added later: LTC, Templates, Export, Shortcuts)
Milestone: Phase 3 — Differentiator (empty)

No milestone (run in parallel):
├── Chore C1  Bootstrap + lint + templates + labels
└── Chore C2  GitHub Actions CI
```

## Issue body templates

### Leaf template

```markdown
## Spec source (SDD)
Implements: `docs/<file>.md#<anchor>`
Related: `<other docs>`

## What
One-paragraph behavior description.

## Acceptance criteria (BDD — Gherkin)
```gherkin
Scenario: <name>
  Given …
  When …
  Then …
```

## Tests to write first (TDD)
- [ ] Unit: `<TestClass>.<test_method>`
- [ ] UI: `<UITestClass>.<test_method>` (covers Scenario X)

## Out of scope
- …

## Definition of Done
- [ ] All tests above written and **failing first** (red), then green
- [ ] Spec section updated if behavior diverged
- [ ] PR linked to this issue and to the parent Epic
- [ ] CI green
```

### Epic template

```markdown
## Spec source
Build-sequence step N — `docs/build-sequence.md#step-N`

## Done when
<the acceptance bullet from build-sequence.md>

## Leaves (expand JIT when milestone becomes active)
- [ ] Leaf: <title>
- [ ] Leaf: <title>

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: …
```

## Out of scope
- …
```

### Chore template

Same as Leaf but Gherkin section is optional; replaced with a Tasks checklist when more appropriate.

## Labels (23)

| Group | Labels | Color |
|---|---|---|
| Kind | `epic`, `leaf`, `chore`, `bug`, `spike` | purple |
| Type | `type:feat`, `type:test`, `type:docs`, `type:ci`, `type:build`, `type:refactor` | blue |
| Area | `area:document`, `area:media`, `area:ui`, `area:commands`, `area:waveform`, `area:dist` | green |
| Priority | `p0-blocker`, `p1`, `p2` | red |
| Status | `blocked`, `needs-spec`, `good-first-issue` | yellow |

Every issue gets exactly one **kind** label and exactly one **type** label. **Area** and **priority** are optional but recommended.

## Files added by chore C1

```
.gitignore
.editorconfig
.swiftlint.yml
CLAUDE.md                                            # see "PR template override" below
.github/
├── ISSUE_TEMPLATE/
│   ├── epic.md
│   ├── leaf.md
│   ├── chore.md
│   ├── bug.md
│   └── config.yml                                   # disable blank issues
└── PULL_REQUEST_TEMPLATE/
    ├── feat.md
    ├── bug.md
    ├── refactor.md
    ├── doc.md
    ├── perf.md
    └── security.md
OnlyCue.xcodeproj                                    # macOS app, SwiftUI lifecycle, target macOS 14
OnlyCue/                                             # folder layout per architecture.md
OnlyCueTests/
OnlyCueUITests/
```

### PR template override (option B)

The `gh-pr` skill reads PR body templates from `<skill-path>/templates/{type}.md`. To make PRs always carry the OnlyCue verification footer, we **fork** those templates into `.github/PULL_REQUEST_TEMPLATE/{type}.md` (GitHub-native multi-template directory, also surfaced via `?template=feat.md` in the web UI).

`CLAUDE.md` adds the override rule:

```markdown
# Pull requests
This project forks the gh-pr skill's PR templates. When the gh-pr skill
runs Step 9c ("Read the template"), it MUST read from
`.github/PULL_REQUEST_TEMPLATE/{PR_TYPE}.md` in this repo, NOT from the
skill's bundled `<skill-path>/templates/{PR_TYPE}.md`. The forked
templates include the OnlyCue verification block which is mandatory.
```

Footer baked into every forked template:

```markdown
---
## OnlyCue verification (required)
**Spec link:** `docs/<file>.md#<anchor>`
**Closes:** #__   (also updates parent Epic task list)

- [ ] New tests added for every behavior (TDD: red→green committed)
- [ ] Gherkin scenarios from the issue mapped to UI tests where applicable
- [ ] Spec updated if behavior diverged from `docs/`
- [ ] CI green
```

## Issues to create at execution time (13)

### MVP epics

| # | Title | Labels |
|---|---|---|
| E1 | `epic: skeleton — Xcode project, .cuelist UTType, ProjectModel round-trip` | `epic` `type:build` `area:document` `p1` |
| E2 | `epic: player core — AVPlayer wrapper, transport bar, time publisher` | `epic` `type:feat` `area:media` `p1` |
| E3 | `epic: media import — file picker, drag-drop, security-scoped bookmarks` | `epic` `type:feat` `area:media` `p1` |
| E4 | `epic: video preview — AVPlayerLayer pane for .mp4/.mov` | `epic` `type:feat` `area:ui` `p1` |
| E5 | `epic: waveform — async peak generator, Canvas renderer, peak cache` | `epic` `type:feat` `area:waveform` `p1` |
| E6 | `epic: cue list pane — read-only table bound to ProjectModel.cues` | `epic` `type:feat` `area:ui` `p1` |
| E7 | `epic: add/edit/delete cues — undoable commands, M shortcut, color picker` | `epic` `type:feat` `area:commands` `p1` |
| E8 | `epic: cue markers — draw on waveform, drag-to-retime, click-to-seek` | `epic` `type:feat` `area:waveform` `p1` |
| E9 | `epic: polish — empty states, missing-media relink, app icon, shortcuts` | `epic` `type:feat` `area:ui` `p2` |
| E10 | `epic: distribution — Developer ID signing, notarization, DMG` | `epic` `type:build` `area:dist` `p1` |

### Chores

| # | Title | Labels | Milestone |
|---|---|---|---|
| C1 | `chore: bootstrap — Xcode project, SwiftLint, issue & PR templates, CLAUDE.md, labels` | `chore` `type:build` `p0-blocker` | (none) |
| C2 | `chore: CI — GitHub Actions, build + XCTest + XCUITest on macos-latest` | `chore` `type:ci` `p1` | (none) |
| C3 | `chore: release pipeline — signing keychain, notarization, DMG script` | `chore` `type:build` `area:dist` `p2` | MVP (blocks E10) |

## Execution sequence

1. **Link remote**: `git remote add origin git@github.com:chienchuanw/only-cue.git && git push -u origin main`
2. **Create labels** (17): one `gh label create --force` per label.
3. **Create milestones** (3): via `gh api repos/.../milestones`.
4. **Create issues** (13) in this order: C1 → C2 → E1..E10 → C3. Each created via `gh issue create --title ... --body-file ... --label ... --milestone ...`.
5. **Cross-link**: edit C3 to mark `Blocks #<E10-number>`.
6. **Verify** (see below).

## Verification

```bash
# Remote linked
git remote -v | grep -q only-cue.git

# Labels in place
[ "$(gh label list --json name | jq length)" -ge 23 ]

# Milestones
[ "$(gh api repos/chienchuanw/only-cue/milestones --jq 'length')" = 3 ]

# Issues
[ "$(gh issue list --state open --json number | jq length)" = 13 ]

# Every Epic has a spec link
for n in $(gh issue list --label epic --json number --jq '.[].number'); do
  gh issue view "$n" --json body --jq '.body' | grep -q 'docs/build-sequence.md' || echo "Epic $n missing spec link"
done
```

A test-PR opened later via `gh-pr` must show the OnlyCue verification block in its body — that confirms the CLAUDE.md override worked.

## Risks & open questions

- **Skill update churn**: forking the gh-pr templates means we don't get upstream improvements automatically. Mitigation: re-diff against the skill's templates quarterly; the OnlyCue footer is the only must-keep delta.
- **CLAUDE.md as the only override mechanism**: relies on the agent reading and respecting it. If the gh-pr skill ever gets a built-in project-override hook, switch to that and delete the CLAUDE.md rule.
- **Issue numbers in cross-references**: epics ship without leaf numbers (leaves don't exist yet); when leaves are added later they auto-get numbers and the epic task list updates manually.

## Out of scope for this spec

- Implementation of any epic or leaf.
- Branching strategy beyond what `gh-dev`/`gh-pr` already enforce.
- Code review checklist beyond the PR template footer.
- Notification/automation rules (GitHub Projects board, auto-assign, etc.).
