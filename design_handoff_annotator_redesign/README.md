# Handoff: Tabia — "The Annotator" Full App Redesign

> **Also in this folder:** `TABS-AND-RAIL.md` (parallel boards as titlebar tabs + left-rail nav — supersedes the masthead nav described below) · `R2-REPERTOIRE-EDITOR.md` (editor tree view, deep spec) · `R6-BOARD-INPUT.md` (how repertoire moves are authored on a board). The two functional specs are mandatory reading — they change behavior, not just paint.

## Overview
This package restyles **Tabia**, a native macOS chess studio (analysis, opening explorer, repertoire trainer, games database with Chess.com/Lichess sync), into a new design language called **The Annotator**: an editorial, chess-press aesthetic — warm paper, ink, typewriter data, a serif voice, and one red pen. It replaces the current dark/glassy look entirely, in **both light and dark mode**.

- Light mode is called **Reading Room** (default by day).
- Dark mode is called **Night Study** (the signature look).
- The two modes share one idea: *the paper board never changes; only the lamp does.*

## About the Design Files
The file `design/Tabia - Product Design.dc.html` is a **design reference created in HTML** — a prototype showing intended look and behavior, not production code to copy. Open it in a browser (needs internet once, for Google Fonts) and pan around: it is one large canvas with 9 numbered sections. **Your task is to recreate these designs in the existing Tabia codebase** (SwiftUI/AppKit — follow whatever the codebase already uses), using its established view components, window handling, and data layer. Do not port HTML/CSS literally; port the *system*.

The HTML is also the best measurement source: every color, size, and spacing value in it is intentional and final. When this README and the HTML disagree, the HTML wins.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, copy tone, and states are final. Recreate pixel-perfectly within native idioms. (Data shown — player names, counts, ratings — is sample data; wire to real data.)

## How to read the design file
Sections are labeled `00–08`. Every window/panel has a code badge (A1, R2, D3, ES4…) referenced below. Section 00 is the design system itself: palettes with usage notes, the board, move-quality scale, the three typefaces, window anatomy, and a component gallery showing **every control in both modes side by side** — treat it as the component acceptance sheet.

## Design Tokens
All tokens are in **`tokens.json`** (machine-readable, with usage notes per token). Load it and wire into the app's theme system. Highlights:

- **Reading Room ground/text**: paper `#F4EFE3`, ink `#1C1710`, hairline `#D9CFB8`, red ink `#9E2B25`.
- **Night Study ground/text**: night `#1C1811`, paper text `#EDE6DA`, hairline `#3A3222`, red accent lifted to `#C25048` (buttons stay `#9E2B25`).
- **Board (both modes)**: light sq `#F0E6CF`, dark sq `#A98F6C`, last move `#E7CF8E`/`#C3A566`. **Never recolor with the theme.**
- **Move quality** (light/dark pairs): Brilliant `#1E7A5A`/`#3FA97C` · Best `#4E7A34`/`#8FB35B` · Book `#8A6F4D`/`#B29A73` · Inaccuracy `#C08A1E`/`#D9A43C` · Mistake `#BC5A22`/`#D07A3E` · Blunder `#9E2B25`/`#C4534A`. Marks are typographic: `!!` `!` `□` `?!` `?` `??`.
- **W/D/L bars are monochrome** (paper→ink stack), never green/red.
- **Radii**: 4/5/7/8/9/11/12/13 (window 13). **Hairlines**: always exactly 1px.

## Typography — three voices (bundle the fonts)
All three are Google Fonts under the OFL — **bundle them in the app bundle**:

1. **Newsreader** (serif) — display + prose voice: screen titles, player names, card titles, empty-state titles. *Italic Newsreader is the product's speaking voice* (annotations, hints, one-line insights). Weights 400/500/600.
2. **Instrument Sans** — labels only: nav tabs, buttons, section headers, chips. **Always uppercase, always letter-spaced (+0.10–0.14em), 9–11px, weights 600/700.** Never body text.
3. **Courier Prime** (mono) — **all data**: SAN notation, evals, FEN, counts, dates, ECO codes, status bars. If it's a number or notation, it's mono. Weights 400/700.

Fallback if bundling is impossible: New York / SF Pro / SF Mono — but the character lives in this trio, so bundling is strongly preferred.

## Window anatomy (every main screen)
- Window 1440×900 reference, radius 13, 1px outline (`#2A2117` light / `#0A0805` dark), traffic lights `#D3766A #D9B36A #8FAE7F`.
- **Titlebar/masthead, 47px**: traffic lights · wordmark `Tabia.` (Newsreader 600 20px; the period in red) · centered nav tabs (ANALYSIS · EXPLORER · REPERTOIRE · GAMES · DATABASE — active tab has a 2px red underline) · right-side actions (max one red-filled button).
- **Content**: column layouts with 1px hairline dividers. Analysis: `300 | fluid | 372`. Repertoire editor: `292 | fluid | 396`. Database: `280 | fluid`. Explorer: `448 | fluid`.
- **Status bar, 28px**: mono 9.5px, two ends — left = context truth (FEN, counts, filters), right = system truth (sync time, engine depth, clock).

## Navigation & entry points
- The main nav has exactly **5 tabs**: ANALYSIS · EXPLORER · REPERTOIRE · GAMES · DATABASE. Engines and Settings are NOT tabs.
- **Settings** is reachable from inside the app: a **gear button (⚙) at the far right of every main screen's masthead** opens the Settings window (compact, 3 tabs: S1 Appearance / S2 Engines / S3 Accounts & Import). The standard macOS routes also work: app menu → Settings… and `⌘,`. Drill mode (R3) intentionally hides the gear — focused chrome.
- **Engine Room (N1)** is a management window, not a main screen. Entry points: `⌘E` · Settings → Engines → "OPEN ENGINE ROOM →" (row exists in S2) · clicking the active engine chip in the Analysis engine panel opens a menu listing installed engines plus "Manage Engines…" · the A1/ES4 empty-state buttons route here. Its masthead shows an ENGINE ROOM title instead of the main nav.
- **Sheets** (R5, D3–D5, N2) attach to the window that spawned them; the **Filters drawer (D2)** slides from the right edge of Database.

## Screens / Views

### 01 · Analysis (the hero)
- **A1 — First launch (dark, empty states)**: Explorer shows the starting position with real master stats (it always has data). Right column: two dashed-border empty cards — "No engine installed" (red DOWNLOAD STOCKFISH + quiet "OR ADD ANY UCI BINARY →" link) and "No moves yet" (bordered IMPORT PGN); below, an inert "Game Review" explainer card. RUN REVIEW button in the masthead is **disabled** (faint, no red).
- **A2 — Reviewed classic (light)**: Left: opening explorer (position name in Newsreader, "9,144 GAMES REACH THIS TABIA", framed W/D/L bar 22px, move rows `SAN | mini W/D/L | count`, Notable games, italic insight + "OPEN IN DATABASE →" red link). Center: players top/bottom (color dots, name, Elo, red bordered TO MOVE chip), board 8×68px squares in its double frame, eval bar 15px wide beside it (paper fill from bottom, red hairline at the boundary, mono value below), and a **plate line** under the board: `PLATE XII` (red mono) + italic caption. Right: engine source segmented row (active = ink-filled chip with pulsing green dot, others bordered: STOCKFISH 17 / LEELA / CLOUD, depth+speed mono right) → 3 PV rows (eval chip + mono line) → move list (`#. | white | black` grid; current move = wash bg + bold; quality marks colored, appended to SAN) → **Game Review card** on raised bg: accuracies as big Newsreader numerals (94.1 / 88.7), eval sparkline in framed box, tally chips with quality-color squares.
- **A3 — Live session (dark)**: same skeleton, source tabs on the explorer (MASTERS / **MY LIBRARY** / REFERENCE), "you" data (your W/D/L in this line, your recent games here, italic insight: "You lose this line when the h-pawn runs…"), Game Review panel in not-run state with red `RUN REVIEW — 41 MOVES` block button.

### 02 · Opening Explorer
- **E1 (light)**: Left column (448px): red `PLATE B90` label, "Sicilian Defence — *Najdorf Variation*" title, mono move sequence, 48px board, `IN REPERTOIRE — WHITE` red-bordered chip, italic scholarly note. Right: source chips (LICHESS MASTERS active) + games count, full-width labeled W/D/L bar (26px), table `MOVE | CONTINUATION (italic names) | GAMES | SHARE | RESULTS bar`, Notable-games 3-card row, italic footer linking to your games in the line.
- **E2 — Reference DB indexing (panel)**: source tabs, "48,309 GAMES SEARCHABLE", amber pulsing `INDEXING… · 27% OF 180,000` + amber progress bar, italic "Search stays available while the rest is indexed." Move list still works. Footer: "PAUSES ON BATTERY".

### 03 · Repertoire
- **R1 — Shelf (light)**: 2×2 book cards (title, red `9 DUE` chip, side label, `214 POSITIONS · 96 YOUR MOVES`, green coverage bar + %, "REVISED TODAY"). Right rail: Training Queue card (Newsreader 44px "23", streak/last/retention stats, red BEGIN DRILL) + Next-7-days due forecast bar chart.
- **R2 — Editor (dark)**: Left inspector for the selected move: ownership (MAIN = red-dot radio card / ALTERNATIVE), flags (drill-as-primary checkbox), evaluation mark picker (`— ! !! ?! ? ??` colored), note (italic Newsreader in a field), idea tags (+ tag), ECO. Center: variation tree — indented rows: dot (solid red = your move, hollow = opponent), bold SAN, italic note, MAIN/ALT chips, **amber dashed `GAP — NO REPLY YET`** badge; selected row washed. Right: 40px board captioned `AFTER 3…♗f5 — YOUR MAIN LINE`, Engine Check card (eval chip + PV + verdict), Recent Deviations (amber left-border quotes: "You played 4.Nf3 — book says 4.Bd3" + game meta).
- **R3 — Drill (light)**: Chrome collapses: masthead shows `DRILLING — CARO-KANN · CARD 4 OF 23`, session score chip (`✓3 ✗0`), REALISTIC mode menu, END SESSION. Center: prompt line, 64px board, ask-card with pulsing red dot "**Your move.** *Play your line — alternatives are accepted.*", SHOW ANSWER / SKIP, and a 23-dot progress strip (green done, red current, bordered upcoming).
- **R4 — Knowledge popover (dark)**: two donut gauges (KNOWN 72% green / COVERED 78% red), 5 mono stats (DUE NOW red), red-flagged **Weak spots** list.
- **R5 — New Repertoire sheet (light)**: name field, side segmented (WHITE/BLACK with color dots), start-from radio cards (Empty / Current board position / Import a PGN study), CANCEL + red CREATE REPERTOIRE.

### 04 · My Games (online sync)
- **G1 — List (dark)**: header "BidiBoy1 — *last synced 2 minutes ago*" + three rating stat cards (BULLET 1577 / BLITZ 1761 / RAPID 1767 with tiny color dots); filter chips (ALL active) + GAMES/STATS segmented; table `WHITE | BLACK | RESULT | OPENING (italic) | ACC | TIME | SOURCE | WHEN` — result colored green/red/neutral **on the mono result text only**; italic footer "Accuracy fills in as games are reviewed."
- **G2 — Stats (dark)**: 12-month rating chart (blitz = paper line, rapid = red line, dashed gridlines, mono axis) + 4 stat cards (49.3% / 1891 / 14 / +38 green); Results-by-color monochrome bars + italic insight ("White is worth four points a hundred to you…"); Win-rate-by-hour column chart; Most-played-openings table (ECO chip, name, count, W/D/L bar, winrate bold).
- **G3 — First sync banner**: amber pulsing `IMPORTING — CHESS.COM`, italic explainer, `1,204 OF 13,789 · ~4 MIN LEFT`, amber progress, PAUSE, "RUNS IN BACKGROUND".

### 05 · Database
The old separate "Databases" home grid is **folded into the sidebar** — collections are one click, not a separate screen.
- **D1 — Ledger (light)**: sidebar LIBRARY (All Games / Chess.com / Lichess / **Classics** selected / Studies / Reference DB with counts) + SMART SETS (Reviewed games, Losses out of book, This month) + italic note that Reference DB is read-only + storage line. Main: search + filter chips (active filters chip in red `FILTERS · 2`) + LEDGER/BOARDS segmented; table `WHITE | BLACK | RESULT | ECO+OPENING | EVENT | DATE | ●` — red dot = reviewed; selected row washed; italic footer about annotations traveling with PGN export.
- **D2 — Filters drawer (light, 340px)**: player search + checkbox list, Elo dual-handle range slider (red active track), event & opening checkboxes, footer CLEAR ALL / red `APPLY — 2 FILTERS`.
- **D3 — Review Imported Games sheet (dark, 640px)**: file name + count, SELECT ALL bar, expanded game card (red left border) with editable PGN tag fields (White/Elo/Black/Result/Event/Date/ECO), collapsed rows below, footer `IMPORT TO [Classics ▾]` + CANCEL + red IMPORT 4 GAMES.
- **D4 — Save Game sheet (light, 560px)**: White/Black, Event/Date, result segmented (`＊ 1–0 0–1 ½–½`, ＊=unfinished), Save-to collection picker, mono PGN preview box, EXPORT TO FILE… / CANCEL / red SAVE TO LIBRARY.
- **D5 — New Collection sheet (dark, 520px)**: name, optional description, "Include in explorer stats" toggle row, CANCEL / red CREATE.

### 06 · Engines
- **N1 — Engine room (dark)**: cards row — Stockfish 17.1 (`ACTIVE` red-filled chip, selected border), Leela (`INSTALLED`), Lichess Cloud (`ONLINE` green), dashed + ADD ENGINE card. Below: settings list for the selected engine (Threads/Hash/MultiPV steppers `− value +`, NNUE toggle) + About card (italic honest description, mono facts: version/strength/license/binary path, quiet red-text REMOVE ENGINE bordered button).
- **N2 — Add Engine sheet (dark, 560px)**: DOWNLOAD/LOCAL BINARY tabs, curated radio list (Stockfish `LATEST`, Leela, Komodo, Lichess Cloud `FREE` — one-line honest descriptions), "OR POINT AT A BINARY" divider + path field + BROWSE…, footer red `DOWNLOAD & INSTALL — 41 MB`.

### 07 · Settings (three tabs, compact windows)
- **S1 — Appearance (dark, 1040px)**: mode segmented (SYSTEM / READING ROOM / NIGHT STUDY), board theme swatch grid (2×2 mini-boards, selected ringed in red, `+28 MORE`), piece style chips (glyph + name, selected red-bordered, `+26 MORE`), toggle rows (Show coordinates / Highlight legal moves / Best-move arrow) with title + mono sublabel.
- **S2 — Engine defaults (light, 860px)**: Default engine picker, Review depth segmented (FAST/BALANCED/DEEP), Analyze-on-open toggle, Cloud-fallback toggle (off state shown).
- **S3 — Accounts & import (dark, 860px)**: account rows (green dot, name+username, games+sync time, SYNC / DISCONNECT-turns-red-on-hover), Auto-sync (interval segmented 15M/1H/6H/DAILY + toggle), Skip duplicates, Classify openings on import.

### 08 · Empty States (pattern: icon → title → one italic sentence → action)
- **ES1** Database first run (dark): "No games in your library" → IMPORT PGN (red) + CONNECT ACCOUNTS.
- **ES2** Repertoire first run (light): "No repertoires yet" → CREATE REPERTOIRE.
- **ES3** Games not connected (dark): "Connect your accounts" + two inline username+CONNECT rows.
- **ES4** Engines first run (light): "No engines configured" → ADD ENGINE (red) + USE LICHESS CLOUD.
Icons are line-drawn, single-color (`ink40`/`paper40`), ~2px stroke, 34–44px.

## Interactions & Behavior
- **Hover**: rows/list items get the mode's wash (`#ECE4CD` / `#241E14`); nav tabs brighten to full ink; red buttons `brightness(1.12–1.15)`; bordered buttons get chrome wash. Cursor pointer on all interactive elements.
- **Selection**: selected rows/cards use the wash + (dark) `#2A2317` with `#4A4130` border; current move in move lists = `#E7DDC0` / `#3F3624` + bold.
- **Live indicators**: engine-running / syncing / indexing dots pulse (scale 1→0.75, opacity 1→0.3, ~1.6s ease-in-out loop). Green = healthy/running, amber = in-progress work.
- **Progress**: hairline-framed track, amber fill for background work; always paired with a mono count and an italic reassurance line; background work never blocks the UI.
- **Toggles**: 36×21, red when on, `borderStrong` when off. Steppers: bordered `− value +`. Segmented controls: bordered container, active segment = ink-filled (paper-filled in dark).
- **Sheets**: centered, window-radius 13, chrome-colored header with title + `✕`, hairline-separated body, footer right-aligned CANCEL (bordered) + one red confirm. Drawer (filters) slides from the right edge.
- **Transitions**: quiet and quick (~150–200ms ease-out); no springy or decorative motion.

## State Management (per screen, what must exist)
- Analysis: engine source (local/leela/cloud), engine running + depth/speed, PV lines (3), current ply, review-run state (none/running/done → accuracies, per-move grades, eval series), explorer source (masters/mine/reference).
- Repertoire: books (side, positions, your-moves, coverage %, due count), tree nodes (owner, main/alt, note, tags, eval mark, gap flag), drill session (queue, index, correct/wrong, mode realistic/strict), SM-2 scheduling data.
- Games: accounts (connected, username, count, last sync), sync/import progress, filters (time control), ratings history per pool.
- Database: collections + smart sets (counts), active filters (players, Elo range, events, openings, result, color), selection, view mode.
- Engines: installed list, active engine, per-engine options (threads/hash/multipv/nnue), download progress.

## Assets
- No raster assets. Board pieces in the mock use Unicode chess glyphs; the app should keep its existing piece-set rendering (32 styles) — restyle only the *chrome* around the board. Empty-state icons are simple inline vector drawings (recreate as SF-Symbol-style custom icons or vector assets).
- Fonts: Newsreader, Instrument Sans, Courier Prime (Google Fonts, OFL — bundle).

## Files
- `design/Tabia - Product Design.dc.html` — the full design reference (open in a browser; sections 00–08). `design/support.js` is its runtime — keep the two files together.
- `tokens.json` — all design tokens with usage notes.
- `CLAUDE_CODE_PROMPT.md` — a ready-to-paste prompt + phased migration plan for Claude Code.
