#!/bin/bash
# Notarize the Developer ID-signed Tabia.app, staple it, and package a DMG.
# Requires a stored notarytool keychain profile named "tabia-notary":
#   xcrun notarytool store-credentials "tabia-notary" \
#     --apple-id "<APPLE_EMAIL>" --team-id "4NRG5R2K23" --password "<APP_SPECIFIC_PASSWORD>"
set -euo pipefail

DIST="/Users/ogulcanbagatir/Desktop/my-projects/tabia/dist"
APP="$DIST/build/Tabia.app"
PROFILE="tabia-notary"
DMG="$DIST/Tabia.dmg"
STAGING="/private/tmp/claude-501/-Users-ogulcanbagatir-Desktop-my-projects-chess/9a202170-2dbd-4fa1-ae61-33c88e67e797/scratchpad/dmg-staging"

[ -d "$APP" ] || { echo "No app at $APP — run build_developerid.sh first."; exit 1; }

echo "==> Zipping app for notarization…"
ZIP="/private/tmp/claude-501/-Users-ogulcanbagatir-Desktop-my-projects-chess/9a202170-2dbd-4fa1-ae61-33c88e67e797/scratchpad/Tabia.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary service (waits for result)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ticket to app…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Building DMG…"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Tabia" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "==> Stapling ticket to DMG…"
xcrun stapler staple "$DMG"

echo "==> Final Gatekeeper check (should say: accepted / Notarized Developer ID):"
spctl -a -vvv --type install "$DMG" 2>&1 | tail -3 || true
spctl -a -vvv --type execute "$APP" 2>&1 | tail -3 || true

echo ""
echo "DONE → $DMG  (upload this to your website)"
