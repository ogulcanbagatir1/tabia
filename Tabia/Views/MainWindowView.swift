import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// Opening explorer data source — shared by the analysis screen and the repertoire editor.
enum ExplorerSource: String, CaseIterable {
    case lichess = "Lichess Masters"
    case library = "My Library"
}

struct MainWindowView: View {
    @StateObject private var board = ChessBoard()
    @StateObject private var gameTree = GameTree()
    @StateObject private var multiEngine = MultiEngineManager()
    // Analysis boards (tabs). The live board/gameTree above are the ACTIVE session's working copy;
    // switching a tab swaps the tree node references in/out (lossless, instant). Tabs hold analysis
    // boards only — repertoire/explorer/etc. are rail sections, never tabs.
    @StateObject private var windowModel = WindowModel()
    @EnvironmentObject var database: GameDatabase
    @EnvironmentObject var repertoireDB: RepertoireDatabase
    @StateObject private var openingBook = OpeningBook.shared
    @StateObject private var gameAnalyzer = GameAnalyzer()
    @StateObject private var lichessExplorer = LichessExplorerService()
    @StateObject private var libraryExplorer = LibraryExplorerService()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettingsAction
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRestoreTabs = false

    // Auto-analyze lives in AppSettings so the Preferences toggle and the in-app ⌃A toggle are the
    // same switch, and the choice survives relaunch.
    /// Set by ⇧⌘R; consumed by RepertoireBrowserView once that screen is mounted.
    @State private var pendingNewRepertoire = false
    /// Screens built so far. See `screenStack`.
    @State private var visitedScreens: Set<AppScreen> = []

    // Screen state that has to outlive the screen. Deliberately `@State` and not `@StateObject`:
    // this keeps the object alive for the window without subscribing to it, so a filter change in
    // the Library never invalidates MainWindowView — only the Library, and only while it is mounted.
    @State private var databaseState = DatabaseBrowserState()
    @State private var chessComState = ChessComBrowserState()
    @State private var repertoireState = RepertoireBrowserState()
    @State private var showingSidebar = true
    @State private var showingSaveSheet = false
    @State private var showingSetupPosition = false
    @State private var arrowMonitor: Any? = nil
    @State private var evaluationDebounceTask: DispatchWorkItem?
    @State private var isSyncingBoard = false
    // Suppresses the dirty flag while we're loading/swapping a game (not a user edit).
    @State private var suppressDirty = false
    // Index of a dirty tab awaiting a Save / Don't Save / Cancel decision on close.
    @State private var tabPendingClose: Int? = nil
    @State private var whiteName: String = ""
    @State private var blackName: String = ""
    @State private var whiteRating: String = ""
    @State private var blackRating: String = ""

    // Opening tracking
    @State private var currentOpeningName: String? = nil
    @State private var currentOpeningECO: String? = nil

    // Loaded-game metadata for the move-list header (event + result).
    @State private var currentEvent: String = ""
    @State private var currentResult: String = ""
    @State private var currentTimeClass: String? = nil
    // Move sequences cached per position so the analysis view body doesn't re-walk the whole line
    // (several times) on every re-render — recomputed once when the position changes.
    @State private var cachedUCI: [String] = []
    @State private var cachedSAN: [String] = []

    // Current loaded game (for saving analysis back)
    @State private var currentGameId: UUID? = nil

    // Repertoire recording: when the active tab was opened from the Repertoire library, moves played
    // on the board are persisted into this repertoire. repNodeMap bridges gameNode.id → repNode.id.
    @State private var activeRepertoire: Repertoire? = nil
    @State private var repNodeMap: [UUID: UUID] = [:]
    @State private var isHydratingRep = false

    // Board flip
    @State private var isBoardFlipped = false

    // Look-ahead: track which node we're speculatively analyzing
    @State private var lookAheadNodeId: UUID?

    // Active screen (masthead navigation). TABIA_SCREEN env overrides the initial screen (dev aid).
    @State private var activeScreen: AppScreen = {
        if let s = ProcessInfo.processInfo.environment["TABIA_SCREEN"], let scr = AppScreen(rawValue: s) { return scr }
        return .analysis
    }()

    // Explorer source toggle
    @State private var explorerSource: ExplorerSource = .lichess
    @State private var explorerSearchText = ""
    // The best-move arrow now lives in EngineArrowBoard (a leaf that observes the engine), so the
    // window body no longer reads the engine's per-tick analysisLines. See AnnBoardArea.swift.

    // Sidebar constraints
    private let minExplorerWidth: CGFloat = 280
    private let minRightSidebarWidth: CGFloat = 300
    private let iconRailWidth: CGFloat = DS.iconRailWidth

    /// Screens are built once and then kept, rather than torn down and rebuilt on every visit.
    ///
    /// Measured: the first mount of the Library costs 150–270 ms of blocked main thread (SwiftUI
    /// building and laying out the tree, plus CoreText resolving the bundled faces), while a second
    /// visit to an already-built screen costs nothing. Switching used to pay that price every time.
    ///
    /// Keeping them alive is only safe because these screens are `.equatable()` on their state
    /// object: an off-screen screen no longer re-renders when the window ticks. Screens are added on
    /// first visit, so launch still builds only Analysis.
    @ViewBuilder private var screenStack: some View {
        ZStack {
            if visitedScreens.contains(.analysis) || activeScreen == .analysis {
                analysisLayout.screenLayer(active: activeScreen == .analysis)
            }
            if visitedScreens.contains(.database) {
                DatabaseBrowserView(onGameSelected: { game in
                    openGameInTab(game)
                }, onReferenceGameSelected: { pgn in
                    newTab()
                    loadGameFromPGN(pgn)
                }, onReviewGame: { game in
                    reviewGame(game)
                }, state: databaseState)
                .equatable()
                .screenLayer(active: activeScreen == .database)
            }
            if visitedScreens.contains(.repertoire) {
                RepertoireBrowserView(onOpen: { rep in openRepertoireInTab(rep) },
                                      onOpenGame: { game in openGameInTab(game) },
                                      browserState: repertoireState,
                                      pendingNewRepertoire: $pendingNewRepertoire)
                .equatable()
                .screenLayer(active: activeScreen == .repertoire)
            }
            if visitedScreens.contains(.chesscom) {
                ChessComBrowserView(onGameSelected: { game in
                    openGameInTab(game)
                }, onReviewGame: { game in
                    reviewGame(game)
                }, state: chessComState)
                .equatable()
                .screenLayer(active: activeScreen == .chesscom)
            }
            // Rarely visited and cheap to build — no reason to keep these resident.
            if activeScreen == .engine { EngineManagerView() }
            if activeScreen == .settings { SettingsScreenView() }
        }
        .onChange(of: activeScreen) { _, screen in visitedScreens.insert(screen) }
        .onAppear { visitedScreens.insert(activeScreen) }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Masthead — wordmark · centered nav tabs · contextual actions + settings gear.
            // Hidden in Drill mode (focused mode) — handled inside RepertoireBrowserView's drill.
            titlebarStrip
            HStack(spacing: 0) {
                RailView(selected: $activeScreen, onSettings: openSettingsWindow)
                    .equatable()
                screenStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(GlassBackground(screen: activeScreen))
        .background { tabShortcutButtons }
        // Let the masthead rise into the title-bar band so the wordmark sits on the same
        // line as the native traffic lights (it reserves horizontal room for them).
        .ignoresSafeArea(.container, edges: .top)
        .overlay { ReferenceActivityBadge() }
        .errorBannerHost()
        .sheet(isPresented: $showingSaveSheet) {
            SaveGameView(gameTree: gameTree, database: database,
                         onSavedGame: { linkTabToGame($0) },
                         onSavedRepertoire: { linkTabToRepertoire($0) })
                .environmentObject(repertoireDB)
        }
        .confirmationDialog("This board has unsaved changes.",
                            isPresented: Binding(get: { tabPendingClose != nil },
                                                 set: { if !$0 { tabPendingClose = nil } }),
                            titleVisibility: .visible) {
            Button("Save…") {
                if let i = tabPendingClose {
                    if i != windowModel.activeIndex { selectTab(i) }
                    if activeRepertoire != nil {
                        saveActiveTab()          // update the repertoire, then close
                        performCloseTab(i)
                    } else {
                        showingSaveSheet = true
                    }
                }
                tabPendingClose = nil
            }
            Button("Don't Save", role: .destructive) {
                if let i = tabPendingClose { performCloseTab(i) }
                tabPendingClose = nil
            }
            Button("Cancel", role: .cancel) { tabPendingClose = nil }
        }
        .sheet(isPresented: $showingSetupPosition) {
            SetUpPositionView(onSetup: { fen in
                setupPosition(fen: fen)
                activeScreen = .analysis
            })
        }
        .onAppear {
            if !didRestoreTabs { didRestoreTabs = true; restoreTabs() }
            startEngineIfConfigured()
            refreshMoveSequences()
            updateCurrentOpening()
            if activeScreen == .analysis { installArrowMonitor() }
        }
        .onDisappear { removeArrowMonitor() }
        .onChange(of: scenePhase) { _, phase in
            // Persist on background only (not on every ⌘-Tab .inactive) — tab ops + willTerminate
            // already cover the frequent cases, so this is just a minimize/hide safety net.
            if phase == .background { persistTabs() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            // macOS may quit without a scenePhase→background transition, so persist on terminate too.
            persistTabs()
        }
        .onChange(of: activeScreen) { _, s in
            if s == .analysis { installArrowMonitor() } else { removeArrowMonitor() }
        }
        // Menu-bar commands (posted from the Scene-level command set) run here in view context.
        // Merged into one subscription so the type-checker stays fast.
        .onReceive(Self.menuCommandPublisher) { note in handleMenuCommand(note.name) }
        .onReceive(NotificationCenter.default.publisher(for: .tabiaOpenMyGames)) { _ in
            activeScreen = .chesscom
        }
        .onChange(of: gameTree.structureVersion) { _, _ in
            // A structural edit (move added / deleted / promoted) makes the active board dirty —
            // unless we're mid-load/swap. Dirty drives the amber tab dot + close-save prompt (§3.3).
            if !suppressDirty { windowModel.active.isDirty = true }
        }
        .onChange(of: gameTree.currentNode.id) { _, _ in
            refreshMoveSequences()
            syncBoardWithGameTree()
            updateCurrentOpening()

            let engine = multiEngine.primaryEngine

            if gameTree.currentNode.id == lookAheadNodeId {
                // Navigated to the look-ahead position — promote speculative results
                multiEngine.promoteSpeculative()
                lookAheadNodeId = nil
                // Analysis is already running for this position, don't re-evaluate
            } else {
                // Different position — discard look-ahead, evaluate normally
                if lookAheadNodeId != nil {
                    multiEngine.discardSpeculative()
                    lookAheadNodeId = nil
                }

                // Use cached evaluation for instant visual feedback (no flash to 0)
                if let cachedEval = gameTree.currentNode.evaluation {
                    engine.evaluation = cachedEval
                }

                if settings.autoAnalyze && !gameAnalyzer.isAnalyzing {
                    evaluatePositionDebounced()
                }
            }
        }
        .onChange(of: multiEngine.selectedIsThinking) { _, isThinking in
            let engine = multiEngine.primaryEngine
            if !isThinking {
                if gameAnalyzer.isAnalyzing {
                    // Game analysis in progress — feed next position to selected engine
                    if let nextBoard = gameAnalyzer.onEngineFinished(engine: engine) {
                        engine.evaluatePosition(board: nextBoard, depth: gameAnalyzer.analysisDepth, movetime: gameAnalyzer.analysisMovetime)
                    } else if gameAnalyzer.isCompleted {
                        // Analysis finished — save to database and go to start
                        saveAnalysisToDatabase()
                        gameTree.goToStart()
                        syncBoardWithGameTree()
                        evaluatePositionDebounced()
                    }
                } else if let eval = engine.evaluation {
                    // Normal single-position analysis — cache eval on current node
                    gameTree.currentNode.evaluation = eval

                    // Start look-ahead for the next position in the game tree
                    if settings.autoAnalyze, lookAheadNodeId == nil,
                       let nextChild = gameTree.currentNode.children.first {
                        lookAheadNodeId = nextChild.id
                        let nextBoard = nextChild.boardState.copy()
                        multiEngine.evaluateSpeculative(board: nextBoard, depth: settings.engineDepth)
                    }
                }
            }
        }
        .onChange(of: settings.engineConfigsJSON) { _, _ in
            // Engine config changed (added, removed, or switched default) — reconfigure
            multiEngine.reconfigure()
        }
        .onChange(of: activeScreen) { _, newScreen in
            // When switching to analysis, ensure engine is running if configured
            if newScreen == .analysis && settings.defaultEngine != nil && !multiEngine.anyEngineAvailable {
                startEngineIfConfigured()
            }
        }
        .background(
            KeyboardNavigationHandler(
                onLeftArrow: {
                    DispatchQueue.main.async {
                        _ = gameTree.goBack()
                    }
                },
                onRightArrow: {
                    DispatchQueue.main.async {
                        _ = gameTree.goForward()
                    }
                }
            )
        )
    }

    // MARK: - Titlebar (A6) — traffic-light zone · board tab · + · right actions

    private var titlebarStrip: some View {
        let count = windowModel.sessions.count
        return HStack(spacing: 0) {
            // Native traffic lights live here. Painted as the rail so the column runs unbroken from
            // the top of the window, carrying the rail's own trailing divider.
            DS.railBg
                .frame(width: DS.railWidth)
                .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }

            // The tab lane claims whatever is left between the rail and the trailing actions. Reading
            // its width here is what lets tabs shrink to fit instead of overflowing at a fixed size.
            GeometryReader { geo in
                let width = tabWidth(forLaneWidth: geo.size.width, count: count)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(windowModel.sessions.enumerated()), id: \.element.id) { index, session in
                            let isActive = index == windowModel.activeIndex
                            BoardTabView(
                                title: isActive ? boardTabTitle : session.title,
                                active: isActive,
                                indicator: tabIndicator(for: session, active: isActive),
                                showClose: count > 1,
                                width: width,
                                onSelect: { selectTab(index) },
                                onClose: { closeTab(index) },
                                onRename: { renameTab(index, $0) }
                            )
                            .equatable()
                        }
                        NewTabButton(action: { newTab() })
                    }
                    .frame(height: DS.titlebarHeight)
                }
            }

            HStack(spacing: 10) { mastheadActions }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .layoutPriority(1)   // actions size to content; the lane absorbs the rest
        }
        .frame(height: DS.titlebarHeight)
        .background(DS.adaptive(light: 0xEDE5D3, dark: 0x211C13))
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    /// Chrome-style tab sizing: tabs share the lane evenly, growing no wider than `maxTabWidth` and
    /// shrinking as more open. At `minTabWidth` they stop shrinking and the lane scrolls instead —
    /// otherwise a dozen tabs would each be a few unreadable pixels.
    private func tabWidth(forLaneWidth lane: CGFloat, count: Int) -> CGFloat {
        let maxTabWidth: CGFloat = 232
        let minTabWidth: CGFloat = 96
        let newTabButtonWidth: CGFloat = 36      // 30pt glyph + its 6pt leading padding

        guard count > 0, lane > 0 else { return maxTabWidth }
        let usable = max(0, lane - newTabButtonWidth)

        // A lone tab gets extra room — there is nothing to share with.
        if count == 1 { return max(minTabWidth, min(280, usable)) }

        return max(minTabWidth, min(maxTabWidth, usable / CGFloat(count)))
    }

    private func tabIndicator(for session: BoardSession, active: Bool) -> TabLeadingIndicator {
        if active {
            // Coarse mirrors on the manager — the window never touches the engine's fine eval stream.
            if multiEngine.selectedIsFrozen { return .frozen }
            if multiEngine.selectedIsThinking { return .engineLive }
            return session.isDirty ? .dirty : .none
        }
        if session.isDirty { return .dirty }
        if session.snapEval != nil { return .frozen }
        return .none
    }

    private var boardTabTitle: String {
        if let c = windowModel.active.customTitle, !c.isEmpty { return c }
        let w = whiteName.isEmpty ? "" : surnameShort(whiteName)
        let b = blackName.isEmpty ? "" : surnameShort(blackName)
        if !w.isEmpty || !b.isEmpty {
            let players = "\(w.isEmpty ? "?" : w) — \(b.isEmpty ? "?" : b)"
            if let o = currentOpeningName, !o.isEmpty { return "\(players) · \(o)" }
            return players
        }
        if let o = currentOpeningName, !o.isEmpty { return o }
        return "New board"
    }

    private func surnameShort(_ name: String) -> String {
        name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? name
    }

    // MARK: - Tab session management (TABS-AND-RAIL §3.1)

    /// Snapshot the live board/game/metadata + engine eval into the active session.
    private func captureActiveSession() {
        let s = windowModel.active
        s.rootNode = gameTree.root
        s.cursorNode = gameTree.currentNode
        s.isFlipped = isBoardFlipped
        s.whiteName = whiteName; s.blackName = blackName
        s.whiteRating = whiteRating; s.blackRating = blackRating
        s.event = currentEvent; s.result = currentResult
        s.timeClass = currentTimeClass
        s.openingName = currentOpeningName; s.openingECO = currentOpeningECO
        s.currentGameId = currentGameId
        s.repertoireId = activeRepertoire?.id
        s.repNodeMap = repNodeMap
        s.title = boardTabTitle
        let e = multiEngine.primaryEngine
        s.snapEval = e.evaluation
        s.snapDepth = e.depth
        s.snapFEN = gameTree.currentNode.boardState.getFEN()
        // Retain the full review with the tab. Returns nil unless a pass completed, so a move that
        // reset the analyzer clears the stored review too.
        s.analysisData = gameAnalyzer.exportAnalysisData()
    }

    private func beginBoardLoad() { suppressDirty = true }
    private func endBoardLoad(clean: Bool) {
        if clean { windowModel.active.isDirty = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { suppressDirty = false }
    }

    /// Load the active session's stored game/metadata into the live board (lossless node swap).
    private func applyActiveSession() {
        let s = windowModel.active
        beginBoardLoad()
        isSyncingBoard = true
        gameTree.root = s.rootNode
        gameTree.currentNode = s.cursorNode
        gameTree.rebuildMainLine()
        board.restoreState(from: s.cursorNode.boardState)
        isBoardFlipped = s.isFlipped
        whiteName = s.whiteName; blackName = s.blackName
        whiteRating = s.whiteRating; blackRating = s.blackRating
        currentEvent = s.event; currentResult = s.result
        currentTimeClass = s.timeClass
        currentOpeningName = s.openingName; currentOpeningECO = s.openingECO
        currentGameId = s.currentGameId
        repNodeMap = s.repNodeMap
        activeRepertoire = s.repertoireId.flatMap { id in repertoireDB.repertoires.first { $0.id == id } }
        isSyncingBoard = false
        refreshMoveSequences()
        // Bring the tab's own review back (if it had one) rather than blanking it. Positional restore
        // needs the freshly-rebuilt main line above, so it runs here.
        if let ad = s.analysisData {
            gameAnalyzer.restoreFromAnalysisData(ad, gameTree: gameTree)
        } else {
            gameAnalyzer.reset()
        }
        endBoardLoad(clean: false)   // keep the session's own dirty state across the swap
        // Show the frozen eval instantly for visual continuity. The currentNode swap above fires
        // onChange(currentNode.id), which re-targets the engine at the new position — so we do NOT
        // trigger a second search here (that raced the first and desynced the UCI flush).
        if let ev = s.snapEval { multiEngine.primaryEngine.evaluation = ev }
    }

    /// Switch to tab `index` (capture current, swap in the target session).
    /// The single shared engine follows the active position — swapping the board re-points its
    /// search (stop-old + go-new inside evaluatePosition), so there is exactly ONE search running,
    /// on the active tab. No manual pause: a redundant bare "stop" here desyncs the UCI flush and
    /// wedges the engine.
    private func selectTab(_ index: Int) {
        activeScreen = .analysis
        guard index != windowModel.activeIndex, windowModel.sessions.indices.contains(index) else { return }
        captureActiveSession()
        windowModel.activeIndex = index
        applyActiveSession()
    }

    /// Create a new empty board and jump to Analysis (§3.7).
    private func newTab() {
        captureActiveSession()
        windowModel.newBoard()
        applyActiveSession()
        activeScreen = .analysis
        persistTabs()
    }

    private func closeTab(_ index: Int) {
        // A dirty board asks to save first (§3.3); clean tabs close silently.
        if windowModel.sessions.indices.contains(index), windowModel.sessions[index].isDirty {
            tabPendingClose = index
            return
        }
        performCloseTab(index)
    }

    private func performCloseTab(_ index: Int) {
        let wasActive = index == windowModel.activeIndex
        // Always sync the live gameTree back into the active session FIRST — otherwise the tab being
        // closed (or the current one) still points at a stale seed tree, so WindowModel.closeTab's
        // isEmpty/pushClosed decision is wrong and ⌘⇧T reopen restores nothing.
        captureActiveSession()
        _ = windowModel.closeTab(at: index)
        if wasActive {
            applyActiveSession()   // re-points the engine to the newly-active board
        }
        activeScreen = .analysis
        persistTabs()
    }

    /// Open a library game as a new tab, or focus the existing tab if already open (§3.7).
    private func openGameInTab(_ game: GameRecord) {
        if let existing = windowModel.indexHoldingGame(game.id) {
            selectTab(existing)
            return
        }
        newTab()
        loadGame(game)
    }

    /// Save — write the active tab's edits back into whatever it's linked to (its repertoire or its
    /// library game). A tab that isn't linked to anything yet falls through to Save As (the sheet).
    private func saveActiveTab() {
        if let rep = activeRepertoire {
            reconcileRepertoire(rep)
            windowModel.active.isDirty = false
        } else if let gameId = currentGameId, let game = database.game(withId: gameId) {
            game.pgn = gameTree.toPGN(headers: linkedGameHeaders())
            if !whiteName.isEmpty { game.white = whiteName }
            if !blackName.isEmpty { game.black = blackName }
            if !currentResult.isEmpty { game.result = currentResult }
            if !currentEvent.isEmpty { game.event = currentEvent }
            database.updateGame(game)
            windowModel.active.isDirty = false
        } else {
            showingSaveSheet = true
        }
    }

    /// Save As — always mint a NEW game or repertoire (via the sheet), then link the tab to it so
    /// the next plain Save updates that same entity instead of spawning another copy.
    private func saveAsActiveTab() { showingSaveSheet = true }

    /// Label for the Save affordance, reflecting what a plain Save will write to.
    private var saveActionLabel: String {
        if activeRepertoire != nil { return "Save to Repertoire" }
        if currentGameId != nil { return "Save Game" }
        return "Save"
    }

    private func linkedGameHeaders() -> [String: String] {
        var h: [String: String] = [:]
        if !whiteName.isEmpty { h["White"] = whiteName }
        if !blackName.isEmpty { h["Black"] = blackName }
        if !currentEvent.isEmpty { h["Event"] = currentEvent }
        if !currentResult.isEmpty { h["Result"] = currentResult }
        return h
    }

    /// After Save As creates a game, bind this tab to it (so plain Save updates it, no duplicates).
    private func linkTabToGame(_ record: GameRecord) {
        activeRepertoire = nil
        currentGameId = record.id
        let s = windowModel.active
        s.repertoireId = nil
        s.repNodeMap = [:]
        s.currentGameId = record.id
        s.isDirty = false
    }

    /// After Save As creates a repertoire, bind this tab to it by matching the live tree to the new
    /// repertoire's nodes (move-by-move), so plain Save reconciles into it instead of forking again.
    private func linkTabToRepertoire(_ rep: Repertoire) {
        repNodeMap = repertoireNodeMap(root: gameTree.root, repertoire: rep)
        currentGameId = nil
        activeRepertoire = rep
        let s = windowModel.active
        s.currentGameId = nil
        s.repertoireId = rep.id
        s.repNodeMap = repNodeMap
        s.customTitle = rep.name
        s.title = rep.name
        s.isDirty = false
        windowModel.objectWillChange.send()
    }

    /// Match a live tree against a repertoire's nodes move-by-move, producing the gameNode → repNode
    /// bridge that `reconcileRepertoire` needs. Used both when Save As mints a repertoire and when a
    /// repertoire tab is restored from disk — the restored tree is rebuilt from PGN, so its node ids
    /// are fresh and the persisted map would be meaningless.
    private func repertoireNodeMap(root: GameNode, repertoire rep: Repertoire) -> [UUID: UUID] {
        guard let rootRepId = rep.rootNodeId,
              let rootRep = rep.nodes.first(where: { $0.id == rootRepId }) else { return [:] }

        var map: [UUID: UUID] = [root.id: rootRep.id]
        func match(_ gameNode: GameNode, _ repNode: RepertoireNode) {
            for child in gameNode.children {
                guard let move = child.move else { continue }
                let uci = UCI.string(from: move)
                if let repChild = repNode.children.first(where: { $0.uciMove == uci }) {
                    map[child.id] = repChild.id
                    match(child, repChild)
                }
            }
        }
        match(root, rootRep)
        return map
    }

    // MARK: - Repertoire recording (open a repertoire as an analysis tab; moves persist as prep)

    /// Open the given repertoire as an analysis tab. Its lines hydrate onto the board; any move you
    /// play from here is recorded back into the repertoire. Focuses an existing tab if already open.
    private func openRepertoireInTab(_ rep: Repertoire) {
        if let existing = windowModel.indexHoldingRepertoire(rep.id) {
            selectTab(existing)
            return
        }
        newTab()
        hydrateRepertoire(rep)
        // Study your own side: a Black repertoire opens from Black's view.
        isBoardFlipped = (rep.side == .black)
        let s = windowModel.active
        s.repertoireId = rep.id
        s.repNodeMap = repNodeMap
        s.isFlipped = isBoardFlipped
        s.customTitle = rep.name
        s.title = rep.name
        activeRepertoire = rep
        windowModel.objectWillChange.send()
        activeScreen = .analysis
        persistTabs()
    }

    /// Rebuild the live GameTree (and repNodeMap) from a repertoire's stored nodes.
    private func hydrateRepertoire(_ rep: Repertoire) {
        repNodeMap.removeAll()
        guard let rootRepId = rep.rootNodeId,
              let rootRepNode = rep.nodes.first(where: { $0.id == rootRepId }) else { return }
        isHydratingRep = true
        repNodeMap[gameTree.root.id] = rootRepNode.id
        hydrateRepChildren(of: rootRepNode, gameNode: gameTree.root)
        gameTree.goToStart()
        gameTree.rebuildMainLine()
        isHydratingRep = false
        syncBoardWithGameTree()
    }

    private func hydrateRepChildren(of repNode: RepertoireNode, gameNode: GameNode) {
        // Primary (main) line first, so the board's main line mirrors the repertoire's.
        for childRep in repNode.children.sorted(by: { $0.isPrimary && !$1.isPrimary }) {
            guard let uci = childRep.uciMove,
                  let move = UCI.move(uci, board: gameNode.boardState) else { continue }
            gameTree.currentNode = gameNode
            guard gameTree.addMove(move, notation: childRep.san) else { continue }
            let newGameNode = gameTree.currentNode
            newGameNode.comment = childRep.annotation   // carry the repertoire's note onto the board
            repNodeMap[newGameNode.id] = childRep.id
            hydrateRepChildren(of: childRep, gameNode: newGameNode)
        }
    }

    /// Mirror the live GameTree into the repertoire: add newly-played moves AND delete moves that
    /// were removed from the board. Runs on every structural edit of a repertoire tab, so it catches
    /// every path (board, move-list context menu, ⌫ menu command) uniformly.
    private func reconcileRepertoire(_ rep: Repertoire) {
        repertoireDB.performBatch { reconcileRepertoireBody(rep) }
    }

    private func reconcileRepertoireBody(_ rep: Repertoire) {
        // 1. Collect every live gameNode reachable from the root.
        var liveNodes: [UUID: GameNode] = [:]
        func collect(_ n: GameNode) { liveNodes[n.id] = n; for c in n.children { collect(c) } }
        collect(gameTree.root)

        // Index the repertoire's nodes once. This used to be a `rep.nodes.first(where:)` linear scan
        // per tree node, three times over — O(n²) on every save. Nodes created below are added here
        // too, since a child's parent may have been minted earlier in this same pass.
        var repNodesById = Dictionary(rep.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // 2. Delete repertoire nodes whose gameNode no longer exists (SwiftData cascades the subtree).
        let orphanedGameIds = repNodeMap.keys.filter { liveNodes[$0] == nil }
        for gameId in orphanedGameIds {
            if let repId = repNodeMap[gameId], let repNode = repNodesById[repId] {
                repertoireDB.deleteNode(repNode)
                repNodesById[repId] = nil
            }
            repNodeMap[gameId] = nil
        }

        // 3. Add live nodes not yet in the repertoire (parent-first, so the parent is always mapped),
        //    and sync notes + main-line status (promote) for nodes already there.
        func addChildren(_ gameNode: GameNode) {
            let isUserMove = gameNode.boardState.turn == (rep.side == .white ? .white : .black)
            let firstChildId = gameNode.children.first?.id
            for child in gameNode.children {
                // The board's main line is child[0]; for the user's own moves that marks the primary.
                let shouldBePrimary = isUserMove && child.id == firstChildId
                if repNodeMap[child.id] == nil,
                   let parentRepId = repNodeMap[gameNode.id],
                   let parentRep = repNodesById[parentRepId],
                   let move = child.move {
                    let ownership: NodeOwnership = isUserMove ? .mineMain : .opponentCritical
                    let newRepNode = RepertoireNode(
                        repertoire: rep,
                        parent: parentRep,
                        uciMove: UCI.string(from: move),
                        san: child.cachedNotation,
                        fen: child.boardState.getFEN(),
                        isUserMove: isUserMove,
                        ownership: ownership,
                        isPrimary: shouldBePrimary
                    )
                    newRepNode.annotation = child.comment
                    repNodeMap[child.id] = newRepNode.id
                    repNodesById[newRepNode.id] = newRepNode
                    repertoireDB.insertNode(newRepNode, into: rep, parent: parentRep)
                } else if let repId = repNodeMap[child.id],
                          let repNode = repNodesById[repId] {
                    // Flush note edits + promote (main-line) changes back to the repertoire.
                    var changed = false
                    if repNode.annotation != child.comment { repNode.annotation = child.comment; changed = true }
                    if repNode.isUserMove, repNode.isPrimary != shouldBePrimary { repNode.isPrimary = shouldBePrimary; changed = true }
                    if changed { repertoireDB.updateNode(repNode) }
                }
                addChildren(child)
            }
        }
        addChildren(gameTree.root)

        windowModel.active.repNodeMap = repNodeMap
    }

    private func cycleTab(_ delta: Int) {
        let n = windowModel.sessions.count
        guard n > 1 else { return }
        selectTab(((windowModel.activeIndex + delta) % n + n) % n)
    }

    private func jumpToTab(_ index: Int) {
        guard windowModel.sessions.indices.contains(index) else { return }
        selectTab(index)
    }

    private func renameTab(_ index: Int, _ name: String) {
        guard windowModel.sessions.indices.contains(index) else { return }
        windowModel.sessions[index].customTitle = name
        windowModel.sessions[index].title = name
        windowModel.objectWillChange.send()
        persistTabs()
    }

    private func reopenClosedTab() {
        captureActiveSession()
        if windowModel.reopenClosed() {
            applyActiveSession()
            activeScreen = .analysis
        }
    }

    // MARK: - Tab persistence (§3.5) — restore open tabs across relaunch

    private static let openTabsKey = "tabia.openTabs"

    private func cursorPath(for s: BoardSession) -> [Int] {
        var path: [Int] = []
        var node = s.cursorNode
        while let parent = node.parent {
            path.append(parent.children.firstIndex(where: { $0 === node }) ?? 0)
            node = parent
        }
        return path.reversed()
    }

    private func persistTabs() {
        captureActiveSession()
        var out: [PersistedTab] = []
        for s in windowModel.sessions {
            let t = GameTree()
            t.root = s.rootNode
            let headers: [String: String] = [
                "White": s.whiteName.isEmpty ? "?" : s.whiteName,
                "Black": s.blackName.isEmpty ? "?" : s.blackName,
                "WhiteElo": s.whiteRating, "BlackElo": s.blackRating,
                "Event": s.event.isEmpty ? "?" : s.event,
                "Result": s.result.isEmpty ? "*" : s.result,
            ]
            out.append(PersistedTab(
                pgn: t.toPGN(headers: headers), cursorPath: cursorPath(for: s),
                isFlipped: s.isFlipped, title: s.title, customTitle: s.customTitle, isDirty: s.isDirty,
                whiteName: s.whiteName, blackName: s.blackName,
                whiteRating: s.whiteRating, blackRating: s.blackRating,
                event: s.event, result: s.result, timeClass: s.timeClass,
                openingName: s.openingName, openingECO: s.openingECO,
                gameId: s.currentGameId?.uuidString,
                repertoireId: s.repertoireId?.uuidString,
                analysisData: s.analysisData))
        }
        let payload = PersistedTabSet(tabs: out, activeIndex: windowModel.activeIndex)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.openTabsKey)
        }
    }

    private func restoreTabs() {
        guard let data = UserDefaults.standard.data(forKey: Self.openTabsKey),
              let payload = try? JSONDecoder().decode(PersistedTabSet.self, from: data),
              !payload.tabs.isEmpty else { return }
        let parser = PGNParser()
        var sessions: [BoardSession] = []
        for pt in payload.tabs {
            let s = BoardSession()
            if !pt.pgn.isEmpty, let g = parser.parse(string: pt.pgn).first, let tree = parser.toGameTree(g) {
                s.rootNode = tree.root
                var node = tree.root
                for idx in pt.cursorPath {
                    guard node.children.indices.contains(idx) else { break }
                    node = node.children[idx]
                }
                s.cursorNode = node
            }
            s.isFlipped = pt.isFlipped
            s.title = pt.title
            s.customTitle = pt.customTitle
            s.isDirty = pt.isDirty
            s.whiteName = pt.whiteName; s.blackName = pt.blackName
            s.whiteRating = pt.whiteRating; s.blackRating = pt.blackRating
            s.event = pt.event; s.result = pt.result; s.timeClass = pt.timeClass
            s.openingName = pt.openingName; s.openingECO = pt.openingECO
            s.currentGameId = pt.gameId.flatMap { UUID(uuidString: $0) }
            s.analysisData = pt.analysisData
            // Rebind the repertoire link. The tree was just rebuilt from PGN with fresh node ids, so
            // the bridge has to be re-derived by matching moves. A repertoire deleted since the last
            // launch drops the link rather than leaving a dangling id.
            if let repId = pt.repertoireId.flatMap({ UUID(uuidString: $0) }),
               let rep = repertoireDB.repertoires.first(where: { $0.id == repId }) {
                s.repertoireId = repId
                s.repNodeMap = repertoireNodeMap(root: s.rootNode, repertoire: rep)
            }
            sessions.append(s)
        }
        guard !sessions.isEmpty else { return }
        windowModel.sessions = sessions
        windowModel.activeIndex = min(max(payload.activeIndex, 0), sessions.count - 1)
        applyActiveSession()
    }

    /// Hidden buttons carrying the tab keyboard shortcuts (⌘T/⌘W/⌃⇥/⌘1…8/⌘⇧T) — non-colliding
    /// with ⌘E (Engine Room) and ⌘, (Settings).
    @ViewBuilder private var tabShortcutButtons: some View {
        Group {
            Button("") { newTab() }.keyboardShortcut("t", modifiers: .command)
            Button("") { closeTab(windowModel.activeIndex) }.keyboardShortcut("w", modifiers: .command)
            Button("") { cycleTab(1) }.keyboardShortcut(.tab, modifiers: .control)
            Button("") { cycleTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("") { reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift])
            ForEach(1...8, id: \.self) { n in
                Button("") { jumpToTab(n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - Masthead & status bar

    @ViewBuilder private var mastheadActions: some View {
        switch activeScreen {
        case .chesscom:
            // Sync lives in the masthead on My Games (handled inside ChessComBrowserView).
            Button("Sync Now") { NotificationCenter.default.post(name: .tabiaSyncGames, object: nil) }
                .buttonStyle(GlassButtonStyle())
        // Library's Filters control moved into the ledger's own header row — it only applies inside
        // a database, so it belongs next to that database's name rather than in window chrome.
        default:
            EmptyView()
        }
    }

    private func mastheadPill(icon: String, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .regular))
                Text(label).font(AnnFont.label(11)).tracking(11 * 0.1)
            }
            .foregroundColor(DS.ink60)
            .padding(.vertical, 5).padding(.horizontal, 12)
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusLeft: String {
        switch activeScreen {
        case .analysis:
            let n = getMoveSequenceSAN().count
            return n == 0 ? "STARTING POSITION" : "MOVE \(n)"
        default:
            return activeScreen.navLabel.uppercased()
        }
    }

    private var statusRight: String {
        multiEngine.anyEngineAvailable ? "ENGINE · READY" : "NO ENGINE"
    }

    /// Opens the standard Settings window (Settings scene). Also bound to ⌘, and the app menu.
    private func openSettingsWindow() {
        openSettingsAction()
    }

    private func boardIconButton(_ icon: String, _ help: String, active: Bool = false,
                                 _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(active ? DS.redAccent : DS.ink60)
                .frame(width: 28, height: 28)
                .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// One menu button gathering every board action (native menu, like a right-click menu).
    private var boardActionsMenu: some View {
        Menu {
            Button { saveActiveTab() } label: { Label(saveActionLabel, systemImage: "square.and.arrow.down") }
            Button { saveAsActiveTab() } label: { Label("Save As…", systemImage: "square.and.arrow.down.on.square") }
            Divider()
            Button { isBoardFlipped.toggle() } label: { Label("Flip Board", systemImage: "arrow.up.arrow.down") }
            Button { resetGame() } label: { Label("Reset Board", systemImage: "arrow.counterclockwise") }
            Button { showingSetupPosition = true } label: { Label("Set Up Position", systemImage: "square.grid.3x3") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.ink60)
                .frame(width: 28, height: 28)
                .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Board actions")
    }

    // MARK: - Analysis Layout (3-column: explorer + board + right sidebar)

    private var analysisLayout: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let availableHeight = geometry.size.height

            let boardAreaComponents = calculateBoardAreaComponents()

            // Sidebar constraints
            let minExplorerWidth: CGFloat = 260
            let maxExplorerWidth: CGFloat = 380
            let minRightSidebarWidth: CGFloat = 320
            let maxRightSidebarWidth: CGFloat = 400
            let sidebarGap: CGFloat = 24

            // Board extras: eval bar + labels + internal padding + gaps
            let boardExtras = boardAreaComponents.evalBarWidth + boardAreaComponents.spacing + boardAreaComponents.labelWidth + 40
            // Vertical chrome inside AnnBoardArea that shares the column with the board: the two
            // player rows, the plate line, the eval value under the bar, the inter-row spacing,
            // and the ±20 vertical padding. Reserve it so the board fills the rest without clipping.
            let verticalExtras: CGFloat = 168

            // Max board size from height
            let maxBoardFromHeight = availableHeight - verticalExtras

            // Max board size from width (after reserving minimum sidebar space)
            let minSidebarsTotal = minExplorerWidth + minRightSidebarWidth + (sidebarGap * 2) + 2
            let maxBoardFromWidth = availableWidth - minSidebarsTotal - boardExtras

            // Largest square that fits its allotted area — height- or width-constrained, min 300.
            let boardSize = max(min(maxBoardFromHeight, maxBoardFromWidth), 300)

            // Board area = board + extras
            let boardAreaWidth = boardSize + boardExtras

            // Distribute remaining width to sidebars
            let remainingForSidebars = max(availableWidth - boardAreaWidth - (sidebarGap * 2) - 2, minExplorerWidth + minRightSidebarWidth)
            let halfRemaining = remainingForSidebars / 2.0
            let finalExplorerWidth = min(max(halfRemaining, minExplorerWidth), maxExplorerWidth)
            let finalRightSidebarWidth = min(max(remainingForSidebars - finalExplorerWidth, minRightSidebarWidth), maxRightSidebarWidth)

            HStack(spacing: 0) {
                // Explorer panel
                VStack(spacing: 0) {
                    // Annotator "OPENING EXPLORER" header: label · source segmented · search
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            AnnLabel("Opening Explorer", size: 10, tracking: 0.14, bold: true, color: DS.ink40)
                            Spacer()
                            Text(explorerSource == .lichess ? "MASTERS" : "YOUR GAMES")
                                .font(AnnFont.mono(10)).foregroundColor(DS.ink40)
                        }
                        AnnSegmented(
                            options: ExplorerSource.allCases.map { ($0, $0.rawValue) },
                            selection: $explorerSource
                        )
                    }
                    .padding(16)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

                    if explorerSource == .lichess {
                        LichessExplorerView(
                            explorerService: lichessExplorer,
                            openingBook: openingBook,
                            board: board,
                            currentMoves: cachedUCI,
                            searchText: $explorerSearchText,
                            onMovePlayed: { uciMove in
                                _ = applySingleUCIMove(uciMove)
                            },
                            onGameLoaded: { pgn in
                                loadGameFromPGN(pgn)
                            },
                            onOpeningSelected: { moves in
                                applyOpeningMoves(moves)
                            }
                        )
                    } else {
                        LibraryExplorerView(
                            explorerService: libraryExplorer,
                            openingBook: openingBook,
                            board: board,
                            currentMoves: cachedUCI,
                            currentSANs: cachedSAN,
                            searchText: $explorerSearchText,
                            onMovePlayed: { uciMove in
                                _ = applySingleUCIMove(uciMove)
                            },
                            onGameLoaded: { pgn in
                                loadGameFromPGN(pgn)
                            },
                            onOpeningSelected: { moves in
                                applyOpeningMoves(moves)
                            }
                        )
                    }
                }
                .frame(width: finalExplorerWidth)
                .background(GlassPanelBackground())
                .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }

                // Board area — Annotator board (players · frame · eval bar · plate · bottom controls)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AnnBoardArea(
                        board: board,
                        gameTree: gameTree,
                        engine: multiEngine.primaryEngine,
                        boardSize: boardSize,
                        whiteName: whiteName,
                        blackName: blackName,
                        whiteRating: whiteRating,
                        blackRating: blackRating,
                        openingName: currentOpeningName,
                        plyCount: cachedSAN.count,
                        isFlipped: isBoardFlipped
                    )
                    .padding(.vertical, 20)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .background(GlassBoardAreaBackground())
                .overlay(alignment: .leading) { Rectangle().fill(DS.hairline).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }
                // Floating board controls — overlaid (absolute) so they never shift the board.
                .overlay(alignment: .topTrailing) {
                    boardActionsMenu
                    .padding(.top, 16)
                    .padding(.trailing, 20)
                }
                // Scroll over the board to step through moves (up = back, down = forward).
                .overlay {
                    ScrollNavCatcher { step in
                        if step > 0 { _ = gameTree.goBack() } else { _ = gameTree.goForward() }
                        syncBoardWithGameTree()
                    }
                }

                // Right sidebar — engine source + PV + Game Review + move list (opening lives in
                // the left explorer, per the design — no "Starting Position" panel here).
                VStack(spacing: 0) {
                    AnalysisPanelView(
                        multiEngine: multiEngine,
                        engine: multiEngine.primaryEngine,
                        gameTree: gameTree,
                        autoAnalyze: $settings.autoAnalyze,
                        gameAnalyzer: gameAnalyzer,
                        onStartAnalysis: startGameAnalysis,
                        onCancelAnalysis: cancelGameAnalysis,
                        onNavigateToEngines: { openWindow(id: WindowID.engineRoom) }
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DS.hairline).frame(height: 1)
                    }

                    // Game review (when completed) sits on top of the moves inside one shared
                    // scroll, so the whole right column scrolls together — not just the move list.
                    MoveListView(
                        gameTree: gameTree,
                        whiteName: whiteName,
                        blackName: blackName,
                        event: currentEvent,
                        openingName: currentOpeningName ?? "",
                        eco: currentOpeningECO ?? "",
                        result: currentResult,
                        gameAnalyzer: gameAnalyzer,
                        showReview: gameAnalyzer.isCompleted,
                        reviewTimeClass: currentTimeClass,
                        onImportPGN: { importPGNForDisplay() },
                        onSetUpPosition: { showingSetupPosition = true },
                        onDropPGNText: { loadGameFromPGN($0) }
                    )
                    .equatable()
                }
                .frame(width: finalRightSidebarWidth)
                .background(GlassPanelBackground())
                .overlay(alignment: .leading) { Rectangle().fill(DS.hairline).frame(width: 1) }
            }
        }
    }

    // MARK: - Helper Functions

    private struct BoardAreaComponents {
        let labelWidth: CGFloat = 20
        let labelHeight: CGFloat = 18
        let evalBarWidth: CGFloat = 34
        let spacing: CGFloat = 16
        let bottomControlsHeight: CGFloat = 50
    }

    private func calculateBoardAreaComponents() -> BoardAreaComponents {
        return BoardAreaComponents()
    }

    private func startEngineIfConfigured() {
        guard settings.defaultEngine != nil else {
            // No engine configured — ensure engines are stopped
            multiEngine.stopAllProcesses()
            return
        }
        if multiEngine.slots.isEmpty {
            multiEngine.setup()
        } else {
            multiEngine.reconfigure()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if settings.autoAnalyze {
                evaluatePositionDebounced()
            }
        }
    }

    private func syncBoardWithGameTree() {
        let currentBoard = gameTree.currentNode.boardState

        // Skip if board is already in sync (same position)
        guard board.turn != currentBoard.turn ||
              board.fullMoveNumber != currentBoard.fullMoveNumber ||
              board.squares != currentBoard.squares else {
            return
        }

        isSyncingBoard = true
        // Restore the FULL snapshot (incl. castling-rights booleans) — copying only squares/turn
        // left the castling flags stale, which blocked re-castling after a takeback.
        board.restoreState(from: currentBoard)
        isSyncingBoard = false
    }

    private func resetGame() {
        beginBoardLoad()
        // Cancel and reset game analysis
        gameAnalyzer.cancel()
        gameAnalyzer.reset()

        // Cancel any pending evaluation and stop all engines
        evaluationDebounceTask?.cancel()
        evaluationDebounceTask = nil
        multiEngine.stopAll()

        let newBoard = ChessBoard()
        board.restoreState(from: newBoard)

        let newTree = GameTree()
        gameTree.root = newTree.root
        gameTree.currentNode = newTree.root
        gameTree.mainLine = [newTree.root]

        // Clear analysis state on all engines
        for slot in multiEngine.slots {
            slot.engine.evaluation = nil
            slot.engine.bestMove = nil
            slot.engine.analysisLines = []
        }

        // Clear player names, ratings, and game tracking
        whiteName = ""
        blackName = ""
        whiteRating = ""
        blackRating = ""
        currentEvent = ""
        currentResult = ""
        currentTimeClass = nil
        currentGameId = nil

        // A fresh board is clean, and its tab reverts to the "New board" title.
        endBoardLoad(clean: true)
        windowModel.active.title = "New board"

        // Use debounced evaluation — onChange may also trigger it,
        // but the debounce ensures only one evaluation runs
        if settings.autoAnalyze {
            evaluatePositionDebounced()
        }
    }

    private func loadGame(_ game: GameRecord) {
        let parser = PGNParser()
        let pgnGames = parser.parse(string: game.pgn)

        guard let pgnGame = pgnGames.first,
              let loadedTree = parser.toGameTree(pgnGame) else {
            return
        }

        beginBoardLoad()

        // Track current game for saving analysis — on BOTH the @State and the active session, so
        // §3.7 focus-or-open (which scans BoardSession.currentGameId) finds this tab next time.
        currentGameId = game.id
        windowModel.active.currentGameId = game.id

        // Replace current game tree contents
        gameTree.root = loadedTree.root
        gameTree.currentNode = loadedTree.root
        gameTree.rebuildMainLine()

        // Set player names
        whiteName = game.white == "Unknown" ? "" : game.white
        blackName = game.black == "Unknown" ? "" : game.black

        // Set player ratings from PGN headers
        whiteRating = pgnGame.headers["WhiteElo"] ?? ""
        blackRating = pgnGame.headers["BlackElo"] ?? ""

        // Navigate to start and sync board
        gameTree.goToStart()
        syncBoardWithGameTree()

        // Set opening from game record — use ECO lookup as fallback
        currentOpeningECO = game.eco
        if let opening = game.opening, !opening.isEmpty {
            currentOpeningName = opening
        } else if let eco = game.eco, !eco.isEmpty {
            currentOpeningName = openingBook.findByECO(eco)
        }

        currentEvent = game.event == "?" ? "" : game.event
        currentResult = game.result == "*" ? "" : game.result
        currentTimeClass = game.timeClass

        // Restore analysis from database if available, otherwise reset
        if let analysisData = game.analysisData {
            gameAnalyzer.restoreFromAnalysisData(analysisData, gameTree: gameTree)
        } else {
            gameAnalyzer.reset()
        }

        // A freshly loaded library game matches the library — not dirty. Also refresh the tab title.
        endBoardLoad(clean: true)
        windowModel.active.title = boardTabTitle

        // Trigger evaluation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            evaluatePositionNow()
        }
    }

    /// All menu-command notifications merged into one publisher (keeps the body's type-check cheap).
    private static let menuCommandPublisher = Publishers.MergeMany(
        [Notification.Name.tabiaNewGame, .tabiaOpenPGN, .tabiaSavePGN, .tabiaExportGame,
         .tabiaCopyFEN, .tabiaPasteFEN, .tabiaFlipBoard, .tabiaStartEngine, .tabiaStopEngine,
         .tabiaAnalyzePosition, .tabiaShowBestMove, .tabiaGoToStart, .tabiaPreviousMove,
         .tabiaNextMove, .tabiaGoToEnd,
         .tabiaScreenAnalysis, .tabiaScreenRepertoire, .tabiaScreenMyGames,
         .tabiaScreenLibrary, .tabiaSetUpPosition, .tabiaFullReview, .tabiaToggleEngine,
         .tabiaToggleAutoAnalyze, .tabiaDeleteMove, .tabiaAnnBrilliant, .tabiaAnnGood,
         .tabiaAnnInteresting, .tabiaAnnDubious, .tabiaAnnMistake, .tabiaAnnBlunder,
         // Screen-scoped commands: intercepted here only to switch screens first, then re-posted
         // for the freshly mounted view to handle (see routeToScreen).
         .tabiaNewRepertoire, .tabiaNewDatabase, .tabiaLibraryToggleFilters, .tabiaSyncGames]
            .map { NotificationCenter.default.publisher(for: $0) }
    )

    /// Screen-scoped commands are handled by a child view that only exists while its screen is
    /// mounted, so firing one from another screen used to vanish. Switch first, then re-post on the
    /// next runloop turn for the now-mounted view. Re-entry is safe: the second pass sees the screen
    /// already active and falls through to the child's own receiver.
    private func routeToScreen(_ screen: AppScreen, then name: Notification.Name) -> Bool {
        guard activeScreen != screen else { return false }
        activeScreen = screen
        DispatchQueue.main.async { NotificationCenter.default.post(name: name, object: nil) }
        return true
    }

    private func handleMenuCommand(_ name: Notification.Name) {
        switch name {
        case .tabiaNewRepertoire:
            _ = routeToScreen(.repertoire, then: name)
            // The flag survives the screen switch; RepertoireBrowserView picks it up on appear.
            pendingNewRepertoire = true
        case .tabiaNewDatabase, .tabiaLibraryToggleFilters:
            _ = routeToScreen(.database, then: name)
        case .tabiaSyncGames:
            _ = routeToScreen(.chesscom, then: name)
        case .tabiaNewGame:        resetGame(); activeScreen = .analysis
        case .tabiaOpenPGN:        openPGNFromPanel()
        case .tabiaSavePGN:        savePGNToFile()
        case .tabiaExportGame:     showingSaveSheet = true
        case .tabiaCopyFEN:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(board.getFEN(), forType: .string)
        case .tabiaPasteFEN:       pasteFEN()
        case .tabiaFlipBoard:      isBoardFlipped.toggle()
        case .tabiaStartEngine:    startEngineIfConfigured()
        case .tabiaStopEngine:     multiEngine.stopAll()
        case .tabiaAnalyzePosition: activeScreen = .analysis; evaluatePositionNow()
        case .tabiaShowBestMove:   settings.showBestMoveArrow.toggle()
        case .tabiaGoToStart:      gameTree.goToStart(); syncBoardWithGameTree()
        case .tabiaPreviousMove:   _ = gameTree.goBack(); syncBoardWithGameTree()
        case .tabiaNextMove:       _ = gameTree.goForward(); syncBoardWithGameTree()
        case .tabiaGoToEnd:        gameTree.goToEnd(); syncBoardWithGameTree()
        case .tabiaScreenAnalysis:   activeScreen = .analysis
        case .tabiaScreenRepertoire: activeScreen = .repertoire
        case .tabiaScreenMyGames:    activeScreen = .chesscom
        case .tabiaScreenLibrary:    activeScreen = .database
        case .tabiaSetUpPosition:    activeScreen = .analysis; showingSetupPosition = true
        case .tabiaFullReview:       activeScreen = .analysis; startGameAnalysis()
        case .tabiaToggleEngine:
            if multiEngine.anyEngineAvailable { multiEngine.stopAll() } else { startEngineIfConfigured() }
        case .tabiaToggleAutoAnalyze: settings.autoAnalyze.toggle()
        case .tabiaDeleteMove:
            if gameTree.currentNode.parent != nil {
                gameTree.deleteFromNode(gameTree.currentNode); syncBoardWithGameTree()
            }
        case .tabiaAnnBrilliant:   annotateCurrent("!!")
        case .tabiaAnnGood:        annotateCurrent("!")
        case .tabiaAnnInteresting: annotateCurrent("!?")
        case .tabiaAnnDubious:     annotateCurrent("?!")
        case .tabiaAnnMistake:     annotateCurrent("?")
        case .tabiaAnnBlunder:     annotateCurrent("??")
        default:                   break
        }
    }

    private func annotateCurrent(_ sym: String) {
        guard gameTree.currentNode.parent != nil else { return }
        gameTree.currentNode.setAnnotation(sym)
        gameTree.objectWillChange.send()
    }

    /// Open a PGN file into the current game (menu: Open PGN…).
    /// Load a game into Analysis and kick off a full engine review of it. The analyzer saves the
    /// per-move quality + accuracies back to the game record on completion, so the row's accuracy fills in.
    private func reviewGame(_ game: GameRecord) {
        loadGame(game)
        activeScreen = .analysis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard multiEngine.anyEngineAvailable, !gameAnalyzer.isAnalyzing else { return }
            startGameAnalysis()
        }
    }

    private func openPGNFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let t = UTType(filenameExtension: "pgn") { panel.allowedContentTypes = [t, .plainText] }
        panel.message = "Choose a PGN file to open"
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        loadGameFromPGN(text)
        activeScreen = .analysis
    }

    /// Write the current game to a .pgn file (menu: Save PGN…).
    private func savePGNToFile() {
        let panel = NSSavePanel()
        if let t = UTType(filenameExtension: "pgn") { panel.allowedContentTypes = [t] }
        panel.nameFieldStringValue = "game.pgn"
        panel.message = "Save the current game as PGN"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var headers: [String: String] = [:]
        if !whiteName.isEmpty { headers["White"] = whiteName }
        if !blackName.isEmpty { headers["Black"] = blackName }
        do {
            try gameTree.toPGN(headers: headers).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            AppErrorReporter.report("Couldn't save the PGN to \(url.lastPathComponent).", error: error)
        }
    }

    /// Load a FEN from the clipboard as a fresh game (menu: Paste FEN).
    private func pasteFEN() {
        guard let fen = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !fen.isEmpty,
              ChessBoard().loadFEN(fen) else { return }   // validate before applying
        let fresh = GameTree(fen: fen)
        gameTree.root = fresh.root
        gameTree.currentNode = fresh.root
        gameTree.rebuildMainLine()
        currentGameId = nil
        gameAnalyzer.reset()
        gameTree.goToStart()
        syncBoardWithGameTree()
        activeScreen = .analysis
    }

    /// Bare ← / → / Home / End step through moves — only on the analysis screen and only when a
    /// text field isn't focused, so typing and other screens keep their normal arrow behaviour.
    private func installArrowMonitor() {
        guard arrowMonitor == nil else { return }
        arrowMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only the analysis screen drives the main gameTree with bare arrows. On other screens
            // (e.g. the repertoire editor, which has its own tree + arrow handler) pass the event
            // through so it isn't hijacked into navigating the wrong, invisible tree.
            guard activeScreen == .analysis else { return event }
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
            if let fr = NSApp.keyWindow?.firstResponder, fr is NSText || fr is NSTextView { return event }
            switch event.keyCode {
            case 123: _ = gameTree.goBack();    syncBoardWithGameTree(); return nil
            case 124: _ = gameTree.goForward(); syncBoardWithGameTree(); return nil
            case 115: gameTree.goToStart();     syncBoardWithGameTree(); return nil
            case 119: gameTree.goToEnd();       syncBoardWithGameTree(); return nil
            default:  return event
            }
        }
    }

    private func removeArrowMonitor() {
        if let m = arrowMonitor { NSEvent.removeMonitor(m); arrowMonitor = nil }
    }

    /// Open a PGN file and view its FIRST game on the board — not saved to the library.
    private func importPGNForDisplay() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Open a PGN to view — this game is not saved to your library"
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            loadGameFromPGN(text)
        }
    }

    /// Load a hand-set position (from the board editor) onto the board — not saved to the library.
    private func setupPosition(fen: String) {
        guard let board = ChessBoard(fen: fen) else { return }
        let rootNode = GameNode(move: nil, parent: nil, boardState: board)
        gameTree.root = rootNode
        gameTree.currentNode = rootNode
        gameTree.rebuildMainLine()

        currentGameId = nil
        whiteName = ""; blackName = ""; whiteRating = ""; blackRating = ""
        currentEvent = ""; currentResult = ""; currentTimeClass = nil
        currentOpeningECO = nil; currentOpeningName = nil

        gameAnalyzer.reset()
        gameTree.goToStart()
        syncBoardWithGameTree()
        updateCurrentOpening()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            evaluatePositionNow()
        }
    }

    private func loadGameFromPGN(_ pgn: String) {
        let parser = PGNParser()
        let pgnGames = parser.parse(string: pgn)

        guard let pgnGame = pgnGames.first,
              let loadedTree = parser.toGameTree(pgnGame) else {
            return
        }

        // Clear current game tracking (this is not from database)
        currentGameId = nil

        // Replace current game tree contents
        gameTree.root = loadedTree.root
        gameTree.currentNode = loadedTree.root
        gameTree.rebuildMainLine()

        // Set player names from PGN headers
        whiteName = pgnGame.headers["White"] ?? ""
        blackName = pgnGame.headers["Black"] ?? ""
        whiteRating = pgnGame.headers["WhiteElo"] ?? ""
        blackRating = pgnGame.headers["BlackElo"] ?? ""

        // Navigate to start and sync board
        gameTree.goToStart()
        syncBoardWithGameTree()

        // Set opening from PGN headers if available
        currentOpeningECO = pgnGame.headers["ECO"]
        currentOpeningName = pgnGame.headers["Opening"]

        let ev = pgnGame.headers["Event"] ?? ""
        currentEvent = ev == "?" ? "" : ev
        let res = pgnGame.headers["Result"] ?? ""
        currentResult = res == "*" ? "" : res
        currentTimeClass = nil   // imported PGN → treated as a standard/classical game

        // Reset analysis
        gameAnalyzer.reset()

        // Trigger evaluation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            evaluatePositionNow()
        }
    }

    private func evaluatePositionDebounced() {
        // Cancel any pending evaluation
        evaluationDebounceTask?.cancel()

        let task = DispatchWorkItem {
            self.evaluatePositionNow()
        }
        evaluationDebounceTask = task

        // Debounce by 200ms to handle rapid navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    private func evaluatePositionNow() {
        // Cancel any pending debounced evaluation to prevent double-analysis
        evaluationDebounceTask?.cancel()
        evaluationDebounceTask = nil

        // Discard any running look-ahead analysis
        if lookAheadNodeId != nil {
            multiEngine.discardSpeculative()
            lookAheadNodeId = nil
        }

        multiEngine.stopAll()

        // Get a fresh copy of the current board state and send to all engines
        let boardToEval = gameTree.currentNode.boardState.copy()
        multiEngine.evaluateAll(board: boardToEval)
    }

    // MARK: - Game Analysis

    private func startGameAnalysis() {
        // Stop any current analysis (including speculative look-ahead)
        evaluationDebounceTask?.cancel()
        evaluationDebounceTask = nil
        if lookAheadNodeId != nil {
            multiEngine.discardSpeculative()
            lookAheadNodeId = nil
        }
        multiEngine.stopAll()

        // Start game analysis using the selected engine only
        let engine = multiEngine.primaryEngine
        if let firstBoard = gameAnalyzer.startAnalysis(gameTree: gameTree) {
            engine.evaluatePosition(board: firstBoard, depth: gameAnalyzer.analysisDepth, movetime: gameAnalyzer.analysisMovetime)
        }
    }

    private func cancelGameAnalysis() {
        gameAnalyzer.cancel()
        multiEngine.stopAll()

        // Resume normal analysis if auto-analyze is on
        if settings.autoAnalyze {
            evaluatePositionDebounced()
        }
    }

    private func saveAnalysisToDatabase() {
        guard let gameId = currentGameId,
              let analysisData = gameAnalyzer.exportAnalysisData(),
              let game = database.game(withId: gameId) else {
            return
        }

        game.analysisData = analysisData
        database.updateGame(game)
    }

    /// Recompute the cached move sequences once when the position changes (called from onChange).
    private func refreshMoveSequences() {
        cachedUCI = getMoveSequenceUCI()
        cachedSAN = getMoveSequenceSAN()
    }

    private func updateCurrentOpening() {
        // Use the cached sequence (refreshed on position change) rather than re-walking the line.
        let uciMoves = cachedUCI

        // Look up the opening
        if let opening = openingBook.findOpening(moves: uciMoves) {
            currentOpeningName = opening.name
            currentOpeningECO = opening.eco
        }
        // If no opening found, keep the last known opening
    }


    private func getMoveSequenceSAN() -> [String] {
        var moves: [String] = []
        let pathToCurrentNode = getPathToCurrentNode()
        for pathNode in pathToCurrentNode {
            if let notation = pathNode.cachedNotation {
                // Strip +/# for clean matching
                var clean = notation
                clean = clean.replacingOccurrences(of: "+", with: "")
                clean = clean.replacingOccurrences(of: "#", with: "")
                moves.append(clean)
            }
        }
        return moves
    }

    private func getMoveSequenceUCI() -> [String] {
        var moves: [String] = []

        // Walk the path from root to current node
        let pathToCurrentNode = getPathToCurrentNode()

        for pathNode in pathToCurrentNode {
            if let move = pathNode.move {
                let uci = UCI.string(from: move)
                moves.append(uci)
            }
        }

        return moves
    }

    private func getPathToCurrentNode() -> [GameNode] {
        // Append + reverse once (O(N)) instead of front-inserting each node (O(N²)).
        var path: [GameNode] = []
        var current: GameNode? = gameTree.currentNode
        while let node = current {
            path.append(node)
            current = node.parent
        }
        return path.reversed()
    }

    /// Parse and apply a single UCI move (e.g. "e2e4") to the board and game tree
    @discardableResult
    private func applySingleUCIMove(_ uci: String) -> Bool {
        guard uci.count >= 4 else { return false }

        let chars = Array(uci)
        guard let fromFileAscii = chars[0].asciiValue,
              let toFileAscii = chars[2].asciiValue else { return false }

        let fromFile = Int(fromFileAscii) - Int(Character("a").asciiValue!)
        guard let fromRank = Int(String(chars[1])) else { return false }
        let toFile = Int(toFileAscii) - Int(Character("a").asciiValue!)
        guard let toRank = Int(String(chars[3])) else { return false }

        let from = Position(fromFile, fromRank - 1)
        let to = Position(toFile, toRank - 1)

        guard let piece = board.pieceAt(from) else { return false }

        // Parse promotion
        var promotionType: PieceType? = nil
        if chars.count >= 5 {
            switch chars[4] {
            case "q": promotionType = .queen
            case "r": promotionType = .rook
            case "b": promotionType = .bishop
            case "n": promotionType = .knight
            default: break
            }
        }

        let capturedPiece = board.pieceAt(to)
        let isEnPassant = piece.type == .pawn && from.file != to.file && capturedPiece == nil
        let isCastling = piece.type == .king && abs(from.file - to.file) == 2

        let move = Move(
            from: from, to: to, piece: piece,
            capturedPiece: isEnPassant ? board.pieceAt(Position(to.file, from.rank)) : capturedPiece,
            isEnPassant: isEnPassant,
            isCastling: isCastling,
            promotionType: promotionType
        )

        if board.makeMove(move) {
            _ = gameTree.addMove(move)
            return true
        }
        return false
    }

    private func applyOpeningMoves(_ uciMoves: [String]) {
        // Cancel any pending evaluation and stop all engines first
        evaluationDebounceTask?.cancel()
        evaluationDebounceTask = nil
        multiEngine.stopAll()

        // Reset board to starting position (inline, not via resetGame,
        // to avoid triggering extra evaluation cycles)
        let newBoard = ChessBoard()
        board.restoreState(from: newBoard)

        let newTree = GameTree()
        gameTree.root = newTree.root
        gameTree.currentNode = newTree.root
        gameTree.mainLine = [newTree.root]

        for slot in multiEngine.slots {
            slot.engine.evaluation = nil
            slot.engine.bestMove = nil
            slot.engine.analysisLines = []
        }

        whiteName = ""
        blackName = ""
        whiteRating = ""
        blackRating = ""

        // Apply each move
        for uci in uciMoves {
            applySingleUCIMove(uci)
        }

        // Sync board with game tree
        syncBoardWithGameTree()
        updateCurrentOpening()

        // Single debounced evaluation — onChange will also call evaluatePositionDebounced,
        // but the debounce mechanism ensures only the last one runs
        if settings.autoAnalyze {
            evaluatePositionDebounced()
        }
    }
}

// MARK: - Board Status Bar

#Preview {
    MainWindowView()
        .environmentObject(GameDatabase.preview())
        .environmentObject(ReferenceDatabase())
        .frame(width: 1300, height: 850)
}
