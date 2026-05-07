# Progress

Append-only session log. Newer entries on top.

---

## 2026-05-07 — CI session (PR #15, issue #2)

**Shipped:** issue #2 (C2 CI). PR #15 merged into `dev`. First PR using the new dev-as-default flow.

**What landed:**
- `.github/workflows/ci.yml` — single `build-test` job on `macos-latest`, ~25 min timeout.
- Pipeline: checkout → `maxim-lobanov/setup-xcode@v1` (latest stable Xcode) → `brew install xcodegen swiftlint xcbeautify` → `swiftlint lint --strict --reporter github-actions-logging` → `xcodegen generate` → `actions/cache@v4` (DerivedData + SPM) → `xcodebuild build` Debug → `xcodebuild test`. Build/test piped through `xcbeautify --renderer github-actions` for proper annotations.
- Triggers: `pull_request` (any branch) and `push` to `main` or `dev`.
- Concurrency: `cancel-in-progress` per ref.
- Code signing disabled (signing is C3's job).

**Coverage of reviewer feedback from PR #14:**
- SwiftLint must fail CI on absent or violating — `--strict` mode + natural `brew install` failure mode covers both.

**Out of scope (deferred):**
- Code signing in CI → C3 (#13).
- Release builds in CI → C3.
- Branch protection (require CI green + 1 review) → repo Settings UI, not committable.

**Verification:** the PR's own check run was the first exercise of the workflow — green on first run.

---

## 2026-05-07 — Bootstrap session (PR #14, issue #1)

**Shipped:** issue #1 (C1 bootstrap). PR #14 merged via rebase into `main`.

**What landed:**
- Repo metadata (linked the GitHub remote, 23 labels, 3 milestones, 13 issues — 10 epics + 3 chores).
- All planning docs under `docs/` (vision, mvp-scope, architecture, data-model, build-sequence, verification, roadmap, decisions).
- Approved spec: `docs/superpowers/specs/2026-05-07-repo-issues-design.md`.
- Implementation plan: `docs/superpowers/plans/2026-05-07-repo-issues.md` + 13 issue body templates committed under `docs/superpowers/plans/issue-bodies/`.
- Setup scripts: `docs/superpowers/plans/setup-labels.sh`, `setup-milestones.sh` (idempotent).
- Project skeleton: `project.yml` (xcodegen 2.45.4), `OnlyCue.xcodeproj` generated and gitignored.
- Folder layout per `docs/architecture.md`: App / Document / Media / UI / Commands / Utilities / Resources.
- Minimal Swift placeholders so the project compiles (real implementations live in E1 onward).
- Configs: `.gitignore`, `.editorconfig`, `.swiftlint.yml` (with `unused_import` correctly under `analyzer_rules`), `Info.plist`.
- GitHub templates: `.github/ISSUE_TEMPLATE/{epic,leaf,chore,bug}.md` + 7 forked PR templates with the OnlyCue verification footer (the original 6 from the gh-pr skill plus a new `chore.md` extending the skill's mapping).
- `CLAUDE.md` with PR template override rule, commit conventions, branching rules, and hard rules.

**Review feedback applied (commit `4bac6bf` after rebase):**
- Bundle ID changed to `com.chienchuanw.OnlyCue` (reverse-DNS must be a domain we control).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` for Release config (Debug stays NO).
- Dropped duplicate `DEVELOPMENT_LANGUAGE: en` from target settings.
- Removed redundant `*.xcodeproj/project.xcworkspace/swiftpm/` from `.gitignore`.
- Rewrote `chore.md` PR footer with chore-shaped items (tooling-verified-locally, no-behavioral-surface, spec/CLAUDE.md updated, CI green).
- Tracked SwiftLint CI enforcement on issue #2; tracked placeholder-test deletion as a leaf on issue #3.

**Branching change:** `dev` is now the default branch on the remote. Issue branches base off `dev`. Production code is on `main`. CLAUDE.md updated to reflect this.

**Tooling installed this session:**
- `xcodegen` (2.45.4) via Homebrew — generates `OnlyCue.xcodeproj` from `project.yml`.
