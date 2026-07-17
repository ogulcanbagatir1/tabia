import Foundation

// MARK: - Library Explorer Data Structures

struct LibraryMoveStats: Identifiable {
    let san: String
    let uci: String
    var whiteWins: Int = 0
    var draws: Int = 0
    var blackWins: Int = 0

    var id: String { uci }

    var totalGames: Int { whiteWins + draws + blackWins }

    var whitePercent: Double {
        totalGames > 0 ? Double(whiteWins) / Double(totalGames) * 100 : 0
    }

    var drawPercent: Double {
        totalGames > 0 ? Double(draws) / Double(totalGames) * 100 : 0
    }

    var blackPercent: Double {
        totalGames > 0 ? Double(blackWins) / Double(totalGames) * 100 : 0
    }
}

/// Lightweight snapshot of a GameRecord for display in sample games list.
struct GameRecordSnapshot: Identifiable {
    let id: UUID
    let white: String
    let black: String
    let result: String
    let date: String
    let pgn: String
}

struct LibraryExplorerResponse {
    let openingName: String?
    let openingECO: String?
    let whiteWins: Int
    let draws: Int
    let blackWins: Int
    let moves: [LibraryMoveStats]
    let sampleGames: [GameRecordSnapshot]

    var totalGames: Int { whiteWins + draws + blackWins }
}

// MARK: - Parsed Game Cache Entry (just SAN moves + result — no board replay needed)

private struct ParsedGame {
    let sanMoves: [String]   // SAN moves from PGN (e.g. ["e4", "e5", "Nf3"])
    let result: String       // "1-0", "0-1", "1/2-1/2", "*"
    let snapshot: GameRecordSnapshot
}

// MARK: - Library Explorer Service

class LibraryExplorerService: ObservableObject {
    @Published var response: LibraryExplorerResponse?
    @Published var isLoading = false

    /// Cache: GameRecord.id → ParsedGame (just SAN moves, very lightweight)
    private var parsedCache: [UUID: ParsedGame] = [:]

    /// Pre-parsed games for currently selected folders
    private var preparsedGames: [ParsedGame] = []

    private var currentWorkItem: DispatchWorkItem?

    /// Prepare games from selected folders and immediately analyze the current position.
    /// Extracts data from SwiftData models on main thread (fast), then parses PGN + aggregates on background.
    func prepareAndAnalyze(games: [GameRecord], currentSANs: [String], board: ChessBoard, openingBook: OpeningBook) {
        currentWorkItem?.cancel()
        isLoading = true
        response = nil

        // Extract lightweight data from @Model objects on main thread (fast)
        var snapshots: [(id: UUID, pgn: String, result: String, snapshot: GameRecordSnapshot)] = []
        for game in games {
            let snap = GameRecordSnapshot(
                id: game.id, white: game.white, black: game.black,
                result: game.result, date: game.date, pgn: game.pgn
            )
            snapshots.append((game.id, game.pgn, game.result, snap))
        }

        let cacheSnapshot = parsedCache
        let boardCopy = board.copy()

        let workItem = DispatchWorkItem { [weak self] in
            // Parse PGN on background thread
            let parser = PGNParser()
            var newCacheEntries: [UUID: ParsedGame] = [:]
            var parsedGames: [ParsedGame] = []

            for entry in snapshots {
                if let cached = cacheSnapshot[entry.id] {
                    parsedGames.append(cached)
                    continue
                }

                let pgnGames = parser.parse(string: entry.pgn)
                guard let pgnGame = pgnGames.first, !pgnGame.moves.isEmpty else { continue }

                let cleanMoves = pgnGame.moves.map { Self.cleanSAN($0) }
                let parsed = ParsedGame(sanMoves: cleanMoves, result: entry.result, snapshot: entry.snapshot)
                newCacheEntries[entry.id] = parsed
                parsedGames.append(parsed)
            }

            let result = Self.aggregate(
                parsedGames: parsedGames,
                currentSANs: currentSANs,
                board: boardCopy,
                openingBook: openingBook
            )

            DispatchQueue.main.async {
                guard let self = self else { return }
                for (key, value) in newCacheEntries {
                    self.parsedCache[key] = value
                }
                self.preparsedGames = parsedGames
                self.response = result
                self.isLoading = false
            }
        }

        currentWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    /// Analyze just the current position (games already prepared). Fast — no PGN parsing.
    func analyze(currentSANs: [String], board: ChessBoard, openingBook: OpeningBook) {
        guard !preparsedGames.isEmpty else {
            response = nil
            return
        }

        currentWorkItem?.cancel()
        isLoading = true

        let games = preparsedGames
        let boardCopy = board.copy()

        let workItem = DispatchWorkItem { [weak self] in
            let result = Self.aggregate(
                parsedGames: games,
                currentSANs: currentSANs,
                board: boardCopy,
                openingBook: openingBook
            )

            DispatchQueue.main.async {
                self?.response = result
                self?.isLoading = false
            }
        }

        currentWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    func clearCache() {
        parsedCache.removeAll()
        preparsedGames = []
    }

    // MARK: - Clean SAN (strip +, #, annotations for matching)

    private static func cleanSAN(_ san: String) -> String {
        var s = san
        s = s.replacingOccurrences(of: "+", with: "")
        s = s.replacingOccurrences(of: "#", with: "")
        return s
    }

    // MARK: - Aggregation

    private static func aggregate(
        parsedGames: [ParsedGame],
        currentSANs: [String],
        board: ChessBoard,
        openingBook: OpeningBook
    ) -> LibraryExplorerResponse {
        let prefixCount = currentSANs.count

        // Collect unique next SANs and their stats
        var moveStatsDict: [String: (san: String, white: Int, draws: Int, black: Int)] = [:]
        var totalWhite = 0, totalDraws = 0, totalBlack = 0
        var sampleGames: [GameRecordSnapshot] = []

        for entry in parsedGames {
            let gameMoves = entry.sanMoves
            guard gameMoves.count >= prefixCount else { continue }

            // Check SAN prefix match
            var matches = true
            for i in 0..<prefixCount {
                if gameMoves[i] != currentSANs[i] {
                    matches = false
                    break
                }
            }
            guard matches else { continue }

            switch entry.result {
            case "1-0": totalWhite += 1
            case "0-1": totalBlack += 1
            case "1/2-1/2": totalDraws += 1
            default: break
            }

            if sampleGames.count < 10 {
                sampleGames.append(entry.snapshot)
            }

            if gameMoves.count > prefixCount {
                let nextSAN = gameMoves[prefixCount]

                var stats = moveStatsDict[nextSAN] ?? (san: nextSAN, white: 0, draws: 0, black: 0)
                switch entry.result {
                case "1-0": stats.white += 1
                case "0-1": stats.black += 1
                case "1/2-1/2": stats.draws += 1
                default: break
                }
                moveStatsDict[nextSAN] = stats
            }
        }

        // Convert unique next SANs → UCI using the current board
        let notation = NotationEngine(board: board)
        var moveStats: [LibraryMoveStats] = []
        for (san, stats) in moveStatsDict {
            let uci: String
            if let move = notation.fromAlgebraic(san) {
                uci = moveToUCI(move)
            } else {
                uci = san // fallback
            }
            moveStats.append(LibraryMoveStats(
                san: san, uci: uci,
                whiteWins: stats.white, draws: stats.draws, blackWins: stats.black
            ))
        }
        moveStats.sort { $0.totalGames > $1.totalGames }

        // Lookup opening using UCI moves from the board path
        let uciMoves = getMoveSequenceUCI(board: board)
        let opening = openingBook.findOpening(moves: uciMoves)

        return LibraryExplorerResponse(
            openingName: opening?.name,
            openingECO: opening?.eco,
            whiteWins: totalWhite,
            draws: totalDraws,
            blackWins: totalBlack,
            moves: moveStats,
            sampleGames: sampleGames
        )
    }

    // MARK: - UCI Helpers

    private static func moveToUCI(_ move: Move) -> String {
        let files = "abcdefgh"
        let fromFile = files[files.index(files.startIndex, offsetBy: move.from.file)]
        let fromRank = move.from.rank + 1
        let toFile = files[files.index(files.startIndex, offsetBy: move.to.file)]
        let toRank = move.to.rank + 1

        var uci = "\(fromFile)\(fromRank)\(toFile)\(toRank)"

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

    /// Get UCI move sequence from board's move history
    private static func getMoveSequenceUCI(board: ChessBoard) -> [String] {
        board.moveHistory.map { moveToUCI($0) }
    }
}
