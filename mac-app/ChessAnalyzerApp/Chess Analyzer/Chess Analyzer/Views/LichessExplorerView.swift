import SwiftUI

struct LichessExplorerView: View {
    @ObservedObject var explorerService: LichessExplorerService
    @ObservedObject var openingBook: OpeningBook
    @ObservedObject private var settings = AppSettings.shared
    var board: ChessBoard
    let currentMoves: [String]
    @Binding var searchText: String
    let onMovePlayed: (String) -> Void
    let onGameLoaded: (String) -> Void
    let onOpeningSelected: ([String]) -> Void

    @ObservedObject private var authService = LichessAuthService.shared

    @State private var isLoadingGame = false
    @State private var loadingGameId: String? = nil
    @State private var authError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if !searchText.isEmpty {
                OpeningSearchResultsList(
                    openingBook: openingBook,
                    searchText: searchText,
                    onOpeningSelected: onOpeningSelected,
                    searchBinding: $searchText
                )
            } else if explorerService.needsAuth {
                authView
            } else if let error = explorerService.error {
                errorView(error)
            } else if let response = explorerService.response {
                explorerContent(response)
            } else if explorerService.isLoading {
                loadingView
            } else if settings.lichessToken.isEmpty {
                authView
            } else {
                emptyView
            }
        }
        .background(.clear)
        .onAppear {
            syncToken()
            if explorerService.response == nil && !explorerService.isLoading {
                fetchData()
            }
        }
        .onChange(of: currentMoves) { _, _ in
            fetchData()
        }
    }

    private func syncToken() {
        explorerService.token = settings.lichessToken
    }

    private func fetchData() {
        syncToken()
        let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        explorerService.fetchExplorerData(fen: startingFEN, moves: currentMoves, topGames: 15)
    }

    // MARK: - Explorer Content

    /// Resolve opening name + ECO: prefer API response, fallback to opening book
    private var resolvedOpening: (name: String, eco: String)? {
        if let opening = explorerService.response?.opening {
            return (opening.name, opening.eco)
        }
        return openingBook.findOpening(moves: currentMoves)
    }

    @ViewBuilder
    private func explorerContent(_ response: LichessExplorerResponse) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Opening info section — always show opening name + ECO when available
                openingInfoSection(
                    totalGames: response.totalGames,
                    stats: (response.white, response.draws, response.black)
                )

                // Moves table header
                if !response.moves.isEmpty {
                    movesTableHeader

                    // Move rows
                    ForEach(Array(response.moves.enumerated()), id: \.element.id) { index, move in
                        moveRow(move, isAlternate: index % 2 == 0)
                    }
                }

                // Notable games
                if let topGames = response.topGames, !topGames.isEmpty {
                    notableGamesSection(topGames)
                }
            }
        }
    }

    // MARK: - Opening Info

    private func openingInfoSection(totalGames: Int, stats: (white: Int, draws: Int, black: Int)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Opening name — bold, prominent
            if let opening = resolvedOpening {
                Text(opening.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(formatGameCount(totalGames))
                    .font(.system(size: 11))
                    .foregroundColor(DS.textTertiary)
            } else {
                Text(formatGameCount(totalGames))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
            }

            // WDL bar
            WDLStatsBar(
                white: totalGames > 0 ? stats.white : 0,
                draws: totalGames > 0 ? stats.draws : 0,
                black: totalGames > 0 ? stats.black : 0
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    // MARK: - Moves Table

    private var movesTableHeader: some View {
        HStack(spacing: 0) {
            Text("Move")
            Text("Games")
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("W / D / L")
                .frame(width: 80, alignment: .center)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(DS.textTertiary)
        .kerning(0.5)
        .textCase(.uppercase)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color.white.opacity(0.03))
    }

    private func moveRow(_ move: LichessMove, isAlternate: Bool) -> some View {
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

    // MARK: - Notable Games

    private func notableGamesSection(_ games: [LichessGame]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Notable Games")
                .padding(.top, 4)

            ForEach(games) { game in
                gameRow(game)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.19)).frame(height: 1)
        }
    }

    private func gameRow(_ game: LichessGame) -> some View {
        let result: String = {
            switch game.winner {
            case "white": return "1-0"
            case "black": return "0-1"
            default: return "1/2-1/2"
            }
        }()
        let date = game.month ?? (game.year.map { String($0) })

        return ExplorerGameRow(
            white: game.white.name ?? "?",
            black: game.black.name ?? "?",
            whiteWeight: game.winner == "white" ? .bold : .regular,
            blackWeight: game.winner == "black" ? .bold : .regular,
            result: result,
            whiteRating: game.white.rating.map(String.init) ?? "",
            blackRating: game.black.rating.map(String.init) ?? "",
            date: date,
            isLoading: isLoadingGame && loadingGameId == game.id
        ) {
            loadGame(game.id)
        }
    }

    private func loadGame(_ gameId: String) {
        guard !isLoadingGame else { return }

        isLoadingGame = true
        loadingGameId = gameId

        explorerService.fetchGamePGN(gameId: gameId) { result in
            isLoadingGame = false
            loadingGameId = nil

            switch result {
            case .success(let pgn):
                onGameLoaded(pgn)
            case .failure(let error):
                print("Failed to load game: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helper Views

    private var loadingView: some View {
        LoadingStateView(message: "Loading...")
    }

    private var emptyView: some View {
        EmptyStateView(
            icon: "book",
            title: "No Opening Data",
            description: "Play moves on the board to explore openings from the Lichess Masters database",
            iconSize: 40
        )
    }

    private var authView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundColor(DS.accentOrange)

            Text("Authentication Required")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.textPrimary)

            Text("Lichess now requires you to log in to access the Masters database.")
                .font(.system(size: 12))
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let authError = authError {
                Text(authError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                self.authError = nil
                authService.startOAuth { result in
                    switch result {
                    case .success(let token):
                        settings.lichessToken = token
                        explorerService.token = token
                        explorerService.clearCache()
                        fetchData()
                    case .failure(let error):
                        self.authError = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if authService.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(authService.isAuthenticating ? "Waiting for Lichess..." : "Login with Lichess")
                }
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .disabled(authService.isAuthenticating)

            Text("Opens lichess.org in your browser")
                .font(.system(size: 10))
                .foregroundColor(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: DS.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(DS.accentOrange)

            Text(error)
                .font(.system(size: 12))
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                fetchData()
            }
            .buttonStyle(GlassButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
