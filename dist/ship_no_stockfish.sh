#!/bin/bash
# Remove the accidentally-bundled stockfish (engine is download-only), re-seal,
# notarize, and package the DMG.
set -uo pipefail

ROOT="/Users/ogulcanbagatir/Desktop/my-projects/chess"
APP="$ROOT/dist/build/Tabia.app"
ENT="$ROOT/mac-app/ChessAnalyzerApp/Chess Analyzer/Chess Analyzer/Tabia.entitlements"
PROJ_SF="$ROOT/mac-app/ChessAnalyzerApp/Chess Analyzer/Chess Analyzer/Resources/stockfish"
ID="Developer ID Application: Ogulcan Bagatir (4NRG5R2K23)"
PROFILE="tabia-notary"
DMG="$ROOT/dist/Tabia.dmg"
SCRATCH="/private/tmp/claude-501/-Users-ogulcanbagatir-Desktop-my-projects-chess/9a202170-2dbd-4fa1-ae61-33c88e67e797/scratchpad"

echo "==> Removing bundled stockfish from project + built app…"
rm -f "$PROJ_SF" && echo "   project Resources/stockfish removed"
rm -f "$APP/Contents/Resources/stockfish" && echo "   app bundle stockfish removed"

echo "==> Re-sealing app (no stockfish)…"
codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$ID" "$APP"

echo "==> Verify…"
[ -e "$APP/Contents/Resources/stockfish" ] && { echo "   STILL PRESENT ❌"; exit 1; } || echo "   stockfish gone ✅"
codesign --verify --deep --strict "$APP" && echo "   signature valid ✅"

echo "==> Zipping + notarizing…"
ZIP="$SCRATCH/Tabia.zip"; rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

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
echo ""
echo "SIZE: $(du -h "$DMG" | cut -f1)"
echo "DONE → $DMG"
