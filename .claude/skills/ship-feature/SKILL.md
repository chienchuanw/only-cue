---
name: ship-feature
description: End-to-end feature delivery for OnlyCue. Use when the user wants to take a feature from idea to merged code with one command. Brainstorms the design, writes a spec and plan, files GitHub issue(s), implements via strict TDD, fixes CI, opens a PR, self-reviews as a senior Swift dev, and merges to dev. Requires an explicit feature target and scope confirmation before any branch or PR is created.
---

# ship-feature

End-to-end feature delivery for OnlyCue. This skill orchestrates the full lifecycle; it does not replace the underlying skills, it sequences them.

## Preconditions

- A concrete feature target must be supplied. If none is given, STOP and ask the user what to ship. Never invent scope.
- Confirm the branch name and PR boundary with the user (one line) before running `git checkout -b` or `gh pr create`. Silent creation is forbidden (see project CLAUDE.md).
- Work happens on an `issues/<N>` branch based off `dev`. Never commit feature code to `dev` or `main` directly.

## Workflow

1. **Brainstorm / design** — invoke `superpowers:brainstorming` to explore intent, requirements, and design before any code.
2. **Spec** — write an approved spec into `docs/superpowers/specs/`. Commit the spec separately, on the issue branch only (never bundle spec files into feature/bug commits).
3. **Plan** — write an implementation plan into `docs/superpowers/plans/` via `superpowers:writing-plans`.
4. **GitHub issue(s)** — file issue(s) with `gh:gh-issue`, each citing the `docs/` section it implements.
5. **Branch** — create the `issues/<N>` branch via `gh:gh-dev` after scope confirmation.
6. **TDD implementation** — `superpowers:test-driven-development`: write the failing test, see it red, implement to green. Commit the failing test separately when practical. No direct `ProjectModel` mutations — go through `Commands/CueCommands.swift`.
7. **CI green** — run the test suite and SwiftLint locally; fix failures at the root cause. Do not skip hooks or weaken checks.
8. **PR** — open via `gh:gh-pr`, using the forked `.github/PULL_REQUEST_TEMPLATE/{type}.md` template with the OnlyCue verification block.
9. **Self-review** — review the diff as a senior Swift dev: correctness, concurrency/MainActor safety, schema-version discipline, accessibility, gesture/hit-test regressions. Use `feature-dev:code-reviewer`.
10. **Merge to dev** — after review feedback is resolved and CI is green, merge the PR into `dev`. Post a summary comment on the PR. Never force-push `dev`/`main`.

## Hard rules (inherited from project CLAUDE.md)

- No App Sandbox entitlements (ADR-007); no embedded media in `.cuelist` (ADR-006).
- Bump `schemaVersion` + add a migration for any `ProjectModel` schema change.
- Deployment target stays ≥ macOS 14.0 (ADR-001).
- Conventional Commits, no `Co-Authored-By` trailers.
