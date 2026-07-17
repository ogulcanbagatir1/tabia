import Foundation

/// A hole in a repertoire: at a position where the OPPONENT is to move, the reference database shows
/// a popular reply that the repertoire has no answer for.
struct CoverageGap: Identifiable {
    let id = UUID()
    /// The tree node whose position the gap is at (opponent to move here).
    let nodeId: UUID
    let positionFEN: String
    /// SAN moves from the repertoire start to this position (for display, e.g. ["e4","c5","Nf3"]).
    let pathSAN: [String]
    let missingUCI: String
    let missingSAN: String
    /// Reference-DB games that reach this position and play the missing reply.
    let gameCount: Int
    /// The missing reply's share of all games at this position (0–100).
    let sharePercent: Double
    /// How well the missing reply scores FOR THE OPPONENT (0–100). High = it hurts.
    let opponentScorePercent: Double

    /// Ranking weight: frequency scaled by how much it favors the opponent.
    var severity: Double { Double(gameCount) * (opponentScorePercent / 100.0) }
}

/// A plain-value snapshot of one opponent-to-move position, extracted from the SwiftData tree on the
/// main thread so the DB-heavy scoring pass can run off-main without touching model objects.
struct CoveragePositionSnapshot {
    let nodeId: UUID
    let fen: String
    let pathSAN: [String]
    let coveredUCIs: Set<String>
}

/// Audits a repertoire against the reference database, surfacing popular opponent replies the tree
/// doesn't cover. Reuses the transposition-aware `ReferenceDatabase.explorer` — the "automated
/// repertoire auditor" a plain trainer can't do.
///
/// Two-phase to stay thread-safe: `snapshot(_:)` reads the SwiftData tree (call on the main thread);
/// `gaps(...)` does only ChessBoard + SQLite work (safe to call off-main).
enum CoverageGapAuditor {

    /// Phase 1 (main thread): collect every opponent-to-move position and what it already covers.
    static func snapshot(_ repertoire: Repertoire) -> (userColor: PieceColor, positions: [CoveragePositionSnapshot]) {
        let userColor: PieceColor = repertoire.side == .white ? .white : .black
        var positions: [CoveragePositionSnapshot] = []
        guard let root = repertoire.nodes.first(where: { $0.id == repertoire.rootNodeId })
                ?? repertoire.nodes.first(where: { $0.parent == nil }) else {
            return (userColor, [])
        }
        collect(node: root, pathSAN: [], userColor: userColor, into: &positions)
        return (userColor, positions)
    }

    private static func collect(node: RepertoireNode,
                                pathSAN: [String],
                                userColor: PieceColor,
                                into positions: inout [CoveragePositionSnapshot]) {
        if !node.fen.isEmpty, let board = ChessBoard(fen: node.fen), board.turn != userColor {
            positions.append(CoveragePositionSnapshot(
                nodeId: node.id,
                fen: node.fen,
                pathSAN: pathSAN,
                coveredUCIs: Set(node.children.compactMap { $0.uciMove })))
        }
        for child in node.children {
            collect(node: child,
                    pathSAN: pathSAN + [child.san ?? child.uciMove ?? "?"],
                    userColor: userColor,
                    into: &positions)
        }
    }

    /// Phase 2 (background-safe): score each snapshot against the reference DB.
    static func gaps(userColor: PieceColor,
                     positions: [CoveragePositionSnapshot],
                     referenceDB: ReferenceDatabase,
                     minGames: Int = 15,
                     minSharePercent: Double = 4.0,
                     maxGaps: Int = 60) -> [CoverageGap] {
        guard referenceDB.isAvailable else { return [] }
        let opponentColor: PieceColor = userColor == .white ? .black : .white

        var gaps: [CoverageGap] = []
        var visited = Set<Int64>()   // dedup transposing positions

        for snap in positions {
            guard let board = ChessBoard(fen: snap.fen) else { continue }
            let key = Zobrist.sqliteKey(board)
            guard visited.insert(key).inserted else { continue }

            let result = referenceDB.explorer(board: board)
            let positionTotal = result.total
            guard positionTotal > 0 else { continue }

            for entry in result.moves where !snap.coveredUCIs.contains(entry.uci) {
                let share = Double(entry.total) / Double(positionTotal) * 100.0
                guard entry.total >= minGames, share >= minSharePercent else { continue }
                // explorer score is from White's perspective; convert to the opponent's.
                let oppScore = opponentColor == .white ? entry.scorePercent : (100.0 - entry.scorePercent)
                gaps.append(CoverageGap(
                    nodeId: snap.nodeId,
                    positionFEN: snap.fen,
                    pathSAN: snap.pathSAN,
                    missingUCI: entry.uci,
                    missingSAN: entry.san,
                    gameCount: entry.total,
                    sharePercent: share,
                    opponentScorePercent: oppScore))
            }
        }

        gaps.sort { $0.severity > $1.severity }
        return Array(gaps.prefix(maxGaps))
    }
}
