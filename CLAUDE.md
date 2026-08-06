# OnlyCue — project rules for AI agents

A native macOS app for lighting designers to plan cue lists against media. See `docs/` for the full picture; start with `README.md`.

## Feature workflow

Follow the standard feature lifecycle: brainstorm/design → spec → plan → GitHub issue(s) → TDD implementation → CI green → PR → review → merge.

## Pull requests

This project forks the `gh-pr` skill's PR templates. When the `gh-pr` skill runs Step 9c ("Read the template"), it MUST read from `.github/PULL_REQUEST_TEMPLATE/{PR_TYPE}.md` in this repo, NOT from the skill's bundled `<skill-path>/templates/{PR_TYPE}.md`. The forked templates include the OnlyCue verification block which is mandatory on every PR.

The mapping from PR type to template file is the same as the skill's:

- `feat` → `.github/PULL_REQUEST_TEMPLATE/feat.md`
- `bug` → `.github/PULL_REQUEST_TEMPLATE/bug.md`
- `refactor` → `.github/PULL_REQUEST_TEMPLATE/refactor.md`
- `doc` → `.github/PULL_REQUEST_TEMPLATE/doc.md`
- `perf` → `.github/PULL_REQUEST_TEMPLATE/perf.md`
- `security` → `.github/PULL_REQUEST_TEMPLATE/security.md`
- `chore` → `.github/PULL_REQUEST_TEMPLATE/chore.md` (OnlyCue addition — not in upstream gh-pr skill; use when the issue carries the `chore` kind label)
- `test` → `.github/PULL_REQUEST_TEMPLATE/test.md` (OnlyCue addition — not in upstream gh-pr skill; use when the issue carries the `type:test` label / the commit is `test(...)`)

If a future PR type is needed and a forked template does not yet exist, stop and add the forked template before creating the PR. Do not fall back to the skill's bundled template silently.

## Commits

Conventional Commits, lowercase after the prefix, imperative tense. Examples:

- `feat(media): add waveform peak generator`
- `fix(commands): undo restores cue id`
- `chore: bump swiftlint config`
- `docs: clarify .cuelist schema versioning`

Do **not** append `Co-Authored-By` trailers, signatures, or other attribution. The `gh-dev` skill's templates already enforce this; keep it that way.

Never bundle spec/design files into feature or bug-fix commits — commit specs separately and only onto the correct issue branch to avoid losing them from `dev`.

## Development discipline

- **Spec-Driven**: every issue cites the `docs/` section it implements. PRs link the spec section in the OnlyCue verification footer.
- **TDD**: write the failing test first, see it red, then implement to green. Commit the failing test as a separate commit when practical.
- **BDD**: acceptance criteria use Gherkin (Given/When/Then) and are mirrored in `OnlyCueUITests/` where they describe user-visible behavior.
- **No direct mutations of `ProjectModel`**. UI and other layers go through the `CueCommands` family (`OnlyCue/Commands/CueCommands.swift` and its `CueCommands+*.swift` extensions — `+Grid`, `+Media`, `+Playback`, `+MA2`, `+Timecode`, etc.). This is the seam for undo, future collaboration, and AI-suggested cues.

## Branching

- Default branch is `dev`. Production-ready code on `main`.
- Branch name for issue work: `issues/<N>` (enforced by the `gh-dev` skill).
- Issue branches base off `dev`. PRs merge into `dev`. Periodically `dev` is fast-forwarded into `main` for releases.
- Do not push to `dev` or `main` directly except for repo-metadata work that has no review value (rare — e.g., post-merge README/status updates after a session).

## Bootstrapping the Xcode project

The project is generated from `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen). The `OnlyCue.xcodeproj/` directory is **not committed** — regenerate it whenever `project.yml`, `Info.plist`, or the source folder structure changes:

```bash
brew install xcodegen      # one-time
xcodegen generate           # creates OnlyCue.xcodeproj
open OnlyCue.xcodeproj
```

If you add a new source folder under `OnlyCue/`, add it as a `sources` path in `project.yml` (or rely on the existing folder rules) and re-run `xcodegen generate`.

## Where things live

- `docs/` — vision, MVP scope, architecture, data model, build sequence, verification, roadmap, ADRs.
- `docs/superpowers/specs/` — approved specs.
- `docs/superpowers/plans/` — implementation plans + reusable artifacts (issue body markdown, setup scripts).
- `OnlyCue/` — app source, organized by subsystem:
  - `App/` — entry point and lifecycle; `Document/` — `ProjectModel`, schema, and migrations (currently at v19); `Commands/` — the `CueCommands` mutation seam.
  - `UI/` — SwiftUI views and the `DS` design-system tokens (`UI/DesignSystem/`); `Media/` — media import and waveform; `Tempo/` — tempo / beat grid.
  - Show-control integrations: `MA2/` (grandMA2), `MIDI/`, `OSC/`, `LTC/` (linear timecode).
  - `Update/` — in-app updates; `Resources/`, `Utilities/` — assets and shared helpers.
- `OnlyCueTests/`, `OnlyCueUITests/` — tests.

## SwiftUI / UI conventions

For SwiftUI gesture work: be cautious with `minimumDistance` and overlapping `.sheet(item:)` / context-menu / drag interactions — verify click-to-seek and accessibility hit-tests still pass before opening a PR.

## Documentation / screenshots

When capturing screenshots for README/docs, always use real screenshots via XCTest/XCUITest UI tests — never use placeholder images.

## Hard rules

- Do not introduce App Sandbox entitlements (ADR-007).
- Do not embed media in `.cuelist` files; reference via security-scoped bookmarks (ADR-006).
- Do not change `ProjectModel` schema without bumping `schemaVersion` and adding a migration (`docs/data-model.md`).
- Do not lower the macOS deployment target below 14.0 (ADR-001).
- The main document window is dark-only (ADR-029) — do not add a light-mode surface. Main-window views consume `DS.*` design tokens (`OnlyCue/UI/DesignSystem/`) rather than raw color / spacing / font literals, enforced by `TokenConformanceTests` (ADR-024/ADR-029).

## Agent skills

### Issue tracker

Issues are tracked as GitHub issues in `chienchuanw/only-cue` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical triage vocabulary — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — an optional `CONTEXT.md` at the repo root (the domain glossary, created lazily when terms actually get resolved; it may not exist yet); ADRs in `docs/decisions.md`. See `docs/agents/domain.md`.
