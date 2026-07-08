# Ready-to-paste prompt for Claude Code

> Copy the `design_handoff_annotator_redesign/` folder into the repo root first, then paste the prompt below.

---

I'm redesigning this app's entire UI. The new design language is called **"The Annotator"** and is fully specified in `design_handoff_annotator_redesign/`:

- `README.md` — complete spec: design system, per-screen layouts (codes A1–ES4), interactions, states.
- `tokens.json` — every color/type/metric token with usage notes. Treat as the single source of truth.
- `design/Tabia - Product Design.dc.html` — the visual reference. Open it in a browser to inspect; measurements in it are final.

Read all three before writing any code. Then work in phases, committing after each:

**Phase 0 — Audit.** Map the existing codebase: where are colors/fonts/spacing defined today, which views implement Analysis / Explorer / Repertoire / Games / Database / Engines / Settings, how is dark mode handled. Produce a short mapping table (existing view → design code) before changing anything.

**Phase 1 — Tokens & fonts.** Create the theme layer from `tokens.json` (both modes: readingRoom + nightStudy). Bundle Newsreader, Instrument Sans, Courier Prime. Wire mode switching (System / Reading Room / Night Study). Delete or deprecate the old palette so nothing new can reference it.

**Phase 2 — Chrome & primitives.** Rebuild the shared shell: titlebar/masthead with centered nav tabs (red underline active), 28px mono status bar, window styling. Then the primitives from README's component list: buttons (red primary / bordered secondary / disabled), segmented controls, chips & badges, toggles (36×21), steppers, inputs, W/D/L monochrome bars, eval chip + PV row, move-list row with quality marks, sheet/drawer scaffold, empty-state pattern. Match section 00 of the HTML exactly, in both modes.

**Phase 3 — Screens, in this order:** Analysis (A1 empty, A2/A3 full) → Explorer (E1, E2 indexing state) → Repertoire (R1 shelf, R2 editor, R3 drill, R4 knowledge, R5 sheet) → Games (G1, G2, G3 banner) → Database (D1, D2 drawer, D3–D5 sheets; fold the old separate "Databases" home screen into the D1 sidebar) → Engines (N1, N2) → Settings (S1–S3) → remaining empty states (ES1–ES4).

**Phase 4 — Sweep.** Grep for any remaining old-palette hexes, old fonts, glass/blur effects, and gradients; remove them. Verify every screen in both modes.

Hard rules (from the design system — do not violate):
1. One red-filled action per screen, max. Red `#9E2B25` (light) / accent `#C25048` (dark) is for actions, active tab, due counts, marks — never backgrounds or decoration.
2. The chess board keeps its sepia paper colors (`#F0E6CF`/`#A98F6C`) in BOTH modes. Do not theme it. Keep existing piece-set rendering.
3. All data (numbers, SAN, FEN, dates, ECO) is mono (Courier Prime). All labels are uppercase, letter-spaced Instrument Sans. Titles/prose are Newsreader; italic Newsreader is the commentary voice.
4. Depth = 1px hairlines + soft shadows only. No blur, no glassmorphism, no gradients, no glow. W/D/L bars are monochrome.
5. Quiet motion only (~150–200ms ease-out; pulsing dots for live work).

Keep all existing functionality and data wiring intact — this is a reskin plus the small IA change in Database (collections into sidebar). Where the app has a screen or control the design doesn't cover, derive it from the tokens + component primitives and flag it in your summary for design review.

---

## Tips for the session

- Give Claude Code this whole folder — don't paraphrase the spec by hand.
- Run phases as separate conversations/PRs if the codebase is large; paste the prompt once and then say "continue with Phase N".
- After Phase 2, screenshot the component gallery next to section 00 of the HTML and compare before proceeding — cheapest place to catch drift.
- Keep the HTML open while reviewing PRs; it is the acceptance reference.
