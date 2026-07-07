# Tabia

A native **macOS** chess studio for analyzing your games and building an opening repertoire that sticks. Tabia brings engine analysis, an opening explorer, a spaced-repetition repertoire trainer, and a personal games database (with Chess.com & Lichess sync) into one fast, native SwiftUI app.

> *Tabia* (a.k.a. *tabiya*) — a well-known standard position reached after an established opening; the launchpad from which the real game begins.

## Features

- **Analysis** — full board with evaluation bar, live engine lines (Stockfish / Leela / Lichess cloud), a variation-aware move tree, and one-click full-game review that grades every move (Brilliant → Blunder) with accuracy scores and an eval graph.
- **Opening Explorer** — browse any position against the **Lichess Masters** database, your own **game library**, or a bundled **reference database** (build a local opening index over ~200k master games).
- **Repertoire trainer** — build opening lines as trees and **drill them with spaced repetition**; see coverage gaps and where you deviate from your own lines; per-repertoire knowledge stats.
- **Games, unified** — sync **Chess.com** and **Lichess**, import PGN databases, organize games in folders, and explore rich stats (rating charts, W/D/L, streaks, top openings).
- **Make it yours** — 38 board themes, 32 piece sets, light/dark.

## Requirements

- macOS 14+ (Apple Silicon)
- Xcode 15+
- No external Swift package dependencies

## Build & run

```bash
open "mac-app/ChessAnalyzerApp/Chess Analyzer/Chess Analyzer.xcodeproj"
# then ⌘R  (scheme: Tabia)
```

Command line:

```bash
xcodebuild -project "mac-app/ChessAnalyzerApp/Chess Analyzer/Chess Analyzer.xcodeproj" \
  -scheme "Tabia" -configuration Debug build
```

## Distribution

Tabia is distributed directly as a **notarized Developer ID DMG** (not the Mac App Store — the local UCI engine is downloaded/run at runtime, which the App Store sandbox disallows). The reproducible signing/notarization pipeline lives in [`dist/`](dist/):

```
dist/build_developerid.sh   # Developer ID + Hardened Runtime release build
dist/resign.sh              # sign nested binaries + strip get-task-allow
dist/notarize_dmg.sh        # notarize, staple, package the DMG
```

## Project layout

```
mac-app/ChessAnalyzerApp/Chess Analyzer/   # the Xcode project (Tabia)
  Chess Analyzer/
    Engine/      # chess logic, UCI engine, game analysis, integrations
    Views/       # SwiftUI screens & components
    Store/       # SwiftData ingest, reference database, dedup
    Database/    # game & repertoire persistence
    Utils/       # settings, opening book, ECO database, design system
    Resources/   # bundled boards, pieces, openings
dist/            # build & notarization scripts
```
