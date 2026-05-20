# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues in `chienchuanw/only-cue`. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Project conventions

OnlyCue issues follow the repo's own workflow (see the root `CLAUDE.md`):

- Issue branches are `issues/<N>`, created via the `gh-dev` skill, based off `dev`.
- Issues cite the `docs/` section they implement (spec-driven development).
- The repo's existing label taxonomy (`type:*`, `area:*`, `epic`/`leaf`/`chore`, `p0`/`p1`/`p2`) is orthogonal to the triage labels in `triage-labels.md` — apply both as relevant.
