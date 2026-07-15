# R2 — Repertoire Editor ("The Manuscript") — Implementation Spec

Dark-mode (Night Study) screen of the Tabia macOS app. Reference render: `Tabia - Product Design.dc.html`, card **R2** (data-screen-label "R2 Repertoire editor (dark)"). This file is standalone — everything needed is below.

## Purpose
The screen where a user **writes** an opening repertoire as a variation tree and annotates each move. Three panes: **Move Inspector** (edit the selected move) · **Variation Tree** (the manuscript) · **Board + context** (position, engine sanity-check, recent deviations). Every edit feeds the spaced-repetition drill queue.

---

## Shared tokens (Night Study)
- Window bg `#1C1811` · titlebar/status bg `#211C13` · card/inset bg `#241E14` · deeper inset `#2A2418` / `#2A2317`
- Hairlines: `#3A3222` (default), `#4A4130` (stronger)
- Text: cream `#F1EADA` (headlines) / `#EDE6DA` (primary) · `#C4B99F` (body-mono) · `#A99C82` (secondary) · `#857A63` (muted) · `#6B6050` (faint)
- Accent red `#C25048` (on dark; buttons use `#9E2B25` with cream text `#F4EFE3`)
- Semantic: green `#3FA97C` · amber `#D9A43C` · orange `#D07A3E` · red `#C4534A`
- Fonts: **Newsreader** (serif — titles, italic notes) · **Instrument Sans** (UI labels, 600–700, uppercase, letter-spacing 0.1–0.14em) · **Courier Prime** (ALL chess notation, meta, chips)
- Window: 1440×900, radius 13, border `#0A0805`

## Window chrome
- **Titlebar** 47px, bg `#211C13`, bottom border `#3A3222`: traffic lights (`#D3766A` `#D9B36A` `#8FAE7F`, 12px) · wordmark "Tabia." (Newsreader 600 20px cream, the period in `#C25048`) · centered nav ANALYSIS / EXPLORER / **REPERTOIRE** (active: cream + 2px bottom border `#C25048`) / GAMES / DATABASE (Instrument Sans 600 11px ls 0.12em; inactive `#857A63`, hover cream) · right: **BEGIN DRILL** primary button (bg `#9E2B25`, cream text, radius 7) + gear icon button (⚙︎, border `#4A4130`, opens Settings, tooltip "Settings — ⌘,").
- **Status bar** 28px, bg `#211C13`, top border `#3A3222`, Courier 9.5px `#857A63`: left `CARO-KANN · 168 MOVES · 1 GAP · AUTOSAVED` · right `SELECTED 3…Bf5 · MAIN · B12`.

## Body layout
CSS grid `292px | 1fr | 396px`, full remaining height; 1px `#3A3222` borders between columns. Left and right columns padding 20–22px; each is a column flex with 14–16px gaps.

---

## LEFT — Move Inspector (292px)
Edits whatever move is selected in the tree. Top→bottom:

1. **Header**: label `MOVE INSPECTOR` (Instrument Sans 700 10px ls 0.14em `#857A63`); below it the move `3…♝f5` (Courier 700 22px `#EDE6DA`) + chip `YOUR MOVE` (Instrument Sans 700 8.5px, `#C25048` text + 1px `#C25048` border, radius 4). Chip reads `THEIR MOVE` when an opponent node is selected (then ownership section hides).
2. **OWNERSHIP** (radio, two full-width rows, radius 7, Courier 11.5px):
   - Selected: `MAIN — drilled as the answer` — bg `#2A2317`, border `#4A4130`, filled red dot 9px.
   - Unselected: `ALTERNATIVE — accepted in drills` — transparent, border `#3A3222`, hollow dot (border `#6B6050`), text `#A99C82`, hover border `#4A4130`.
   - Rule: per position, exactly one of *your* replies is MAIN; others are ALT (accepted as correct in drills, never asked for).
3. **FLAGS** (checkboxes, Courier 11px):
   - `DRILL AS PRIMARY ANSWER` — checked: 15px box bg `#9E2B25` with cream ✓, text `#C4B99F`.
   - `IMPORTANT FOR ME ✦` — unchecked: outlined box border `#4A4130`, text `#857A63`. (Important moves get priority in drill scheduling.)
4. **EVALUATION** (segmented chips, Courier 700 12px, radius 6, padding 5×10): `—` selected (bg `#EDE6DA`, ink `#1C1710` text); then outlined chips `!` `!!` (green `#3FA97C`), `?!` (amber `#D9A43C`), `?` (orange `#D07A3E`), `??` (red `#C4534A`) — border `#3A3222`, hover border takes the chip's own color. Single-select; stores the annotation glyph on the move.
5. **NOTE**: editable text box — bg `#241E14`, border `#3A3222`, radius 8, min-height 72px; content in *italic Newsreader 13.5px* `#EDE6DA`, line-height 1.55. Sample: "The point of the whole line: the bad bishop leaves home before …e6 locks it in."
6. **IDEA TAGS**: chip row (Courier 10px `#C4B99F`, border `#4A4130`, radius 5): `good bishop`, `before …e6`, plus a dashed add-chip `+ tag` (`#857A63`, dashed `#4A4130`).
7. **Footer** (pushed to bottom with margin-top auto): `ECO` label left, `B12` chip right (Courier 700 11px, border `#4A4130`).

## CENTER — Variation Tree
1. **Header** (padding 20px 26px 14px, bottom border `#3A3222`): repertoire switcher pill `Caro-Kann ▾` (Newsreader 600 22px cream in 1px `#3A3222` outline, radius 9 — dropdown lists all repertoires: Alapin vs Sicilian, Caro-Kann, Queen's Gambit Declined) · meta `BLACK VS 1.E4 · 168 MOVES · 78% COVERAGE` (Courier 10.5px `#857A63`) · spacer · chip `8 DUE` (Courier 700 10px, `#C25048` text + border, radius 4).
2. **Tree rows** (scrollable, padding 12px 14px, 1px gaps). Row anatomy, all vertically centered, 10px gaps:
   - Indent: `padding-left = 18 + depth × 26` px (depth 0–2 in sample).
   - **Dot** 9px: filled `#C25048` = *your* move; hollow (1.5px border `#6B6050`) = *their* move.
   - **SAN** Courier 700 13.5px `#EDE6DA` (e.g. `3…Bf5`).
   - *Italic note* Newsreader 13px `#A99C82`, flex 1, ellipsis.
   - Optional ownership chip `MAIN`/`ALT` (Instrument Sans 700 8.5px, `#A99C82`, border `#4A4130`, radius 4).
   - Optional gap badge `GAP — NO REPLY YET` (amber `#D9A43C` text + **dashed** amber border).
   - Selected row bg `#2A2317`; hover bg `#241E14`; radius 7.
3. **Sample data** (exact rows, in order — depth / dot / SAN / note / chip):
   - 0 hollow `1.e4`
   - 0 filled `1…c6` "the Caro-Kann — your defence" MAIN
   - 0 hollow `2.d4`
   - 0 filled `2…d5` MAIN
   - 1 hollow `3.e5` "Advance Variation"
   - 1 filled `3…Bf5` "bishop out before …e6" MAIN ← **selected**
   - 2 hollow `4.Nf3`
   - 2 filled `4…e6` MAIN
   - 2 hollow `4.h4` "the aggressive try"
   - 2 filled `4…h5` "fix the pawn" ALT
   - 1 hollow `3.exd5` "Exchange Variation"
   - 1 filled `3…cxd5` MAIN
   - 1 hollow `3.Nc3` "Classical"
   - 1 filled `3…dxe4` MAIN
   - 1 hollow `3.f3` "Fantasy Variation" + GAP badge
4. **Caption** under rows: *italic* Newsreader 12.5px `#857A63`: "Solid dots are your moves; hollow dots are theirs. One gap left in the Fantasy."

Behavior: clicking a row selects it → inspector binds to it, right board shows the position after that move, status bar updates. Clicking the GAP row puts the board in "add a reply" state. New moves are added by playing them on the board (append under selected node).

## RIGHT — Board & context (396px)
1. **Mini board** 8×40px squares (320px), centered. Position: **after 1.e4 c6 2.d4 d5 3.e5 Bf5** (FEN `rn1qkbnr/pp2pppp/2p5/3pPb2/3P4/8/PPP2PPP/RNBQKBNR w KQkq - 1 4`), last move c8→f5 highlighted. Square colors: light `#F0E6CF`, dark `#A98F6C`; highlight `#E7CF8E`/`#C3A566`. Frame: 1px `#0A0805` + ring shadows `0 0 0 3px #241E14, 0 0 0 4px #4A4130`. Caption below: `AFTER 3…♝f5 — YOUR MAIN LINE` (Courier 10px `#857A63`).
2. **ENGINE CHECK card** (bg `#241E14`, border `#3A3222`, radius 11, padding 14×18): label + one line: eval chip `−0.10` (Courier 700 11.5px cream on `#2A2418`, border `#4A4130`, radius 5, 52px wide, centered) + PV `4.Nf3 e6 5.Be2 c5 6.Be3 Qb6 — fine for Black` (Courier 11.5px `#C4B99F`, ellipsis). A quiet one-line sanity check of the selected move, not a full engine pane.
3. **RECENT DEVIATIONS** list — items with 2px left border `#D9A43C`, padding-left 12:
   - *"You played 4.Nf3 — book says 4.Bd3"* / `VS ANNA_K · BLITZ · 3D AGO`
   - *"Left book at move 9 vs the Marshall setup"* / `VS TIGRAN22 · RAPID · 5D AGO`
   - (Italic Newsreader 13.5px `#EDE6DA` + Courier 9px `#857A63` meta. Clicking opens that game in Analysis.)
4. **Bottom note** (margin-top auto, italic 12.5px `#857A63`): "Every edit is a card — the drill queue updates as you write."

## Interaction summary (for a real build)
- Selection drives all three panes (tree row ↔ inspector ↔ board ↔ status bar).
- Inspector edits mutate the selected node: ownership (MAIN/ALT invariant per position), flags, eval glyph, note, tags. Autosave; status bar shows AUTOSAVED.
- Board is also an input: playing a legal move on it appends a child to the selected node (or navigates if the move already exists).
- COVERAGE % = share of popular master continuations your tree answers; GAP rows are the missing answers.
- BEGIN DRILL switches to the drill screen (R3) seeded by the `8 DUE` cards.
