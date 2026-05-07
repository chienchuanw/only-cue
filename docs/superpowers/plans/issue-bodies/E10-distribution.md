## Spec source
Build-sequence step 10 — `docs/build-sequence.md` ("Distribution")
Decisions — `docs/decisions.md` (ADR-007)
Verification — `docs/verification.md` (Distribution sanity check)

## Blocked by
Chore C3 (release pipeline must exist first).

## Done when
A signed, notarized DMG built via the C3 pipeline installs cleanly on a Mac that has never seen the app, with no Gatekeeper warning, and the app launches and runs the manual end-to-end script in `docs/verification.md`.

## Leaves
- [ ] Leaf: Tag `v0.1.0` on the merge commit that completes E9
- [ ] Leaf: Run `bash scripts/build-release.sh` against the tag → notarized `OnlyCue.app`
- [ ] Leaf: `codesign --verify --deep --strict --verbose=2 OnlyCue.app` clean
- [ ] Leaf: `spctl --assess --type execute OnlyCue.app` accepts
- [ ] Leaf: Run `bash scripts/make-dmg.sh` → `OnlyCue-0.1.0.dmg`
- [ ] Leaf: Manual install on a clean Mac account (or VM); run full `docs/verification.md` script
- [ ] Leaf: Create GitHub Release with the DMG attached

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: First-launch on a clean Mac
  Given OnlyCue-0.1.0.dmg downloaded on a Mac that has never seen the app
  When the user mounts the DMG and drags OnlyCue.app to /Applications
  And launches OnlyCue from /Applications
  Then no Gatekeeper warning appears
  And the app reaches the empty-document window within 3 seconds

Scenario: End-to-end manual script passes
  Given OnlyCue is installed per the previous scenario
  Then every step of docs/verification.md ("Manual end-to-end script") passes
```

## Out of scope
- Sparkle auto-update
- Mac App Store
- Crash reporting
