#!/usr/bin/env bash
# Package OnlyCue.app into a drag-install DMG.
# Run after scripts/build-release.sh.
#
# Two modes (RELEASE_MODE env var, matched to build-release.sh):
#   unsigned   Plain DMG, no signing or notarization. Default.
#              First-launch from the DMG hits Gatekeeper; users right-click → Open
#              or `xattr -dr com.apple.quarantine /Applications/OnlyCue.app`.
#   signed     DMG is codesigned, notarized, and stapled. Requires the same
#              Developer ID identity + notarytool keychain profile used by
#              build-release.sh.
#
# Env overrides:
#   RELEASE_MODE     unsigned | signed                    (default: unsigned)
#   NOTARY_PROFILE   keychain profile for notarytool      (signed only; default: OnlyCueNotary)
#   DEVELOPER_ID     Developer ID Application identity    (signed only; default: auto-detected)
#   BUILD_DIR        scratch dir                          (default: build)
#
# Output: $BUILD_DIR/OnlyCue-<version>.dmg
set -euo pipefail

RELEASE_MODE="${RELEASE_MODE:-unsigned}"
BUILD_DIR="${BUILD_DIR:-build}"
APP_PATH="$BUILD_DIR/export/OnlyCue.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v create-dmg >/dev/null || fail "create-dmg not found. brew install create-dmg"
[[ -d "$APP_PATH" ]] || fail "$APP_PATH missing. Run scripts/build-release.sh first."

case "$RELEASE_MODE" in
    unsigned) ;;
    signed)
        NOTARY_PROFILE="${NOTARY_PROFILE:-OnlyCueNotary}"
        if [[ -z "${DEVELOPER_ID:-}" ]]; then
            DEVELOPER_ID="$(security find-identity -v -p codesigning login.keychain 2>/dev/null \
                | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
            [[ -n "$DEVELOPER_ID" ]] || fail "No 'Developer ID Application' identity in login.keychain."
        fi
        ;;
    *)
        fail "Unknown RELEASE_MODE='$RELEASE_MODE'. Expected 'unsigned' or 'signed'."
        ;;
esac

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="$BUILD_DIR/OnlyCue-${VERSION}.dmg"

log "Building DMG for OnlyCue $VERSION"
rm -f "$DMG_PATH"

create-dmg \
    --volname "OnlyCue $VERSION" \
    --window-size 540 380 \
    --icon-size 96 \
    --icon "OnlyCue.app" 140 200 \
    --app-drop-link 400 200 \
    --hide-extension "OnlyCue.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

if [[ "$RELEASE_MODE" == "signed" ]]; then
    log "Signing DMG"
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

    log "Submitting DMG to Apple notary service"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    log "Stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH"

    log "Verifying DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

    log "Done. Signed + notarized DMG at: $DMG_PATH"
else
    log "Done. Unsigned DMG at: $DMG_PATH"
    log "Note: end users hit Gatekeeper on first launch. README install instructions describe the right-click → Open / xattr workaround."
fi
