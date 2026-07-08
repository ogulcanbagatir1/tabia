import Foundation

// Dev-only sample data, gated behind the TABIA_SEED env var (never runs in normal use).
// Lets the data-populated screens (Database ledger, Games, Repertoire shelf, Engine room)
// render during redesign verification. Seeds only when the library is empty.

enum DevSeed {
    static func seedIfRequested(database: GameDatabase, repertoire: RepertoireDatabase, settings: AppSettings) {
        guard ProcessInfo.processInfo.environment["TABIA_SEED"] != nil else { return }
        guard database.libraryGameCount == 0 else { return }

        let classics = database.createFolder(name: "Classics")
        let studies = database.createFolder(name: "Studies")

        func pgn(_ w: String, _ b: String, _ r: String, _ eco: String, _ moves: String) -> String {
            "[Event \"?\"]\n[White \"\(w)\"]\n[Black \"\(b)\"]\n[Result \"\(r)\"]\n[ECO \"\(eco)\"]\n\n\(moves) \(r)\n"
        }
        let body = "1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e5 7. Nb3 Be6 8. f3 Be7"

        // Personal library — Classics
        let classicGames: [GameRecord] = [
            GameRecord(event: "World Championship", site: "Reykjavik", date: "1972.07.16", round: "6",
                       white: "Spassky, Boris", black: "Fischer, Robert", result: "0-1",
                       eco: "D59", opening: "Queen's Gambit Declined, Tartakower",
                       pgn: pgn("Spassky, Boris", "Fischer, Robert", "0-1", "D59", body),
                       folder: classics, whiteElo: 2660, blackElo: 2785),
            GameRecord(event: "Candidates", site: "Zürich", date: "1953.09.12", round: "2",
                       white: "Bronstein, David", black: "Keres, Paul", result: "1-0",
                       eco: "E58", opening: "Nimzo-Indian, Main Line",
                       pgn: pgn("Bronstein, David", "Keres, Paul", "1-0", "E58", body),
                       folder: classics, whiteElo: 2600, blackElo: 2610),
            GameRecord(event: "Linares", site: "Linares", date: "1993.03.01", round: "10",
                       white: "Kasparov, Garry", black: "Karpov, Anatoly", result: "1/2-1/2",
                       eco: "B90", opening: "Sicilian, Najdorf",
                       pgn: pgn("Kasparov, Garry", "Karpov, Anatoly", "1/2-1/2", "B90", body),
                       folder: classics, whiteElo: 2815, blackElo: 2760),
            GameRecord(event: "USSR Championship", site: "Moscow", date: "1969.09.20", round: "17",
                       white: "Tal, Mikhail", black: "Polugaevsky, Lev", result: "1-0",
                       eco: "B96", opening: "Sicilian, Najdorf, Polugaevsky",
                       pgn: pgn("Tal, Mikhail", "Polugaevsky, Lev", "1-0", "B96", body),
                       folder: classics, whiteElo: 2650, blackElo: 2620),
        ]
        // Studies
        let studyGames: [GameRecord] = [
            GameRecord(event: "Study", site: "?", date: "2024.01.10", round: "?",
                       white: "Najdorf line", black: "English Attack", result: "*",
                       eco: "B90", opening: "Sicilian, Najdorf, English Attack",
                       pgn: pgn("Najdorf line", "English Attack", "*", "B90", body),
                       folder: studies, whiteElo: nil, blackElo: nil),
        ]
        // Online (Chess.com-synced) — sourceUsername populates the Games screen
        let onlineGames: [GameRecord] = (0..<6).map { i in
            let tc = ["bullet", "blitz", "blitz", "rapid", "rapid", "rapid"][i]
            let res = ["1-0", "0-1", "1-0", "1/2-1/2", "1-0", "0-1"][i]
            return GameRecord(event: "Live Chess", site: "Chess.com", date: "2026.07.0\(i+1)", round: "?",
                              white: i % 2 == 0 ? "BidiBoy1" : "opponent\(i)",
                              black: i % 2 == 0 ? "opponent\(i)" : "BidiBoy1",
                              result: res, eco: "B90", opening: "Sicilian, Najdorf",
                              pgn: pgn("BidiBoy1", "opponent\(i)", res, "B90", body),
                              timeClass: tc, sourceUsername: "BidiBoy1",
                              sourceUrl: "https://chess.com/game/\(i)",
                              whiteElo: 1760 + i * 3, blackElo: 1755 + i * 2)
        }
        database.addGames(classicGames + studyGames)
        database.addGames(onlineGames, isChessComImport: true)

        // Engines — guard separately: engine configs live in UserDefaults (persist across the
        // in-memory seed launches), so only add them when none exist to avoid accumulation.
        if settings.engines.isEmpty {
            settings.addEngine(EngineConfig(id: UUID(), name: "Stockfish 17.1", path: "/opt/homebrew/bin/stockfish", isDefault: true, source: .downloaded))
            settings.addEngine(EngineConfig(id: UUID(), name: "Leela Chess Zero", path: "/opt/homebrew/bin/lc0", isDefault: false, source: .downloaded))
        }

        // Repertoires
        _ = repertoire.createRepertoire(name: "Najdorf as Black", side: .black, summary: "Sicilian Najdorf — main lines and sidelines.")
        _ = repertoire.createRepertoire(name: "Ruy López as White", side: .white, summary: "Closed Ruy López, Chigorin & Breyer.")
        _ = repertoire.createRepertoire(name: "Caro-Kann Repair", side: .black, summary: "Fixing the lines you keep losing.")
    }
}
