#!/bin/bash
# Sign, notarize, and staple the DMG itself (the app inside is already notarized+stapled).
set -uo pipefail
ROOT="/Users/ogulcanbagatir/Desktop/my-projects/chess"
DMG="$ROOT/dist/Tabia.dmg"
ID="Developer ID Application: Ogulcan Bagatir (4NRG5R2K23)"
PROFILE="tabia-notary"

echo "==> Signing the DMG…"
codesign --force --sign "$ID" --timestamp "$DMG"

echo "==> Notarizing the DMG (Apple queue may be slow)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling the DMG…"
xcrun stapler staple "$DMG" && xcrun stapler validate "$DMG"

echo "==> Final Gatekeeper check (should be accepted):"
spctl -a -vvv --type install "$DMG" 2>&1 | tail -3 || true
echo "DONE → $DMG"
