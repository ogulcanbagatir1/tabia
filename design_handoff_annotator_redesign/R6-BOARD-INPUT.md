# R6-BOARD-INPUT.md — Repertoire Editor: Board Input Mode

**Addendum to `R2-REPERTOIRE-EDITOR.md` — read that first.** This spec answers "where do the moves come from?" — how a repertoire is *authored*: first creation and later editing. Design reference: `design/Tabia - Product Design.dc.html`, section 03, screen **R6**.

This is a functional spec. The editor gains a second view and a recording model; the tree view (R2) is unchanged except where noted.

---

## 1 · The model: one editor, two views

The repertoire editor is **one screen with two views** of the same repertoire:

- **TREE** (R2) — the map. Read, reorganize, annotate: ownership, marks, notes, tags, gap badges.
- **BOARD** (R6) — the pen. Every move enters the repertoire here, by playing it.

A segmented control `TREE | BOARD` sits in the editor header next to the repertoire title (bordered segment, active = ink-filled chip, Instrument Sans 9.5px +0.12em 700). Shortcut **⌥T** toggles. The two views share one cursor (a node in the variation tree): select a row in TREE and flip to BOARD → the board stands on that exact position; play moves in BOARD and flip back → that node is selected and revealed in TREE.

**First creation flows here**: R5 (New Repertoire sheet) → CREATE lands directly in BOARD view at the start position (or the imported PGN's root), ready to record move 1. An empty repertoire never shows an empty tree — it shows a board.

## 2 · R6 layout (1440×900 reference, columns `292 | fluid | 396`)

### 2.1 Header row (below the standard editor masthead)
Left→right: repertoire title + `▾` (Newsreader 600 20px, bordered, click = switch repertoire) · `TREE | BOARD` segmented + mono `⌥T` hint · flex space · **recording indicator**: pulsing red dot (8px, `#C25048`, 1.6s ease pulse) + `RECORDING INTO CARO-KANN` (Instrument Sans 9.5px 700 red). The indicator is always on in BOARD view — it reassures the user that played moves are being written, not just browsed.

### 2.2 Left column (292px) — THE LINE SO FAR
- Header label `THE LINE SO FAR` (Instrument Sans 10px +0.14em 700 `#857A63`).
- Move rows, grid `26px | 1fr | 1fr`: move number (mono 11px `#6B6050`) · White's move · Black's move. Each move: 8px ownership dot (solid red `#C25048` = your side's move, hollow `#6B6050` ring = opponent's) + SAN in Courier Prime 13px bold ink. Current position's row: wash bg `#2A2317` + 1px hairline border, radius 7.
- Under the list: `▸ CURSOR` (mono 10px bold red) + `NEW MOVES BRANCH HERE` (mono 10px `#857A63`) — labels the semantics of the cursor.
- **ALREADY IN THE TREE HERE** block (hairline-topped): the existing children of the cursor node, one line each — ownership dot + SAN bold + italic Newsreader status: `— main, answered` / `— answered` / amber dashed dot + `— gap, no reply` (`#D9A43C`). This is how the author sees what's already covered *without leaving the board*.
- Bottom (pinned): italic Newsreader 13px explainer ("Step back with ←, play a different move — that is a branch. Nothing to manage; the tree grows under your hands.") + mono hint `← → STEP · ⌫ TAKE BACK · ⌥↵ PROMOTE TO MAIN`.

### 2.3 Center — the board
- Prompt line above the board (544px wide, spread): **turn prompt** Newsreader 15px — "Their move *— pick White's try to answer*" when it's the opponent's turn, "Your move *— write your reply*" when it's the author's side; right: mono `MOVE 4 · WHITE`.
- Board: standard 8×68px squares in the double frame (same as A2/A3). Pieces are draggable; legal-move enforcement on.
- **Overlay arrows** on the board, drawn for the cursor node's existing children (opponent's turn only):
  - Solid green arrow `#3FA97C` (7px stroke, round caps, arrowhead) = move already in the tree **and answered**.
  - Dashed amber arrow `#D9A43C` (13/9 dash) = move in the tree but a **gap** (no reply recorded).
  - Legend under the board, mono 10px: `IN THE TREE — ANSWERED` / `GAP — PLAY IT, THEN YOUR REPLY`.
  - Max ~4 arrows; beyond that draw the main + gaps only. No arrows on your own turn (the prompt is to *write*, not to review).
- Plate line under the board (Annotator idiom): `PLATE IX` red mono + italic caption describing the position ("After 3…Bf5 — drag a piece, and the move is written.").

### 2.4 Right column (396px) — theory + typing + engine
- **WHITE'S TRIES HERE** (or BLACK'S — the opponent side at the cursor): header + `MASTERS · 214K GAMES` mono right. Rows, grid `66px | 1fr | auto`: SAN mono 13.5px bold · `61% · 131K` mono 10.5px `#857A63` · status chip:
  - `✓ COVERED — 4…E6` — green `#3FA97C` bordered chip (shows the recorded reply).
  - `GAP — ADD REPLY` — amber **dashed** border chip; the row also gets a wash bg + amber border to pull the eye (this is the author's to-do).
  - `+ ADD` — quiet bordered chip for moves not yet in the tree.
  - Row click **plays that move on the board** (same as dragging it). Italic footnote says exactly that.
  - Data source: same masters DB the Explorer uses, filtered to the cursor position, sorted by frequency. Percentages = share of games.
- **OR TYPE IT**: a SAN input field (mono 12px, sidebar-toned bg, hairline border, radius 8, blinking red block cursor). Accepts a single SAN move, a sequence (`4.h4 h6 5.g4 Bd7`), or a **pasted PGN** — all merge into the tree at the cursor (see §3.4).
- **ENGINE CHECK** card (raised bg `#241E14`, pinned bottom): eval chip (mono 11.5px bold in a bordered box) + one PV line + plain verdict ("— fine for Black"). Runs on the cursor position at modest depth (see §3.6).

### 2.5 Status bar
Left: `PLAY ON THE BOARD · TYPE SAN · PASTE PGN — ALL ROADS INTO THE TREE · ⌘Z UNDOES`. Right: `CURSOR AFTER 3…Bf5 · WHITE TO MOVE · AUTOSAVED`.

## 3 · Behavior — the recording model

### 3.1 The cursor
One cursor = one node in the variation tree (position + the path that reached it). It is shared across TREE and BOARD views. `←`/`→` step back/forward along the current line; stepping back does **not** delete anything — it just moves the cursor. `⌫` is *take back* only for a move played seconds ago in this session that has no children/annotations; otherwise it steps back like `←` (never destructive on established tree content — deletion lives in TREE view).

### 3.2 Playing a move writes it
Any legal move played on the board (drag, or click-click):
- If the move **already exists** as a child of the cursor → the cursor advances into it. Nothing is duplicated. The board simply walks the tree.
- If it's **new** → create a node, advance the cursor. If a sibling already exists, the new node is an **alternative**; the first-ever child of a node is its **main** line. `⌥↵` promotes the cursor's move to main (demoting the previous main to alternative). Ownership is automatic: moves by the repertoire's side are "your moves" (solid dot), the other side's are "their moves" (hollow) — this drives R2's ownership display and the drill engine (only *your* moves are quizzed; their moves define the branching).
- Branching gesture: step back with `←`, play a different move. That's the whole authoring model — no "add variation" command exists.
- **Gap semantics**: a leaf node whose last move is the *opponent's* = a gap (`GAP — NO REPLY YET` in R2, amber everywhere). A leaf ending on *your* move is fine (that's just where your prep ends). Recording your reply on a gap node clears the gap.
- `⌘Z`/`⇧⌘Z` = full undo/redo of tree edits (add/promote/take-back), separate from cursor motion.

### 3.3 Theory-row click = played move
Clicking a row in WHITE'S TRIES is identical to playing that move on the board — same code path, same rules (§3.2). It exists because picking the opponent's most common tries from real data is the core loop of building coverage.

### 3.4 Typed SAN / pasted PGN — merge, don't append
The input field parses SAN sequences and full PGNs (with variations and comments):
- Moves that already exist in the tree at each step are **folded** (no duplicates); new ones are inserted, first-child-becomes-main rule applies; PGN comments land as move notes; PGN variations become alternatives.
- The merge is applied *from the cursor* for bare SAN sequences, and *from the repertoire root* for pasted PGNs with full games (detect: PGN tag section or move number 1 while cursor ≠ root → ask via a small sheet: "Merge from the start, or from the current position?").
- After a merge, the cursor lands at the end of the merged main sequence; a one-line toast in the status bar reports `MERGED — 12 NEW MOVES · 3 DUPLICATES FOLDED`.
- Illegal/ambiguous SAN: the field shakes, the offending token underlined red, nothing is applied (all-or-nothing per submission).

### 3.5 Autosave
The repertoire saves continuously (every tree edit, debounced ~1s). No save button, no dirty state — the status bar says `AUTOSAVED`. (This is unlike analysis boards, which use explicit save — a repertoire is a document you *garden*, not a file you export.) `⌘Z` history survives view toggles but not app relaunch.

### 3.6 Engine check
Modest fixed depth (~D18 or ~2s, whichever first) on the cursor position, re-queried on cursor move, cached per position. It exists to catch blunders while authoring, not for deep analysis — no depth controls, no MultiPV in this view. Uses the globally selected engine; obeys the active-tab engine rule from `TABS-AND-RAIL.md` (this window's search counts as the active work; pause it when the window is inactive).

### 3.7 Masters data
The tries panel queries the bundled/remote masters DB by position (Zobrist/FEN), same source as Explorer. If the position falls out of book (<50 games), the panel collapses to an italic note — "Out of book — you're on your own here. The engine still checks your work." — and the board arrows stop; only recorded-tree arrows for gaps remain.

## 4 · Entry points (recap)
- **R5 CREATE** → BOARD view, move 1 (or PGN root).
- **R1 shelf card click** → TREE view (R2) as today; ⌥T or any "add reply" affordance → BOARD.
- **R2 gap badge click** (`GAP — NO REPLY YET`) → jumps to BOARD view with the cursor on that gap node — the single most important navigation in the feature.
- **R4 weak-spot row click** → same jump.

## 5 · Light mode
R6 is shown dark. Map with tokens as usual; board colors never change. Green/amber chips use the light-mode quality pair (`#1E7A5A` / `#C08A1E`).

## 6 · Acceptance checklist
1. R5 → CREATE lands on BOARD view, start position, recording indicator on; playing 1.e4 creates the first node, autosaved.
2. Play a line to move 6, `←` back twice, play a different move → alternative created; ⌥↵ promotes it to main; R2 TREE reflects all of it instantly.
3. Opponent's turn: arrows show covered (green) vs gap (amber dashed); clicking a tries-row plays the move; recording a reply flips that row's chip to `✓ COVERED — <SAN>`.
4. Type `4.h4 h6 5.g4` in the field → merges from cursor; repeat the same submission → `0 NEW · DUPLICATES FOLDED`, tree unchanged.
5. Paste a full PGN with variations while cursor is mid-tree → merge-origin sheet appears; merging from start folds the shared trunk, adds the rest.
6. Gap badge in TREE view jumps to BOARD on that node; recording a reply clears the badge and the amber dot in THE LINE SO FAR.
7. ⌥T round-trips TREE↔BOARD preserving cursor; ⌘Z undoes the last tree edit in either view.
8. Out-of-book position: tries panel shows the italic fallback; engine check still runs.
