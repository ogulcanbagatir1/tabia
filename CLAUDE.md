# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a native macOS SwiftUI app (Swift 5.9+, macOS 13.0+, Xcode 15.0+). No external package dependencies.

```bash
# Open in Xcode
open ChessAnalyzerApp/Chess\ Analyzer/Chess\ Analyzer.xcodeproj

# Command-line build
xcodebuild -project "ChessAnalyzerApp/Chess Analyzer/Chess Analyzer.xcodeproj" -scheme "Tabia" -configuration Debug build

# Close the app, rebuild, and open (use after each feature implementation)
pkill -x "Tabia" 2>/dev/null; xcodebuild -project "ChessAnalyzerApp/Chess Analyzer/Chess Analyzer.xcodeproj" -scheme "Tabia" -configuration Debug build && open "$(xcodebuild -project 'ChessAnalyzerApp/Chess Analyzer/Chess Analyzer.xcodeproj' -scheme 'Tabia' -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/Tabia.app"

# Run from Xcode: ⌘R
```

**IMPORTANT**: Always close the app before rebuilding. Use the single command above which includes `pkill` to close the app, rebuild, and reopen - all in one step. Do not run build and open as separate commands.

**After every feature implementation**, use the combined command to close, rebuild, and reopen the app to verify changes work correctly.

There are no test targets, linters, or formatters configured in the project.

## Architecture

The app follows an MVC pattern with SwiftUI reactive views. All source code lives in `ChessAnalyzer/`.

### Engine Layer (`Engine/`)
Core chess logic, no UI dependencies:
- **ChessBoard** — Board state as 8x8 array, piece management, FEN export, `makeMove()` API
- **MoveGenerator** — Legal move generation per piece type, special moves (castling, en passant, promotion), check/checkmate detection
- **GameTree** — Tree structure for game history with variation/branch support, navigation (`goBack`/`goForward`), PGN export
- **NotationEngine** — Bidirectional conversion between `Move` objects and standard algebraic notation (e.g., "Nf3", "O-O"), handles disambiguation
- **StockfishEngine** — UCI protocol wrapper for external Stockfish binary via `Process`. Falls back to mock evaluation (piece value counting) when Stockfish is unavailable

### Views Layer (`Views/`)
- **MainWindowView** — Three-column layout coordinating board, game tree, engine, and database
- **BoardView** — Interactive board rendering with Unicode piece symbols (♔♕♖♗♘♙), legal move highlighting, click-to-move
- **MoveListView** — Move history with variation display and navigation controls
- **GameLibraryView** — Sidebar game browser with search, filtering, PGN import/export
- **EvaluationBar** — Visual evaluation meter (centipawns)
- **PreferencesView** — Engine path, analysis depth (5-30), board theme, animation speed

### Data Layer
- **GameDatabase** (`Database/`) — In-memory game records persisted to UserDefaults, CRUD operations, full-text search, filtering by player/opening/result, statistics
- **PGNParser** (`PGN/`) — Parses PGN files including headers and move text, supports multi-game files

### Data Flow
```
BoardView (user click) → MoveGenerator (validate) → ChessBoard (update state)
  → GameTree (record move) → NotationEngine (algebraic notation)
  → StockfishEngine (evaluate) → EvaluationBar + MoveListView (display)
  → GameDatabase (persist)
```

## Key Data Structures
- `Piece`, `PieceType`, `PieceColor`, `Position`, `Move` — defined in `ChessBoard.swift`
- `GameRecord` — defined in `GameDatabase.swift`, contains headers, PGN, result, ECO code, tags

## Known Incomplete Areas
- `StockfishEngine.start()`: Process execution is commented out
- `MoveGenerator.leavesKingInCheck()`: Simplified stub
- Menu commands in `TabiaApp.swift` (formerly `ChessAnalyzerApp.swift`): File I/O handlers are TODOs
- Sliding piece attack detection is incomplete
