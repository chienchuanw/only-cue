# Releasing OnlyCue

How to cut a drag-installable DMG of OnlyCue. Owned by C3 (#13); E10 (#12) consumes the DMG produced here.

This is a **local** workflow on a Mac with Xcode. CI release builds are an explicit follow-up after C3 lands (see issue #13 "Out of scope").

The repo supports two distribution modes:

| Mode | Membership | First-launch UX | When to use |
|---|---|---|---|
| **Unsigned** (default) | Free Apple ID | Gatekeeper blocks; user right-clicks → Open once, or runs `xattr` | Every release while we're on the free tier |
| **Signed + notarized** | Paid Apple Developer Program ($99/yr) | Silent, no Gatekeeper prompt | Once we upgrade |

Both produce a perfectly legal DMG. The difference is only what end users see on first launch.

## Free-tier release (unsigned, default)

### One-time setup

```bash
brew install xcodegen create-dmg xcbeautify
```

That's it. No Apple Developer Program enrollment, no certificates, no notarization credentials.

### Cutting a release

1. Bump `CFBundleShortVersionString` in `OnlyCue/Resources/Info.plist`. Bump `CFBundleVersion` to a strictly increasing integer.

2. Make sure `dev` is green and you're on a clean working tree.

3. Build the .app (ad-hoc signed):

   ```bash
   bash scripts/build-release.sh
   ```

   Default `RELEASE_MODE=unsigned`. Output: `build/export/OnlyCue.app`.

   The .app carries an ad-hoc signature (`codesign -s -`), which lets it run after the user clears the quarantine flag once. Without *any* signature it would refuse to launch with the misleading "is damaged" error.

4. Package the DMG:

   ```bash
   bash scripts/make-dmg.sh
   ```

   Output: `build/OnlyCue-<version>.dmg`. Plain, unsigned, perfectly valid.

5. Smoke-test on a Mac that has never seen the app:
   - Mount the DMG, drag `OnlyCue.app` into `/Applications`.
   - Eject the DMG.
   - **First launch:** double-clicking will show "OnlyCue cannot be opened because the developer cannot be verified." That's expected for an unsigned build.
   - **Right-click → Open** on `/Applications/OnlyCue.app`, then click "Open" in the dialog. The app launches and the system remembers the override for future launches.
   - Alternatively, one-shot bypass via Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/OnlyCue.app
     ```

### What to tell end users

Add an `## Install` section to the GitHub release notes (and to the README's install section once E10 lands):

> 1. Download `OnlyCue-x.y.z.dmg`.
> 2. Open the DMG and drag **OnlyCue** into your Applications folder.
> 3. **First launch:** right-click on `OnlyCue.app` and choose **Open**. macOS will warn that the developer can't be verified — click **Open** anyway. Future launches are silent.
>
> *Why the right-click step?* OnlyCue is currently distributed without a paid Apple Developer ID signature. The app and DMG are unsigned but otherwise unmodified. If you're uncomfortable with the right-click step, you can build from source ([instructions](../README.md#build)).

## Paid-membership release (signed + notarized)

When we upgrade to the Apple Developer Program ($99/yr), the same scripts produce a Gatekeeper-clean release with `RELEASE_MODE=signed`.

### One-time setup

You need:

- An active **Apple Developer Program** membership.
- Xcode (full IDE, not just command-line tools) — `xcode-select -p` should print a path under `/Applications/Xcode.app`. If not: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- Homebrew tools (same as unsigned): `brew install xcodegen create-dmg xcbeautify`.

#### Developer ID Application certificate

1. In Apple Developer → Certificates → "+" → **Developer ID Application**.
2. Generate a CSR via Keychain Access → Certificate Assistant → "Request a Certificate from a Certificate Authority…" → save to disk.
3. Upload the CSR, download the `.cer`, double-click to import into the **login** keychain.
4. Verify:
   ```bash
   security find-identity -v -p codesigning login.keychain | grep "Developer ID Application"
   ```

The build script auto-picks the first matching identity. Override with `DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"` if you have more than one.

> Note: this step requires the **Account Holder** or **Admin** role on the Apple Developer team. Free-tier accounts cannot create Developer ID certificates — that's why the unsigned path exists.

#### Notarization keychain profile

`notarytool` reads credentials from the login keychain. Create a profile **once**:

```bash
xcrun notarytool store-credentials "OnlyCueNotary" \
    --apple-id "<your-apple-id-email>" \
    --team-id "<TEAMID>" \
    --password "<app-specific-password>"
```

`<app-specific-password>` is a 19-character password generated at <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords. Not your Apple ID password.

The build script reads `NOTARY_PROFILE` (default `OnlyCueNotary`) from this keychain entry — no secrets ever live in the repo.

### Cutting a signed release

```bash
RELEASE_MODE=signed bash scripts/build-release.sh
RELEASE_MODE=signed bash scripts/make-dmg.sh
```

Both the .app and the DMG are codesigned, notarized (separate submissions), and stapled. Output: `build/OnlyCue-<version>.dmg`. First launch is silent on a fresh Mac.

## Publishing the release

Tagging and `gh release create` belong to E10 (#12), which consumes the DMG produced by either workflow above. Keeping the boundary clean lets C3 land independently of distribution decisions.

## Troubleshooting

- **"OnlyCue is damaged and can't be opened"** (unsigned mode) — the app is missing even an ad-hoc signature. Re-run `bash scripts/build-release.sh`; the script's final step verifies the ad-hoc signature with `codesign --verify`. If that passes and users still see "damaged", their browser stripped the signature on download (rare); have them download via `curl -LO` instead.
- **`security find-identity` finds nothing** (signed mode) — the cert isn't in `login.keychain`. Open Keychain Access, drag the `.cer` (or `.p12` if exported with the private key) into "login".
- **`notarytool submit` rejects with "invalid credentials"** — re-run `store-credentials` with a fresh app-specific password. Apple invalidates them when revoked.
- **Notary returns `Invalid` status** — fetch the log: `xcrun notarytool log <submission-id> --keychain-profile OnlyCueNotary`. Most common cause is unsigned embedded resources; the export step's `--options=runtime` flag plus `signingStyle=automatic` in `scripts/export-options.plist` should already cover this.
- **`spctl --assess` says "rejected"** after staple (signed mode) — the staple may not have completed. Re-run `xcrun stapler staple build/export/OnlyCue.app` and try again.
- **`create-dmg` complains about volume names** — make sure no DMG with the same volume name is already mounted (`hdiutil info`).

## Why no sandbox

ADR-007 keeps App Sandbox **off** for MVP so security-scoped bookmarks and document-based file access work without sandbox temporary entitlements. We still ship a legal app — Developer ID + notarization (when on a paid plan) is Gatekeeper-clean, and ad-hoc signing is a documented Apple distribution mode for non-Developer-Program developers. If we ever flip the sandbox on, both `MediaImporter.importMedia` and `MediaImporter.reload` need to start/stop accessing security-scoped resources around `AVURLAsset` access.
