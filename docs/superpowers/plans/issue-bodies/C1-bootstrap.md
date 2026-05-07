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
