# Releasing OnlyCue

How to cut a notarized, drag-installable build of OnlyCue. Owned by C3 (#13); E10 (#12) consumes the DMG produced here.

This is a **local** workflow on a Mac with Xcode. CI release builds are an explicit follow-up after C3 lands (see issue #13 "Out of scope").

## One-time machine setup

You need:

- Xcode (full IDE, not just command-line tools) — `xcode-select -p` should print a path under `/Applications/Xcode.app`. If not: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- An active **Apple Developer Program** membership.
- Homebrew tools: `brew install xcodegen create-dmg xcbeautify`.

### Developer ID Application certificate

1. In Apple Developer → Certificates → "+" → **Developer ID Application**.
2. Generate a CSR via Keychain Access → Certificate Assistant → "Request a Certificate from a Certificate Authority…" → save to disk.
3. Upload the CSR, download the `.cer`, double-click to import into the **login** keychain.
4. Verify:
   ```bash
   security find-identity -v -p codesigning login.keychain | grep "Developer ID Application"
   ```

The build script will auto-pick the first matching identity. Override with `DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"` if you have more than one.

### Notarization keychain profile

`notarytool` reads credentials from the login keychain. Create a profile **once**:

```bash
xcrun notarytool store-credentials "OnlyCueNotary" \
    --apple-id "<your-apple-id-email>" \
    --team-id "<TEAMID>" \
    --password "<app-specific-password>"
```

`<app-specific-password>` is a 19-character password generated at <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords. Not your Apple ID password.

The build script reads `NOTARY_PROFILE` (default `OnlyCueNotary`) from this keychain entry — no secrets ever live in the repo.

## Cutting a release

1. Bump `CFBundleShortVersionString` in `OnlyCue/Resources/Info.plist`. Bump `CFBundleVersion` to a strictly increasing integer.

2. Make sure `dev` is green and you're on a clean working tree.

3. Build, sign, notarize, and staple:

   ```bash
   bash scripts/build-release.sh
   ```

   Takes a few minutes — the bulk is Apple's notary turnaround. The script fails fast if either prerequisite (cert, notary profile) is missing.

   Output: `build/export/OnlyCue.app`.

4. Package the DMG:

   ```bash
   bash scripts/make-dmg.sh
   ```

   Output: `build/OnlyCue-<version>.dmg`.

5. Smoke-test on a Mac that has never seen the app:
   - Mount the DMG, drag `OnlyCue.app` into `/Applications`.
   - Eject the DMG.
   - Open `/Applications/OnlyCue.app`. **Expected:** launches without a Gatekeeper warning. If a "from the Internet" prompt appears, that's the standard quarantine prompt for first launch — it should *not* be the "cannot be opened because Apple cannot check it for malicious software" wall.

## Publishing the release

Tagging and `gh release create` belong to E10 (#12), which consumes the DMG produced by the workflow above. Keeping the boundary clean lets C3 land independently of distribution decisions.

## Troubleshooting

- **`security find-identity` finds nothing** — the cert isn't in `login.keychain`. Open Keychain Access, drag the `.cer` (or `.p12` if exported with the private key) into "login".
- **`notarytool submit` rejects with "invalid credentials"** — re-run `store-credentials` with a fresh app-specific password. Apple invalidates them when revoked.
- **Notary returns `Invalid` status** — fetch the log: `xcrun notarytool log <submission-id> --keychain-profile OnlyCueNotary`. Most common cause is unsigned embedded resources; the export step's `--options=runtime` flag plus `signingStyle=automatic` in `scripts/export-options.plist` should already cover this.
- **`spctl --assess` says "rejected"** after staple — the staple may not have completed. Re-run `xcrun stapler staple build/export/OnlyCue.app` and try again.
- **`create-dmg` complains about volume names** — make sure no DMG with the same volume name is already mounted (`hdiutil info`).

## Why no sandbox

ADR-007 keeps App Sandbox **off** for MVP so security-scoped bookmarks and document-based file access work without sandbox temporary entitlements. We still ship Developer ID + notarization (Gatekeeper-clean), just not the sandbox. If we ever flip the sandbox on, both `MediaImporter.importMedia` and `MediaImporter.reload` need to start/stop accessing security-scoped resources around `AVURLAsset` access — see the comment in `OnlyCue/Commands/MediaImporter.swift`.
