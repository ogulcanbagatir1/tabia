# Chess Pieces

This folder should contain chess piece images.

## Required Images

### White Pieces
- WhiteKing.png
- WhiteQueen.png
- WhiteRook.png
- WhiteBishop.png
- WhiteKnight.png
- WhitePawn.png

### Black Pieces
- BlackKing.png
- BlackQueen.png
- BlackRook.png
- BlackBishop.png
- BlackKnight.png
- BlackPawn.png

## Alternative: Unicode Symbols

Currently, the app uses Unicode chess symbols (♔♕♖♗♘♙♚♛♜♝♞♟) which are built-in.

To use custom images instead:
1. Add PNG images to this folder
2. Update `Piece.symbol` in `ChessBoard.swift` to load images
3. Use Image(piece.imageName) instead of Text(piece.symbol)

## Recommended Size
- 512x512 pixels
- PNG format with transparency
- High contrast for visibility
