import Foundation

// MARK: - Opening Tree Node

class OpeningNode: Identifiable {
    let id = UUID()
    let move: String?  // UCI move (e.g., "e2e4") or nil for root
    let san: String?   // Standard algebraic notation (e.g., "e4")
    var name: String?  // Opening name if this position has one
    var eco: String?   // ECO code if applicable
    var children: [OpeningNode] = []
    weak var parent: OpeningNode?

    init(move: String? = nil, san: String? = nil, name: String? = nil, eco: String? = nil, parent: OpeningNode? = nil) {
        self.move = move
        self.san = san
        self.name = name
        self.eco = eco
        self.parent = parent
    }

    func addChild(move: String, san: String, name: String? = nil, eco: String? = nil) -> OpeningNode {
        let child = OpeningNode(move: move, san: san, name: name, eco: eco, parent: self)
        children.append(child)
        return child
    }

    /// Get the full move sequence from root to this node
    var moveSequence: [String] {
        var moves: [String] = []
        var current: OpeningNode? = self
        while let node = current, node.move != nil {
            moves.insert(node.move!, at: 0)
            current = node.parent
        }
        return moves
    }

    /// Get the full SAN sequence from root to this node
    var sanSequence: [String] {
        var moves: [String] = []
        var current: OpeningNode? = self
        while let node = current, node.san != nil {
            moves.insert(node.san!, at: 0)
            current = node.parent
        }
        return moves
    }
}

// MARK: - Opening Book

class OpeningBook: ObservableObject {
    static let shared = OpeningBook()

    let root: OpeningNode

    // Quick lookup by move sequence (UCI moves joined by space)
    private var positionToOpening: [String: (name: String, eco: String)] = [:]

    // Quick lookup by ECO code → opening name
    private var ecoToOpening: [String: String] = [:]

    private var isLoaded = false

    init() {
        root = OpeningNode(name: "Starting Position")
        loadFromJSON()
    }

    /// Find opening name for a sequence of UCI moves
    func findOpening(moves: [String]) -> (name: String, eco: String)? {
        guard isLoaded else { return nil }

        var key = moves.joined(separator: " ")

        // Try exact match first
        if let opening = positionToOpening[key] {
            return opening
        }

        // Progressively shorter prefixes — trim the joined string back to each preceding space
        // instead of re-joining ever-shorter arrays (avoids an O(N) allocation per step).
        while let space = key.lastIndex(of: " ") {
            key = String(key[..<space])
            if let opening = positionToOpening[key] {
                return opening
            }
        }

        return nil
    }

    /// Find opening name by ECO code (e.g. "B90" → "Sicilian Defense: Najdorf Variation")
    func findByECO(_ eco: String) -> String? {
        guard isLoaded else { return nil }
        return ecoToOpening[eco]
    }

    /// Get the opening node for a sequence of moves
    func findNode(moves: [String]) -> OpeningNode? {
        guard isLoaded else { return nil }

        var current = root
        for move in moves {
            guard let child = current.children.first(where: { $0.move == move }) else {
                return nil
            }
            current = child
        }
        return current
    }

    // MARK: - Load from Pre-computed JSON

    private func loadFromJSON() {
        guard let url = Bundle.main.url(forResource: "openings", withExtension: "json") else {
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            return
        }

        struct OpeningEntry: Decodable {
            let eco: String
            let name: String
            let uci: [String]
            let san: [String]
        }

        guard let entries = try? JSONDecoder().decode([OpeningEntry].self, from: data) else {
            return
        }

        for entry in entries {
            guard entry.uci.count == entry.san.count, !entry.uci.isEmpty else { continue }

            // Build tree nodes
            var currentNode = root
            for i in 0..<entry.uci.count {
                let uciMove = entry.uci[i]
                let sanMove = entry.san[i]

                if let existingChild = currentNode.children.first(where: { $0.move == uciMove }) {
                    currentNode = existingChild
                } else {
                    currentNode = currentNode.addChild(move: uciMove, san: sanMove)
                }
            }

            // Set opening info on the terminal node
            currentNode.name = entry.name
            currentNode.eco = entry.eco

            // Register in flat lookup tables
            let key = entry.uci.joined(separator: " ")
            positionToOpening[key] = (entry.name, entry.eco)
            ecoToOpening[entry.eco] = entry.name
        }

        isLoaded = true
    }
}
