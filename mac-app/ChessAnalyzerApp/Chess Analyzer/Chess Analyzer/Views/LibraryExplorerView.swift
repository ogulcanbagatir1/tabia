import SwiftUI

/// The explorer's display model: the user's own library stats optionally blended with the
/// reference DB's. Both sources produce the same per-move W/D/L shape, so they sum by move.
private struct MergedExplorer {
    var white = 0
    var draw = 0
    var black = 0
    var moves: [LibraryMoveStats] = []
    var sampleGames: [GameRecordSnapshot] = []

    var total: Int { white + draw + black }
    var hasData: Bool { total > 0 || !moves.isEmpty }
}

struct LibraryExplorerView: View {
    @ObservedObject var explorerService: LibraryExplorerService
    @EnvironmentObject var database: GameDatabase
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    @ObservedObject var openingBook: OpeningBook
    @ObservedObject var board: ChessBoard
    let currentMoves: [String]  // UCI move sequence from root to current node
    let currentSANs: [String]   // SAN move sequence from root to current node
    @Binding var searchText: String
    let onMovePlayed: (String) -> Void
    let onGameLoaded: (String) -> Void  // Called with PGN string
    let onOpeningSelected: ([String]) -> Void

    @State private var selectedFolderIds: Set<UUID?> = []  // nil = unfiled
    @State private var isInitialized = false
    @State private var showingFolderPicker = false

    // Reference DB is just another database in the library: opt in via the picker and its
    // per-position stats (Zobrist, transposition-aware) blend into the same W/D/L table.
    @State private var includeReference = false
    @State private var referenceResult = ReferenceExplorerResult()
    @State private var showingIndexing = false

    // The modifier chain is split across `body`/`baseView` so each `some View` expression stays
    // small enough for the SwiftUI type-checker (a long single chain trips its timeout).
    var body: some View {
        baseView
            .onChange(of: includeReference) { _, _ in
                queryReference()
            }
            .onChange(of: referenceDatabase.indexedGameCount) { _, _ in
                queryReference()
            }
            .sheet(isPresented: $showingIndexing) {
                IndexingSheet(referenceDB: referenceDatabase) { showingIndexing = false }
            }
    }

    private var baseView: some View {
        content
            .background(DS.bgSecondary)
            .onAppear {
                if !isInitialized {
                    // Select all folders + unfiled by default
                    var ids: Set<UUID?> = [nil]  // unfiled
                    for folder in database.folders {
                        ids.insert(folder.id)
                    }
                    selectedFolderIds = ids
                    isInitialized = true
                    prepareAndAnalyze()
                } else {
                    analyzeCurrentPosition()
                }
                queryReference()
            }
            .onChange(of: currentSANs) { _, _ in
                analyzeCurrentPosition()
                queryReference()
            }
            .onChange(of: selectedFolderIds) { _, _ in
                prepareAndAnalyze()
            }
    }

    // Split out so the lifecycle-modifier chain on `body` type-checks quickly.
    private var content: some View {
        VStack(spacing: 0) {
            toolbar

            Rectangle()
                .fill(DS.glassSeparator)
                .frame(height: 1)

            if !searchText.isEmpty {
                OpeningSearchResultsList(
                    openingBook: openingBook,
                    searchText: searchText,
                    onOpeningSelected: onOpeningSelected,
                    searchBinding: $searchText
                )
            } else {
                libraryBody
            }
        }
    }

    // Toolbar: the databases picker (folders + unfiled + reference DB).
    private var toolbar: some View {
        HStack(spacing: DS.spacingSM) {
            Button(action: { showingFolderPicker.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(folderPickerLabel)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.bgSecondary)
                .cornerRadius(DS.radiusSM)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingFolderPicker) {
                folderPickerPopover
            }

            Spacer()
        }
        .padding(.horizontal, DS.spacingMD)
        .padding(.vertical, DS.spacingSM)
    }

    /// The non-search body: merged library + reference results, or the appropriate empty/loading state.
    @ViewBuilder
    private var libraryBody: some View {
        let data = mergedData()   // compute once per render
        if data.hasData {
            explorerContent(data)
        } else if explorerService.isLoading {
            loadingView
        } else if referenceCheckedButUnindexed {
            referenceUnindexedState
        } else if explorerService.response != nil {
            emptyResultsView
        } else {
            emptyView
        }
    }

    // MARK: - Folder Picker

    /// The reference DB is only offered as a database once it has been downloaded.
    private var referenceAvailable: Bool { referenceDatabase.gameCount > 0 }

    private var folderPickerLabel: String {
        // Databases = folders + unfiled + (reference, if downloaded).
        let totalDatabases = database.folders.count + 1 + (referenceAvailable ? 1 : 0)
        let selected = selectedFolderIds.count + (includeReference ? 1 : 0)
        if selected == totalDatabases {
            return "All"
        } else if selected == 0 {
            return "None"
        } else {
            return "\(selected) selected"
        }
    }

    private var folderPickerPopover: some View {
        VStack(alignment: .leading, spacing: DS.spacingXS) {
            Text("Select Databases")
                .font(.system(size: 12, weight: .semibold))
                .padding(.bottom, DS.spacingXS)

            // Select All / None
            HStack {
                Button("All") {
                    var ids: Set<UUID?> = [nil]
                    for folder in database.folders {
                        ids.insert(folder.id)
                    }
                    selectedFolderIds = ids
                    includeReference = referenceAvailable
                }
                .buttonStyle(GlassButtonStyle())
                .controlSize(.small)

                Button("None") {
                    selectedFolderIds = []
                    includeReference = false
                }
                .buttonStyle(GlassButtonStyle())
                .controlSize(.small)
            }
            .padding(.bottom, DS.spacingXS)

            Rectangle()
                .fill(DS.glassSeparator)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Unfiled option
                    folderCheckbox(label: "Unfiled Games", id: nil)

                    // Folders
                    ForEach(database.folders, id: \.id) { folder in
                        folderCheckbox(label: folder.name, id: folder.id)
                    }

                    // Reference DB — a read-only database that lives alongside your own.
                    if referenceAvailable {
                        Rectangle()
                            .fill(DS.glassSeparator)
                            .frame(height: 1)
                            .padding(.vertical, 3)
                        referenceCheckbox
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(DS.spacingMD)
        .frame(width: 220)
    }

    private func folderCheckbox(label: String, id: UUID?) -> some View {
        Button(action: {
            if selectedFolderIds.contains(id) {
                selectedFolderIds.remove(id)
            } else {
                selectedFolderIds.insert(id)
            }
        }) {
            HStack(spacing: DS.spacingSM) {
                Image(systemName: selectedFolderIds.contains(id) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(selectedFolderIds.contains(id) ? DS.accent : DS.textSecondary)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(DS.textPrimary)

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var referenceCheckbox: some View {
        Button(action: { includeReference.toggle() }) {
            HStack(spacing: DS.spacingSM) {
                Image(systemName: includeReference ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(includeReference ? DS.accent : DS.textSecondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(referenceDatabase.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(DS.textPrimary)
                        .lineLimit(1)
                    Text(referenceDatabase.indexedGameCount == 0
                         ? "Reference · not indexed"
                         : "Reference · \(formatNumber(referenceDatabase.indexedGameCount)) indexed")
                        .font(.system(size: 9))
                        .foregroundColor(DS.textTertiary)
                }

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Fetching

    /// Show loading immediately, then gather games and analyze on next run loop tick.
    private func prepareAndAnalyze() {
        explorerService.isLoading = true
        explorerService.response = nil

        // Defer heavy work so the loading UI renders first
        DispatchQueue.main.async {
            let games = gatherSelectedGames()
            explorerService.prepareAndAnalyze(games: games, currentSANs: currentSANs, board: board, openingBook: openingBook)
        }
    }

    /// Analyze just the current position (games already prepared). Fast.
    private func analyzeCurrentPosition() {
        explorerService.analyze(currentSANs: currentSANs, board: board, openingBook: openingBook)
    }

    private func gatherSelectedGames() -> [GameRecord] {
        let cap = 100_000
        var games: [GameRecord] = []
        for id in selectedFolderIds {
            let remaining = cap - games.count
            guard remaining > 0 else { break }
            if let folderId = id {
                games.append(contentsOf: database.gamesInFolder(folderId, limit: remaining))
            } else {
                games.append(contentsOf: database.unfiledGames(limit: remaining))
            }
        }
        return games
    }

    // MARK: - Reference DB merge

    /// Re-query the reference DB for the current position (transposition-aware, Zobrist).
    private func queryReference() {
        guard includeReference, referenceDatabase.isAvailable, referenceDatabase.gameCount > 0 else {
            if referenceResult.total != 0 || !referenceResult.moves.isEmpty {
                referenceResult = ReferenceExplorerResult()
            }
            return
        }
        referenceResult = referenceDatabase.explorer(board: board)
    }

    /// Reference DB is selected but nothing is searchable (indexed) yet.
    private var referenceCheckedButUnindexed: Bool {
        includeReference && referenceAvailable && referenceDatabase.indexedGameCount == 0
    }

    /// Library response + (optionally) the reference result, merged by move into one view.
    private func mergedData() -> MergedExplorer {
        var m = MergedExplorer()

        // While the reference is folded in AND the library is re-aggregating in the background,
        // `explorerService.response` still holds the PREVIOUS position/folder set. Summing that
        // stale library count with the fresh reference result would show wrong cross-position
        // totals, so drop the library side until it catches up (reference-only, always current).
        // The library-only path keeps its original behaviour (brief stale data while loading).
        let libraryValid = !(includeReference && explorerService.isLoading)
        if libraryValid, let r = explorerService.response {
            m.white = r.whiteWins
            m.draw = r.draws
            m.black = r.blackWins
            m.moves = r.moves
            m.sampleGames = r.sampleGames
        }
        guard includeReference, referenceResult.total > 0 else { return m }

        // NOTE: the two sides count games slightly differently — the reference index only stores
        // a row *before* each move, so a game that ENDS exactly at this position isn't in the
        // reference totals, whereas the library counts it. The gap is games terminating on the
        // current position (≈0 for openings), so the merged header can marginally undercount the
        // reference side. Reconciling would require re-indexing the reference DB, so we accept it.
        m.white += referenceResult.white
        m.draw += referenceResult.draw
        m.black += referenceResult.black

        // Sum reference per-move counts into the library moves, then append reference-only moves.
        // Match by UCI first; fall back to normalized SAN because the library stores a raw SAN as
        // the "uci" when NotationEngine can't parse it (e.g. nonstandard castling) — that bogus key
        // would never equal the reference's real UCI, splitting one move across two rows.
        var indexByUci: [String: Int] = [:]
        var indexBySan: [String: Int] = [:]
        for (i, mv) in m.moves.enumerated() {
            indexByUci[mv.uci] = i
            indexBySan[Self.normalizedSAN(mv.san)] = i
        }
        for e in referenceResult.moves {
            if let i = indexByUci[e.uci] ?? indexBySan[Self.normalizedSAN(e.san)] {
                m.moves[i].whiteWins += e.white
                m.moves[i].draws += e.draw
                m.moves[i].blackWins += e.black
            } else {
                var nm = LibraryMoveStats(san: e.san, uci: e.uci)
                nm.whiteWins = e.white
                nm.draws = e.draw
                nm.blackWins = e.black
                let idx = m.moves.count
                indexByUci[e.uci] = idx
                indexBySan[Self.normalizedSAN(e.san)] = idx
                m.moves.append(nm)
            }
        }
        m.moves.sort { $0.totalGames > $1.totalGames }
        return m
    }

    /// Canonicalize a SAN for cross-source matching: drop check/mate marks and unify castling
    /// spellings (O-O / 0-0 / OO all collapse to "O-O") so library and reference rows align.
    private static func normalizedSAN(_ san: String) -> String {
        let stripped = san.replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "#", with: "")
        switch stripped.uppercased() {
        case "O-O", "0-0", "OO":       return "O-O"
        case "O-O-O", "0-0-0", "OOO":  return "O-O-O"
        default:                       return stripped
        }
    }

    /// Resolve opening: prefer response data, fallback to opening book
    private var resolvedOpening: (name: String, eco: String)? {
        if let name = explorerService.response?.openingName,
           let eco = explorerService.response?.openingECO {
            return (name, eco)
        }
        return openingBook.findOpening(moves: currentMoves)
    }

    // MARK: - Explorer Content

    @ViewBuilder
    private func explorerContent(_ data: MergedExplorer) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Reference selected but not searchable yet — surface the index builder inline.
                if referenceCheckedButUnindexed {
                    referenceIndexBanner
                }

                // Opening info — always show opening name + ECO when available
                openingInfoSection(
                    totalGames: data.total,
                    stats: (data.white, data.draw, data.black)
                )

                // Moves table
                if !data.moves.isEmpty {
                    movesTableHeader

                    ForEach(Array(data.moves.enumerated()), id: \.element.id) { index, move in
                        moveRow(move, isAlternate: index % 2 == 0)
                    }
                }

                // Sample games
                if !data.sampleGames.isEmpty {
                    sampleGamesSection(data.sampleGames)
                }
            }
        }
    }

    // MARK: - Opening Info

    private func openingInfoSection(totalGames: Int, stats: (white: Int, draws: Int, black: Int)) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let opening = resolvedOpening {
                Text(opening.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    ECOBadge(eco: opening.eco)

                    Text(formatGameCount(totalGames))
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                }
            } else {
                Text(formatGameCount(totalGames))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
            }

            WDLStatsBar(white: stats.white, draws: stats.draws, black: stats.black)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    // MARK: - Moves Table

    private var movesTableHeader: some View {
        HStack(spacing: 0) {
            Text("Move")
            Text("Games")
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("W / D / L")
                .frame(width: 90, alignment: .center)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(DS.textTertiary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    private func moveRow(_ move: LibraryMoveStats, isAlternate: Bool) -> some View {
        let isBook = openingBook.findNode(moves: currentMoves + [move.uci]) != nil
        return ExplorerMoveRow(
            san: move.san,
            totalGames: move.totalGames,
            whitePercent: move.whitePercent,
            drawPercent: move.drawPercent,
            blackPercent: move.blackPercent,
            isBookMove: isBook,
            isAlternate: isAlternate
        ) {
            onMovePlayed(move.uci)
        }
    }

    // MARK: - Sample Games Section

    private func sampleGamesSection(_ games: [GameRecordSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Games in Position")
                .padding(.top, 4)

            ForEach(games, id: \.id) { game in
                gameRow(game)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    private func gameRow(_ game: GameRecordSnapshot) -> some View {
        ExplorerGameRow(
            white: game.white,
            black: game.black,
            whiteWeight: game.result == "1-0" ? .bold : .regular,
            blackWeight: game.result == "0-1" ? .bold : .regular,
            result: game.result,
            date: game.date.isEmpty ? nil : game.date
        ) {
            onGameLoaded(game.pgn)
        }
    }

    private func formatGameCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: n)) ?? "\(n)") + " games"
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }

    // MARK: - Helper Views

    private var loadingView: some View {
        LoadingStateView(message: "Analyzing library...")
    }

    private var emptyView: some View {
        EmptyStateView(
            icon: "books.vertical",
            title: "No Library Data",
            description: "Select databases to explore your personal opening repertoire",
            iconSize: 40
        )
    }

    private var emptyResultsView: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Games Found",
            description: "No games found in this position from the selected databases",
            iconSize: 40
        )
    }

    /// Slim inline banner shown above library results when the reference DB is selected but
    /// not indexed yet (so the user understands why it isn't contributing, with a way to fix it).
    private var referenceIndexBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 12))
                .foregroundColor(DS.accent)
            Text("\(referenceDatabase.displayName) isn't indexed — build the opening index to include it.")
                .font(.system(size: 10))
                .foregroundColor(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button("Build") { showingIndexing = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    /// Full empty state when the reference DB is the only selected source and it isn't indexed.
    private var referenceUnindexedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(DS.accent)
            Text("Reference DB Not Indexed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.textPrimary)
            Text("Build the opening index to include \(referenceDatabase.displayName) in your library explorer.")
                .font(.system(size: 12))
                .foregroundColor(DS.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button(action: { showingIndexing = true }) {
                Label("Build opening index", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
