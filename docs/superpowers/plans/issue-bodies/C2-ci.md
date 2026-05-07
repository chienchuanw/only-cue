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
