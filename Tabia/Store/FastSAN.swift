import Foundation

/// Fast SAN → Move resolver for high-throughput ingest.
///
/// `NotationEngine.fromAlgebraic` generates full legal moves per call. This resolver
/// instead locates the source square by pseudo-legal reachability + SAN disambiguation:
/// in the common case exactly one piece can reach the destination, so no legality test
/// is needed; only the rare pin-ambiguous case defers to the reference engine. Move
/// *application* is delegated to `ChessBoard.makeMove`, so castling/en-passant/rights/
/// turn handling is unchanged.
///
/// Parsing works on raw ASCII bytes (no `CharacterSet`, `String.contains`, `suffix`,
/// `Position(algebraic:)`, etc.) — SAN is pure ASCII and Swift's Unicode-aware String
/// operations were ~95% of the per-move cost.
enum FastSAN {

    // ASCII byte constants
    private static let bO: UInt8 = 79, bZero: UInt8 = 48, bDash: UInt8 = 45
    private static let bx: UInt8 = 120, bEq: UInt8 = 61

    static func move(_ raw: String, on board: ChessBoard) -> Move? {
        var b = Array(raw.utf8)

        // Strip trailing check/mate/annotation bytes: + # ! ?
        while let last = b.last, last == 0x2B || last == 0x23 || last == 0x21 || last == 0x3F {
            b.removeLast()
        }
        guard !b.isEmpty else { return nil }

        // Castling (O-O / O-O-O, also 0-0 / 0-0-0).
        if b == [bO, bDash, bO, bDash, bO] || b == [bZero, bDash, bZero, bDash, bZero] {
            return castle(board, kingside: false)
        }
        if b == [bO, bDash, bO] || b == [bZero, bDash, bZero] {
            return castle(board, kingside: true)
        }

        // Promotion (=Q ...).
        var promo: PieceType? = nil
        if let eq = b.firstIndex(of: bEq) {
            if eq + 1 < b.count { promo = pieceType(byte: b[eq + 1]) }
            b.removeSubrange(eq...)
        }

        // Capture marker.
        let isCapture = b.contains(bx)
        if isCapture { b.removeAll { $0 == bx } }

        guard b.count >= 2 else { return nil }

        // Destination = last two bytes (file, rank).
        let fileByte = b[b.count - 2], rankByte = b[b.count - 1]
        guard fileByte >= 97, fileByte <= 104, rankByte >= 49, rankByte <= 56 else { return nil }
        let dest = Position(Int(fileByte) - 97, Int(rankByte) - 49)

        // Prefix = optional piece letter + optional disambiguation (file and/or rank).
        let prefixCount = b.count - 2
        var type: PieceType = .pawn
        var i = 0
        if prefixCount > 0, let pt = pieceType(byte: b[0]) { type = pt; i = 1 }
        var dFile = -1, dRank = -1
        while i < prefixCount {
            let c = b[i]
            if c >= 97 && c <= 104 { dFile = Int(c) - 97 }
            else if c >= 49 && c <= 56 { dRank = Int(c) - 49 }
            i += 1
        }

        // Collect candidate source squares. Hoist `board.squares` ONCE — re-reading the
        // @Published property (and re-subscripting the nested arrays) per square was the
        // dominant cost.
        let color = board.turn
        let squares = board.squares
        var candidates: [Position] = []
        for file in 0..<8 {
            if dFile >= 0 && file != dFile { continue }
            let col = squares[file]
            for rank in 0..<8 {
                if dRank >= 0 && rank != dRank { continue }
                guard let p = col[rank], p.color == color, p.type == type else { continue }
                if canReach(type: type, color: color, from: Position(file, rank), to: dest,
                            isCapture: isCapture, squares: squares) {
                    candidates.append(Position(file, rank))
                }
            }
        }

        let from: Position
        switch candidates.count {
        case 1: from = candidates[0]
        case 0: return nil
        default:
            // Ambiguous after disambiguation → a pin makes one illegal. Defer to the
            // reference engine for this single (rare) move to stay correct.
            return NotationEngine(board: board).fromAlgebraic(raw)
        }

        let piece = squares[from.file][from.rank]!
        let captured = squares[dest.file][dest.rank]
        let isEP = type == .pawn && from.file != dest.file && captured == nil
        return Move(from: from, to: dest, piece: piece,
                    capturedPiece: isEP ? Piece(type: .pawn, color: color.opposite) : captured,
                    isEnPassant: isEP, isCastling: false, promotionType: promo)
    }

    // MARK: - Reachability (pseudo-legal, no check test)

    private static func canReach(type: PieceType, color: PieceColor, from: Position, to: Position,
                                 isCapture: Bool, squares: [[Piece?]]) -> Bool {
        let df = to.file - from.file, dr = to.rank - from.rank
        switch type {
        case .knight:
            return (abs(df) == 1 && abs(dr) == 2) || (abs(df) == 2 && abs(dr) == 1)
        case .king:
            return abs(df) <= 1 && abs(dr) <= 1
        case .bishop:
            return abs(df) == abs(dr) && df != 0 && pathClear(from, to, squares)
        case .rook:
            return (df == 0) != (dr == 0) && pathClear(from, to, squares)
        case .queen:
            return ((abs(df) == abs(dr) && df != 0) || ((df == 0) != (dr == 0))) && pathClear(from, to, squares)
        case .pawn:
            let dir = color == .white ? 1 : -1
            if isCapture { return abs(df) == 1 && dr == dir }    // diagonal capture / en passant
            if df != 0 { return false }                           // non-capture push: same file only
            if dr == dir { return squares[to.file][to.rank] == nil }   // single push
            let startRank = color == .white ? 1 : 6
            if dr == 2 * dir && from.rank == startRank {                 // double push
                return squares[from.file][from.rank + dir] == nil && squares[to.file][to.rank] == nil
            }
            return false
        }
    }

    /// True if all squares strictly between `from` and `to` (a straight line) are empty.
    private static func pathClear(_ from: Position, _ to: Position, _ squares: [[Piece?]]) -> Bool {
        let sf = (to.file - from.file).signum(), sr = (to.rank - from.rank).signum()
        var f = from.file + sf, r = from.rank + sr
        while f != to.file || r != to.rank {
            if squares[f][r] != nil { return false }
            f += sf; r += sr
        }
        return true
    }

    // MARK: - Helpers

    private static func castle(_ board: ChessBoard, kingside: Bool) -> Move? {
        let color = board.turn
        let rank = color == .white ? 0 : 7
        guard let king = board.squares[4][rank], king.type == .king, king.color == color else { return nil }
        return Move(from: Position(4, rank), to: Position(kingside ? 6 : 2, rank), piece: king,
                    capturedPiece: nil, isEnPassant: false, isCastling: true, promotionType: nil)
    }

    private static func pieceType(byte: UInt8) -> PieceType? {
        switch byte {
        case 75: return .king    // K
        case 81: return .queen   // Q
        case 82: return .rook    // R
        case 66: return .bishop  // B
        case 78: return .knight  // N
        default: return nil
        }
    }
}
