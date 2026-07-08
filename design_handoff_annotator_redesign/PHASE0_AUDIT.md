# Phase 0 — Codebase Audit ("The Annotator" redesign)

Read-only audit mapping the existing SwiftUI codebase to the Annotator design codes.
No product code changed in this phase.

## Where the design system lives today
- **`Utils/DesignSystem.swift`** — the single `DS` token enum (colors, type, spacing, radii,
  animations) **plus** all glassmorphism (`Glass*` structs/modifiers, `.ultraThinMaterial`,
  radial/linear gradients, glows, shadows). Today: Apple-blue accent, SF system fonts, **green**
  board (`#EBECD0`/`#739552`), radii 6/8/12/20, spacing 4–48. → **Full replacement in Phase 1.**
- **`Utils/AppSettings.swift`** — `AppAppearance` (system/light/dark), 38 board themes,
  33 piece styles, board/coord/arrow toggles, engine configs. Feeds S1–S3.
- **`ChessAnalyzerApp.swift`** — `WindowGroup`, `.windowStyle(.hiddenTitleBar)`, app-level
  `.preferredColorScheme(appAppearance)`, menu commands, NSWindow transparency tweaks.
- **`Views/Components/IconRailView.swift`** — current nav: 64px **left glass icon rail**;
  `AppScreen` enum = analysis/database/repertoire/chesscom/engine/settings.
- **`Views/MainWindowView.swift`** — 3-column `analysisLayout` + `ContentSwitcher`;
  **hardcodes `.preferredColorScheme(.dark)` (line ~122)** — this override is why the app is
  always dark. Remove in Phase 1.

## Mapping: existing → design code
| Design | Existing views |
|---|---|
| **§00 System / chrome** | `DesignSystem.swift`, `AppSettings.swift`, `ChessAnalyzerApp.swift`, `IconRailView.swift`, `MainWindowView` shell |
| **01 Analysis** A1/A2/A3 | `MainWindowView.analysisLayout`, `BoardView`, `AnalysisPanelView`(×4), `MoveListView`(×12), `EvaluationBar`, `EvaluationGraphView` (Game-Review sparkline), `CurrentOpeningView`, `BoardStatusBar`, `KnightLoader` |
| **02 Explorer** E1/E2 | `LichessExplorerView`, `LibraryExplorerView`, `ExplorerMoveRow`, `ExplorerGameRow`, `WDLStatsBar`, `IndexingSheet` (E2), `ReferenceActivityBadge` — **+ NEW standalone screen** |
| **03 Repertoire** R1–R5 | `RepertoireBrowserView`(R1), `RepertoireEditorView`+`RepertoireMoveTreeView`(R2), `RepertoireDrillView`(R3), `RepertoireStatsView`+`CoverageGapView`(R4), `RepertoireDeviationBadge`; R5 sheet = new |
| **04 Games** G1–G3 | `ChessComBrowserView`(G1), `ChessComStatsView`(G2), `ChessComTabView`, `ChessComImportView`(G3) |
| **05 Database** D1–D5 | `DatabaseBrowserView` (D1; fold root grid → sidebar; `FilterInlineList`→D2 drawer; `NewDatabaseSheet`→D5), `GameLibraryView`, `ReferenceBrowseView`, `PGNImportView`(D3), `SaveGameView`(D4), `FolderImportSheet` |
| **06 Engines** N1/N2 | `EngineManagerView`(×4) + add-engine sheet (`EngineDownloadService`) |
| **07 Settings** S1–S3 | `PreferencesView`/`SettingsScreenView`(×8) |
| **08 Empty** ES1–ES4 | `EmptyStateView` (shared) + per-screen |

### Primitives (§00 gallery) → existing
`Glass*` buttons → red-primary / bordered / disabled · `glassToggle` 36×20 → **36×21 red** ·
ad-hoc segmenteds (explorer picker, result seg) → standard · `WDLStatsBar` → **monochrome** ·
`MoveListView` rows + quality marks · `AnalysisPanelView` eval chip / PV row ·
`ECOBadge`/`SectionLabel`/`*Badge` chips · `EmptyStateView` · `KnightLoader` → **pulsing dots** ·
`.sheet` → Annotator sheet chrome.

## Dark-mode handling
App-level `appAppearance` → `.preferredColorScheme`, colors via `DS.adaptive(light:dark:)`
(NSColor appearance). **`MainWindowView` hardcodes `.dark`** (remove). Rename modes →
**System / Reading Room / Night Study**. Board must stay sepia regardless of mode.

## Glass / blur / gradient inventory (Phase 4 sweep)
All `Glass*` in `DesignSystem.swift` + usages in: `MainWindowView`, `IconRailView`,
`AnalysisPanelView`, `DatabaseBrowserView`, `EngineManagerView`, `ChessComBrowserView`,
`ChessComStatsView`, `MoveListView`, `PreferencesView`, `RepertoireBrowserView`,
`RepertoireDrillView`, `RepertoireEditorView`, `EvaluationBar`, `KnightLoader`,
`ReferenceActivityBadge`. Plus inline `Color(hex:)` / `.font(.system(...))` across many views.

## Flags for design review (defaults derived from tokens + primitives)
1. **EXPLORER becomes a top-level tab** (today only a panel inside Analysis). Analysis keeps its
   own explorer column; the standalone screen reuses the same components.
2. **Engines + Settings aren't in the 5 masthead tabs.** Proposed: right-side masthead icon
   buttons (gear = Settings via ⌘,, cpu = Engines).
3. **Board-theme picker (38) vs "board is always sepia":** keep picker, default = Annotator sepia,
   light/dark mode never overrides board colors.
4. **Screens the design doesn't cover** (derive + flag): `CoverageGapView`, `ChessComImportView`,
   PGN-import flows, Lichess-auth, `SaveGameView` details.
5. **`KnightLoader`** (branded spinner) → replaced by pulsing dots per the motion rule.

## Phase plan (as given)
1. Tokens & fonts (both modes, bundle 3 fonts, mode switching, retire old palette).
2. Chrome & primitives (masthead, status bar, window; §00 component gallery).
3. Screens: Analysis → Explorer → Repertoire → Games → Database → Engines → Settings → empty states.
4. Sweep (old hexes/fonts/glass/gradients) + verify every screen in both modes.
