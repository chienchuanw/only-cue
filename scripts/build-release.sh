#!/usr/bin/env bash
# Build a Release OnlyCue.app.
#
# Two modes (RELEASE_MODE env var):
#   unsigned   ad-hoc signed (CODE_SIGN_IDENTITY=-), no notarization. Default.
#              Free-tier friendly. End users have to right-click → Open or
#              run `xattr -dr com.apple.quarantine` once. See docs/release.md.
#   signed     Developer ID signed + notarized + stapled. Requires a paid
#              Apple Developer Program membership (Developer ID Application
#              certificate in login keychain + notarytool keychain profile).
#
# Env overrides:
#   RELEASE_MODE     unsigned | signed                     (default: unsigned)
#   NOTARY_PROFILE   keychain profile for notarytool       (signed only; default: OnlyCueNotary)
#   DEVELOPER_ID     full "Developer ID Application: ..."  (signed only; default: auto-detected)
#   BUILD_DIR        scratch dir                           (default: build)
#   SCHEME           xcodebuild scheme                     (default: OnlyCue)
#   CONFIGURATION    xcodebuild configuration              (default: Release)
#
# Output: $BUILD_DIR/export/OnlyCue.app
set -euo pipefail

RELEASE_MODE="${RELEASE_MODE:-unsigned}"
BUILD_DIR="${BUILD_DIR:-build}"
SCHEME="${SCHEME:-OnlyCue}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="$BUILD_DIR/OnlyCue.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/OnlyCue.app"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Pre-flight
command -v xcodebuild >/dev/null || fail "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"
command -v xcodegen   >/dev/null || fail "xcodegen not found. brew install xcodegen"
command -v xcrun      >/dev/null || fail "xcrun not found. Install Xcode command line tools."

case "$RELEASE_MODE" in
    unsigned) ;;
    signed)
        NOTARY_PROFILE="${NOTARY_PROFILE:-OnlyCueNotary}"
        if [[ -z "${DEVELOPER_ID:-}" ]]; then
            DEVELOPER_ID="$(security find-identity -v -p codesigning login.keychain 2>/dev/null \
                | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
            [[ -n "$DEVELOPER_ID" ]] || fail "No 'Developer ID Application' identity in login.keychain. Import the certificate first (see docs/release.md)."
        fi
        log "Signing identity: $DEVELOPER_ID"

        if ! security find-generic-password -s "com.apple.gke.notary.tool" -a "$NOTARY_PROFILE" >/dev/null 2>&1; then
            fail "notarytool keychain profile '$NOTARY_PROFILE' missing. Run: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <TEAMID> --password <app-pw>"
        fi
        log "Notarization profile present: $NOTARY_PROFILE"
        ;;
    *)
        fail "Unknown RELEASE_MODE='$RELEASE_MODE'. Expected 'unsigned' or 'signed'."
        ;;
esac

# Clean slate
rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

log "Regenerating Xcode project from project.yml"
xcodegen generate

if [[ "$RELEASE_MODE" == "signed" ]]; then
    log "Archiving for Developer ID ($CONFIGURATION)"
    xcodebuild archive \
        -project OnlyCue.xcodeproj \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_STYLE=Manual \
        "CODE_SIGN_IDENTITY=$DEVELOPER_ID" \
        OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
        | xcbeautify --renderer terminal --quieter
    [[ "${PIPESTATUS[0]}" -eq 0 ]] || fail "xcodebuild archive failed"
    [[ -d "$ARCHIVE_PATH" ]] || fail "Archive not produced at $ARCHIVE_PATH"

    log "Exporting Developer ID build"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$(dirname "$0")/export-options.plist"
    [[ -d "$APP_PATH" ]] || fail "Export did not produce $APP_PATH"

    ZIP_PATH="$BUILD_DIR/OnlyCue.zip"
    log "Zipping for notarization submission"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    log "Submitting to Apple notary service (this can take a few minutes)"
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    log "Stapling notarization ticket"
    xcrun stapler staple "$APP_PATH"

    log "Verifying signature"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"

    log "Verifying Gatekeeper acceptance"
    spctl --assess --type execute --verbose=2 "$APP_PATH"

    log "Done. Signed + notarized app at: $APP_PATH"
else
    log "Archiving with ad-hoc signature ($CONFIGURATION)"
    xcodebuild archive \
        -project OnlyCue.xcodeproj \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="-" \
        | xcbeautify --renderer terminal --quieter
    [[ "${PIPESTATUS[0]}" -eq 0 ]] || fail "xcodebuild archive failed"
    [[ -d "$ARCHIVE_PATH" ]] || fail "Archive not produced at $ARCHIVE_PATH"

    log "Copying ad-hoc signed .app out of archive"
    cp -R "$ARCHIVE_PATH/Products/Applications/OnlyCue.app" "$APP_PATH"

    log "Verifying ad-hoc signature"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"

    log "Done. Ad-hoc signed app at: $APP_PATH"
    log "Note: Gatekeeper will refuse this on first launch. End users right-click → Open, or run 'xattr -dr com.apple.quarantine /Applications/OnlyCue.app'."
fi
