#!/bin/bash
# Copy chess piece PNGs to app bundle

PIECES_SRC="${SRCROOT}/Chess Analyzer/Resources/Pieces"
PIECES_DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/Pieces"

mkdir -p "$PIECES_DEST"
cp -f "${PIECES_SRC}"/*.png "$PIECES_DEST/"

echo "✅ Copied chess pieces to bundle"
