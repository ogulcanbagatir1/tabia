#!/usr/bin/env bash
#
# Build → sign (Developer ID) → notarize → staple Tabia for direct distribution.
#
# One-time setup (see NOTARIZE.md):
#   1. Apple Developer Program membership (team 67U3MGM2PW is already set).
#   2. A "Developer ID Application" certificate installed in your login keychain.
#   3. Stored notary credentials:
#        xcrun notarytool store-credentials TabiaNotary \
#          --apple-id "you@example.com" --team-id 67U3MGM2PW --password "APP-SPECIFIC-PW"
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
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "hardened" || true
# The runtime flag must be present for notarization to pass:
if ! codesign -dvvv "$APP" 2>&1 | grep -q "flags=.*runtime"; then
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

# Package a stapled, ready-to-ship zip alongside the app.
DIST_ZIP="$BUILD_DIR/Tabia-notarized.zip"
ditto -c -k --keepParent "$APP" "$DIST_ZIP"

echo ""
echo "✅ Done."
echo "   App:  $APP"
echo "   Ship: $DIST_ZIP"
echo "   (Distribute the stapled .app — e.g. inside a .dmg or the zip above.)"
