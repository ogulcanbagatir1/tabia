# Chess Analyzer — Complete App Description

A native macOS desktop application for chess game analysis, database management, and Chess.com integration. The app targets serious chess players who want to study their games, explore openings, and improve through engine analysis.

**Platform:** macOS 13.0+ (native SwiftUI)
**Minimum window:** 900 x 600 px (maximizes on launch)

---

## App Navigation

The app uses a **vertical icon rail** on the far left edge (always visible) with 5 screens:

1. **Analysis** — The main screen. Board + engine + move tree + opening explorer.
2. **Database** — Game library organized in folders. Import/export PGN.
3. **Chess.com** — Connect a Chess.com account, sync games, view statistics.
4. **Engine** — Download and configure chess engines (Stockfish, Lc0, cloud).
5. **Settings** — Appearance, board/piece themes, display toggles.

The top 4 icons are grouped at the top of the rail. Settings is pinned to the bottom.

---

## Screen 1: Analysis (Main Screen)

This is the most complex screen. It has a **4-column layout**:

### Column 1: Icon Rail (56px)
Always visible. See "App Navigation" above.

### Column 2: Explorer Panel (280px, left sidebar)

A togglable opening explorer with two data sources selectable via a segmented control at the top:

**Source A — Lichess Masters Database:**
- Queries the Lichess Masters API for the current board position
- Shows: opening name + ECO code (if recognized), total games, Win/Draw/Loss percentages as a horizontal stacked bar
- **Moves table** with columns:
  - Move (SAN notation, e.g. "e4", "Nf3") — 80px
  - Games (formatted count, e.g. "1.5K") — right-aligned
  - W/D/L mini-bar (90px wide, ~6px tall stacked bar: white/gray/black segments)
  - Book indicator icon if move is in the opening book
- Each move row is clickable — plays that move on the board
- **Notable Games section** below the moves: list of top master games in the position
  - Each row: White name (rating) vs Black name (rating), result, year
  - Clicking a game loads its full PGN into the analysis board

**Source B — My Library:**
- Same layout as Lichess but uses the user's own game database
- Additional toolbar: folder picker button to select which databases to include
  - Popover with checkboxes: "Unfiled Games" + each database folder
  - "All" / "None" bulk selection buttons
- Shows sample games from the user's library instead of master games

**Opening search bar** (both sources):
- Text field with magnifying glass icon
- Searches openings by name or ECO code
- Results list: opening name, move sequence (formatted SAN), ECO badge
- Clicking a result navigates the board to that opening position

### Column 3: Board Area (flexible width, center)

**Top: Board Status Bar**
- New Game button (resets the board)
- Save Game button (opens save sheet)
- Camera Tracking toggle button (activates camera-based board recognition)
- Flip Board button (rotates board 180 degrees)
- Player info: White circle + name + rating, "vs", Black circle + name + rating
- Move counter badge: "Move N"

**Center: Chess Board + Evaluation Bar**

The board and eval bar sit side by side, centered in the available space.

**Evaluation Bar** (vertical, 20px wide, to the left of the board):
- Vertical bar split into white (bottom) and black (top) portions
- The split point represents the engine's evaluation:
  - 50/50 = equal position
  - More white = white is winning
  - More black = black is winning
- Evaluation text displayed inside: "+1.2", "-0.5", "+M3" (mate in 3), "0.0"
- Smooth animated transitions when evaluation changes
- Only updates display at depth >= 16 to prevent flickering

**Chess Board** (square, fills available height):
- 8x8 grid with rank labels (1-8) on the left, file labels (a-h) on the bottom
- Supports 38 board themes (10 solid-color, 28 image-based)
- Supports 32 piece icon styles
- **Interactions:**
  - Click a piece to select it — shows legal move dots on valid destination squares
  - Click a legal move square to execute the move
  - Drag-and-drop a piece to move it (minimum 5px drag distance, piece follows cursor with shadow)
  - Right-click a square to toggle a red highlight
  - Right-click drag between two squares to draw an orange arrow
  - Left-click anywhere clears all arrows and highlights
  - Scroll wheel up/down navigates backward/forward through moves
  - Left/Right arrow keys navigate backward/forward
- **Visual indicators:**
  - Last move highlighted (from/to squares in yellow/gold)
  - Legal move dots (small circles on empty squares, corner triangles on capture squares)
  - Best move arrow (blue-indigo semi-transparent arrow from engine recommendation)
  - User-drawn arrows (orange, from right-click drag)
  - Move annotation badge (colored circle at destination square showing classification: !!, !, *, ?!, ?, ??, etc.)

### Column 4: Right Panel (300px, right sidebar)

Stacked vertically with 3-4 cards:

**Card 1: Current Opening**
- "OPENING" section label
- Opening name (bold, up to 2 lines)
- ECO code (accent colored)
- Shows "Starting Position" when no opening is detected
- Automatically detected as moves are played by matching against the opening book

**Card 2: Engine Analysis**
- Header: engine icon (CPU or cloud), engine name (dropdown if multiple engines configured), "Auto" toggle switch, "Analyze" button (starts full game analysis)
- When multiple engines are configured, the engine name is a dropdown menu to switch between them
- **Normal mode:** Shows 3 analysis lines (always 3 rows for stable layout):
  - Each line: evaluation badge (e.g. "+1.2", colored by advantage), followed by the principal variation in algebraic notation with move numbers (up to 20 half-moves)
  - If position is checkmate: "White/Black wins by checkmate"
- **Game analysis mode:** Shows progress bar + percentage + "Analyzing game..." text. "Cancel" button appears.
- **No engine installed:** Shows download icon, "No Engine Installed" message, "Download Engine" button that navigates to the Engine screen
- Depth badge (e.g. "d22") shown when engine is thinking

**Card 3: Game Analysis Results** (only visible after a full game analysis completes)
- Two side-by-side player accuracy cards:
  - White side: accuracy percentage (color-coded), classification breakdown
  - Black side: same layout
  - Classification categories with counts: Brilliant (!!, green), Great (!, blue), Best (*, light green), Book (B, brown), Good (+, light blue), Okay (o, purple), Inaccuracy (?!, amber), Mistake (?, orange), Blunder (??, red)
- **Evaluation graph** below the accuracy cards:
  - 80px tall graph showing evaluation over the course of the game
  - Dashed center line = equal
  - White area above center = white advantage
  - Black area below center = black advantage
  - Accent-colored line connecting evaluation points
  - Vertical line + dot at current move position
  - **Clickable:** Clicking anywhere on the graph navigates to that move

**Card 4: Move List**
- Header: "Moves" label + 4 navigation buttons (go to start, back, forward, go to end)
- Scrollable move list showing the full game tree:
  - Moves displayed in pairs: move number + white move + black move
  - Current move highlighted with accent background
  - Alternating row backgrounds for readability
  - Variations shown indented with expand/collapse chevron and parentheses
  - Move annotations shown as colored text suffixes
  - Comment indicator icon (small note icon) on moves with comments — click to expand/collapse
  - Auto-scrolls to keep current move visible
- **Context menu on any move** (right-click):
  - "Add Note" / "Edit Note" — opens a note editor popover with text field, Save/Cancel
  - "Delete Note" — removes comment
  - Annotation submenu: "! Good move", "!! Brilliant move", "? Mistake", "?? Blunder", "!? Interesting move", "?! Dubious move", "Clear annotation"
  - "Promote to Main Line" — makes a variation the main line (only on non-main-line moves)
  - "Make Subline" — demotes main line move to a variation (only on main line with siblings)
  - "Delete from here" — deletes the move and all descendants

### Camera Tracking Mode (replaces right panel content when active)

When camera tracking is activated, the right panel switches to:

**Camera Tracking Panel:**
1. Header with status indicator (color-coded dot: green=tracking, orange=calibrating, red=error, yellow=paused)
2. Live camera preview (180px tall) with overlay visualizations:
   - Raw corner detection points (cyan dots)
   - Board quadrilateral outline (green) with labeled corners (a1, h1, h8, a8)
   - Grid overlay (yellow lines showing the 8x8 grid)
   - Camera selection picker (if multiple cameras available)
3. Detected position: mini chess board (160x160) showing what the camera sees, with changed squares highlighted in orange. FEN string display. Last detected move in algebraic notation.
4. Control buttons: Find Corners, Start/Stop Tracking, Flip Board, Reset
5. Statistics: frames processed, moves detected, detection rate %

Plus the Move List card below.

### Save Game Sheet (modal, 500x550)

Opened from the "Save" button on the status bar:
- Form fields: White player, Black player, Event, Site, Date picker, Result picker (*, 1-0, 0-1, 1/2-1/2)
- Save location: folder picker listing all database folders
- PGN preview: read-only monospaced text block
- Actions: Cancel, Export to File (saves .pgn via system save dialog), Save to Library (adds to database)

---

## Screen 2: Database

Two-level navigation: root view (folder grid) and drill-in view (game table).

### Root View (Folder Grid)

- **Header:** "Game Database" title, subtitle showing folder count and total game count
- **Buttons:** "Import PGN" (bordered style), "New Folder" (filled/prominent style)
- **3-column grid of folder cards:**
  - "All Games" card: tray icon, accent color, total game count
  - One card per database folder: cylinder icon, orange color, per-folder game count, sorted alphabetically
  - "New Database" card: dashed border, plus icon, "Create new" label
- **Context menu on folder cards:** Rename, Export (PGN or SQLite format picker), Delete (with confirmation)
- **Drag-and-drop:** Drop .pgn files onto the grid to trigger import

### Drill-in View (Game Table)

Entered by clicking any folder card or "All Games":

**Header bar:** Back button (chevron), folder name, Filters toggle button (with active filter count badge), "Import PGN" button

**Filter Panel** (toggleable, horizontally scrollable row of filter cards):

| Filter | Type | Details |
|--------|------|---------|
| **Players** | Two searchable pickers | Separate White and Black player selection. Popover with search field + scrollable list of all known player names from the database. |
| **Result** | Checkbox selection | Three options: "White wins" (1-0), "Draw" (1/2-1/2), "Black wins" (0-1) |
| **Elo Range** | Dual-thumb sliders | Two independent range sliders (White Elo, Black Elo). Range: 0-3000, step 50. Visual dual-thumb slider UI. |
| **Opening** | Searchable picker | Popover with search + scrollable list of all opening names (merged from database + ECO database) |
| **Tournament** | Searchable picker | Popover with search + scrollable list of all event names from database |
| **Date Range** | Two text fields | "From" and "To" with format YYYY.MM.DD |

- "Apply" button (shown when changes pending)
- "Reset" button (shown when filters active)

**Sortable data table** with 7 columns:

| Column | Content |
|--------|---------|
| White | White circle + player name |
| Black | Black circle + player name |
| Result | Result text (monospaced, bold) |
| Opening | Opening name / ECO code |
| Event | Tournament/event name |
| Site | Location |
| Date | Game date |

- Each column header is clickable to sort ascending/descending (chevron indicator)
- Default sort: date descending
- Row selection: single click, Cmd+click (toggle multi-select), Shift+click (range select)
- Double-click opens game in analysis
- Infinite scroll with loading indicator

**Context menu on game rows:**
- "Open" — loads game in analysis
- "Move to..." — submenu listing all folders + "New Database..."
- "Delete" — with batch support for multi-selection

**Empty states:**
- No games at all: stack icon, "No Games Yet", "Import PGN files to get started", Import button
- Filters active but no results: filter icon, "No games match your filters", "Clear Filters" button

**Status bar:** Game count (with "filtered" indicator), loading spinner, selection count

**New Database Sheet** (modal):
- Name text field
- PGN drop zone + file browser
- "Create" button

**PGN Import Sheet** (modal, 700x500 min, 800x600 ideal):
- Left panel: game list with checkboxes, "Select All" / "Select None" buttons
  - Each row: checkbox, White vs Black, ECO code, move count, result badge
- Right panel: editable metadata for selected game
  - Players: White name + Elo, Black name + Elo
  - Event: name + round, site + date
  - Game: result picker (1-0, 0-1, 1/2-1/2, *), ECO code, opening name
  - Moves preview (monospaced, first 10 moves)
- Footer: destination folder picker, Cancel, "Import N Games" button
- Progress state: spinner + progress bar + "X of Y games"

**Export formats:** PGN (.pgn) and SQLite (.db3)

---

## Screen 3: Chess.com

Two states: disconnected and connected.

### Disconnected State

- Large green circle with person icon
- "Connect Chess.com" heading
- "Import and sync your games from Chess.com" description
- "Connect Account" button (green)

### Connected State

**Profile header:**
- Green avatar circle with first initial of username
- Username (large, bold)
- Last sync time (relative, e.g. "5 min ago")
- "Sync Games" button (green)
- Ellipsis menu: "Account Settings", "Disconnect Account" (destructive)

**Stats cards row:** Three cards side by side:
- Bullet: colored dot + "Bullet" label + current rating (large bold) or "-"
- Blitz: colored dot + "Blitz" label + current rating
- Rapid: colored dot + "Rapid" label + current rating

Time control colors: Bullet = orange, Blitz = blue, Rapid = green, Daily = purple

**Filter pills row:** Capsule-shaped toggle buttons: "All", "Bullet", "Blitz", "Rapid"

**Games table** (sortable, with infinite scroll):

| Column | Content |
|--------|---------|
| White | Player name |
| Black | Player name |
| Result | Color-coded: green = win, red = loss, gray = draw |
| Opening | Opening name / ECO |
| Time | Time control (colored by type) |
| Date | Game date |

- Column headers clickable for sort
- Row selection: click, Cmd+click, Shift+click, double-click to open
- Context menu: "Open Game", "Move to..." (folder submenu + "New Database...")
- Infinite scroll with loading indicator

**Empty states:** Loading spinner, "No games yet" + Refresh button, "No games match filters"

**Status bar:** Game count, "filtered" label, selection count

### Chess.com Connect Sheet (modal, 400x300)

- Username text field
- Progress bar during fetch (shows archive progress, games found count, estimated time)
- Connect/Save/Disconnect/Cancel buttons
- Error display

### Games/Stats Toggle

A segmented control switches between "Games" (table view above) and "Stats":

### Stats View (when toggled to "Stats")

A scrollable dashboard with 6 card sections:

**Card 1: Time Control Filter**
- Pill buttons: All, Bullet, Blitz, Rapid, Daily (color-coded)
- Filters all cards below

**Card 2: Overview**
- Total games count (large)
- Current and peak rating
- Custom donut chart: win/draw/loss proportions with win rate % in center
- W/D/L legend with counts and colored dots

**Card 3: Rating Chart**
- Line chart showing rating over time
- Y-axis: rating values (rounded to nearest 25)
- X-axis: dates (start, middle, end)
- Colored lines per time control with gradient fills
- Hover interaction: crosshair, nearest-point dot, tooltip with time class + rating + date

**Card 4: Results by Color**
- White vs Black performance comparison
- Side-by-side: game counts, win rates, wins, draws, losses
- Better side highlighted in bold

**Card 5: Performance by Time of Day**
- Four time slots with icons:
  - Morning (06:00-12:00) — sunrise icon
  - Afternoon (12:00-17:00) — sun icon
  - Evening (17:00-21:00) — sunset icon
  - Night (21:00-06:00) — moon icon
- Each row: icon, label, time range, game count, W/D/L, win rate
- Best slot highlighted with accent background
- Insight text summarizing best time

**Card 6: Top Openings**
- Accordion list of up to 10 most-played openings
- Collapsed: ECO badge, opening name, game count, win rate, expand chevron
- Expanded: W/D/L totals, White games + win rate, Black games + win rate

**Card 7: Activity & Streaks**
- Monthly game count bar chart (last 12 months)
- Streak stats: Current Win Streak, Best Win Streak, Current Loss Streak, Worst Loss Streak (with colored icons)

---

## Screen 4: Engine Manager

**Header:** "Engine Manager" title, subtitle with engine count

**Engine card grid** (adaptive grid, min 200px per card, max 280px):

Each engine card shows:
- Icon (cloud icon for cloud engines, CPU icon for local engines)
- Engine name
- Status indicator: colored dot — green = Available, orange = Not Found, blue = Online/Cloud
- "Active" badge if this is the default engine

**"Add Engine" card:** Dashed border, plus icon, "Download or import" subtitle

**Per-engine settings panel** (shown below grid when an engine card is selected):
- "Engine Settings" heading
- **Threads** slider (1 to max CPU cores)
- **Hash (MB)** slider (16 to 4096 MB)
- **MultiPV** stepper (1 to 5 lines)
- **Analysis Depth** slider (10 to 80), labels "fast" and "deep"
- Cloud engines only show MultiPV (no local resource settings)

**Context menu on engine cards:**
- "Set as Default" (if not already default)
- "Show in Finder" (local engines only)
- "Remove" (destructive)

### Add Engine Sheet (modal)

Three sections:

**Available for Download:**
- Stockfish — "Strongest open-source engine", download from GitHub releases
- Leela Chess Zero (Lc0) — "Neural network engine", download + optional weights
- Komodo Dragon — external link to website

Each row: colored icon, name, description, action button (Download with progress / Installed checkmark / Website link)

**Cloud Analysis:**
- Lichess Cloud — free cloud evaluation using Lichess API
- "Add" / "Added" toggle

**Add From File:**
- "Browse..." button to select any UCI-compatible engine binary

### Lc0 Weights Sheet (sub-modal, for Lc0 only)

- "Download Neural Network" title
- List of weight file presets:
  - BT4 (Very Large) — ~365 MB, needs 4 GB GPU
  - BT3 (Large) — ~190 MB, needs 2.6 GB GPU
  - T3 (Medium) — ~150 MB, needs 1.8 GB GPU
  - T1 (Small) — ~35 MB, needs 1.6 GB GPU
- Each with download button + progress indicator
- "Skip" button

---

## Screen 5: Settings

Three tabs accessible via a tab bar: **Appearance**, **Engine**, **About**.

### Appearance Tab

**Appearance Mode:**
- Segmented picker: System, Light, Dark

**Board Theme:**
- 6-column grid of theme preview tiles (square)
- Each tile shows a 2x2 light/dark square pattern, or a board image thumbnail
- Selected theme has accent border
- **38 total themes:**
  - 10 solid-color: Classic (cream/brown), Green, Blue, Brown, Purple, Gray, Coral, Ocean, Wood, Midnight
  - 28 image-based: 8 Bit, Bases, Blue Board, Brown Board, Bubblegum, Burled Wood, Dark Wood, Dash, Glass, Graffiti, Green Board, Icy Sea, Light, Lolz, Marble, Metal, Neon, Newspaper, Orange, Overlay, Parchment, Purple Board, Red, Sand, Sky, Stone, Tan, Tournament, Translucent, Walnut

**Piece Style:**
- 6-column grid of piece preview tiles (square)
- Each tile shows a black knight piece on a light square
- Selected style has accent border
- **32 total styles:** Classic, Neo, Modern, Alpha, 8 Bit, Bases, Book, Bubblegum, Cases, Club, Condal, Dash, Game Room, Glass, Gothic, Graffiti, Icy Sea, Light, Lolz, Marble, Maya, Metal, Nature, Neo Wood, Neon, Newspaper, Ocean, Sky, Space, Tigers, Tournament, Vintage, Wood

**Display Options:**
- "Show Coordinates" — toggle (shows rank/file labels on board edge)
- "Highlight Legal Moves" — toggle (shows dots on legal move squares)
- "Show Best Move Arrow" — toggle (shows engine's recommended move as an arrow)

### Engine Tab

**Stockfish Engine:**
- Engine status: green checkmark "Stockfish found" + path, OR orange warning "Stockfish not found", OR spinner "Checking..."
- Custom Engine Path: text field + "Browse..." file picker
- Help text: "Leave empty to auto-detect from /usr/local/bin or /opt/homebrew/bin"
- Analysis Depth: stepper (range 10-80)
- "Auto-analyze moves" toggle

**Performance (display only):**
- Multi-PV: 3 lines
- Threads: 2
- Hash Size: 128 MB

**Installation Help:**
- Homebrew command: `brew install stockfish`
- Link to Stockfish website

### About Tab

- App icon (crown)
- "Chess Analyzer" title
- Version number
- Feature list (bullet points)
- "Built with SwiftUI" footer

---

## Data Capabilities

### Game Database
- **Storage:** SwiftData (SQLite-backed), persisted in app container
- **Organization:** Games organized into folders (databases). Games can be "unfiled" (no folder).
- **Fields per game:** White, Black, Event, Site, Date, Round, Result, ECO code, Opening name, PGN text, Tags, White Elo, Black Elo, Time class, Source username, Source URL, Analysis data
- **Operations:** Add, update, delete, move between folders, bulk operations
- **Search:** Full-text across player names, events, dates
- **Import:** PGN files (single or multi-game), drag-and-drop, Chess.com sync
- **Export:** PGN format, SQLite (.db3) format
- **Statistics:** Total games, W/D/L counts, top 10 players, top 10 openings

### Chess.com Integration
- **API:** Chess.com public API (no authentication needed, just username)
- **Sync:** Fetches game archives (monthly chunks), supports incremental sync from last synced archive
- **Deduplication:** Uses source URL to prevent duplicate imports
- **Stats:** Comprehensive pre-computed statistics cached in database per time class

### Opening Book
- **Source:** Bundled `openings.json` with tree structure
- **Coverage:** Full ECO database (A00-E99, 500 codes) + opening tree for position lookup
- **Lookup:** By UCI move sequence (tries progressively shorter prefixes), by ECO code, by search text

### Engine Integration
- **Protocol:** UCI (Universal Chess Interface)
- **Supported engines:** Stockfish (downloaded from GitHub), Lc0 (with neural network weights), any custom UCI engine binary, Lichess cloud evaluation
- **Features:** Multi-PV (1-5 lines), configurable threads/hash/depth, speculative look-ahead analysis
- **Game analysis:** Full-game automated analysis with move classification, accuracy computation, and annotation assignment
- **Move classification thresholds:**
  - Blunder: >= 200 centipawn loss, or >= 100 cp and position flips, or >= 25% win probability loss
  - Mistake: >= 100 cp loss
  - Inaccuracy: >= 50 cp loss
  - Brilliant: <= 5 cp loss + best move + sacrifice + gap >= 150 cp
  - Great: <= 10 cp loss + not recapture + alternatives much worse
  - Best: rank 1 + <= 10 cp loss
  - Good: rank 2 + <= 20 cp loss
  - Okay: rank 3 + <= 30 cp loss
  - Book: move found in opening book

### Camera Tracking
- **Purpose:** Detect a physical chess board through the Mac's camera and track moves in real-time
- **Process:** Camera feed -> corner detection -> perspective transform -> piece detection (CoreML model) -> move tracking -> board sync
- **States:** Idle, Requesting Permission, Calibrating, Tracking, Board Lost, Paused, Error
- **Features:** Multiple camera support, board flip, grid overlay visualization, FEN detection, move detection with joint (two-move) and greedy (single-move with 1-second timeout) strategies, statistics tracking

### PGN Parser
- **Capabilities:** Multi-game files, full variation/comment support, multiple text encodings (UTF-8, ISO Latin 1, ASCII, Windows CP1252)
- **Output:** Flat move list OR full game tree with variations, comments, and annotations
- **Export:** Full PGN generation from game tree with headers

### Game Tree
- **Structure:** Tree of nodes, each with: move, board state, comment, annotation, evaluation, children (variations)
- **Navigation:** Go to start/end, forward/backward, jump to any node, jump to move number
- **Variation support:** Add variations, promote to main line, demote to subline, delete subtrees
- **Annotations:** !!, !, !?, ?!, ?, ??, *, B (book), + (good), o (okay)
- **PGN export:** Full PGN generation with headers, variations, comments, and annotations

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Left arrow | Previous move |
| Right arrow | Next move |
| Scroll wheel up | Previous move |
| Scroll wheel down | Next move |
| Cmd+N | New Game |
| Cmd+O | Open PGN |
| Cmd+S | Save PGN |
| Cmd+Shift+I | Import PGN Database |
| Cmd+Shift+C | Copy FEN / Camera Tracking |
| Cmd+Shift+V | Paste FEN |
| Cmd+F | Flip Board |
| Cmd+E | Start Engine |
| Cmd+Shift+E | Stop Engine |
| Cmd+A | Analyze Position |
| Cmd+B | Show Best Move |
| Cmd+Option+Left | Go to Start |
| Cmd+Left | Previous Move |
| Cmd+Right | Next Move |
| Cmd+Option+Right | Go to End |

---

## Color Semantics

| Purpose | Color |
|---------|-------|
| Brilliant move | Green (#1ABF66) |
| Great move | Blue (#3387DE) |
| Best move | Light green (#8CCC59) |
| Book move | Brown (#A68C66) |
| Good move | Light blue |
| Okay move | Purple |
| Inaccuracy | Amber (#EDA619) |
| Mistake | Orange (#E87623) |
| Blunder | Red (#D62E2E) |
| Bullet time control | Orange (#E68C33) |
| Blitz time control | Blue (#4DB3D9) |
| Rapid time control | Green (#73AD59) |
| Daily time control | Purple (#9980D9) |
| Chess.com branding | Green (#73AD59) |
| White winning (eval bar) | Light gray (#ECECEC) |
| Black winning (eval bar) | Dark gray (#262626) |
| Accuracy >= 90% | Green |
| Accuracy >= 70% | Yellow |
| Accuracy >= 50% | Orange |
| Accuracy < 50% | Red |

---

## All Modals, Sheets, Alerts, and Popovers

The app has 33 overlay surfaces total (10 sheets, 12 alerts, 1 confirmation dialog, 8 popovers, 2 system file pickers). Here is every one:

### New Database Sheet (420 x 440)

**Triggered by:** "New Folder" button on Database root, clicking the dashed "New Database" card, or "New Database..." in a move-to-folder context menu.

**Contents:**
- Header: "New Database" title, "Cancel" button
- "Database Name" label + text field (placeholder: "My Database")
- "Import PGN (optional)" section:
  - When no files: drop zone with doc icon, "Drop PGN files here" text, "Browse..." button (opens system file picker)
  - When files added: file list with icon + filename + remove (x) button per file, "Add more..." button
  - Supports drag-and-drop of .pgn files onto the drop zone
- Footer: "Create" button (prominent, disabled when name is empty)
- **Produces:** folder name + optional PGN file URLs

### PGN Import Sheet (700 x 500 min, 800 x 600 ideal)

**Triggered by:** "Import PGN" buttons on Database or Game Library screens, or drag-and-drop of PGN files.

**Contents:**
- Header: doc icon, "Import PGN" title, "5 of 10 selected" count text
- **Split view (left + right):**
  - **Left panel (250px min):** "Select All" / "Select None" buttons, scrollable game list with checkboxes. Each row: checkbox, "White vs Black" names, ECO code badge, move count, result badge (color-coded: green=1-0, red=0-1, gray=draw). Selected game highlighted.
  - **Right panel (300px min):** Editable metadata for the selected game:
    - Players group: White name + Elo, Black name + Elo (text fields)
    - Event group: Event name, Round, Site, Date (text fields)
    - Game details group: Result picker (segmented: 1-0, 0-1, 1/2-1/2, *), ECO code, Opening name
    - Moves preview (monospaced, read-only, first 10 moves + "..." if more)
    - Placeholder when no game selected: "Select a game to edit"
- Footer: Destination folder picker ("Default" + all folders), "Cancel" button, "Import N Games" button (disabled when none selected)
- **Loading state:** spinner + "Parsing PGN files..."
- **Error state:** warning icon + error message
- **Import progress state:** progress bar + "X of Y games" count

### Save Game Sheet (500 x 550)

**Triggered by:** "Save" button on the board status bar.

**Contents:**
- Header: "Save Game" title, close (x) button
- Form sections:
  - Players: White text field, Black text field
  - Event Details: Event, Site, Date picker (date only), Result picker (segmented: *, 1-0, 0-1, 1/2-1/2)
  - Save Location: folder picker ("Default" + all folders sorted alphabetically)
  - PGN Preview: read-only monospaced text block (max 8 lines)
- Footer: "Cancel" button, "Export to File..." button (opens system save dialog with default name "White_vs_Black.pgn"), "Save to Library" button (prominent)
- **Success alert:** "Game Saved" — "The game has been saved to your library." with "OK" button that dismisses the sheet

### Chess.com Connect Sheet (400 x 300)

**Triggered by:** "Connect Account" button (when disconnected), or "Account Settings" from the ellipsis menu (when connected).

**Contents:**
- Header: Chess.com icon (green), title ("Connect Chess.com" when new, "Account Settings" when editing), close (x) button
- "Chess.com Username" label + text field (placeholder: "Enter username", pre-populated if editing)
- **Progress section** (during fetch):
  - Progress bar (green fill)
  - Percentage text
  - "Archive X of Y" progress counter
  - Games found count
- **Error section:** warning icon + error message
- Footer: "Disconnect" button (red, destructive, only when already connected), "Cancel" button, "Connect"/"Save" button (prominent, green, shows spinner when loading, disabled when username empty)
- **Behavior:** On connect, fetches all games from Chess.com API. On success, saves username and dismisses. On error, stays open showing the error.

### Chess.com Import Sheet (500 x 550)

**Triggered by:** Can be presented separately for bulk Chess.com import.

**Contents:**
- Header: Chess.com icon (green), "Import from Chess.com" title, close (x) button
- Username text field + "Fetch" button (prominent, disabled when empty/loading)
- **Progress:** Progress bar, percentage, "Archive X of Y", games found count, estimated time remaining
- **Games list:** Selection count ("X of Y selected"), "Select All"/"Deselect All" buttons, scrollable list:
  - Each row: selection circle (checkmark when selected), time class badge (colored: bullet=orange, blitz=blue, rapid=green, daily=purple), player names with ratings, result, date
- Footer: "Last import: ..." info text, "Clear History" button, "Import Selected (N)" button (prominent)
- **Success alert:** "Import Complete" — "Successfully imported N games to your library." with "OK"

### Folder Import Sheet (340 x 320)

**Triggered by:** Drag-and-drop of PGN files onto the game library.

**Contents:**
- Header: folder+ icon, "Import Games" title, file description (filename or "N files")
- Toggle: "Create new database" switch
  - When ON: "Database name" text field (pre-populated from first PGN filename)
  - When OFF: "Select database" picker ("Unfiled" + all folders)
- Footer: "Cancel" button, "Import" button (disabled when creating new folder with empty name)

### Add Engine Sheet (520 x 480)

**Triggered by:** Clicking the "Add Engine" card on Engine Manager.

**Contents:**
- Header: "Add Engine" title, "Close" button
- Scrollable content with 3 sections:
  - **"Available for Download"** section:
    - Stockfish: icon, "Strongest open-source engine" description, Download/Installed/Progress button
    - Leela Chess Zero: icon, "Neural network engine" description, Download button (triggers Lc0 Weights Sheet after download)
    - Komodo Dragon: icon, description, "Website" button (external link)
  - **"Cloud Analysis"** section:
    - Lichess Cloud: cloud icon, "Free cloud analysis — no download needed", Add/Added button
  - **"Or Add From File"** section:
    - "Browse..." button (opens system file picker for UCI engine binary), "Select a UCI engine binary" label
- Status bar: download progress text + spinner when downloading
- Error bar: warning icon + error message

### Lc0 Weights Sheet (460 x 380)

**Triggered by:** Automatically after downloading Lc0 engine.

**Contents:**
- Header: "Download Neural Network" title, "Lc0 requires a neural network weights file to play" subtitle, "Skip" button
- Scrollable list of weight presets:
  - BT4 (Very Large): ~365 MB, needs 4 GB GPU — Download button
  - BT3 (Large): ~190 MB, needs 2.6 GB GPU — Download button
  - T3 (Medium): ~150 MB, needs 1.8 GB GPU — Download button
  - T1 (Small): ~35 MB, needs 1.6 GB GPU — Download button
  - Each with download progress indicator
- Status bar: download progress + spinner

### Move Note Editor Popover (280px wide)

**Triggered by:** Right-click context menu "Add Note" or "Edit Note" on any move in the move list.

**Contents:**
- "Move Note" title
- Multi-line text editor (min height 80, max height 150), pre-populated with existing comment
- "Cancel" button, "Save" button (prominent, disabled when text is empty for new notes)

### Database Filter Popovers (various)

#### Player/Opening/Tournament Picker Popover (280px wide, 320px scroll height)

**Triggered by:** Clicking a filter field in the Database filter panel (4 instances: White Player, Black Player, Opening, Tournament).

**Contents:**
- Title (e.g. "White player", "Opening", "Tournament")
- Search field with magnifying glass icon + clear button
- Scrollable list of matching names from database
- "No results" empty state
- Clicking an item selects it and dismisses

#### Game Library Filters Popover (340px wide)

**Triggered by:** Filter button on the Game Library sidebar.

**Contents:**
- Header: "Filters" title, "Reset" button (red, shown when filters active)
- Scrollable sections:
  - **Time Control:** pill buttons — All, Bullet, Blitz, Rapid, Daily
  - **Result:** pill buttons — All, 1-0, 0-1, Draw
  - **Played As** (only if Chess.com username exists): pill buttons — All, White, Black
  - **Opening:** search field + scrollable flow layout of opening family pills (max 150px height)
  - **Date Range:** "From" date picker + clear button, "To" date picker + clear button
- Footer: active filter count, "Done" button (accent pill)

#### Chess.com Filters Popover (340px wide)

**Triggered by:** Filter button on the Chess.com Games tab.

**Contents:**
- Header: "Filters" title, "Reset" button (red)
- Scrollable sections:
  - **Time Control:** pill buttons — All, Bullet, Blitz, Rapid, Daily (green when active)
  - **Result:** pill buttons — All, Wins, Losses, Draws (green when active)
  - **Played As:** pill buttons — All, White, Black (green when active)
  - **Opening:** search field + quick-pick flow layout pills: Sicilian, French, Caro-Kann, Italian, Spanish, Queen's Gambit, King's Indian, English
  - **Date Range:** two date pickers with clear buttons
- Footer: active count, "Done" button (green pill)

### Library Explorer Folder Picker Popover (220px wide, 200px scroll height)

**Triggered by:** Folder button in the Library Explorer toolbar.

**Contents:**
- "Select Databases" title
- "All" / "None" quick-select buttons
- Scrollable checkbox list: "Unfiled Games" + each database folder
- Each row: checkbox icon (filled when selected) + folder name

### Alerts (simple confirmations)

| Alert | Trigger | Title | Message | Buttons |
|-------|---------|-------|---------|---------|
| Import Success/Error | After PGN import | "Import Successful" or "Import Error" | Result message | OK |
| Rename Database | Context menu "Rename..." on folder | "Rename Database" | Text field for new name | Cancel, Rename |
| Delete Database (2-button) | Context menu "Delete..." on Database screen | "Delete Database" | "This will permanently delete this database and all its games." | Cancel, Delete (destructive) |
| Delete Database (3-button) | Context menu "Delete..." on Game Library | "Delete Database" | "Delete games in this database or keep them?" | Cancel, Keep Games, Delete Games (destructive) |
| New Database (simple) | "New Database..." in Game Library folder menu | "New Database" | Text field for name | Cancel, Create |
| Delete All | Trash button on Game Library | "Delete All" | "Delete all games and databases? This cannot be undone." | Cancel, Delete All (destructive) |
| New Database + Move | "New Database..." in move-to-folder menu (Chess.com) | "New Database" | "Create a new database and move N game(s) into it." + text field | Cancel, Create & Move |
| Game Saved | After saving to library | "Game Saved" | "The game has been saved to your library." | OK (dismisses sheet) |
| Import Complete | After Chess.com import | "Import Complete" | "Successfully imported N games to your library." | OK |

### Export Format Confirmation Dialog

**Triggered by:** Context menu "Export..." on a folder card.

**Contents:**
- Title: "Export [folder name]"
- Two format options: "PGN (.pgn)", "SQLite (.db3)"
- Cancel button
- Selecting a format opens a system save dialog with the appropriate file extension

---

## All Context Menus (Right-Click)

### Move List — Right-click any move
- "Add Note" / "Edit Note" (opens note editor popover)
- "Delete Note" (destructive, only when note exists)
- Separator
- "! Good move" — sets annotation
- "!! Brilliant move" — sets annotation
- "? Mistake" — sets annotation
- "?? Blunder" — sets annotation
- "!? Interesting move" — sets annotation
- "?! Dubious move" — sets annotation
- "Clear annotation" — removes annotation
- Separator
- "Promote to Main Line" (only on non-main-line variations)
- "Make Subline" (only on main line moves with siblings)
- "Delete from here" (destructive — deletes move and all descendants)

### Database — Right-click a folder card
- "Rename..."
- "Export..."
- "Delete..." (destructive)

### Database — Right-click a game row
- "Open" — loads game in analysis
- "Move to..." — submenu listing all folders + "New Database..."
- "Delete" (destructive, batch-deletes if multi-selected)

### Chess.com — Right-click a game row
- "Open Game" — loads game in analysis
- "Move to..." / "Move N Games to..." — submenu listing all folders + "New Database..."
- "Deselect All" (only when multiple selected)

### Engine Manager — Right-click an engine card
- "Set as Default" (hidden if already default)
- "Show in Finder" (hidden for cloud engines)
- "Remove" (destructive)

### Game Library — Right-click a game row
- "Open" — loads game
- "Export..." — opens system save dialog for PGN
- "Move to..." / "Move N games to..." — submenu listing all folders
- "Delete" (destructive)

---

## Design Considerations

- The app should support both **light and dark mode** natively
- The analysis screen is the primary screen — users spend 80%+ of their time here
- The board must always be square and as large as possible given the window size
- The explorer panel (left) and analysis panel (right) are dense information panels that need good information hierarchy
- The move list needs to handle deeply nested variations (3-4 levels of indentation)
- Database tables need to handle thousands of games with virtual scrolling
- Stats view has rich data visualizations (donut charts, line charts, bar charts, horizontal stacked bars)
- Engine analysis lines update in real-time as the engine thinks
- The evaluation bar animates smoothly between positions
- The game analysis progress needs clear feedback (progress bar, percentage, current move)
- Filter panels appear on multiple screens (Database, Chess.com) with different filter sets
- The camera tracking feature is experimental and secondary to the main analysis workflow
