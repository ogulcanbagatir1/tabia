import Foundation

/// An in-memory book of how a specific opponent (or a set of imported games) actually plays: for
/// each position, the moves they chose and how often. Keyed by the SAME Zobrist bit-pattern the
/// drill uses (`Zobrist.sqliteKey`), so it drops straight into the opponent-reply weighting for
/// tournament prep — "drill what Magnus does against your London, weighted by how often he does it".
///
/// Built off the fast `IngestBoard` (whose keys are byte-identical to `Zobrist.hash`), so a whole
/// opponent PGN is processed in milliseconds.
struct OpponentBook {
    let name: String
    let gameCount: Int
    let plyCount: Int
    private let table: [Int64: [String: Int]]   // positionHash → (uci → times played)

    var isEmpty: Bool { table.isEmpty }

    /// Move frequencies the opponent played from the given position, or nil if unseen.
    func frequencies(at positionHash: Int64) -> [String: Int]? { table[positionHash] }

    /// Build from already-parsed games. When `opponentName` is set, only that player's moves are
    /// recorded (matched case-insensitively against the White/Black headers); otherwise both sides.
    static func build(games: [PGNGame], opponentName: String?, maxPly: Int = 40) -> OpponentBook {
        let board = IngestBoard()
        var table: [Int64: [String: Int]] = [:]
        var used = 0, plies = 0
        let query = opponentName?.trimmingCharacters(in: .whitespaces).lowercased()

        for g in games {
            let recordWhite: Bool
            let recordBlack: Bool
            if let q = query, !q.isEmpty {
                recordWhite = g.white.lowercased().contains(q)
                recordBlack = g.black.lowercased().contains(q)
                if !recordWhite && !recordBlack { continue }
            } else {
                recordWhite = true
                recordBlack = true
            }

            board.reset()
            var recorded = false
            for (ply, san) in g.moves.enumerated() {
                if ply >= maxPly { break }
                guard let r = board.resolve(san) else { break }
                let moverIsWhite = board.whiteToMove
                if (moverIsWhite && recordWhite) || (!moverIsWhite && recordBlack) {
                    let key = board.zobristKey()          // position BEFORE the move (where it's chosen)
                    let uci = OpponentBook.uci(from: r)
                    table[key, default: [:]][uci, default: 0] += 1
                    plies += 1
                    recorded = true
                }
                board.apply(r)
            }
            if recorded { used += 1 }
        }

        return OpponentBook(name: opponentName?.isEmpty == false ? opponentName! : "Imported games",
                            gameCount: used, plyCount: plies, table: table)
    }

    /// Parse + build from a PGN file (call off the main thread for large files).
    static func build(fileURL: URL, opponentName: String?) -> OpponentBook {
        let games = (try? PGNParser().parse(file: fileURL)) ?? []
        return build(games: games, opponentName: opponentName)
    }

    private static func uci(from r: IngestBoard.Resolved) -> String {
        func sq(_ i: Int) -> String {
            let file = Character(UnicodeScalar(97 + i % 8)!)
            return "\(file)\(i / 8 + 1)"
        }
        let promo = ["", "q", "r", "b", "n"]
        return sq(r.from) + sq(r.to) + (r.promo < promo.count ? promo[r.promo] : "")
    }
}
