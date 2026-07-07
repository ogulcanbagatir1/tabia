import Foundation

// MARK: - PGN Move Node (supports variations)

class PGNMoveNode {
    var move: String
    var moveNumber: Int
    var isBlackMove: Bool
    var comment: String?
    var annotation: String = ""  // NAG: "", "!", "!!", "?", "??", "!?", "?!"
    var variations: [[PGNMoveNode]] = []  // Alternative lines at this point
    var next: PGNMoveNode?

    init(move: String, moveNumber: Int, isBlackMove: Bool, comment: String? = nil, annotation: String = "") {
        self.move = move
        self.moveNumber = moveNumber
        self.isBlackMove = isBlackMove
        self.comment = comment
        self.annotation = annotation
    }
}

struct PGNGame {
    var headers: [String: String] = [:]
    var moves: [String] = []  // Main line moves (for backward compatibility)
    var moveTree: PGNMoveNode?  // Full move tree with variations
    var result: String = "*"

    var event: String { headers["Event"] ?? "?" }
    var site: String { headers["Site"] ?? "?" }
    var date: String { headers["Date"] ?? "????.??.??" }
    var round: String { headers["Round"] ?? "?" }
    var white: String { headers["White"] ?? "?" }
    var black: String { headers["Black"] ?? "?" }
    var eco: String? { headers["ECO"] }
    var opening: String? { headers["Opening"] }

    /// Reconstruct a PGN string from parsed headers and moves
    func toPGNString() -> String {
        var pgn = ""

        let standardOrder = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
        for key in standardOrder {
            let value = headers[key] ?? "?"
            pgn += "[\(key) \"\(value)\"]\n"
        }

        for (key, value) in headers where !standardOrder.contains(key) {
            pgn += "[\(key) \"\(value)\"]\n"
        }

        pgn += "\n"

        // If we have a move tree, export it with variations
        if let tree = moveTree {
            pgn += exportMoveTree(tree)
        } else {
            // Fall back to simple move list
            var moveText = ""
            for (index, move) in moves.enumerated() {
                let moveNumber = index / 2 + 1
                if index % 2 == 0 {
                    moveText += "\(moveNumber). "
                }
                moveText += "\(move) "
            }
            pgn += moveText
        }

        pgn += result
        return pgn
    }

    private func exportMoveTree(_ node: PGNMoveNode?) -> String {
        guard let node = node else { return "" }

        var result = ""
        var current: PGNMoveNode? = node

        while let n = current {
            // Add move number for white moves or at start of variation
            if !n.isBlackMove {
                result += "\(n.moveNumber). "
            } else if result.isEmpty || result.hasSuffix("( ") {
                result += "\(n.moveNumber)... "
            }

            result += "\(n.move)\(n.annotation) "

            // Add comment if present
            if let comment = n.comment, !comment.isEmpty {
                result += "{ \(comment) } "
            }

            // Add variations
            for variation in n.variations {
                if let firstMove = variation.first {
                    result += "( "
                    result += exportMoveTree(firstMove)
                    result += ") "
                }
            }

            current = n.next
        }

        return result
    }
}

class PGNParser {
    func parse(file: URL) throws -> [PGNGame] {
        // Try different encodings
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .ascii, .windowsCP1252]

        var content: String?
        var lastError: Error?

        for encoding in encodings {
            do {
                content = try String(contentsOf: file, encoding: encoding)
                break
            } catch {
                lastError = error
            }
        }

        guard let fileContent = content else {
            throw lastError ?? NSError(domain: "PGNParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read file with any supported encoding"])
        }

        return parse(string: fileContent)
    }
    
    func parse(string: String) -> [PGNGame] {
        return splitGames(string).compactMap { parseGame(header: $0.header, moveText: $0.moveText) }
    }

    /// Split a multi-game PGN into per-game (headerBlock, moveTextBlock) using ONE character scanner
    /// that tracks `{}` comments (across newlines), `;` line comments, and `()` variations. A new game
    /// begins only at a `[` tag line at line start, outside any comment/variation, AFTER movetext has
    /// started — so a result token or a `[` inside a comment/variation can't falsely split a game.
    func splitGames(_ string: String) -> [(header: String, moveText: String)] {
        var games: [(String, String)] = []
        var header = "", moveText = ""
        var seenMoveText = false
        var inComment = false, inLineComment = false, varDepth = 0
        var atLineStart = true

        func flush() {
            if !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               !moveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                games.append((header, moveText))
            }
            header = ""; moveText = ""; seenMoveText = false
            inComment = false; inLineComment = false; varDepth = 0
        }

        let chars = Array(string)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if inLineComment {
                moveText.append(c)
                if c == "\n" { inLineComment = false; atLineStart = true } else { atLineStart = false }
                i += 1; continue
            }
            if inComment {
                moveText.append(c)
                if c == "}" { inComment = false }
                atLineStart = false; i += 1; continue
            }
            if c == "{" { inComment = true; seenMoveText = true; moveText.append(c); atLineStart = false; i += 1; continue }
            if c == ";" { inLineComment = true; moveText.append(c); atLineStart = false; i += 1; continue }
            if c == "(" { varDepth += 1; seenMoveText = true; moveText.append(c); atLineStart = false; i += 1; continue }
            if c == ")" { if varDepth > 0 { varDepth -= 1 }; moveText.append(c); atLineStart = false; i += 1; continue }

            // Tag line at line start (outside comment/variation) — new game if movetext already began.
            if atLineStart && c == "[" && varDepth == 0 {
                if seenMoveText { flush() }
                var line = ""
                while i < chars.count && chars[i] != "\n" { line.append(chars[i]); i += 1 }
                if i < chars.count { i += 1 } // consume newline
                header += line + "\n"
                atLineStart = true
                continue
            }

            if !c.isWhitespace { seenMoveText = true }
            moveText.append(c)
            atLineStart = (c == "\n")
            i += 1
        }
        flush()
        return games
    }

    private func parseGame(header: String, moveText: String) -> PGNGame? {
        var game = PGNGame()
        for raw in header.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") { parseHeader(line, into: &game) }
        }

        let movetext = moveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !movetext.isEmpty {
            if let tree = parseMoveTextWithVariations(movetext) {
                game.moveTree = tree
                game.moves = mainlineMoves(tree)
            } else {
                // Keep the flat main line if the tree parse yields nothing (never regress to zero moves).
                extractMainLineMoves(movetext, into: &game)
            }
            if let r = extractResult(movetext) { game.result = r }
        }

        if game.moves.isEmpty && game.headers.isEmpty { return nil }
        return game
    }

    /// Flat main-line SAN list from a parsed move tree (mainline = the `next` chain, no variations).
    private func mainlineMoves(_ tree: PGNMoveNode?) -> [String] {
        var out: [String] = []
        var node = tree
        while let n = node { out.append(n.move); node = n.next }
        return out
    }

    /// The last result token in the movetext, skipping comment tokens.
    private func extractResult(_ moveText: String) -> String? {
        let results: Set<String> = ["1-0", "0-1", "1/2-1/2", "*"]
        for t in tokenizeMoveText(moveText).reversed() {
            if t.hasPrefix("{") { continue }
            if results.contains(t) { return t }
        }
        return nil
    }
    
    private func parseHeader(_ line: String, into game: inout PGNGame) {
        // Format: [Key "Value"]
        guard line.hasPrefix("[") && line.hasSuffix("]") else { return }
        
        let content = line.dropFirst().dropLast()
        let parts = content.split(separator: " ", maxSplits: 1)
        
        guard parts.count == 2 else { return }
        
        let key = String(parts[0])
        var value = String(parts[1])
        
        // Remove quotes
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        
        game.headers[key] = value
        if key == "Result" {
            game.result = value
        }
    }
    
    /// Extract just the main line moves (ignoring variations) for backward compatibility
    private func extractMainLineMoves(_ line: String, into game: inout PGNGame) {
        // Remove comments {...}
        var cleanLine = line
        while let start = cleanLine.firstIndex(of: "{"),
              let end = cleanLine[start...].firstIndex(of: "}") {
            cleanLine.removeSubrange(start...end)
        }

        // Remove variations (...) - for main line extraction only
        var depth = 0
        var filtered = ""
        for char in cleanLine {
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
            } else if depth == 0 {
                filtered.append(char)
            }
        }
        cleanLine = filtered

        // Split by whitespace
        let tokens = cleanLine.split(separator: " ").map { String($0) }

        for token in tokens {
            let cleanToken = token.trimmingCharacters(in: .whitespaces)

            // Skip empty tokens
            if cleanToken.isEmpty {
                continue
            }

            // Skip result markers
            if ["1-0", "0-1", "1/2-1/2", "*"].contains(cleanToken) {
                game.result = cleanToken
                continue
            }

            // Skip standalone ellipsis (used for Black's move indicator)
            // Also handle unicode ellipsis character (…)
            if cleanToken == "..." || cleanToken == ".." || cleanToken == "…" {
                continue
            }

            // Skip move numbers (e.g., "1.", "23.", "1...", "15...")
            // Move numbers are digits followed by one or more dots
            if cleanToken.range(of: #"^\d+\.+$"#, options: .regularExpression) != nil {
                continue
            }

            // Handle move numbers attached to moves (e.g., "1.e4" -> "e4", "1...e5" -> "e5")
            var moveText = cleanToken
            if let range = cleanToken.range(of: #"^\d+\.+"#, options: .regularExpression) {
                moveText = String(cleanToken[range.upperBound...])
            }

            // Also handle standalone ellipsis prefix (e.g., "...e5" -> "e5")
            // Handle both regular dots and unicode ellipsis (…)
            if moveText.hasPrefix("…") {
                moveText = String(moveText.dropFirst(1))
            } else if moveText.hasPrefix("...") {
                moveText = String(moveText.dropFirst(3))
            } else if moveText.hasPrefix("..") {
                moveText = String(moveText.dropFirst(2))
            }

            // Skip if empty after removing move number/ellipsis
            if moveText.isEmpty {
                continue
            }

            // Strip annotation suffix before validation/storage
            let (cleanMove, _) = stripAnnotation(moveText)

            // This should be a move
            if isValidMove(cleanMove) {
                game.moves.append(cleanMove)
            }
        }
    }

    /// Parse full move text including variations into a tree structure
    func parseMoveTextWithVariations(_ moveText: String) -> PGNMoveNode? {
        let tokens = tokenizeMoveText(moveText)
        var index = 0
        var moveNumber = 1
        var isBlackMove = false

        return parseVariation(tokens: tokens, index: &index, moveNumber: &moveNumber, isBlackMove: &isBlackMove)
    }

    private func tokenizeMoveText(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inComment = false
        var inLineComment = false

        func flush() {
            if !current.isEmpty {
                tokens.append(contentsOf: current.split(separator: " ").map { String($0) })
                current = ""
            }
        }

        for char in text {
            if inLineComment {
                if char == "\n" { inLineComment = false }
                continue
            }
            if char == "{" {
                flush()
                inComment = true
                current = "{"
            } else if char == "}" {
                current += "}"
                tokens.append(current)
                current = ""
                inComment = false
            } else if inComment {
                current.append(char)
            } else if char == ";" {          // rest-of-line comment
                flush()
                inLineComment = true
            } else if char == "(" {
                flush()
                tokens.append("(")
            } else if char == ")" {
                flush()
                tokens.append(")")
            } else if char.isWhitespace {
                flush()
            } else {
                current.append(char)
            }
        }

        flush()
        return tokens.filter { !$0.isEmpty }
    }

    private func parseVariation(tokens: [String], index: inout Int, moveNumber: inout Int, isBlackMove: inout Bool) -> PGNMoveNode? {
        var firstNode: PGNMoveNode?
        var lastNode: PGNMoveNode?

        while index < tokens.count {
            let token = tokens[index]

            // Handle variation start
            if token == "(" {
                index += 1
                // Save current state
                var varMoveNumber = moveNumber
                var varIsBlackMove = isBlackMove

                // If last move was white, variation starts with black at same move number
                // If last move was black, variation would be alternative to that black move
                if let last = lastNode {
                    varMoveNumber = last.moveNumber
                    varIsBlackMove = last.isBlackMove
                }

                if let variation = parseVariation(tokens: tokens, index: &index, moveNumber: &varMoveNumber, isBlackMove: &varIsBlackMove) {
                    lastNode?.variations.append([variation])
                }
                continue
            }

            // Handle variation end
            if token == ")" {
                index += 1
                return firstNode
            }

            // Handle comments
            if token.hasPrefix("{") && token.hasSuffix("}") {
                let comment = String(token.dropFirst().dropLast())
                lastNode?.comment = comment
                index += 1
                continue
            }

            // Handle move numbers (e.g., "1.", "1...", "23.")
            if token.contains(".") {
                let parts = token.split(separator: ".", omittingEmptySubsequences: false)
                if let numStr = parts.first, let num = Int(numStr) {
                    moveNumber = num
                    // Count dots to determine if it's black's move
                    let dotCount = token.filter { $0 == "." }.count
                    isBlackMove = dotCount >= 3

                    // Check if there's a move after the number (e.g., "1.e4")
                    let afterDots = token.replacingOccurrences(of: #"^\d+\.+"#, with: "", options: .regularExpression)
                    let (cleanAfterDots, afterDotsAnn) = stripAnnotation(afterDots)
                    if !cleanAfterDots.isEmpty && isValidMove(cleanAfterDots) {
                        let node = PGNMoveNode(move: cleanAfterDots, moveNumber: moveNumber, isBlackMove: isBlackMove, annotation: afterDotsAnn)
                        if firstNode == nil {
                            firstNode = node
                        }
                        lastNode?.next = node
                        lastNode = node
                        isBlackMove = !isBlackMove
                        if isBlackMove == false {
                            moveNumber += 1
                        }
                    }
                }
                index += 1
                continue
            }

            // Handle result markers
            if ["1-0", "0-1", "1/2-1/2", "*"].contains(token) {
                index += 1
                continue
            }

            // Skip NAG tokens ($1, $2, …)
            if token.hasPrefix("$") {
                index += 1
                continue
            }

            // Handle moves
            let (cleanToken, tokenAnn) = stripAnnotation(token)
            if isValidMove(cleanToken) {
                let node = PGNMoveNode(move: cleanToken, moveNumber: moveNumber, isBlackMove: isBlackMove, annotation: tokenAnn)
                if firstNode == nil {
                    firstNode = node
                }
                lastNode?.next = node
                lastNode = node

                isBlackMove = !isBlackMove
                if !isBlackMove {
                    moveNumber += 1
                }
            }

            index += 1
        }

        return firstNode
    }
    
    /// Strip annotation suffix from a move string, returning (cleanMove, annotation)
    private func stripAnnotation(_ moveText: String) -> (String, String) {
        // Check longest annotations first to avoid partial matches
        let annotations = ["!!", "??", "!?", "?!", "!", "?"]
        for ann in annotations {
            if moveText.hasSuffix(ann) {
                let clean = String(moveText.dropLast(ann.count))
                if !clean.isEmpty {
                    return (clean, ann)
                }
            }
        }
        return (moveText, "")
    }

    /// Anchored SAN matcher. Annotations (!?…) are stripped before validation; check/mate suffixes
    /// (+/#) and promotion (=Q) are allowed. Anchoring (^…$) rejects comment words that merely
    /// CONTAIN a square substring (the old permissive check let "d4-ish" phantom moves through).
    private static let sanRegex = try? NSRegularExpression(
        pattern: "^(O-O(-O)?|0-0(-0)?|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](=[QRBNqrbn])?)[+#]?$"
    )

    private func isValidMove(_ move: String) -> Bool {
        guard !move.isEmpty else { return false }
        if let re = PGNParser.sanRegex {
            return re.firstMatch(in: move, range: NSRange(move.startIndex..., in: move)) != nil
        }
        // Defensive fallback (only if the regex failed to compile): old permissive check.
        if move.hasPrefix("O-O") || move.hasPrefix("0-0") { return true }
        for f in "abcdefgh" { for r in "12345678" where move.contains("\(f)\(r)") { return true } }
        return false
    }
    
    // MARK: - Convert PGN to GameTree

    func toGameTree(_ pgnGame: PGNGame) -> GameTree? {
        // Prefer the full variation tree when we parsed one — preserves variations + comments on load.
        if let tree = pgnGame.moveTree {
            let gameTree = GameTree()
            buildGameTreeFromMoveTree(tree, gameTree: gameTree, parentNode: gameTree.root)
            gameTree.rebuildMainLine()   // buildGameTreeFromMoveTree uses addChild, which doesn't track mainLine
            gameTree.goToStart()
            return gameTree
        }

        let gameTree = GameTree()

        // Use the main line moves for basic import
        for moveText in pgnGame.moves {
            // Create a fresh NotationEngine from the current node's board state
            let currentBoard = gameTree.currentNode.boardState
            let notationEngine = NotationEngine(board: currentBoard)

            guard let move = notationEngine.fromAlgebraic(moveText) else {
                print("Warning: Could not parse move: \(moveText)")
                break
            }

            // Pass the original notation string to avoid recomputing it
            if !gameTree.addMove(move, notation: moveText) {
                print("Warning: Could not execute move: \(moveText)")
                break
            }
        }

        gameTree.goToStart()
        return gameTree
    }

    /// Convert PGN to GameTree with full variation support
    func toGameTreeWithVariations(_ pgnGame: PGNGame, moveText: String) -> GameTree? {
        let gameTree = GameTree()

        // Parse the move text into a tree structure
        guard let moveTree = parseMoveTextWithVariations(moveText) else {
            // Fall back to simple parsing
            return toGameTree(pgnGame)
        }

        // Build the game tree from the parsed move tree
        buildGameTreeFromMoveTree(moveTree, gameTree: gameTree, parentNode: gameTree.root)

        gameTree.goToStart()
        return gameTree
    }

    private func buildGameTreeFromMoveTree(_ moveNode: PGNMoveNode?, gameTree: GameTree, parentNode: GameNode) {
        guard let moveNode = moveNode else { return }

        var currentPGNNode: PGNMoveNode? = moveNode
        var currentGameNode = parentNode

        while let pgnNode = currentPGNNode {
            // Parse and execute the move
            let currentBoard = currentGameNode.boardState
            let notationEngine = NotationEngine(board: currentBoard)

            if let move = notationEngine.fromAlgebraic(pgnNode.move) {
                // Add the move to the game tree
                let newBoard = currentBoard.copy()
                if newBoard.makeMove(move) {
                    let newGameNode = currentGameNode.addChild(move: move, boardState: newBoard, notation: pgnNode.move)

                    // Add annotation if present
                    if !pgnNode.annotation.isEmpty {
                        newGameNode.annotation = pgnNode.annotation
                    }

                    // Add comment if present
                    if let comment = pgnNode.comment {
                        newGameNode.comment = comment
                    }

                    // Process variations (alternatives to the NEXT move)
                    for variation in pgnNode.variations {
                        if let variationStart = variation.first {
                            // Variations branch from the current position (before this move was made)
                            // So we add them as siblings to the newGameNode
                            buildVariationFromMoveTree(variationStart, gameTree: gameTree, parentNode: currentGameNode)
                        }
                    }

                    currentGameNode = newGameNode
                }
            }

            currentPGNNode = pgnNode.next
        }
    }

    private func buildVariationFromMoveTree(_ moveNode: PGNMoveNode, gameTree: GameTree, parentNode: GameNode) {
        var currentPGNNode: PGNMoveNode? = moveNode
        var currentGameNode = parentNode

        while let pgnNode = currentPGNNode {
            let currentBoard = currentGameNode.boardState
            let notationEngine = NotationEngine(board: currentBoard)

            if let move = notationEngine.fromAlgebraic(pgnNode.move) {
                let newBoard = currentBoard.copy()
                if newBoard.makeMove(move) {
                    let newGameNode = currentGameNode.addChild(move: move, boardState: newBoard, notation: pgnNode.move)

                    // Add annotation if present
                    if !pgnNode.annotation.isEmpty {
                        newGameNode.annotation = pgnNode.annotation
                    }

                    if let comment = pgnNode.comment {
                        newGameNode.comment = comment
                    }

                    // Process nested variations
                    for variation in pgnNode.variations {
                        if let variationStart = variation.first {
                            buildVariationFromMoveTree(variationStart, gameTree: gameTree, parentNode: currentGameNode)
                        }
                    }

                    currentGameNode = newGameNode
                }
            }

            currentPGNNode = pgnNode.next
        }
    }

}

// MARK: - PGN Exporter

class PGNExporter {
    func export(_ gameTree: GameTree, headers: [String: String] = [:]) -> String {
        return gameTree.toPGN(headers: headers)
    }
    
    func export(games: [GameTree], headers: [[String: String]]) -> String {
        var result = ""
        
        for (index, game) in games.enumerated() {
            let gameHeaders = index < headers.count ? headers[index] : [:]
            result += export(game, headers: gameHeaders)
            result += "\n\n"
        }
        
        return result
    }
    
    func save(_ gameTree: GameTree, to url: URL, headers: [String: String] = [:]) throws {
        let pgn = export(gameTree, headers: headers)
        try pgn.write(to: url, atomically: true, encoding: .utf8)
    }
}
