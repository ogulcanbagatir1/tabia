import SwiftUI

struct LibraryExplorerView: View {
    @ObservedObject var explorerService: LibraryExplorerService
    @EnvironmentObject var database: GameDatabase
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

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: folder picker + loading indicator
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
            } else if let response = explorerService.response {
                if response.totalGames == 0 && response.moves.isEmpty {
                    emptyResultsView
                } else {
                    explorerContent(response)
                }
            } else if explorerService.isLoading {
                loadingView
            } else {
                emptyView
            }
        }
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
        }
        .onChange(of: currentSANs) { _, _ in
            analyzeCurrentPosition()
        }
        .onChange(of: selectedFolderIds) { _, _ in
            prepareAndAnalyze()
        }
    }

    // MARK: - Folder Picker

    private var folderPickerLabel: String {
        let totalFolders = database.folders.count + 1 // +1 for unfiled
        if selectedFolderIds.count == totalFolders {
            return "All"
        } else if selectedFolderIds.isEmpty {
            return "None"
        } else {
            return "\(selectedFolderIds.count) selected"
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
                }
                .buttonStyle(GlassButtonStyle())
                .controlSize(.small)

                Button("None") {
                    selectedFolderIds = []
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
                }
            }
            .frame(maxHeight: 200)
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
    private func explorerContent(_ response: LibraryExplorerResponse) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Opening info — always show opening name + ECO when available
                openingInfoSection(
                    totalGames: response.totalGames,
                    stats: (response.whiteWins, response.draws, response.blackWins)
                )

                // Moves table
                if !response.moves.isEmpty {
                    movesTableHeader

                    ForEach(Array(response.moves.enumerated()), id: \.element.id) { index, move in
                        moveRow(move, isAlternate: index % 2 == 0)
                    }
                }

                // Sample games
                if !response.sampleGames.isEmpty {
                    sampleGamesSection(response.sampleGames)
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
}
