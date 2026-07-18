import Foundation

class NotationEngine {
    let board: ChessBoard
    let moveGenerator: MoveGenerator
    
    init(board: ChessBoard) {
        self.board = board
        self.moveGenerator = MoveGenerator(board: board)
    }
    
    // MARK: - Move to Algebraic Notation
    func toAlgebraic(_ move: Move) -> String {
        var notation = ""
        
        // Castling
        if move.isCastling {
            let isKingside = move.to.file > move.from.file
            return isKingside ? "O-O" : "O-O-O"
        }
        
        // Piece symbol (except pawns)
        if move.piece.type != .pawn {
            notation += move.piece.type.rawValue
            
            // Disambiguate if needed
            let disambiguation = getDisambiguation(for: move)
            notation += disambiguation
        }
        
        // Capture indicator
        if move.capturedPiece != nil || move.isEnPassant {
            if move.piece.type == .pawn {
                // For pawn captures, include the file
                notation += move.from.algebraic.prefix(1)
            }
            notation += "x"
        }
        
        // Destination square
        notation += move.to.algebraic
        
        // Promotion
        if let promotionType = move.promotionType {
            notation += "=\(promotionType.rawValue)"
        }
        
        // Check / Checkmate — compute isInCheck once; only run the expensive
        // hasAnyLegalMove scan when we actually need to distinguish + from #.
        let tempBoard = board.copy()
        _ = tempBoard.makeMove(move)
        let gen = MoveGenerator(board: tempBoard)
        let opponent = board.turn.opposite

        if gen.isInCheck(color: opponent) {
            notation += gen.hasAnyLegalMove(for: opponent) ? "+" : "#"
        }

        return notation
    }
    
    private func getDisambiguation(for move: Move) -> String {
        // Find other pieces of the same type that can move to the same square
        let sameTypePieces = findSameTypePieces(as: move.piece, excluding: move.from)
        
        var needsFile = false
        var needsRank = false
        var sameFile = false
        var sameRank = false
        
        for position in sameTypePieces {
            let moves = moveGenerator.legalMoves(for: position)
            if moves.contains(where: { $0.to == move.to }) {
                // Another piece can also move to this square
                if position.file == move.from.file {
                    sameFile = true
                    needsRank = true
                } else {
                    needsFile = true
                }
                
                if position.rank == move.from.rank {
                    sameRank = true
                }
            }
        }
        
        // If there's ambiguity on the same file, we need both file and rank
        if sameFile && sameRank {
            return "\(move.from.algebraic.prefix(1))\(move.from.rank + 1)"
        }
        
        if needsRank && sameFile {
            return "\(move.from.rank + 1)"
        }
        
        if needsFile {
            return String(move.from.algebraic.prefix(1))
        }
        
        return ""
    }
    
    private func findSameTypePieces(as piece: Piece, excluding position: Position) -> [Position] {
        var positions: [Position] = []
        
        for file in 0..<8 {
            for rank in 0..<8 {
                let pos = Position(file, rank)
                if pos != position,
                   let boardPiece = board.pieceAt(pos),
                   boardPiece.type == piece.type && boardPiece.color == piece.color {
                    positions.append(pos)
                }
            }
        }
        
        return positions
    }
    
    // MARK: - Algebraic Notation to Move
    func fromAlgebraic(_ notation: String) -> Move? {
        var notation = notation.trimmingCharacters(in: .whitespaces)
        
        // Remove check/checkmate indicators
        notation = notation.replacingOccurrences(of: "+", with: "")
        notation = notation.replacingOccurrences(of: "#", with: "")
        notation = notation.replacingOccurrences(of: "!", with: "")
        notation = notation.replacingOccurrences(of: "?", with: "")
        
        // Castling
        if notation == "O-O" || notation == "0-0" {
            return findCastlingMove(kingside: true)
        }
        if notation == "O-O-O" || notation == "0-0-0" {
            return findCastlingMove(kingside: false)
        }
        
        // Parse piece type
        let pieceType: PieceType
        var index = notation.startIndex
        
        if let first = notation.first, "KQRBN".contains(first) {
            pieceType = PieceType(rawValue: String(first))!
            index = notation.index(after: index)
        } else {
            pieceType = .pawn
        }
        
        // Parse the rest. The destination square is ALWAYS the trailing two chars of the core token
        // (after stripping promotion "=X"/pawn-suffix and the capture "x"); anything before is
        // disambiguation. Parsing promotion first is what makes "e8=Q"/"exd8=Q" work — the previous
        // heuristic consumed the destination file as a hint and returned nil for every promotion.
        var core = String(notation[index...])
        var promotionType: PieceType?

        // Promotion written as "=Q" (standard) …
        if let eq = core.firstIndex(of: "=") {
            let after = core.index(after: eq)
            if after < core.endIndex {
                promotionType = PieceType(rawValue: String(core[after]).uppercased())
            }
            core = String(core[..<eq])
        } else if pieceType == .pawn, let last = core.last, "QRBN".contains(last) {
            // … or without "=" (e.g. "e8Q").
            promotionType = PieceType(rawValue: String(last))
            core = String(core.dropLast())
        }

        var isCapture = false
        if let x = core.firstIndex(of: "x") {
            isCapture = true
            core.remove(at: x)
        }

        guard core.count >= 2, let destPos = Position(algebraic: String(core.suffix(2))) else { return nil }

        var fileHint: Int?
        var rankHint: Int?
        for ch in core.dropLast(2) {
            if let f = "abcdefgh".firstIndex(of: ch) {
                fileHint = "abcdefgh".distance(from: "abcdefgh".startIndex, to: f)
            } else if let r = Int(String(ch)), (1...8).contains(r) {
                rankHint = r - 1
            }
        }

        return findMove(pieceType: pieceType,
                        to: destPos,
                        fileHint: fileHint,
                        rankHint: rankHint,
                        isCapture: isCapture,
                        promotionType: promotionType)
    }
    
    private func findMove(pieceType: PieceType, 
                         to destination: Position,
                         fileHint: Int?,
                         rankHint: Int?,
                         isCapture: Bool,
                         promotionType: PieceType?) -> Move? {
        
        // Find all pieces of this type that can move to destination
        for file in 0..<8 {
            for rank in 0..<8 {
                let position = Position(file, rank)
                
                // Check hints
                if let fHint = fileHint, file != fHint { continue }
                if let rHint = rankHint, rank != rHint { continue }
                
                guard let piece = board.pieceAt(position),
                      piece.type == pieceType,
                      piece.color == board.turn else {
                    continue
                }
                
                let moves = moveGenerator.legalMoves(for: position)
                if let move = moves.first(where: { $0.to == destination }) {
                    // If promotion is specified, find the matching move
                    if let promo = promotionType {
                        if move.promotionType == promo {
                            return move
                        }
                    } else if move.promotionType == nil {
                        return move
                    }
                }
            }
        }
        
        return nil
    }
    
    private func findCastlingMove(kingside: Bool) -> Move? {
        let rank = board.turn == .white ? 0 : 7
        let kingPos = Position(4, rank)
        
        guard let king = board.pieceAt(kingPos),
              king.type == .king && king.color == board.turn else {
            return nil
        }
        
        let moves = moveGenerator.legalMoves(for: kingPos)
        let targetFile = kingside ? 6 : 2
        
        return moves.first { $0.isCastling && $0.to.file == targetFile }
    }
}

extension ChessBoard {
    func copy() -> ChessBoard {
        let newBoard = ChessBoard()
        newBoard.restoreState(from: self)
        return newBoard
    }

    /// Overwrite this board's ENTIRE state from `other`, in place. Use this whenever the live board
    /// must be made to match a stored snapshot (e.g. navigating the game tree, reset, applying an
    /// opening line). It is critical that this copies the castling-rights booleans too: the king's
    /// `hasMoved` flag travels inside `squares`, but MoveGenerator also requires
    /// `whiteCanCastleKingside`/etc., so if those are left stale the engine silently refuses to let
    /// you castle again after taking a castling move back.
    func restoreState(from other: ChessBoard) {
        squares = other.squares
        turn = other.turn
        enPassantTarget = other.enPassantTarget
        halfMoveClock = other.halfMoveClock
        fullMoveNumber = other.fullMoveNumber
        whiteCanCastleKingside = other.whiteCanCastleKingside
        whiteCanCastleQueenside = other.whiteCanCastleQueenside
        blackCanCastleKingside = other.blackCanCastleKingside
        blackCanCastleQueenside = other.blackCanCastleQueenside
        moveHistory = other.moveHistory
        gameOver = other.gameOver
        adoptPositionHistory(from: other)
    }

    /// Convert a UCI PV to algebraic notation. Mutates a copy of self; self is untouched.
    /// Used by the engine analysis panel to render PV lines on-demand (cheap to call per render).
    func toAlgebraicPV(uciMoves: [String]) -> [String] {
        let board = self.copy()
        var notations: [String] = []

        for uci in uciMoves {
            guard uci.count >= 4 else { continue }
            let chars = Array(uci)

            guard let fromFileAscii = chars[0].asciiValue,
                  let toFileAscii = chars[2].asciiValue,
                  chars[0] >= "a" && chars[0] <= "h",
                  chars[2] >= "a" && chars[2] <= "h" else { break }

            let fromFile = Int(fromFileAscii) - Int(Character("a").asciiValue!)
            guard let fromRank = Int(String(chars[1])), fromRank >= 1 && fromRank <= 8 else { break }
            let toFile = Int(toFileAscii) - Int(Character("a").asciiValue!)
            guard let toRank = Int(String(chars[3])), toRank >= 1 && toRank <= 8 else { break }

            let from = Position(fromFile, fromRank - 1)
            let to = Position(toFile, toRank - 1)

            guard let piece = board.pieceAt(from) else { break }

            var promotionType: PieceType? = nil
            if chars.count >= 5 {
                switch chars[4] {
                case "q": promotionType = .queen
                case "r": promotionType = .rook
                case "b": promotionType = .bishop
                case "n": promotionType = .knight
                default: break
                }
            }

            let capturedPiece = board.pieceAt(to)
            let isEnPassant = piece.type == .pawn && from.file != to.file && capturedPiece == nil
            let isCastling = piece.type == .king && abs(from.file - to.file) == 2

            let move = Move(
                from: from, to: to, piece: piece,
                capturedPiece: isEnPassant ? board.pieceAt(Position(to.file, from.rank)) : capturedPiece,
                isEnPassant: isEnPassant,
                isCastling: isCastling,
                promotionType: promotionType
            )

            notations.append(NotationEngine(board: board).toAlgebraic(move))

            if !board.makeMove(move) { break }
        }

        return notations
    }
}
