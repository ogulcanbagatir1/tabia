import Foundation

// MARK: - Piece Types
enum PieceType: String, Codable {
    case king = "K"
    case queen = "Q"
    case rook = "R"
    case bishop = "B"
    case knight = "N"
    case pawn = "P"
}

enum PieceColor: String, Codable {
    case white
    case black
    
    var opposite: PieceColor {
        return self == .white ? .black : .white
    }
}

struct Piece: Codable, Equatable {
    let type: PieceType
    let color: PieceColor
    var hasMoved: Bool = false
    
    var symbol: String {
        let symbols: [PieceType: (white: String, black: String)] = [
            .king: ("♔", "♚"),
            .queen: ("♕", "♛"),
            .rook: ("♖", "♜"),
            .bishop: ("♗", "♝"),
            .knight: ("♘", "♞"),
            .pawn: ("♙", "♟")
        ]
        
        let pair = symbols[type]!
        return color == .white ? pair.white : pair.black
    }
    
    var imageFileName: String {
        let colorPrefix = color == .white ? "w" : "b"
        let pieceNames: [PieceType: String] = [
            .king: "king",
            .queen: "queen",
            .rook: "rook",
            .bishop: "bishop",
            .knight: "knight",
            .pawn: "pawn"
        ]
        return "\(colorPrefix)_\(pieceNames[type]!)_png_shadow_128px.png"
    }
}

// MARK: - Position
struct Position: Hashable, Codable {
    let file: Int  // 0-7 (a-h)
    let rank: Int  // 0-7 (1-8)
    
    init(_ file: Int, _ rank: Int) {
        self.file = file
        self.rank = rank
    }
    
    init?(algebraic: String) {
        guard algebraic.count == 2 else { return nil }
        let fileChar = algebraic.first!
        let rankChar = algebraic.last!
        
        guard let file = "abcdefgh".firstIndex(of: fileChar),
              let rank = Int(String(rankChar)),
              rank >= 1 && rank <= 8 else {
            return nil
        }
        
        self.file = "abcdefgh".distance(from: "abcdefgh".startIndex, to: file)
        self.rank = rank - 1
    }
    
    var algebraic: String {
        let fileChar = "abcdefgh"[String.Index(utf16Offset: file, in: "abcdefgh")]
        return "\(fileChar)\(rank + 1)"
    }
    
    func isValid() -> Bool {
        return file >= 0 && file < 8 && rank >= 0 && rank < 8
    }
    
    func offset(file: Int, rank: Int) -> Position {
        return Position(self.file + file, self.rank + rank)
    }
}

// MARK: - Move
struct Move: Codable, Equatable {
    let from: Position
    let to: Position
    let piece: Piece
    let capturedPiece: Piece?
    let isEnPassant: Bool
    let isCastling: Bool
    let promotionType: PieceType?
    
    init(from: Position, to: Position, piece: Piece, 
         capturedPiece: Piece? = nil,
         isEnPassant: Bool = false,
         isCastling: Bool = false,
         promotionType: PieceType? = nil) {
        self.from = from
        self.to = to
        self.piece = piece
        self.capturedPiece = capturedPiece
        self.isEnPassant = isEnPassant
        self.isCastling = isCastling
        self.promotionType = promotionType
    }
}

// MARK: - Chess Board
class ChessBoard: ObservableObject {
    @Published var squares: [[Piece?]]
    @Published var turn: PieceColor
    @Published var moveHistory: [Move]
    @Published var gameOver: Bool = false
    
    var enPassantTarget: Position?
    var halfMoveClock: Int = 0
    var fullMoveNumber: Int = 1

    /// Zobrist keys of every position that has occurred in this line, current one last. Drives
    /// threefold repetition. Reset whenever the position is *set* (FEN load, new game) rather than
    /// played, since prior occurrences no longer belong to this line.
    private(set) var positionHistory: [UInt64] = []
    
    // Castling rights
    var whiteCanCastleKingside: Bool = true
    var whiteCanCastleQueenside: Bool = true
    var blackCanCastleKingside: Bool = true
    var blackCanCastleQueenside: Bool = true
    
    init() {
        self.squares = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        self.turn = .white
        self.moveHistory = []
        setupInitialPosition()
    }
    
    func setupInitialPosition() {
        // Clear board
        for file in 0..<8 {
            for rank in 0..<8 {
                squares[file][rank] = nil
            }
        }
        
        // Setup pawns
        for file in 0..<8 {
            squares[file][1] = Piece(type: .pawn, color: .white)
            squares[file][6] = Piece(type: .pawn, color: .black)
        }
        
        // Setup other pieces
        let backRank: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for (file, pieceType) in backRank.enumerated() {
            squares[file][0] = Piece(type: pieceType, color: .white)
            squares[file][7] = Piece(type: pieceType, color: .black)
        }
        
        turn = .white
        moveHistory = []
        enPassantTarget = nil
        halfMoveClock = 0
        fullMoveNumber = 1
        gameOver = false
        resetPositionHistory()
    }

    func pieceAt(_ position: Position) -> Piece? {
        guard position.isValid() else { return nil }
        return squares[position.file][position.rank]
    }
    
    func setPiece(_ piece: Piece?, at position: Position) {
        guard position.isValid() else { return }
        squares[position.file][position.rank] = piece
    }
    
    func makeMove(_ move: Move) -> Bool {
        // Basic validation
        guard let movingPiece = pieceAt(move.from),
              movingPiece.color == turn else {
            return false
        }
        
        // Execute move
        setPiece(nil, at: move.from)
        var movedPiece = movingPiece
        movedPiece.hasMoved = true
        
        // Handle promotion
        if let promotionType = move.promotionType {
            movedPiece = Piece(type: promotionType, color: movingPiece.color, hasMoved: true)
        }
        
        setPiece(movedPiece, at: move.to)
        
        // Handle en passant capture
        if move.isEnPassant, let target = enPassantTarget {
            let capturePos = Position(target.file, move.from.rank)
            setPiece(nil, at: capturePos)
        }
        
        // Handle castling
        if move.isCastling {
            let isKingside = move.to.file > move.from.file
            let rookFromFile = isKingside ? 7 : 0
            let rookToFile = isKingside ? move.to.file - 1 : move.to.file + 1
            
            if let rook = pieceAt(Position(rookFromFile, move.from.rank)) {
                setPiece(nil, at: Position(rookFromFile, move.from.rank))
                var movedRook = rook
                movedRook.hasMoved = true
                setPiece(movedRook, at: Position(rookToFile, move.from.rank))
            }
        }
        
        // Update en passant target
        if movingPiece.type == .pawn && abs(move.to.rank - move.from.rank) == 2 {
            enPassantTarget = Position(move.from.file, (move.from.rank + move.to.rank) / 2)
        } else {
            enPassantTarget = nil
        }
        
        // Update castling rights
        // King moves - lose both castling rights for that side
        if movingPiece.type == .king {
            if movingPiece.color == .white {
                whiteCanCastleKingside = false
                whiteCanCastleQueenside = false
            } else {
                blackCanCastleKingside = false
                blackCanCastleQueenside = false
            }
        }

        // Rook moves from original square - lose that side's castling right
        if movingPiece.type == .rook {
            if movingPiece.color == .white {
                if move.from == Position(0, 0) { whiteCanCastleQueenside = false }
                if move.from == Position(7, 0) { whiteCanCastleKingside = false }
            } else {
                if move.from == Position(0, 7) { blackCanCastleQueenside = false }
                if move.from == Position(7, 7) { blackCanCastleKingside = false }
            }
        }

        // Rook captured on original square - opponent loses that castling right
        if move.capturedPiece?.type == .rook {
            if move.to == Position(0, 0) { whiteCanCastleQueenside = false }
            if move.to == Position(7, 0) { whiteCanCastleKingside = false }
            if move.to == Position(0, 7) { blackCanCastleQueenside = false }
            if move.to == Position(7, 7) { blackCanCastleKingside = false }
        }

        // Update move counters
        if movingPiece.type == .pawn || move.capturedPiece != nil {
            halfMoveClock = 0
        } else {
            halfMoveClock += 1
        }

        if turn == .black {
            fullMoveNumber += 1
        }

        // Switch turn
        turn = turn.opposite
        moveHistory.append(move)
        positionHistory.append(Zobrist.hash(self))
        gameOver = status().isOver

        return true
    }

    /// Seed `positionHistory` with the current position. Call after setting a position directly.
    func resetPositionHistory() {
        positionHistory = [Zobrist.hash(self)]
    }

    /// Carry another board's repetition history across (used by `restoreState`).
    func adoptPositionHistory(from other: ChessBoard) {
        positionHistory = other.positionHistory
    }

    // MARK: - Terminal conditions

    enum GameStatus: Equatable {
        case ongoing
        case checkmate(winner: PieceColor)
        case stalemate
        case insufficientMaterial
        case fiftyMoveRule
        case threefoldRepetition

        var isOver: Bool { self != .ongoing }

        /// PGN result tag for this outcome.
        var resultTag: String {
            switch self {
            case .ongoing:                 return "*"
            case .checkmate(let winner):   return winner == .white ? "1-0" : "0-1"
            default:                       return "1/2-1/2"
            }
        }

        var label: String {
            switch self {
            case .ongoing:               return ""
            case .checkmate(let winner): return winner == .white ? "White wins by checkmate" : "Black wins by checkmate"
            case .stalemate:             return "Draw — stalemate"
            case .insufficientMaterial:  return "Draw — insufficient material"
            case .fiftyMoveRule:         return "Draw — fifty-move rule"
            case .threefoldRepetition:   return "Draw — threefold repetition"
            }
        }
    }

    /// The position's terminal state. Checkmate and stalemate are decided for the side to move;
    /// the draw rules are properties of the position/history and apply regardless.
    func status() -> GameStatus {
        let gen = MoveGenerator(board: self)

        if !gen.hasAnyLegalMove(for: turn) {
            return gen.isInCheck(color: turn) ? .checkmate(winner: turn.opposite) : .stalemate
        }
        if gen.isInsufficientMaterial() { return .insufficientMaterial }
        // 100 half-moves = 50 full moves by each side.
        if halfMoveClock >= 100 { return .fiftyMoveRule }
        if isThreefoldRepetition() { return .threefoldRepetition }
        return .ongoing
    }

    /// True once the current position has appeared three times in this line.
    func isThreefoldRepetition() -> Bool {
        guard let current = positionHistory.last else { return false }
        return positionHistory.reduce(0) { $1 == current ? $0 + 1 : $0 } >= 3
    }
    
    func getFEN() -> String {
        var fen = ""
        
        // Board position
        for rank in (0..<8).reversed() {
            var emptyCount = 0
            for file in 0..<8 {
                if let piece = squares[file][rank] {
                    if emptyCount > 0 {
                        fen += "\(emptyCount)"
                        emptyCount = 0
                    }
                    let symbol = piece.type.rawValue
                    fen += piece.color == .white ? symbol : symbol.lowercased()
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 {
                fen += "\(emptyCount)"
            }
            if rank > 0 {
                fen += "/"
            }
        }
        
        // Active color
        fen += " \(turn == .white ? "w" : "b")"
        
        // Castling rights — only emit a right when the piece placement actually supports it (king on
        // its home square AND the matching rook on its corner). A manually set-up position keeps the
        // ChessBoard default "all rights = true" flags even when the king/rooks aren't home, so the
        // naive version emitted e.g. "KQkq" for a middlegame board; that is an illegal FEN and the
        // Lichess opening explorer rejects it with HTTP 400. For any legally-reached position the
        // flags already imply the pieces are home, so this only ever corrects set-up positions.
        func isPiece(_ file: Int, _ rank: Int, _ type: PieceType, _ color: PieceColor) -> Bool {
            squares[file][rank].map { $0.type == type && $0.color == color } ?? false
        }
        let whiteKingHome = isPiece(4, 0, .king, .white)
        let blackKingHome = isPiece(4, 7, .king, .black)
        var castling = ""
        if whiteCanCastleKingside,  whiteKingHome, isPiece(7, 0, .rook, .white) { castling += "K" }
        if whiteCanCastleQueenside, whiteKingHome, isPiece(0, 0, .rook, .white) { castling += "Q" }
        if blackCanCastleKingside,  blackKingHome, isPiece(7, 7, .rook, .black) { castling += "k" }
        if blackCanCastleQueenside, blackKingHome, isPiece(0, 7, .rook, .black) { castling += "q" }
        fen += " \(castling.isEmpty ? "-" : castling)"
        
        // En passant target
        fen += " \(enPassantTarget?.algebraic ?? "-")"
        
        // Halfmove clock and fullmove number
        fen += " \(halfMoveClock) \(fullMoveNumber)"

        return fen
    }

    // MARK: - FEN Loading (inverse of getFEN)

    /// Construct a board directly from a FEN string. Fails (returns nil) if the FEN is malformed.
    convenience init?(fen: String) {
        self.init()
        guard loadFEN(fen) else { return nil }
    }

    /// Load a full FEN into this board: piece placement, active color, castling rights,
    /// en-passant target, and clocks. Returns false on a malformed FEN; on failure the board
    /// is left untouched (all writes are committed only after successful parsing).
    @discardableResult
    func loadFEN(_ fen: String) -> Bool {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return false }

        let ranks = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return false }

        var newSquares: [[Piece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        for (rankIndex, rankStr) in ranks.enumerated() {
            let rank = 7 - rankIndex          // FEN lists rank 8 first
            var file = 0
            for ch in rankStr {
                if let empty = ch.wholeNumberValue, empty >= 1, empty <= 8 {
                    file += empty
                } else {
                    guard file < 8, var piece = Self.pieceFromFENChar(ch) else { return false }
                    // Derive hasMoved so castling/pawn-double-push stay correct: a piece is
                    // "unmoved" only when it still sits on its standard home square.
                    piece.hasMoved = !Self.isHomeSquare(piece: piece, file: file, rank: rank)
                    newSquares[file][rank] = piece
                    file += 1
                }
            }
            guard file == 8 else { return false }
        }

        let active = parts[1].lowercased()
        guard active == "w" || active == "b" else { return false }

        let castling = parts.count >= 3 ? parts[2] : "-"
        let ep = parts.count >= 4 ? parts[3] : "-"
        let half = parts.count >= 5 ? (Int(parts[4]) ?? 0) : 0
        let full = parts.count >= 6 ? (Int(parts[5]) ?? 1) : 1

        // Commit (all-or-nothing).
        squares = newSquares
        turn = active == "w" ? .white : .black
        whiteCanCastleKingside  = castling.contains("K")
        whiteCanCastleQueenside = castling.contains("Q")
        blackCanCastleKingside  = castling.contains("k")
        blackCanCastleQueenside = castling.contains("q")
        enPassantTarget = ep == "-" ? nil : Position(algebraic: ep)
        halfMoveClock = half
        fullMoveNumber = full
        moveHistory = []
        gameOver = false
        resetPositionHistory()
        return true
    }

    private static func pieceFromFENChar(_ ch: Character) -> Piece? {
        let color: PieceColor = ch.isUppercase ? .white : .black
        let type: PieceType
        switch ch.uppercased() {
        case "K": type = .king
        case "Q": type = .queen
        case "R": type = .rook
        case "B": type = .bishop
        case "N": type = .knight
        case "P": type = .pawn
        default:  return nil
        }
        return Piece(type: type, color: color)
    }

    private static func isHomeSquare(piece: Piece, file: Int, rank: Int) -> Bool {
        let homeRank = piece.color == .white ? 0 : 7
        switch piece.type {
        case .pawn:   return rank == (piece.color == .white ? 1 : 6)
        case .rook:   return rank == homeRank && (file == 0 || file == 7)
        case .knight: return rank == homeRank && (file == 1 || file == 6)
        case .bishop: return rank == homeRank && (file == 2 || file == 5)
        case .queen:  return rank == homeRank && file == 3
        case .king:   return rank == homeRank && file == 4
        }
    }
}
