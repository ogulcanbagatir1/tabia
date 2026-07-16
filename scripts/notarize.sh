#!/usr/bin/env bash
#
# Build → sign (Developer ID) → notarize → staple Tabia for direct distribution.
#
# One-time setup (see NOTARIZE.md):
#   1. Apple Developer Program membership (team 4NRG5R2K23 is already set).
#   2. A "Developer ID Application" certificate installed in your login keychain.
#   3. Stored notary credentials:
#        xcrun notarytool store-credentials TabiaNotary \
#          --apple-id "you@example.com" --team-id 4NRG5R2K23 --password "APP-SPECIFIC-PW"
#
# Then just run:  ./scripts/notarize.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="mac-app/ChessAnalyzerApp/Chess Analyzer/Chess Analyzer.xcodeproj"
SCHEME="Tabia"
CONFIG="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-TabiaNotary}"

BUILD_DIR="$REPO_ROOT/build/notarize"
ARCHIVE="$BUILD_DIR/Tabia.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Tabia.app"
ZIP="$BUILD_DIR/Tabia.zip"

echo "▸ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ [1/6] Archiving ($CONFIG)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" archive

echo "▸ [2/6] Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$REPO_ROOT/scripts/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR"

echo "▸ [3/6] Verifying signature + Hardened Runtime…"
codesign --verify --deep --strict --verbose=2 "$APP"
# The runtime flag must be present for notarization to pass. Capture codesign's output to a
# variable first — piping straight into `grep -q` makes grep close the pipe early, codesign dies
# with SIGPIPE, and `set -o pipefail` then reports the whole check as failed even on a match.
CS_INFO="$(codesign -dvvv "$APP" 2>&1 || true)"
if ! printf '%s' "$CS_INFO" | grep -q "flags=.*runtime"; then
    echo "  ✗ Hardened Runtime flag not found on the signed app. Aborting." >&2
    exit 1
fi

echo "▸ [4/6] Zipping for notary submission…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ [5/6] Submitting to Apple notary (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ [6/6] Stapling the ticket…"
xcrun stapler staple "$APP"

echo "▸ Final Gatekeeper assessment:"
spctl -a -vvv -t exec "$APP" || true

# Version-stamped, stapled archive for the Sparkle appcast.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
TAG="v${VERSION}"
DIST_ZIP="$BUILD_DIR/Tabia-${VERSION}.zip"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$APP" "$DIST_ZIP"

# Remove the temporary notary-submission zip so generate_appcast doesn't see two archives with
# the same bundle version (it errors "Duplicate updates are not supported").
rm -f "$ZIP"

# Generate + sign the Sparkle appcast. The private EdDSA key is read from the keychain
# (created once via generate_keys — see scripts/UPDATES.md).
GEN_APPCAST="${SPARKLE_BIN:-}"
if [ -z "$GEN_APPCAST" ]; then
    GEN_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)"
fi
if [ -n "$GEN_APPCAST" ] && [ -x "$GEN_APPCAST" ]; then
    echo "▸ Generating signed appcast…"
    "$GEN_APPCAST" \
        --download-url-prefix "https://github.com/ogulcanbagatir1/tabia/releases/download/${TAG}/" \
        "$BUILD_DIR"
    echo "   appcast: $BUILD_DIR/appcast.xml"
else
    echo "⚠︎ generate_appcast not found — appcast skipped."
    echo "  Build once in Xcode so SPM fetches Sparkle's tools, or set SPARKLE_BIN=/path/to/generate_appcast."
fi

echo ""
echo "✅ Done."
echo "   App:     $APP"
echo "   Archive: $DIST_ZIP"
echo "   Appcast: $BUILD_DIR/appcast.xml (if generated)"
echo ""
echo "Release: create a GitHub release tagged ${TAG}, and upload BOTH"
echo "  $(basename "$DIST_ZIP")  and  appcast.xml  as release assets."
echo "See scripts/UPDATES.md for the full flow."
