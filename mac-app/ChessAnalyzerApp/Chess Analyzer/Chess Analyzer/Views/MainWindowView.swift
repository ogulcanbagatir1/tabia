import SwiftUI
import AppKit

struct MainWindowView: View {
    @StateObject private var board = ChessBoard()
    @StateObject private var gameTree = GameTree()
    @StateObject private var multiEngine = MultiEngineManager()
    @EnvironmentObject var database: GameDatabase
    @StateObject private var openingBook = OpeningBook.shared
    @StateObject private var gameAnalyzer = GameAnalyzer()
    @StateObject private var lichessExplorer = LichessExplorerService()
    @StateObject private var libraryExplorer = LibraryExplorerService()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettingsAction

    @State private var autoAnalyze = true
    @State private var showingSidebar = true
    @State private var showingSaveSheet = false
    @State private var evaluationDebounceTask: DispatchWorkItem?
    @State private var isSyncingBoard = false
    @State private var whiteName: String = ""
    @State private var blackName: String = ""
    @State private var whiteRating: String = ""
    @State private var blackRating: String = ""

    // Opening tracking
    @State private var currentOpeningName: String? = nil
    @State private var currentOpeningECO: String? = nil

    // Current loaded game (for saving analysis back)
    @State private var currentGameId: UUID? = nil

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

    // The reference DB is no longer a top-level source: it's selectable as a database
    // inside "My Library" (see LibraryExplorerView's database picker).
    enum ExplorerSource: String, CaseIterable {
        case lichess = "Lichess Masters"
        case library = "My Library"
    }

    // Computed arrow from engine's best move suggestion
    private var engineArrow: BoardArrow? {
        guard settings.showBestMoveArrow,
              let firstLine = multiEngine.primaryEngine.analysisLines.first,
              let uciMove = firstLine.pvMoves.first,
              uciMove.count >= 4 else {
            return nil
        }

        let chars = Array(uciMove)
        guard let fromFileAscii = chars[0].asciiValue,
              let toFileAscii = chars[2].asciiValue else { return nil }

        let fromFile = Int(fromFileAscii) - Int(Character("a").asciiValue!)
        guard let fromRank = Int(String(chars[1])) else { return nil }
        let toFile = Int(toFileAscii) - Int(Character("a").asciiValue!)
        guard let toRank = Int(String(chars[3])) else { return nil }

        let from = Position(fromFile, fromRank - 1)
        let to = Position(toFile, toRank - 1)

        guard from.isValid() && to.isValid() else { return nil }

        // Blue-indigo color for engine suggestion arrow
        return BoardArrow(from: from, to: to, color: DS.accent.opacity(0.7))
    }

    // Sidebar constraints
    private let minExplorerWidth: CGFloat = 280
    private let minRightSidebarWidth: CGFloat = 300
    private let iconRailWidth: CGFloat = DS.iconRailWidth

    var body: some View {
        VStack(spacing: 0) {
            // Masthead — wordmark · centered nav tabs · contextual actions + settings gear.
            // Hidden in Drill mode (focused mode) — handled inside RepertoireBrowserView's drill.
            MastheadView(
                active: $activeScreen,
                onSelectTab: { activeScreen = $0 },
                onSettings: openSettingsWindow,
                rightActions: { mastheadActions }
            )

            Group {
                switch activeScreen {
                case .analysis:
                    analysisLayout
                case .explorer:
                    ExplorerScreenView()
                case .database:
                    DatabaseBrowserView(onGameSelected: { game in
                        loadGame(game)
                        activeScreen = .analysis
                    }, onReferenceGameSelected: { pgn in
                        loadGameFromPGN(pgn)
                        activeScreen = .analysis
                    })
                case .repertoire:
                    RepertoireBrowserView()
                case .chesscom:
                    ChessComBrowserView(onGameSelected: { game in
                        loadGame(game)
                        activeScreen = .analysis
                    })
                case .engine:
                    EngineManagerView()
                case .settings:
                    SettingsScreenView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AnnStatusBar(left: statusLeft, right: statusRight)
        }
        .background(GlassBackground(screen: activeScreen))
        .overlay { ReferenceActivityBadge() }
        .sheet(isPresented: $showingSaveSheet) {
            SaveGameView(gameTree: gameTree, database: database)
        }
        .onAppear {
            startEngineIfConfigured()
            updateCurrentOpening()
        }
        .onChange(of: gameTree.currentNode.id) { _, _ in
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

                if autoAnalyze && !gameAnalyzer.isAnalyzing {
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
                    if autoAnalyze, lookAheadNodeId == nil,
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

    // MARK: - Masthead & status bar

    @ViewBuilder private var mastheadActions: some View {
        switch activeScreen {
        case .analysis:
            Button("Run Review") { startGameAnalysis() }
                .buttonStyle(AnnButtonStyle(kind: multiEngine.anyEngineAvailable ? .primary : .disabled))
                .disabled(!multiEngine.anyEngineAvailable || gameAnalyzer.isAnalyzing)
        default:
            EmptyView()
        }
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
            let verticalExtras = boardAreaComponents.labelHeight + boardAreaComponents.bottomControlsHeight + 40

            // Max board size from height
            let maxBoardFromHeight = availableHeight - verticalExtras

            // Max board size from width (after reserving minimum sidebar space)
            let minSidebarsTotal = minExplorerWidth + minRightSidebarWidth + (sidebarGap * 2) + 2
            let maxBoardFromWidth = availableWidth - minSidebarsTotal - boardExtras

            // Board = min(width-constrained, height-constrained), clamped to minimum 300
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
                        AnnSearchField(text: $explorerSearchText, placeholder: "Search openings…")
                    }
                    .padding(16)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

                    if explorerSource == .lichess {
                        LichessExplorerView(
                            explorerService: lichessExplorer,
                            openingBook: openingBook,
                            board: board,
                            currentMoves: getMoveSequenceUCI(),
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
                            currentMoves: getMoveSequenceUCI(),
                            currentSANs: getMoveSequenceSAN(),
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

                // Board area — Annotator board (players · double frame · eval bar · plate)
                VStack(spacing: 0) {
                    // Slim toolbar: new game · save · flip
                    HStack(spacing: 6) {
                        boardIconButton("arrow.counterclockwise", "New Game") { resetGame() }
                        boardIconButton("square.and.arrow.down", "Save Game") { showingSaveSheet = true }
                        Spacer()
                        boardIconButton("arrow.up.arrow.down",
                                        isBoardFlipped ? "View as White" : "View as Black",
                                        active: isBoardFlipped) { isBoardFlipped.toggle() }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

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
                        plyCount: getMoveSequenceSAN().count,
                        isFlipped: isBoardFlipped,
                        explorerArrow: engineArrow
                    )
                    .padding(.vertical, 20)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .background(GlassBoardAreaBackground())
                .overlay(alignment: .leading) { Rectangle().fill(DS.hairline).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }

                // Right sidebar — sections separated by bottom borders, no card styling
                VStack(spacing: 0) {
                    CurrentOpeningView(
                        openingName: currentOpeningName,
                        eco: currentOpeningECO
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DS.hairline).frame(height: 1)
                    }

                    AnalysisPanelView(
                        multiEngine: multiEngine,
                        gameTree: gameTree,
                        autoAnalyze: $autoAnalyze,
                        gameAnalyzer: gameAnalyzer,
                        onStartAnalysis: startGameAnalysis,
                        onCancelAnalysis: cancelGameAnalysis,
                        onNavigateToEngines: { openWindow(id: WindowID.engineRoom) }
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DS.hairline).frame(height: 1)
                    }

                    if gameAnalyzer.isCompleted {
                        GameAnalysisResultsView(
                            gameAnalyzer: gameAnalyzer,
                            gameTree: gameTree
                        )
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }
                    }

                    MoveListView(gameTree: gameTree)
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
        let evalBarWidth: CGFloat = 24
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
            if autoAnalyze {
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
        board.squares = currentBoard.squares
        board.turn = currentBoard.turn
        board.moveHistory = currentBoard.moveHistory
        board.enPassantTarget = currentBoard.enPassantTarget
        board.halfMoveClock = currentBoard.halfMoveClock
        board.fullMoveNumber = currentBoard.fullMoveNumber
        isSyncingBoard = false
    }

    private func resetGame() {
        // Cancel and reset game analysis
        gameAnalyzer.cancel()
        gameAnalyzer.reset()

        // Cancel any pending evaluation and stop all engines
        evaluationDebounceTask?.cancel()
        evaluationDebounceTask = nil
        multiEngine.stopAll()

        let newBoard = ChessBoard()
        board.squares = newBoard.squares
        board.turn = newBoard.turn
        board.moveHistory = newBoard.moveHistory
        board.enPassantTarget = newBoard.enPassantTarget
        board.halfMoveClock = newBoard.halfMoveClock
        board.fullMoveNumber = newBoard.fullMoveNumber

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
        currentGameId = nil

        // Use debounced evaluation — onChange may also trigger it,
        // but the debounce ensures only one evaluation runs
        if autoAnalyze {
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

        // Track current game for saving analysis
        currentGameId = game.id

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

        // Restore analysis from database if available, otherwise reset
        if let analysisData = game.analysisData {
            gameAnalyzer.restoreFromAnalysisData(analysisData, gameTree: gameTree)
        } else {
            gameAnalyzer.reset()
        }

        // Trigger evaluation
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
        if autoAnalyze {
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

    private func updateCurrentOpening() {
        // Get the move sequence from root to current position
        let uciMoves = getMoveSequenceUCI()

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
                let uci = moveToUCI(move)
                moves.append(uci)
            }
        }

        return moves
    }

    private func getPathToCurrentNode() -> [GameNode] {
        var path: [GameNode] = []
        var current: GameNode? = gameTree.currentNode

        while let node = current {
            path.insert(node, at: 0)
            current = node.parent
        }

        return path
    }

    private func moveToUCI(_ move: Move) -> String {
        let files = "abcdefgh"
        let fromFile = files[files.index(files.startIndex, offsetBy: move.from.file)]
        let fromRank = move.from.rank + 1
        let toFile = files[files.index(files.startIndex, offsetBy: move.to.file)]
        let toRank = move.to.rank + 1

        var uci = "\(fromFile)\(fromRank)\(toFile)\(toRank)"

        // Add promotion piece if applicable
        if let promotion = move.promotionType {
            switch promotion {
            case .queen: uci += "q"
            case .rook: uci += "r"
            case .bishop: uci += "b"
            case .knight: uci += "n"
            default: break
            }
        }

        return uci
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
        board.squares = newBoard.squares
        board.turn = newBoard.turn
        board.moveHistory = newBoard.moveHistory
        board.enPassantTarget = newBoard.enPassantTarget
        board.halfMoveClock = newBoard.halfMoveClock
        board.fullMoveNumber = newBoard.fullMoveNumber

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
        if autoAnalyze {
            evaluatePositionDebounced()
        }
    }
}

// MARK: - Board Status Bar

struct BoardStatusBar: View {
    @ObservedObject var board: ChessBoard
    @ObservedObject var engine: StockfishEngine
    @Binding var isBoardFlipped: Bool
    let whiteName: String
    let blackName: String
    let whiteRating: String
    let blackRating: String
    let onNewGame: () -> Void
    let onSave: () -> Void

    private var whiteDisplayName: String {
        whiteName.isEmpty ? "White" : whiteName
    }

    private var blackDisplayName: String {
        blackName.isEmpty ? "Black" : blackName
    }

    private var evalText: String {
        guard let eval = engine.evaluation else { return "—" }
        if abs(eval) >= 10000 {
            let mateIn = Int(abs(eval) - 10000)
            if mateIn == 0 { return eval > 0 ? "1-0" : "0-1" }
            return "\(eval > 0 ? "+" : "-")M\(mateIn)"
        }
        let pv = eval / 100.0
        if abs(pv) < 0.05 { return "0.0" }
        return String(format: "%+.1f", pv)
    }

    private var evalColor: Color {
        guard let eval = engine.evaluation else { return DS.evalNeutral }
        let pv = eval / 100.0
        if abs(pv) < 0.3 { return DS.evalNeutral }
        return eval > 0 ? DS.evalWhiteWinning : DS.evalBlackWinning
    }

    private var evalTextColor: Color {
        guard let eval = engine.evaluation else { return .white }
        let pv = eval / 100.0
        if abs(pv) < 0.3 { return .white }
        return eval > 0 ? .black : .white
    }

    var body: some View {
        HStack(spacing: 6) {
            // Toolbar buttons (left group)
            HStack(spacing: 6) {
                toolbarButton(icon: "arrow.counterclockwise", action: onNewGame, help: "New Game")
                toolbarButton(icon: "square.and.arrow.down", action: onSave, help: "Save Game")
            }

            Spacer()

            // Player info (center)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: 0xECECEC))
                    .frame(width: 10, height: 10)
                Text("\(whiteDisplayName)\(!whiteRating.isEmpty ? " (\(whiteRating))" : "")")
                    .font(AnnFont.serif(12, .medium))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))

                Text("vs")
                    .font(AnnFont.serif(11, .regular))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.2))

                Circle()
                    .fill(Color(hex: 0x262626))
                    .overlay(Circle().strokeBorder(Color(hex: 0xFFFFFF, opacity: 0.2), lineWidth: 1))
                    .frame(width: 10, height: 10)
                Text("\(blackDisplayName)\(!blackRating.isEmpty ? " (\(blackRating))" : "")")
                    .font(AnnFont.serif(12, .medium))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))

                RepertoireDeviationBadge(board: board)
            }

            Spacer()

            // Right group
            toolbarButton(
                icon: "arrow.up.arrow.down",
                action: { isBoardFlipped.toggle() },
                isActive: isBoardFlipped,
                help: isBoardFlipped ? "View as White" : "View as Black"
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private func toolbarButton(icon: String, action: @escaping () -> Void, isActive: Bool = false, help: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(isActive ? DS.accent : Color(hex: 0xFFFFFF, opacity: 0.67))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(GameDatabase.preview())
        .environmentObject(ReferenceDatabase())
        .frame(width: 1300, height: 850)
}
