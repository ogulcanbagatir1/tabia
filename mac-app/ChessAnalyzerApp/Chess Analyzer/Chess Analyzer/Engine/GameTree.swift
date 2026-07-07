import Foundation

// MARK: - Game Tree Node
class GameNode: Identifiable, ObservableObject {
    let id = UUID()
    @Published var move: Move?
    @Published var comment: String = ""
    @Published var annotation: String = ""  // "", "!", "!!", "?", "??", "!?", "?!"
    @Published var evaluation: Double?

    /// Pre-computed algebraic notation for this move (computed once when node is created)
    var cachedNotation: String?

    weak var parent: GameNode?
    @Published var children: [GameNode] = []
    @Published var boardState: ChessBoard

    var isMainLine: Bool {
        guard let parent = parent else { return true }
        return parent.children.first === self
    }

    init(move: Move? = nil, parent: GameNode? = nil, boardState: ChessBoard, notation: String? = nil) {
        self.move = move
        self.parent = parent
        self.boardState = boardState
        self.cachedNotation = notation
    }

    func addChild(move: Move, boardState: ChessBoard, notation: String? = nil) -> GameNode {
        // Use provided notation or compute it (expensive - creates NotationEngine + MoveGenerator)
        let cachedNotation = notation ?? NotationEngine(board: self.boardState).toAlgebraic(move)
        let child = GameNode(move: move, parent: self, boardState: boardState, notation: cachedNotation)
        children.append(child)
        return child
    }
    
    func setAnnotation(_ annotation: String) {
        let valid = ["", "!", "!!", "?", "??", "!?", "?!", "*", "B", "+", "o"]
        self.annotation = valid.contains(annotation) ? annotation : ""
    }

    func getMainLineDepth() -> Int {
        var depth = 0
        var current: GameNode? = self
        
        while let node = current, let parent = node.parent {
            if node.isMainLine {
                depth += 1
            }
            current = parent
        }
        
        return depth
    }
    
    func getMoveNumber() -> Int {
        return boardState.fullMoveNumber
    }
}

// MARK: - Game Tree
class GameTree: ObservableObject {
    @Published var root: GameNode
    @Published var currentNode: GameNode
    @Published var mainLine: [GameNode] = []

    // Navigation lock to prevent concurrent modifications
    private var isNavigating = false

    init() {
        let initialBoard = ChessBoard()
        let rootNode = GameNode(move: nil, parent: nil, boardState: initialBoard)
        self.root = rootNode
        self.currentNode = rootNode
        self.mainLine = [rootNode]
    }

    init(fen: String) {
        let board = ChessBoard()
        // TODO: Load FEN
        let rootNode = GameNode(move: nil, parent: nil, boardState: board)
        self.root = rootNode
        self.currentNode = rootNode
        self.mainLine = [rootNode]
    }
    
    // MARK: - Move Management
    
    /// Add a move to the current position
    /// - Parameters:
    ///   - move: The move to add
    ///   - notation: Optional pre-computed notation (avoids expensive recomputation when loading PGN)
    func addMove(_ move: Move, notation: String? = nil) -> Bool {
        // Check if this move already exists in children. Match on promotion target (and en
        // passant/castling) too — otherwise a second promotion choice from the same square (e.g.
        // e8=N after e8=Q) silently navigates to the existing queen node, making underpromotion
        // variations impossible to create.
        if let existingChild = currentNode.children.first(where: {
            $0.move?.from == move.from && $0.move?.to == move.to
                && $0.move?.promotionType == move.promotionType
                && $0.move?.isEnPassant == move.isEnPassant
                && $0.move?.isCastling == move.isCastling
        }) {
            // Move already exists, just navigate to it
            currentNode = existingChild
            return true
        }

        // Create new board state
        let newBoard = currentNode.boardState.copy()
        guard newBoard.makeMove(move) else {
            return false
        }

        // Add new node with optional notation
        let newNode = currentNode.addChild(move: move, boardState: newBoard, notation: notation)
        currentNode = newNode

        // Update main line if this is on the main line
        if newNode.isMainLine {
            mainLine.append(newNode)
        }

        return true
    }
    
    /// Add a variation (alternative move) at current position
    func addVariation(_ move: Move, notation: String? = nil) -> Bool {
        guard let parent = currentNode.parent else {
            // Can't add variation at root
            return false
        }

        // Create new board state from parent
        let newBoard = parent.boardState.copy()
        guard newBoard.makeMove(move) else {
            return false
        }

        // Add as sibling (variation)
        let newNode = parent.addChild(move: move, boardState: newBoard, notation: notation)
        currentNode = newNode

        return true
    }
    
    /// Delete current variation
    func deleteCurrentVariation() {
        guard let parent = currentNode.parent,
              !currentNode.isMainLine else {
            return
        }

        parent.children.removeAll { $0 === currentNode }
        currentNode = parent
    }

    /// Delete a specific node and all moves after it.
    /// Navigates to the parent node afterward.
    func deleteFromNode(_ node: GameNode) {
        guard let parent = node.parent else {
            // Can't delete the root node — clear all children instead
            root.children.removeAll()
            currentNode = root
            rebuildMainLine()
            return
        }

        // If we're currently at the deleted node or any of its descendants,
        // navigate back to the parent first
        if isDescendantOrSelf(currentNode, of: node) {
            currentNode = parent
        }

        parent.children.removeAll { $0 === node }
        rebuildMainLine()
    }

    /// Check if `node` is `ancestor` itself or a descendant of `ancestor`
    private func isDescendantOrSelf(_ node: GameNode, of ancestor: GameNode) -> Bool {
        var current: GameNode? = node
        while let n = current {
            if n === ancestor { return true }
            current = n.parent
        }
        return false
    }
    
    /// Promote variation to main line
    func promoteToMainLine() {
        guard let parent = currentNode.parent,
              !currentNode.isMainLine else {
            return
        }
        
        // Swap with first child (main line)
        if let mainLineIndex = parent.children.firstIndex(where: { $0 === currentNode }) {
            parent.children.swapAt(0, mainLineIndex)
            rebuildMainLine()
        }
    }
    
    /// Demote a main-line node to a subline (move it to the last position among siblings)
    func demoteToSubline(_ node: GameNode) {
        guard let parent = node.parent,
              node.isMainLine,
              parent.children.count > 1 else { return }

        // Move the first child (main line) to the end
        let main = parent.children.removeFirst()
        parent.children.append(main)
        rebuildMainLine()
    }

    /// Promote a specific node to main line
    func promoteNodeToMainLine(_ node: GameNode) {
        guard let parent = node.parent,
              !node.isMainLine else { return }

        if let idx = parent.children.firstIndex(where: { $0 === node }) {
            parent.children.swapAt(0, idx)
            rebuildMainLine()
        }
    }

    // MARK: - Navigation

    func goToStart() {
        guard !isNavigating else { return }
        isNavigating = true
        defer { isNavigating = false }
        currentNode = root
    }

    func goBack() -> Bool {
        guard !isNavigating else { return false }
        isNavigating = true
        defer { isNavigating = false }

        guard let parent = currentNode.parent else {
            return false
        }
        currentNode = parent
        return true
    }

    func goForward() -> Bool {
        guard !isNavigating else { return false }
        isNavigating = true
        defer { isNavigating = false }

        let children = currentNode.children // Capture to avoid race condition
        guard let firstChild = children.first else {
            return false
        }
        currentNode = firstChild
        return true
    }

    func goToEnd() {
        guard !isNavigating else { return }
        isNavigating = true
        defer { isNavigating = false }

        var node = currentNode
        while !node.children.isEmpty {
            node = node.children[0] // Follow main line
        }
        currentNode = node
    }

    func goToNode(_ node: GameNode) {
        guard !isNavigating else { return }
        isNavigating = true
        defer { isNavigating = false }
        currentNode = node
    }
    
    func goToMove(number: Int) {
        goToStart()
        var count = 0
        
        while count < number && !currentNode.children.isEmpty {
            currentNode = currentNode.children[0]
            if currentNode.boardState.turn == .white {
                count += 1
            }
        }
    }
    
    // MARK: - Helpers
    
    func rebuildMainLine() {
        mainLine = [root]
        var current = root
        
        while let firstChild = current.children.first {
            mainLine.append(firstChild)
            current = firstChild
        }
    }
    
    func getVariations(at node: GameNode) -> [GameNode] {
        guard let parent = node.parent else {
            return []
        }
        
        return parent.children.filter { $0 !== node }
    }
    
    func getAllMoves() -> [Move] {
        var moves: [Move] = []
        var current: GameNode? = root
        
        while let node = current, let firstChild = node.children.first {
            if let move = firstChild.move {
                moves.append(move)
            }
            current = firstChild
        }
        
        return moves
    }
    
    func getMoveList() -> [(moveNumber: Int, white: String?, black: String?)] {
        var result: [(Int, String?, String?)] = []
        var moves: [String] = []
        
        // Traverse main line
        var current = root
        while let firstChild = current.children.first {
            if let move = firstChild.move {
                let notation = NotationEngine(board: current.boardState).toAlgebraic(move)
                moves.append(notation)
            }
            current = firstChild
        }
        
        // Group into move pairs
        var moveNumber = 1
        var i = 0
        while i < moves.count {
            let whiteMove = moves[i]
            let blackMove = i + 1 < moves.count ? moves[i + 1] : nil
            result.append((moveNumber, whiteMove, blackMove))
            moveNumber += 1
            i += 2
        }
        
        return result
    }
    
    // MARK: - PGN Export
    
    func toPGN(headers: [String: String] = [:]) -> String {
        var pgn = ""
        
        // Headers
        let defaultHeaders: [String: String] = [
            "Event": "?",
            "Site": "?",
            "Date": "????.??.??",
            "Round": "?",
            "White": "?",
            "Black": "?",
            "Result": "*"
        ]
        
        let allHeaders = defaultHeaders.merging(headers) { _, new in new }
        
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            pgn += "[\(key) \"\(value)\"]\n"
        }
        
        pgn += "\n"
        
        // Moves — recurse over the tree so sibling variations ( … ) and node { comments } survive
        // export. The old flat walk emitted only the mainline and silently dropped all analysis.
        pgn += renderMoves(parent: root, forceNumber: false)

        pgn += allHeaders["Result"] ?? "*"

        return pgn
    }

    /// One move token with its move number / ellipsis and inline annotation.
    private func moveToken(node: GameNode, parent: GameNode, forceNumber: Bool) -> String {
        guard let move = node.move else { return "" }
        let notation = node.cachedNotation ?? NotationEngine(board: parent.boardState).toAlgebraic(move)
        let annotated = notation + node.annotation
        let num = parent.boardState.fullMoveNumber
        if parent.boardState.turn == .white {
            return "\(num). \(annotated) "
        } else if forceNumber {
            return "\(num)... \(annotated) "
        } else {
            return "\(annotated) "
        }
    }

    /// Recursively render the mainline from `parent`, emitting each extra child as a ( … ) variation
    /// and each node's comment as { … }. A black move following a comment/variation is renumbered "N…".
    private func renderMoves(parent: GameNode, forceNumber: Bool) -> String {
        guard let main = parent.children.first else { return "" }
        var out = moveToken(node: main, parent: parent, forceNumber: forceNumber)
        if !main.comment.isEmpty { out += "{ \(sanitizeComment(main.comment)) } " }
        var interrupted = !main.comment.isEmpty
        for sib in parent.children.dropFirst() {
            out += "( "
            out += moveToken(node: sib, parent: parent, forceNumber: true)
            if !sib.comment.isEmpty { out += "{ \(sanitizeComment(sib.comment)) } " }
            out += renderMoves(parent: sib, forceNumber: !sib.comment.isEmpty)
            out += ") "
            interrupted = true
        }
        out += renderMoves(parent: main, forceNumber: interrupted)
        return out
    }

    /// PGN comments cannot contain braces; neutralize any in user-entered text.
    private func sanitizeComment(_ s: String) -> String {
        s.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
    }
}
