import Foundation

// Piece type indices (file-private so both static and instance methods use them unqualified).
private let PAWN = 0, KNIGHT = 1, BISHOP = 2, ROOK = 3, QUEEN = 4, KING = 5

/// A flat, non-observable board used ONLY for high-throughput PGN ingest.
///
/// The app's `ChessBoard` is an `@Published`-wrapped `[[Piece?]]`; reading it between
/// mutations (SAN resolve → makeMove, per ply) thrashes copy-on-write on the nested
/// arrays, which dominated ingest time. `IngestBoard` uses a flat `[Int8]` (0 = empty,
/// 1...12 = piece index + 1) with the SAME square + piece indexing as `Zobrist`, so its
/// keys are byte-for-byte identical to `Zobrist.hash(ChessBoard)` — verified against the
/// reference engine. It replicates `ChessBoard.makeMove`'s rules exactly.
///
/// Encoding: square index = rank*8 + file (0...63). piece code = pieceIndex+1, where
/// pieceIndex = type*2 + (white ? 0 : 1), type: pawn=0,knight=1,bishop=2,rook=3,queen=4,king=5.
final class IngestBoard {

    var sq = [Int8](repeating: 0, count: 64)
    var whiteToMove = true
    var wk = true, wq = true, bk = true, bq = true
    var epFile = -1, epRank = -1   // en-passant target square (raw), -1 = none

    init() { reset() }

    @inline(__always) private static func code(_ type: Int, _ white: Bool) -> Int8 {
        Int8(type * 2 + (white ? 0 : 1) + 1)
    }
    @inline(__always) private func typeOf(_ c: Int8) -> Int { (Int(c) - 1) / 2 }
    @inline(__always) private func isWhite(_ c: Int8) -> Bool { (Int(c) - 1) % 2 == 0 }

    func reset() {
        for i in 0..<64 { sq[i] = 0 }
        let back = [ROOK, KNIGHT, BISHOP, QUEEN, KING, BISHOP, KNIGHT, ROOK]
        for f in 0..<8 {
            sq[f] = IngestBoard.code(back[f], true)            // rank 0
            sq[8 + f] = IngestBoard.code(PAWN, true)           // rank 1
            sq[48 + f] = IngestBoard.code(PAWN, false)         // rank 6
            sq[56 + f] = IngestBoard.code(back[f], false)      // rank 7
        }
        whiteToMove = true
        wk = true; wq = true; bk = true; bq = true
        epFile = -1; epRank = -1
    }

    struct Resolved { let from: Int; let to: Int; let promo: Int; let isCastle: Bool; let isEP: Bool }

    // MARK: - Resolve (SAN → move), pseudo-legal + disambiguation

    func resolve(_ raw: String) -> Resolved? {
        var b = Array(raw.utf8)
        while let last = b.last, last == 0x2B || last == 0x23 || last == 0x21 || last == 0x3F { b.removeLast() }
        guard !b.isEmpty else { return nil }

        let white = whiteToMove
        // Castling.
        if b == [79, 45, 79, 45, 79] || b == [48, 45, 48, 45, 48] {   // O-O-O / 0-0-0
            let r = white ? 0 : 7
            return Resolved(from: r * 8 + 4, to: r * 8 + 2, promo: 0, isCastle: true, isEP: false)
        }
        if b == [79, 45, 79] || b == [48, 45, 48] {                   // O-O / 0-0
            let r = white ? 0 : 7
            return Resolved(from: r * 8 + 4, to: r * 8 + 6, promo: 0, isCastle: true, isEP: false)
        }

        var promo = 0
        if let eq = b.firstIndex(of: 0x3D) {
            if eq + 1 < b.count { promo = promoCode(b[eq + 1]) }
            b.removeSubrange(eq...)
        }
        let isCapture = b.contains(120)
        if isCapture { b.removeAll { $0 == 120 } }
        guard b.count >= 2 else { return nil }

        let fileByte = b[b.count - 2], rankByte = b[b.count - 1]
        guard fileByte >= 97, fileByte <= 104, rankByte >= 49, rankByte <= 56 else { return nil }
        let destFile = Int(fileByte) - 97, destRank = Int(rankByte) - 49
        let dest = destRank * 8 + destFile

        let prefixCount = b.count - 2
        var type = PAWN
        var i = 0
        if prefixCount > 0, let pt = pieceCode(b[0]) { type = pt; i = 1 }
        var dFile = -1, dRank = -1
        while i < prefixCount {
            let c = b[i]
            if c >= 97 && c <= 104 { dFile = Int(c) - 97 }
            else if c >= 49 && c <= 56 { dRank = Int(c) - 49 }
            i += 1
        }

        let want = IngestBoard.code(type, white)
        var c0 = -1, c1 = -1, n = 0
        var file = dFile >= 0 ? dFile : 0
        let fileEnd = dFile >= 0 ? dFile + 1 : 8
        while file < fileEnd {
            var rank = dRank >= 0 ? dRank : 0
            let rankEnd = dRank >= 0 ? dRank + 1 : 8
            while rank < rankEnd {
                let from = rank * 8 + file
                if sq[from] == want && canReach(type: type, white: white, from: from, fromFile: file, fromRank: rank,
                                                to: dest, toFile: destFile, toRank: destRank, isCapture: isCapture) {
                    if n == 0 { c0 = from } else if n == 1 { c1 = from }
                    n += 1
                }
                rank += 1
            }
            file += 1
        }

        let from: Int
        if n == 1 { from = c0 }
        else if n == 0 { return nil }
        else { from = legalOne(c0, c1, type: type, white: white, dest: dest, promo: promo) ?? c0 }

        let isEP = type == PAWN && (from % 8) != destFile && sq[dest] == 0
        return Resolved(from: from, to: dest, promo: promo, isCastle: false, isEP: isEP)
    }

    // MARK: - Apply (mirrors ChessBoard.makeMove)

    func apply(_ m: Resolved) {
        let movingCode = sq[m.from]
        let type = typeOf(movingCode)
        let white = isWhite(movingCode)
        let fromFile = m.from % 8, fromRank = m.from / 8
        let toFile = m.to % 8, toRank = m.to / 8
        let capturedCode = sq[m.to]

        sq[m.from] = 0
        if m.promo > 0 {
            sq[m.to] = IngestBoard.code(promoType(m.promo), white)
        } else {
            sq[m.to] = movingCode
        }
        if m.isEP { sq[fromRank * 8 + toFile] = 0 }              // captured pawn sits behind
        if m.isCastle {
            let kingside = toFile > fromFile
            let rookFrom = fromRank * 8 + (kingside ? 7 : 0)
            let rookTo = fromRank * 8 + (kingside ? toFile - 1 : toFile + 1)
            sq[rookTo] = sq[rookFrom]; sq[rookFrom] = 0
        }

        // Castling rights.
        if type == KING {
            if white { wk = false; wq = false } else { bk = false; bq = false }
        }
        if type == ROOK {
            if m.from == 0 { wq = false }
            if m.from == 7 { wk = false }
            if m.from == 56 { bq = false }
            if m.from == 63 { bk = false }
        }
        if typeOf(capturedCode) == ROOK && capturedCode != 0 {
            if m.to == 0 { wq = false }
            if m.to == 7 { wk = false }
            if m.to == 56 { bq = false }
            if m.to == 63 { bk = false }
        }

        // En-passant target.
        if type == PAWN && abs(toRank - fromRank) == 2 {
            epFile = fromFile; epRank = (fromRank + toRank) / 2
        } else {
            epFile = -1; epRank = -1
        }
        whiteToMove.toggle()
    }

    // MARK: - Zobrist (identical scheme to Zobrist.hash)

    func zobristKey() -> Int64 {
        var h: UInt64 = 0
        for idx in 0..<64 {
            let c = sq[idx]
            if c == 0 { continue }
            h ^= Zobrist.pieceKey(pieceIndex: Int(c) - 1, square: idx)
        }
        if !whiteToMove { h ^= Zobrist.sideToMoveKey }
        if wk { h ^= Zobrist.castlingKey(0) }
        if wq { h ^= Zobrist.castlingKey(1) }
        if bk { h ^= Zobrist.castlingKey(2) }
        if bq { h ^= Zobrist.castlingKey(3) }
        if epFile >= 0 && epCapturable() { h ^= Zobrist.enPassantFileKey(epFile) }
        return Int64(bitPattern: h)
    }

    private func epCapturable() -> Bool {
        let pawnRank = whiteToMove ? 4 : 3
        let want = IngestBoard.code(PAWN, whiteToMove)
        for df in [-1, 1] {
            let f = epFile + df
            if f >= 0 && f < 8 && sq[pawnRank * 8 + f] == want { return true }
        }
        return false
    }

    // MARK: - Reachability + rare legality resolution

    private func canReach(type: Int, white: Bool, from: Int, fromFile: Int, fromRank: Int,
                          to: Int, toFile: Int, toRank: Int, isCapture: Bool) -> Bool {
        let df = toFile - fromFile, dr = toRank - fromRank
        switch type {
        case KNIGHT: return (abs(df) == 1 && abs(dr) == 2) || (abs(df) == 2 && abs(dr) == 1)
        case KING:   return abs(df) <= 1 && abs(dr) <= 1
        case BISHOP: return abs(df) == abs(dr) && df != 0 && pathClear(fromFile, fromRank, toFile, toRank)
        case ROOK:   return (df == 0) != (dr == 0) && pathClear(fromFile, fromRank, toFile, toRank)
        case QUEEN:  return ((abs(df) == abs(dr) && df != 0) || ((df == 0) != (dr == 0))) && pathClear(fromFile, fromRank, toFile, toRank)
        default: // pawn
            let dir = white ? 1 : -1
            if isCapture { return abs(df) == 1 && dr == dir }   // diagonal capture / EP
            if df != 0 { return false }                          // non-capture push: same file only
            if dr == dir { return sq[to] == 0 }
            let startRank = white ? 1 : 6
            if dr == 2 * dir && fromRank == startRank {
                return sq[(fromRank + dir) * 8 + fromFile] == 0 && sq[to] == 0
            }
            return false
        }
    }

    private func pathClear(_ ff: Int, _ fr: Int, _ tf: Int, _ tr: Int) -> Bool {
        let sf = (tf - ff).signum(), sr = (tr - fr).signum()
        var f = ff + sf, r = fr + sr
        while f != tf || r != tr {
            if sq[r * 8 + f] != 0 { return false }
            f += sf; r += sr
        }
        return true
    }

    /// Pick the candidate whose move does not leave its own king in check (a pin).
    private func legalOne(_ a: Int, _ b: Int, type: Int, white: Bool, dest: Int, promo: Int) -> Int? {
        for from in [a, b] {
            var copy = sq
            copy[dest] = copy[from]; copy[from] = 0
            let kingCode = IngestBoard.code(KING, white)
            var kingIdx = -1
            for i in 0..<64 where copy[i] == kingCode { kingIdx = i; break }
            if kingIdx >= 0 && !isAttacked(copy, kingIdx, byWhite: !white) { return from }
        }
        return nil
    }

    private func isAttacked(_ board: [Int8], _ target: Int, byWhite: Bool) -> Bool {
        let tf = target % 8, tr = target / 8
        // knights
        let kn = IngestBoard.code(KNIGHT, byWhite)
        for (df, dr) in [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)] {
            let f = tf + df, r = tr + dr
            if f >= 0 && f < 8 && r >= 0 && r < 8 && board[r*8+f] == kn { return true }
        }
        // king
        let kg = IngestBoard.code(KING, byWhite)
        for df in -1...1 { for dr in -1...1 where !(df == 0 && dr == 0) {
            let f = tf + df, r = tr + dr
            if f >= 0 && f < 8 && r >= 0 && r < 8 && board[r*8+f] == kg { return true }
        } }
        // pawns (attacker pushes toward target: white pawns attack from rank-1)
        let pw = IngestBoard.code(PAWN, byWhite)
        let pr = byWhite ? tr - 1 : tr + 1
        if pr >= 0 && pr < 8 {
            for f in [tf - 1, tf + 1] where f >= 0 && f < 8 { if board[pr*8+f] == pw { return true } }
        }
        // sliders
        let rook = IngestBoard.code(ROOK, byWhite)
        let bishop = IngestBoard.code(BISHOP, byWhite)
        let queen = IngestBoard.code(QUEEN, byWhite)
        let ortho = [(1,0),(-1,0),(0,1),(0,-1)], diag = [(1,1),(1,-1),(-1,1),(-1,-1)]
        for (df, dr) in ortho {
            var f = tf + df, r = tr + dr
            while f >= 0 && f < 8 && r >= 0 && r < 8 {
                let c = board[r*8+f]
                if c != 0 { if c == rook || c == queen { return true }; break }
                f += df; r += dr
            }
        }
        for (df, dr) in diag {
            var f = tf + df, r = tr + dr
            while f >= 0 && f < 8 && r >= 0 && r < 8 {
                let c = board[r*8+f]
                if c != 0 { if c == bishop || c == queen { return true }; break }
                f += df; r += dr
            }
        }
        return false
    }

    // MARK: - Byte helpers

    private func pieceCode(_ byte: UInt8) -> Int? {
        switch byte {
        case 75: return KING
        case 81: return QUEEN
        case 82: return ROOK
        case 66: return BISHOP
        case 78: return KNIGHT
        default: return nil
        }
    }
    /// SAN promotion byte → promo code (1=Q,2=R,3=B,4=N) matching Ingestor.encodeMove.
    private func promoCode(_ byte: UInt8) -> Int {
        switch byte { case 81: return 1; case 82: return 2; case 66: return 3; case 78: return 4; default: return 0 }
    }
    private func promoType(_ promo: Int) -> Int {
        switch promo { case 1: return QUEEN; case 2: return ROOK
        case 3: return BISHOP; case 4: return KNIGHT; default: return QUEEN }
    }
}
