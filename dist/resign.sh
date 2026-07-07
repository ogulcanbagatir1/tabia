#!/bin/bash
# Re-sign the built Tabia.app correctly for notarization:
#  - sign nested binaries (bundled stockfish, onnxruntime.framework) with
#    Developer ID + Hardened Runtime + secure timestamp
#  - re-seal the app with entitlements that do NOT include get-task-allow
set -uo pipefail

APP="/Users/ogulcanbagatir/Desktop/my-projects/tabia/dist/build/Tabia.app"
ENT="/Users/ogulcanbagatir/Desktop/my-projects/tabia/mac-app/ChessAnalyzerApp/Chess Analyzer/Chess Analyzer/Tabia.entitlements"
ID="Developer ID Application: Ogulcan Bagatir (4NRG5R2K23)"

echo "==> 1/3 signing bundled stockfish (69MB, timestamp server may be slow)…"
codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/Resources/stockfish" && echo "   done"

echo "==> 2/3 signing onnxruntime.framework…"
codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/Frameworks/onnxruntime.framework" && echo "   done"

echo "==> 3/3 re-sealing app (no get-task-allow)…"
codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$ID" "$APP" && echo "   done"

echo ""
echo "===== VERIFY ====="
echo "-- get-task-allow removed?"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "get-task-allow" && echo "  STILL PRESENT ❌" || echo "  removed ✅"
echo "-- stockfish signature:"
codesign -dvv "$APP/Contents/Resources/stockfish" 2>&1 | grep -iE "Authority=Developer ID|Timestamp=|flags=" | head -3
echo "-- onnxruntime signature:"
codesign -dvv "$APP/Contents/Frameworks/onnxruntime.framework" 2>&1 | grep -iE "Authority=Developer ID|Timestamp=|flags=" | head -3
echo "-- app deep/strict verify:"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
echo "DONE"
