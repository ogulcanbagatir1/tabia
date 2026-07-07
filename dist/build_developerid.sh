#!/bin/bash
# Build a Developer ID-signed, Hardened-Runtime Release .app of Tabia
# for direct (outside App Store) distribution.
set -euo pipefail

PROJ="/Users/ogulcanbagatir/Desktop/my-projects/tabia/mac-app/ChessAnalyzerApp/Chess Analyzer/Chess Analyzer.xcodeproj"
SCHEME="Tabia"
TEAM="4NRG5R2K23"
DD="/private/tmp/claude-501/-Users-ogulcanbagatir-Desktop-my-projects-chess/9a202170-2dbd-4fa1-ae61-33c88e67e797/scratchpad/dist-build"
OUT="/Users/ogulcanbagatir/Desktop/my-projects/tabia/dist/build"

echo "==> Cleaning + building Release (Developer ID, Hardened Runtime)…"
xcodebuild \
  -project "$PROJ" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DD" \
  clean build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  2>&1 | tail -5

# NOTE: the bundled Contents/Resources/stockfish (a loose Mach-O) is NOT signed
# by Xcode. After this build, run dist/resign.sh to sign nested binaries
# (stockfish + onnxruntime) with Hardened Runtime + timestamp and re-seal the app,
# then dist/notarize_dmg.sh. Flow: build_developerid.sh -> resign.sh -> notarize_dmg.sh

APP="$DD/Build/Products/Release/Tabia.app"
[ -d "$APP" ] || { echo "BUILD FAILED: no app at $APP"; exit 1; }

mkdir -p "$OUT"
rm -rf "$OUT/Tabia.app"
cp -R "$APP" "$OUT/Tabia.app"
APP="$OUT/Tabia.app"

echo ""
echo "==> Signature summary:"
codesign -dvvv "$APP" 2>&1 | grep -iE "Authority|TeamIdentifier|flags|Timestamp" | head -8

echo ""
echo "==> Verify (deep, strict):"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3 && echo "  signature OK"

echo ""
echo "==> Hardened runtime flag present?"
codesign -d --verbose=2 "$APP" 2>&1 | grep -i "flags=" | grep -iq "runtime" && echo "  YES (runtime)" || echo "  NO — hardened runtime missing!"

echo ""
echo "==> Embedded frameworks signing:"
find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" 2>/dev/null | while read -r fw; do
  echo "  $(basename "$fw"): $(codesign -dvv "$fw" 2>&1 | grep -i 'Authority=Developer ID' | head -1 || echo 'NOT Developer ID signed')"
done

echo ""
echo "==> Gatekeeper assessment (will FAIL until notarized — expected):"
spctl -a -vvv --type execute "$APP" 2>&1 | tail -3 || true

echo ""
echo "BUILD+SIGN DONE → $APP"
