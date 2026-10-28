#!/bin/bash
# Re-sign an archived FluidVoice.app with one stable identity and package it.
#
# Usage: scripts/fork-sign-and-package.sh <archive.xcarchive> <output-dir> <signing-identity>
#   signing-identity: a codesigning identity name or SHA-1 in the default keychain search list,
#                     or "-" for ad-hoc (permissions must then be re-granted after every update).
#
# The signing steps follow upstream's PR archive workflow: Xcode flattens CTranscribe's version
# symlinks, so the framework layout is restored before nested code is signed inside-out.

set -euo pipefail

ARCHIVE_PATH="$1"
OUTPUT_DIR="$2"
IDENTITY="$3"

APP_PATH="$ARCHIVE_PATH/Products/Applications/FluidVoice.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/FluidVoice"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ENTITLEMENTS="$(mktemp -t fluidvoice-entitlements).plist"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"

test -x "$EXECUTABLE_PATH"

# Fork privacy checks: the analytics key must be gone from the bundle and the binary.
if /usr/libexec/PlistBuddy -c 'Print :POSTHOG_API_KEY' "$INFO_PLIST" >/dev/null 2>&1; then
    echo "Info.plist still contains POSTHOG_API_KEY." >&2
    exit 1
fi
if grep -aqE 'phc_[A-Za-z0-9]{40}' "$EXECUTABLE_PATH"; then
    echo "Executable contains a PostHog project key." >&2
    exit 1
fi

# Keep Xcode's expanded entitlements (Fluid.entitlements plus target capabilities such as Audio Input).
codesign -d --entitlements - --xml "$APP_PATH" > "$ENTITLEMENTS" 2>/dev/null
plutil -lint "$ENTITLEMENTS"
if [[ "$(plutil -extract 'com\.apple\.security\.device\.audio-input' raw -o - "$ENTITLEMENTS")" != "true" ]]; then
    echo "Xcode's effective entitlements are missing Audio Input." >&2
    exit 1
fi

CTRANSCRIBE_FRAMEWORK="$APP_PATH/Contents/Frameworks/CTranscribe.framework"
test -d "$CTRANSCRIBE_FRAMEWORK/Versions/A"
rm -rf \
    "$CTRANSCRIBE_FRAMEWORK/Versions/Current" \
    "$CTRANSCRIBE_FRAMEWORK/CTranscribe" \
    "$CTRANSCRIBE_FRAMEWORK/Resources" \
    "$CTRANSCRIBE_FRAMEWORK/Versions/A/_CodeSignature"
ln -s A "$CTRANSCRIBE_FRAMEWORK/Versions/Current"
ln -s Versions/Current/CTranscribe "$CTRANSCRIBE_FRAMEWORK/CTranscribe"
ln -s Versions/Current/Resources "$CTRANSCRIBE_FRAMEWORK/Resources"

sign() {
    codesign --force --sign "$IDENTITY" --timestamp=none "$@"
}

sign "$CTRANSCRIBE_FRAMEWORK"
sign "$APP_PATH/Contents/Frameworks/MediaRemoteAdapter.framework"
FV_SERVE="$APP_PATH/Contents/Helpers/fv-serve"
test -x "$FV_SERVE"
sign --options runtime "$FV_SERVE"
sign --options runtime --entitlements "$ENTITLEMENTS" --identifier "$BUNDLE_IDENTIFIER" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Signature)=' || true
echo "Designated requirement (what macOS ties Microphone/Accessibility grants to):"
codesign -d -r- "$APP_PATH" 2>&1 | sed -n 's/^designated => /  /p'

mkdir -p "$OUTPUT_DIR"
ZIP_PATH="$OUTPUT_DIR/FluidVoice-$VERSION.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256")
echo "zip-path=$ZIP_PATH"
