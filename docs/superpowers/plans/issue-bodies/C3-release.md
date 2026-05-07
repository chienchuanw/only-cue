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
