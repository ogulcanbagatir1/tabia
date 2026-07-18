import Foundation

/// Long algebraic (UCI) move notation — "e2e4", "e7e8q".
///
/// This was copy-pasted into five parsers and six encoders across the repertoire, drill, analysis
/// and explorer layers; two of them sat in the same file. Consolidated here so the promotion table
/// and the en-passant/castling inference can't drift apart between call sites.
///
/// The packed-integer variants (`OpponentBook.uci(from: IngestBoard.Resolved)` and
/// `ReferenceDatabase.uci(from: Int32)`) work on square indices rather than `Move`/`Position` and
/// stay where they are.
enum UCI {

    /// Encode a move. Promotion suffix is lowercase, per the UCI spec.
    static func string(from move: Move) -> String {
        var s = square(move.from) + square(move.to)
        switch move.promotionType {
        case .queen:  s += "q"
        case .rook:   s += "r"
        case .bishop: s += "b"
        case .knight: s += "n"
        default:      break
        }
        return s
    }

    /// Decode a move against `board`, which supplies the moving piece and capture context.
    /// Returns nil when the string is malformed or the origin square is empty.
    ///
    /// En passant and castling are inferred from the geometry rather than stated: a pawn changing
    /// file onto an empty square is en passant, a king moving two files is castling.
    static func move(_ uci: String, board: ChessBoard) -> Move? {
        guard uci.count >= 4 else { return nil }
        let chars = Array(uci)

        guard let fromFileAscii = chars[0].asciiValue,
              let toFileAscii = chars[2].asciiValue,
              let fromRank = Int(String(chars[1])),
              let toRank = Int(String(chars[3])) else { return nil }

        let aValue = Int(Character("a").asciiValue!)
        let from = Position(Int(fromFileAscii) - aValue, fromRank - 1)
        let to = Position(Int(toFileAscii) - aValue, toRank - 1)
        guard let piece = board.pieceAt(from) else { return nil }

        var promotionType: PieceType? = nil
        if chars.count >= 5 {
            switch chars[4] {
            case "q", "Q": promotionType = .queen
            case "r", "R": promotionType = .rook
            case "b", "B": promotionType = .bishop
            case "n", "N": promotionType = .knight
            default: break
            }
        }

        let capturedPiece = board.pieceAt(to)
        let isEnPassant = piece.type == .pawn && from.file != to.file && capturedPiece == nil
        let isCastling = piece.type == .king && abs(from.file - to.file) == 2

        return Move(
            from: from,
            to: to,
            piece: piece,
            capturedPiece: isEnPassant ? board.pieceAt(Position(to.file, from.rank)) : capturedPiece,
            isEnPassant: isEnPassant,
            isCastling: isCastling,
            promotionType: promotionType
        )
    }

    /// "e4" for a position.
    static func square(_ p: Position) -> String {
        let file = Character(UnicodeScalar(Int(Character("a").asciiValue!) + p.file)!)
        return "\(file)\(p.rank + 1)"
    }
}
