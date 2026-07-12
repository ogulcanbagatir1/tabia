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

                // Move rows (no column header — the section frames itself)
                if !response.moves.isEmpty {
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
            if let opening = resolvedOpening {
                openingTitle(opening.name, eco: opening.eco)
            }

            Text("\(formatNumber(totalGames)) games reach this tabia")
                .font(AnnFont.voice(12))
                .foregroundColor(DS.ink40)

            // WDL bar (framed, with in-segment percentages)
            WDLStatsBar(
                white: totalGames > 0 ? stats.white : 0,
                draws: totalGames > 0 ? stats.draws : 0,
                black: totalGames > 0 ? stats.black : 0
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    /// Editorial opening title: the family in serif, the specific variation in the italic voice,
    /// plus a small ECO badge — e.g. "Ruy Lopez, Closed — *Chigorin Defence*  C98".
    private func openingTitle(_ name: String, eco: String) -> some View {
        let title: Text
        if let comma = name.range(of: ",", options: .backwards) {
            let main = String(name[..<comma.lowerBound])
            let sub = name[comma.upperBound...].trimmingCharacters(in: .whitespaces)
            title = Text(main).font(AnnFont.serif(15, .semibold))
                + Text(" — ").font(AnnFont.serif(15)).foregroundColor(DS.ink40)
                + Text(sub).font(AnnFont.voice(15))
        } else {
            title = Text(name).font(AnnFont.serif(15, .semibold))
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            title
                .foregroundColor(DS.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !eco.isEmpty {
                Text(eco)
                    .font(AnnFont.mono(10, bold: true)).foregroundColor(DS.ink40)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                    .fixedSize()
            }
        }
    }

    // MARK: - Moves Table

    /// "12. " for White to move, "12… " for Black — the move number the explorer's moves belong to.
    private var moveNumberPrefix: String {
        let n = currentMoves.count / 2 + 1
        return currentMoves.count % 2 == 0 ? "\(n). " : "\(n)… "
    }

    private func moveRow(_ move: LichessMove, isAlternate: Bool) -> some View {
        let isBook = openingBook.findNode(moves: currentMoves + [move.uci]) != nil
        return ExplorerMoveRow(
            movePrefix: moveNumberPrefix,
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
            Rectangle().fill(DS.hairline).frame(height: 1)
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
                .font(AnnFont.serif(14, .semibold))
                .foregroundColor(DS.textPrimary)

            Text("Lichess now requires you to log in to access the Masters database.")
                .font(AnnFont.serif(12))
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let authError = authError {
                Text(authError)
                    .font(AnnFont.serif(11))
                    .foregroundColor(DS.semLoss)
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
                .font(AnnFont.serif(10))
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
                .font(AnnFont.serif(12))
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
