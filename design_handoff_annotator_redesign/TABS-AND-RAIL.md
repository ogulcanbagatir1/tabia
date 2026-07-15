# TABS-AND-RAIL.md — Parallel Boards (Tabs) + Left Rail Navigation

**Spec for two connected features added to the Annotator redesign.** Read `README.md` and `tokens.json` first — all colors/type rules there apply. Design reference: `design/Tabia - Product Design.dc.html`, section 01, screens **A5** (tab strip variant) and **A6** (final: left rail + titlebar tabs). **A6 is the layout to ship.** A5 exists only to document the tab strip's anatomy — reuse its tab states verbatim inside A6's titlebar.

This is a functional spec, not just a skin. Implement the window-model changes it describes.

---

## 1 · The mental model (do not deviate)

- A **tab holds a board, not a place.** One tab = one analysis session: a game + its move list + engine state + view scroll. Tabs are NOT the section nav — ANALYSIS / EXPLORER / REPERTOIRE / GAMES / DATABASE still switch the *whole window's* section, exactly as today.
- Sections and tabs are orthogonal: switching to EXPLORER does not touch the open boards; coming back to ANALYSIS restores the active tab exactly as left.
- **One board open = no visible tab management burden.** The single board renders as one wide tab in the titlebar (A6) — there is never a separate strip row that appears/disappears (that was A5; rejected for costing 37px of height).
- A1–A3 (existing analysis screens) are simply "the one-tab case" — they do not change except for the new chrome around them.

## 2 · Window chrome — the A6 layout

Replaces the centered-nav masthead **on all 5 main sections** (Analysis, Explorer, Repertoire, Games, Database). Settings/Engine Room windows and sheets keep their existing chrome. Drill mode (R3) keeps its collapsed chrome and **hides the rail** — focus is sacred there.

### 2.1 Titlebar (47px, unchanged height)
Left→right: traffic lights (86px zone) · **tab strip** (fills available width) · `+` new-tab button · flexible space · right-side action buttons (unchanged per section: SAVE GAME, RUN REVIEW on Analysis, etc). Background `#211C13` dark / `#EDE5D3` light, 1px bottom hairline (`#3A3222` / `#D9CFB8`).

The whole titlebar remains a drag region except tabs and buttons (standard NSWindow behavior).

### 2.2 Left rail (84px wide, full height under titlebar)
- Background: sidebar tone (`#17130D` dark / `#EFE8D8` light), 1px right hairline.
- Top: wordmark `T.` — Newsreader 600 23px, ink color, red period (`#C25048` dark / `#9E2B25` light). Replaces the full `Tabia.` wordmark (which no longer fits; the full wordmark still appears in Settings/About).
- Then 5 nav items, in order: ANALYSIS · EXPLORER · REPERTOIRE · GAMES · DATABASE. Each item: 19px line icon (1.6pt stroke, round caps) above an Instrument Sans 8.5px +0.10em 600 label, 10px vertical padding, full-width.
  - **Active**: text/icon `#F1EADA` (dark) / ink (light) + **2px red bar on the item's left edge** (the red-underline idiom, rotated 90°).
  - Inactive: `#857A63`, hover → full ink color, cursor pointer. No fills, no pill backgrounds — this is the Annotator, not a dock.
  - Icons (match the reference SVGs in A6): Analysis = board grid quadrant, Explorer = branching tree with node dots, Repertoire = open book, Games = text lines, Database = cylinder.
- Bottom (pinned): gear ⚙ → Settings (replaces the old masthead gear; `⌘,` unchanged).
- No collapse/expand behavior. Fixed 84px.

### 2.3 Tabs in the titlebar
Tab anatomy (from A5's state table — reuse exactly):

- Size: 232px wide fixed, full titlebar height, 14px left / 10px right padding, contents 9px gap.
- **Active tab**: background = content bg (`#1C1811` dark — it visually fuses with the content below), 1px left+right hairlines, and an **inset 2px red top edge** (`#C25048`). Title: Courier Prime 11px **bold**, full ink color.
- **Inactive tab**: transparent bg, 1px right hairline separating it from the next, title Courier Prime 11px regular `#857A63`. Hover: wash bg `#241E14` / `#E4DBC6`, close ✕ appears.
- **Leading indicator** (one of three):
  - Pulsing green dot `#1E7A5A` — engine is live on this tab (active tab only, and only while the engine runs).
  - `‖` glyph (Courier Prime 10px bold, `#6B6050`) — background tab whose engine eval is frozen (see §3.2).
  - Amber dot `#D9A43C` (static, 6px) — board has unsaved changes. Unsaved beats frozen if both apply.
- **Close ✕**: Courier Prime 11px, `#857A63`; visible on the active tab always, on inactive tabs on hover only; hover on ✕ itself = wash bg + ink color. Middle-click anywhere on a tab also closes it.
- **Tab title** = game identity, auto-derived, in this priority: PGN players (`You — MalckT · Najdorf` — append opening name once known) → import filename → `New board`. User can rename via double-click (inline edit) or context menu.
- **`+` button**: 30×26px, 1px hairline border, radius 6, `+` mono 13px; hover wash. Tooltip "New board — ⌘T". Sits immediately after the last tab.
- **Overflow**: tabs shrink from 232px down to a 130px floor as count grows; beyond that the strip scrolls horizontally (no dropdown). Practical ceiling ~8 tabs before scrolling.
- **One tab open**: the single tab still renders (it carries the engine dot / unsaved state and the title) but its close ✕ hides — closing the last board just resets it to the empty state (A1). It may widen to 280px max.
- Reorder by drag, standard macOS feel. **Drag a tab out of the strip → it becomes its own window** (see §3.4).

### 2.4 What the tab strip shows per section
The tab strip is **always visible in all 5 sections** (boards are the app's working set, like a browser's), but tabs activate the ANALYSIS section when clicked from elsewhere: clicking tab "Kasparov — Topalov" while in DATABASE switches the window to Analysis with that board active. This makes the strip a constant "what I have open" shelf. `+` from any section = new empty board + jump to Analysis.

## 3 · Behavior (the part that is not UI)

### 3.1 Tab = session state
Each tab owns, fully isolated from other tabs: the game (moves, annotations, header), current ply cursor, board orientation, engine analysis cache (evals per position already searched), explorer query state, move-list scroll position, and dirty flag. Switching tabs swaps all of it; nothing bleeds across.

### 3.2 One engine, the active tab — this is a hard rule
Local UCI engines (Stockfish etc.) run **only on the active tab's position**:

- On tab switch: the outgoing tab's engine search **pauses** — kill the search but keep its best-so-far result (eval, PV, depth) cached and displayed frozen. The tab gets the `‖` indicator. Do NOT keep multiple Stockfish instances searching in background tabs; that melts laptops and drains batteries for no user benefit.
- The incoming tab **resumes** from its cached state: show the frozen eval instantly, restart the search at the same position; when the new search passes the frozen depth, the display goes live again (frozen state visually: eval numbers at 60% opacity or with the `‖` mark in the engine panel — see A5's inactive-tab spec).
- **Cloud engines are exempt**: a cloud eval subscription may stay live on every tab simultaneously (it's someone else's CPU). If a background tab has a live cloud eval, it keeps the green dot but dimmed.
- Engine settings (which engine, threads, hash) are global, not per-tab.

### 3.3 Unsaved state & closing
- A board becomes dirty on any move/annotation change not yet saved to the library. Amber dot on the tab; window's `documentEdited` (dot in the red traffic light) reflects the *active* tab.
- `⌘W` / ✕ on a dirty tab: standard sheet — **Save / Don't Save / Cancel** (Save routes to the existing D4 Save Game sheet). Clean tabs close silently.
- Closing the last tab never closes the window; it resets to A1 empty state.
- `⌘⇧T` reopens the last closed tab (keep a small stack, ≥5 entries, session-scoped).

### 3.4 Tear-out → new window
Dragging a tab off the strip detaches the board into a new window (NSWindow with the same A6 chrome, its own single tab). This is *the* two-boards-side-by-side answer. Dragging a tab from one window's strip into another's merges it there. If the OS-level drag session is hard to get right in one shot, ship a context-menu item "Move to New Window" first and note the drag as TODO — the capability matters more than the gesture.

### 3.5 Persistence
- Open tabs (each tab's game as PGN + cursor + orientation + title), tab order, and the active tab index persist across relaunch — restore silently on launch. Engine caches are not persisted.
- Unsaved boards persist too (they're the whole point of restore); they come back with the amber dot.

### 3.6 Keyboard
- `⌘T` new board (jumps to Analysis) · `⌘W` close tab (if Analysis section focused; otherwise closes window per macOS convention — match Safari's behavior) · `⌃⇥` / `⌃⇧⇥` next/previous tab · `⌘1…⌘8` jump to tab N · `⌘⇧T` reopen closed.
- These must not collide with existing shortcuts (`⌘E` Engine Room, `⌘,` Settings unchanged).

### 3.7 Which entry points create tabs
- Database/Games: double-click a game row → opens as a **new tab** (or focuses the existing tab if that same library game is already open — match by library id).
- Explorer "open in analysis" actions → new tab with the current line pre-played.
- File → Open PGN with N games → one tab for the file's first game + the D3 review sheet for import, unchanged.
- Repertoire drill/editor never creates analysis tabs.

## 4 · Status bar (28px, unchanged)
Right side gains the board context when >1 tab: `BOARD 2 OF 3 · ENGINE ON ACTIVE TAB · D24`. Left side unchanged per section.

## 5 · Light mode
A5/A6 are shown dark (Night Study). Map to Reading Room with tokens: titlebar `#EDE5D3`, active tab bg = content paper `#F4EFE3`, red top edge `#9E2B25`, inactive text `#8A7D63`, hairlines `#D9CFB8`, rail bg `#EFE8D8`. The tab/rail *anatomy* is identical in both modes.

## 6 · Acceptance checklist
1. Rail replaces top nav on all 5 sections; active item has left red bar; gear at rail bottom opens Settings; `⌘,`/`⌘E` still work.
2. Two boards open → two titlebar tabs; switching is instant and restores full session state including engine panel showing frozen-then-resuming eval.
3. Background tab shows `‖`; its frozen eval survives the switch; active tab is the only one consuming engine CPU (verify in Activity Monitor).
4. Dirty tab: amber dot, close asks to save, relaunch restores it dirty.
5. `⌘T` from Database creates a board and lands in Analysis; the strip is visible in Database.
6. Tab from Database double-click focuses existing tab if the game is already open.
7. One tab: no ✕, no strip-management feel; A1 empty state intact.
8. Tear-out (or "Move to New Window") yields an independent window; both windows' engines obey the active-tab rule **per window** (one engine instance per window is acceptable; a global single instance following the frontmost window is better).
