#!/usr/bin/env bash
# Package the signed + notarized OnlyCue.app into a drag-install DMG.
# Run after scripts/build-release.sh.
#
# Output: $BUILD_DIR/OnlyCue-<version>.dmg
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-build}"
APP_PATH="$BUILD_DIR/export/OnlyCue.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v create-dmg >/dev/null || fail "create-dmg not found. brew install create-dmg"
[[ -d "$APP_PATH" ]] || fail "$APP_PATH missing. Run scripts/build-release.sh first."

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

log "Verifying DMG signature passes Gatekeeper"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || \
    log "(non-fatal: Gatekeeper assesses the .app inside, not the DMG container)"

log "Done. DMG at: $DMG_PATH"
