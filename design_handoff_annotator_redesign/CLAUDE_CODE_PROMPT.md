# Ready-to-paste prompt for Claude Code

> Copy the `design_handoff_annotator_redesign/` folder into the repo root first, then paste the prompt below.

---

I'm redesigning this app's entire UI. The new design language is called **"The Annotator"** and is fully specified in `design_handoff_annotator_redesign/`:

- `README.md` — complete spec: design system, per-screen layouts (codes A1–ES4), interactions, states.
- `tokens.json` — every color/type/metric token with usage notes. Treat as the single source of truth.
- `TABS-AND-RAIL.md` — **functional spec**: parallel analysis boards as titlebar tabs + left-rail navigation (screens A5/A6). This changes the window model, not just the skin — read fully.
- `R2-REPERTOIRE-EDITOR.md` — deep spec for the repertoire editor tree view.
- `R6-BOARD-INPUT.md` — **functional spec**: how repertoire moves are authored on a board (editor's second view, recording model, gap-closing loop).
- `design/Tabia - Product Design.dc.html` — the visual reference. Open it in a browser to inspect; measurements in it are final.

Read all of these before writing any code. Then work in phases, committing after each:

**Phase 0 — Audit.** Map the existing codebase: where are colors/fonts/spacing defined today, which views implement Analysis / Explorer / Repertoire / Games / Database / Engines / Settings, how is dark mode handled. Produce a short mapping table (existing view → design code) before changing anything.

**Phase 1 — Tokens & fonts.** Create the theme layer from `tokens.json` (both modes: readingRoom + nightStudy). Bundle Newsreader, Instrument Sans, Courier Prime. Wire mode switching (System / Reading Room / Night Study). Delete or deprecate the old palette so nothing new can reference it.

**Phase 2 — Chrome & primitives.** Rebuild the shared shell per `TABS-AND-RAIL.md` (A6 layout): 84px left rail with the 5 nav items (2px red left bar on active) and gear pinned at the bottom (opens Settings; `⌘,` too), titlebar with the board-tab strip + `+` button, 28px mono status bar, window styling. Note: the centered-nav masthead shown on A1–A3/E1/R1… in the HTML is the *pre-rail* chrome — A6 supersedes it everywhere except Settings/Engine Room windows and sheets; everything else about those screens stands. Then the primitives from README's component list: buttons (red primary / bordered secondary / disabled), segmented controls, chips & badges, toggles (36×21), steppers, inputs, W/D/L monochrome bars, eval chip + PV row, move-list row with quality marks, sheet/drawer scaffold, empty-state pattern. Match section 00 of the HTML exactly, in both modes.

**Phase 3 — Screens, in this order:** Analysis (A1 empty, A2/A3 full, A4 setup) → **board tabs behavior** (TABS-AND-RAIL §3: per-tab session state, engine pause/resume with `‖` frozen evals, dirty tracking + save sheet, persistence across relaunch, ⌘T/⌘W/⌃⇥, tear-out or "Move to New Window") → Explorer (E1, E2 indexing state) → Repertoire (R1 shelf, R2 editor tree view, **R6 board-input view** per R6-BOARD-INPUT.md: TREE|BOARD toggle ⌥T, shared cursor, play-to-record, theory tries panel with covered/gap chips, board arrows, SAN/PGN merge, autosave, gap-badge jump) → R3 drill, R4 knowledge, R5 sheet (CREATE lands in BOARD view) → Games (G1, G2, G3 banner) → Database (D1, D2 drawer, D3–D5 sheets; fold the old separate "Databases" home screen into the D1 sidebar; double-click a game → opens as a board tab) → Engines (N1 is NOT a nav item — it opens via ⌘E, Settings→Engines, or "Manage Engines…" in the Analysis engine selector; N2 sheet) → Settings (S1–S3, opened with ⌘, as a separate window) → remaining empty states (ES1–ES4).

**Phase 4 — Sweep.** Grep for any remaining old-palette hexes, old fonts, glass/blur effects, and gradients; remove them. Verify every screen in both modes.

Hard rules (from the design system — do not violate):
1. One red-filled action per screen, max. Red `#9E2B25` (light) / accent `#C25048` (dark) is for actions, active tab, due counts, marks — never backgrounds or decoration.
2. The chess board keeps its sepia paper colors (`#F0E6CF`/`#A98F6C`) in BOTH modes. Do not theme it. Keep existing piece-set rendering.
3. All data (numbers, SAN, FEN, dates, ECO) is mono (Courier Prime). All labels are uppercase, letter-spaced Instrument Sans. Titles/prose are Newsreader; italic Newsreader is the commentary voice.
4. Depth = 1px hairlines + soft shadows only. No blur, no glassmorphism, no gradients, no glow. W/D/L bars are monochrome.
5. Quiet motion only (~150–200ms ease-out; pulsing dots for live work).

Keep all existing functionality and data wiring intact. This is a reskin **plus three functional changes**: (1) Database collections fold into the D1 sidebar; (2) multiple analysis boards as tabs with the one-engine-active-tab rule (TABS-AND-RAIL.md); (3) the repertoire editor's board-input recording model (R6-BOARD-INPUT.md). The two functional specs each end with an acceptance checklist — run every item before calling the phase done. Where the app has a screen or control the design doesn't cover, derive it from the tokens + component primitives and flag it in your summary for design review.

---

## Tips for the session

- Give Claude Code this whole folder — don't paraphrase the spec by hand.
- Run phases as separate conversations/PRs if the codebase is large; paste the prompt once and then say "continue with Phase N".
- After Phase 2, screenshot the component gallery next to section 00 of the HTML and compare before proceeding — cheapest place to catch drift.
- Keep the HTML open while reviewing PRs; it is the acceptance reference.
