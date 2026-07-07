import Foundation

class MoveGenerator {
    let board: ChessBoard
    
    init(board: ChessBoard) {
        self.board = board
    }
    
    // MARK: - Legal Moves
    func legalMoves(for position: Position) -> [Move] {
        guard let piece = board.pieceAt(position),
              piece.color == board.turn else {
            return []
        }
        
        var moves: [Move] = []
        
        switch piece.type {
        case .pawn:
            moves = pawnMoves(from: position, piece: piece)
        case .knight:
            moves = knightMoves(from: position, piece: piece)
        case .bishop:
            moves = bishopMoves(from: position, piece: piece)
        case .rook:
            moves = rookMoves(from: position, piece: piece)
        case .queen:
            moves = queenMoves(from: position, piece: piece)
        case .king:
            moves = kingMoves(from: position, piece: piece)
        }
        
        // Filter out moves that leave king in check
        return moves.filter { move in
            !leavesKingInCheck(move)
        }
    }
    
    func allLegalMoves(for color: PieceColor) -> [Move] {
        var allMoves: [Move] = []

        for file in 0..<8 {
            for rank in 0..<8 {
                let position = Position(file, rank)
                if let piece = board.pieceAt(position), piece.color == color {
                    allMoves.append(contentsOf: legalMoves(for: position))
                }
            }
        }

        return allMoves
    }

    /// Like `allLegalMoves(for:).isEmpty == false` but short-circuits on the first
    /// legal move found. Used by `isCheckmate` to avoid the large allocation cost
    /// of materializing every legal move for the side to move — on the main thread
    /// during `toAlgebraic`, that was the main source of move-input lag.
    func hasAnyLegalMove(for color: PieceColor) -> Bool {
        for file in 0..<8 {
            for rank in 0..<8 {
                let position = Position(file, rank)
                if let piece = board.pieceAt(position), piece.color == color {
                    if !legalMoves(for: position).isEmpty {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    // MARK: - Pawn Moves
    private func pawnMoves(from position: Position, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let direction = piece.color == .white ? 1 : -1
        let startRank = piece.color == .white ? 1 : 6
        let promotionRank = piece.color == .white ? 7 : 0
        
        // Forward move
        let oneForward = position.offset(file: 0, rank: direction)
        if oneForward.isValid() && board.pieceAt(oneForward) == nil {
            if oneForward.rank == promotionRank {
                // Promotion
                for promotionType in [PieceType.queen, .rook, .bishop, .knight] {
                    moves.append(Move(from: position, to: oneForward, piece: piece, promotionType: promotionType))
                }
            } else {
                moves.append(Move(from: position, to: oneForward, piece: piece))
                
                // Double forward from start
                if position.rank == startRank {
                    let twoForward = position.offset(file: 0, rank: direction * 2)
                    if twoForward.isValid() && board.pieceAt(twoForward) == nil {
                        moves.append(Move(from: position, to: twoForward, piece: piece))
                    }
                }
            }
        }
        
        // Captures
        for fileOffset in [-1, 1] {
            let capturePos = position.offset(file: fileOffset, rank: direction)
            if capturePos.isValid() {
                if let capturedPiece = board.pieceAt(capturePos),
                   capturedPiece.color != piece.color {
                    if capturePos.rank == promotionRank {
                        for promotionType in [PieceType.queen, .rook, .bishop, .knight] {
                            moves.append(Move(from: position, to: capturePos, piece: piece, 
                                            capturedPiece: capturedPiece, promotionType: promotionType))
                        }
                    } else {
                        moves.append(Move(from: position, to: capturePos, piece: piece, capturedPiece: capturedPiece))
                    }
                }
                
                // En passant
                if let enPassantTarget = board.enPassantTarget,
                   capturePos == enPassantTarget {
                    let capturedPawnPos = Position(enPassantTarget.file, position.rank)
                    if let capturedPawn = board.pieceAt(capturedPawnPos) {
                        moves.append(Move(from: position, to: capturePos, piece: piece,
                                        capturedPiece: capturedPawn, isEnPassant: true))
                    }
                }
            }
        }
        
        return moves
    }
    
    // MARK: - Knight Moves
    private func knightMoves(from position: Position, piece: Piece) -> [Move] {
        let offsets = [
            (2, 1), (2, -1), (-2, 1), (-2, -1),
            (1, 2), (1, -2), (-1, 2), (-1, -2)
        ]
        
        return offsets.compactMap { (fileOffset, rankOffset) in
            let target = position.offset(file: fileOffset, rank: rankOffset)
            guard target.isValid() else { return nil }
            
            if let targetPiece = board.pieceAt(target) {
                if targetPiece.color != piece.color {
                    return Move(from: position, to: target, piece: piece, capturedPiece: targetPiece)
                }
                return nil
            }
            
            return Move(from: position, to: target, piece: piece)
        }
    }
    
    // MARK: - Bishop Moves
    private func bishopMoves(from position: Position, piece: Piece) -> [Move] {
        return slidingMoves(from: position, piece: piece, directions: [
            (1, 1), (1, -1), (-1, 1), (-1, -1)
        ])
    }
    
    // MARK: - Rook Moves
    private func rookMoves(from position: Position, piece: Piece) -> [Move] {
        return slidingMoves(from: position, piece: piece, directions: [
            (1, 0), (-1, 0), (0, 1), (0, -1)
        ])
    }
    
    // MARK: - Queen Moves
    private func queenMoves(from position: Position, piece: Piece) -> [Move] {
        return slidingMoves(from: position, piece: piece, directions: [
            (1, 0), (-1, 0), (0, 1), (0, -1),
            (1, 1), (1, -1), (-1, 1), (-1, -1)
        ])
    }
    
    // MARK: - King Moves
    private func kingMoves(from position: Position, piece: Piece) -> [Move] {
        var moves: [Move] = []
        
        // Normal moves
        let offsets = [
            (1, 0), (-1, 0), (0, 1), (0, -1),
            (1, 1), (1, -1), (-1, 1), (-1, -1)
        ]
        
        for (fileOffset, rankOffset) in offsets {
            let target = position.offset(file: fileOffset, rank: rankOffset)
            guard target.isValid() else { continue }
            
            if let targetPiece = board.pieceAt(target) {
                if targetPiece.color != piece.color {
                    moves.append(Move(from: position, to: target, piece: piece, capturedPiece: targetPiece))
                }
            } else {
                moves.append(Move(from: position, to: target, piece: piece))
            }
        }
        
        // Castling
        if !piece.hasMoved {
            moves.append(contentsOf: castlingMoves(from: position, piece: piece))
        }
        
        return moves
    }
    
    // MARK: - Helper Methods
    private func slidingMoves(from position: Position, piece: Piece, directions: [(Int, Int)]) -> [Move] {
        var moves: [Move] = []
        
        for (fileDir, rankDir) in directions {
            var current = position
            
            while true {
                current = current.offset(file: fileDir, rank: rankDir)
                guard current.isValid() else { break }
                
                if let targetPiece = board.pieceAt(current) {
                    if targetPiece.color != piece.color {
                        moves.append(Move(from: position, to: current, piece: piece, capturedPiece: targetPiece))
                    }
                    break
                }
                
                moves.append(Move(from: position, to: current, piece: piece))
            }
        }
        
        return moves
    }
    
    private func castlingMoves(from position: Position, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let rank = piece.color == .white ? 0 : 7
        let opponentColor = piece.color.opposite

        // Cannot castle if king is in check
        if isSquareAttacked(position, by: opponentColor) {
            return moves
        }

        // Kingside castling
        let canCastleKingside = piece.color == .white ?
            board.whiteCanCastleKingside : board.blackCanCastleKingside

        if canCastleKingside {
            let e = Position(4, rank) // King's starting square
            let f = Position(5, rank) // King passes through
            let g = Position(6, rank) // King's destination
            let h = Position(7, rank) // Rook's position

            // Check squares are empty
            if board.pieceAt(f) == nil && board.pieceAt(g) == nil,
               let rook = board.pieceAt(h),
               rook.type == .rook && rook.color == piece.color && !rook.hasMoved {
                // Check king doesn't pass through or land on attacked squares
                if !isSquareAttacked(f, by: opponentColor) &&
                   !isSquareAttacked(g, by: opponentColor) {
                    moves.append(Move(from: position, to: g, piece: piece, isCastling: true))
                }
            }
        }

        // Queenside castling
        let canCastleQueenside = piece.color == .white ?
            board.whiteCanCastleQueenside : board.blackCanCastleQueenside

        if canCastleQueenside {
            let a = Position(0, rank) // Rook's position
            let b = Position(1, rank) // Must be empty
            let c = Position(2, rank) // King's destination
            let d = Position(3, rank) // King passes through

            // Check squares are empty (b, c, d must be empty)
            if board.pieceAt(b) == nil && board.pieceAt(c) == nil && board.pieceAt(d) == nil,
               let rook = board.pieceAt(a),
               rook.type == .rook && rook.color == piece.color && !rook.hasMoved {
                // Check king doesn't pass through or land on attacked squares
                // King moves from e to c, passing through d
                if !isSquareAttacked(d, by: opponentColor) &&
                   !isSquareAttacked(c, by: opponentColor) {
                    moves.append(Move(from: position, to: c, piece: piece, isCastling: true))
                }
            }
        }

        return moves
    }
    
    private func leavesKingInCheck(_ move: Move) -> Bool {
        // Make a copy of the board and apply the move
        let testBoard = board.copy()

        // Apply move manually without validation
        // Note: squares is indexed as [file][rank]
        testBoard.squares[move.to.file][move.to.rank] = move.piece
        testBoard.squares[move.from.file][move.from.rank] = nil

        // Handle en passant capture
        if move.isEnPassant {
            let capturedPawnRank = move.from.rank
            testBoard.squares[move.to.file][capturedPawnRank] = nil
        }

        // Handle castling - move the rook too
        if move.isCastling {
            let rank = move.from.rank
            if move.to.file == 6 { // Kingside
                let rook = testBoard.squares[7][rank]
                testBoard.squares[7][rank] = nil
                testBoard.squares[5][rank] = rook
            } else if move.to.file == 2 { // Queenside
                let rook = testBoard.squares[0][rank]
                testBoard.squares[0][rank] = nil
                testBoard.squares[3][rank] = rook
            }
        }

        // Check if own king is in check after the move
        let testGen = MoveGenerator(board: testBoard)
        return testGen.isInCheck(color: move.piece.color)
    }
    
    // MARK: - Game State
    func isInCheck(color: PieceColor) -> Bool {
        // Find king position
        var kingPosition: Position?
        for file in 0..<8 {
            for rank in 0..<8 {
                let pos = Position(file, rank)
                if let piece = board.pieceAt(pos),
                   piece.type == .king && piece.color == color {
                    kingPosition = pos
                    break
                }
            }
            if kingPosition != nil { break }
        }
        
        guard let kingPos = kingPosition else { return false }
        
        // Check if any opponent piece attacks the king
        return isSquareAttacked(kingPos, by: color.opposite)
    }
    
    func isSquareAttacked(_ position: Position, by attackingColor: PieceColor) -> Bool {
        // Check for pawn attacks
        let pawnDirection = attackingColor == .white ? 1 : -1
        for fileOffset in [-1, 1] {
            let attackPos = position.offset(file: fileOffset, rank: -pawnDirection)
            if attackPos.isValid(),
               let piece = board.pieceAt(attackPos),
               piece.type == .pawn && piece.color == attackingColor {
                return true
            }
        }

        // Check for knight attacks
        let knightOffsets = [
            (2, 1), (2, -1), (-2, 1), (-2, -1),
            (1, 2), (1, -2), (-1, 2), (-1, -2)
        ]
        for (fileOffset, rankOffset) in knightOffsets {
            let attackPos = position.offset(file: fileOffset, rank: rankOffset)
            if attackPos.isValid(),
               let piece = board.pieceAt(attackPos),
               piece.type == .knight && piece.color == attackingColor {
                return true
            }
        }

        // Check for king attacks (adjacent squares)
        let kingOffsets = [
            (1, 0), (-1, 0), (0, 1), (0, -1),
            (1, 1), (1, -1), (-1, 1), (-1, -1)
        ]
        for (fileOffset, rankOffset) in kingOffsets {
            let attackPos = position.offset(file: fileOffset, rank: rankOffset)
            if attackPos.isValid(),
               let piece = board.pieceAt(attackPos),
               piece.type == .king && piece.color == attackingColor {
                return true
            }
        }

        // Check for sliding piece attacks (bishop, rook, queen)
        // Diagonal directions (bishop and queen)
        let diagonalDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        for (fileDir, rankDir) in diagonalDirections {
            var current = position
            while true {
                current = current.offset(file: fileDir, rank: rankDir)
                guard current.isValid() else { break }

                if let piece = board.pieceAt(current) {
                    if piece.color == attackingColor &&
                       (piece.type == .bishop || piece.type == .queen) {
                        return true
                    }
                    break // Blocked by a piece
                }
            }
        }

        // Straight directions (rook and queen)
        let straightDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for (fileDir, rankDir) in straightDirections {
            var current = position
            while true {
                current = current.offset(file: fileDir, rank: rankDir)
                guard current.isValid() else { break }

                if let piece = board.pieceAt(current) {
                    if piece.color == attackingColor &&
                       (piece.type == .rook || piece.type == .queen) {
                        return true
                    }
                    break // Blocked by a piece
                }
            }
        }

        return false
    }
    
    func isCheckmate(color: PieceColor) -> Bool {
        return isInCheck(color: color) && !hasAnyLegalMove(for: color)
    }

    func isStalemate(color: PieceColor) -> Bool {
        return !isInCheck(color: color) && !hasAnyLegalMove(for: color)
    }
}
