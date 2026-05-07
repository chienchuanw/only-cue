# Findings

Non-obvious things learned during development. Things you'd want to remember next time you hit the same situation.

---

## xcodegen `info:` directive overwrites custom Info.plist

The `targets.<name>.info: { path: ... }` key in `project.yml` causes xcodegen to **generate** an `Info.plist` at the given path — overwriting any custom contents (including `UTExportedTypeDeclarations`).

**Workaround:** don't use the `info:` key. Instead set in target settings:
```yaml
GENERATE_INFOPLIST_FILE: NO
INFOPLIST_FILE: OnlyCue/Resources/Info.plist
```

Then xcodegen leaves the plist alone.

## Reverse-DNS bundle IDs must use a domain you control

Started with `com.onlycue.OnlyCue`; `onlycue.com` isn't owned. Changed to `com.chienchuanw.OnlyCue` before any persistence layer (UserDefaults, Keychain, document UTType) was wired up. Renaming a bundle ID later requires migration code for every persistence layer that uses it as a namespace.

## SwiftLint `unused_import` belongs under `analyzer_rules`, not `opt_in_rules`

It's an analyzer rule — runs only with `swiftlint analyze`, not regular lint. SwiftLint emits a config warning if it's listed under `opt_in_rules`. Move it to its own `analyzer_rules` block.

## SwiftLint can't load SourceKit on Command Line Tools-only systems

`Loading sourcekitdInProc.framework/Versions/A/sourcekitdInProc failed` when running `swiftlint` from a system that has only Xcode Command Line Tools, not full Xcode. The lint engine still produces results (exit 0 was observed) but analyzer rules silently fail. Inside Xcode the framework is available, so the pre-build script works there. CI must be on a runner with full Xcode.

## gh-pr skill has no `chore` PR type by default

The skill's PR types are `feat / bug / refactor / doc / perf / security`. Repos that use `chore` as a kind label need to add `.github/PULL_REQUEST_TEMPLATE/chore.md` and document the mapping in `CLAUDE.md`. Without that, the gh-pr skill falls back to inferring from commit history or asks the user.

## gh-pr skill template fork requires CLAUDE.md override rule

The skill reads PR templates from a hardcoded path inside its own bundle (`<skill-path>/templates/{type}.md`). To fork the templates into the repo (so the OnlyCue verification footer is enforced), put forked copies under `.github/PULL_REQUEST_TEMPLATE/{type}.md` and add an explicit override rule in `CLAUDE.md` redirecting the skill to read from the repo. Without the rule, the skill silently uses its bundled templates.

## Idempotent gh setup scripts beat one-shot snippets

`gh label create --force` updates existing labels in place. For milestones, the upstream API has no `--force`, so wrap in a script that checks existence by title first. Both flow through `setup-labels.sh` and `setup-milestones.sh` so re-running them is safe and the team can rebuild repo state from text.

## xcodegen `configs:` block lets you split warning-as-error per config

```yaml
configs:
  Debug: debug
  Release: release

settings:
  configs:
    Debug:
      SWIFT_TREAT_WARNINGS_AS_ERRORS: NO
    Release:
      SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
```

Debug stays loose for fast iteration; Release fails fast on drift. The `configs:` keys at the project root tell xcodegen which Xcode build configurations to generate.

## A `Closes #N` line in the PR body auto-closes the issue at merge

Verified on PR #14 → issue #1. No need to manually close the issue. Same syntax works for `Fixes #N` / `Resolves #N`. If the PR uses GitHub's "linked issues" UI, that's separate from this body marker but functions identically.
