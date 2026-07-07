#!/bin/bash
# Wait for the already-submitted notarization to finish, then staple + build the DMG.
set -uo pipefail
SUB="41504da1-2e4c-4233-8185-35799e3344ac"
PROFILE="tabia-notary"
ROOT="/Users/ogulcanbagatir/Desktop/my-projects/chess"
APP="$ROOT/dist/build/Tabia.app"
DMG="$ROOT/dist/Tabia.dmg"
SCRATCH="/private/tmp/claude-501/-Users-ogulcanbagatir-Desktop-my-projects-chess/9a202170-2dbd-4fa1-ae61-33c88e67e797/scratchpad"

echo "==> Waiting for notarization $SUB to finish (Apple's queue is slow)…"
xcrun notarytool wait "$SUB" --keychain-profile "$PROFILE"

STATUS=$(xcrun notarytool info "$SUB" --keychain-profile "$PROFILE" 2>&1 | awk '/status:/{print $2}')
echo "==> Final status: $STATUS"
if [ "$STATUS" != "Accepted" ]; then
  echo "NOT accepted — fetching log:"
  xcrun notarytool log "$SUB" --keychain-profile "$PROFILE" 2>&1 | head -60
  exit 1
fi

echo "==> Stapling app…"
xcrun stapler staple "$APP" && xcrun stapler validate "$APP"

echo "==> Building DMG…"
STAGING="$SCRATCH/dmg-staging"; rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Tabia" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
xcrun stapler staple "$DMG"

echo "==> Final Gatekeeper checks:"
spctl -a -vvv --type install "$DMG" 2>&1 | tail -2 || true
spctl -a -vvv --type execute "$APP" 2>&1 | tail -2 || true
echo "SIZE: $(du -h "$DMG" | cut -f1)"
echo "DONE → $DMG"
