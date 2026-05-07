# OnlyCue — project rules for AI agents

A native macOS app for lighting designers to plan cue lists against media. See `docs/` for the full picture; start with `README.md`.

## Pull requests

This project forks the `gh-pr` skill's PR templates. When the `gh-pr` skill runs Step 9c ("Read the template"), it MUST read from `.github/PULL_REQUEST_TEMPLATE/{PR_TYPE}.md` in this repo, NOT from the skill's bundled `<skill-path>/templates/{PR_TYPE}.md`. The forked templates include the OnlyCue verification block which is mandatory on every PR.

The mapping from PR type to template file is the same as the skill's:

- `feat` → `.github/PULL_REQUEST_TEMPLATE/feat.md`
- `bug` → `.github/PULL_REQUEST_TEMPLATE/bug.md`
- `refactor` → `.github/PULL_REQUEST_TEMPLATE/refactor.md`
- `doc` → `.github/PULL_REQUEST_TEMPLATE/doc.md`
- `perf` → `.github/PULL_REQUEST_TEMPLATE/perf.md`
- `security` → `.github/PULL_REQUEST_TEMPLATE/security.md`

If a future PR type is needed and a forked template does not yet exist, stop and add the forked template before creating the PR. Do not fall back to the skill's bundled template silently.

## Commits

Conventional Commits, lowercase after the prefix, imperative tense. Examples:

- `feat(media): add waveform peak generator`
- `fix(commands): undo restores cue id`
- `chore: bump swiftlint config`
- `docs: clarify .cuelist schema versioning`

Do **not** append `Co-Authored-By` trailers, signatures, or other attribution. The `gh-dev` skill's templates already enforce this; keep it that way.

## Development discipline

- **Spec-Driven**: every issue cites the `docs/` section it implements. PRs link the spec section in the OnlyCue verification footer.
- **TDD**: write the failing test first, see it red, then implement to green. Commit the failing test as a separate commit when practical.
- **BDD**: acceptance criteria use Gherkin (Given/When/Then) and are mirrored in `OnlyCueUITests/` where they describe user-visible behavior.
- **No direct mutations of `ProjectModel`**. UI and other layers go through `Commands/CueCommands.swift`. This is the seam for undo, future collaboration, and AI-suggested cues.

## Branching

- Branch name for issue work: `issues/<N>` (enforced by the `gh-dev` skill).
- Base branch: `main`. No `dev`/`develop` branch.
- Do not push to `main` directly except for repo-metadata work that has no review value (rare).

## Where things live

- `docs/` — vision, MVP scope, architecture, data model, build sequence, verification, roadmap, ADRs.
- `docs/superpowers/specs/` — approved specs.
- `docs/superpowers/plans/` — implementation plans + reusable artifacts (issue body markdown, setup scripts).
- `OnlyCue/` — app source (created by issue #1).
- `OnlyCueTests/`, `OnlyCueUITests/` — tests.

## Hard rules

- Do not introduce App Sandbox entitlements (ADR-007).
- Do not embed media in `.cuelist` files; reference via security-scoped bookmarks (ADR-006).
- Do not change `ProjectModel` schema without bumping `schemaVersion` and adding a migration (`docs/data-model.md`).
- Do not lower the macOS deployment target below 14.0 (ADR-001).
