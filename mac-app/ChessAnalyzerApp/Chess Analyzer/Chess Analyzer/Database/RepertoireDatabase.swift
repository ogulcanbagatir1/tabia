import Foundation
import SwiftUI
import SwiftData

// MARK: - Repertoire Database

/// Service layer for Repertoires (mirrors GameDatabase). All mutations go through here so
/// SwiftUI views can refresh via the published cache + objectWillChange notifications.
class RepertoireDatabase: ObservableObject {
    private var modelContext: ModelContext
    private let container: ModelContainer

    @Published private(set) var repertoires: [Repertoire] = []
    @Published private(set) var folders: [RepertoireFolder] = []

    init(modelContext: ModelContext, container: ModelContainer) {
        self.modelContext = modelContext
        self.container = container
        refreshCache()
        backfillFENs()
    }

    private func refreshCache() {
        let repDescriptor = FetchDescriptor<Repertoire>(
            sortBy: [SortDescriptor(\.dateModified, order: .reverse)]
        )
        repertoires = (try? modelContext.fetch(repDescriptor)) ?? []

        let folderDescriptor = FetchDescriptor<RepertoireFolder>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.name)]
        )
        folders = (try? modelContext.fetch(folderDescriptor)) ?? []
    }

    private func save() {
        try? modelContext.save()
        objectWillChange.send()
        refreshCache()
    }

    // MARK: - Counts / Filters

    var repertoireCount: Int { repertoires.count }

    func repertoires(side: RepertoireSide) -> [Repertoire] {
        repertoires.filter { $0.side == side }
    }

    func repertoires(in folderId: UUID?) -> [Repertoire] {
        guard let folderId else {
            return repertoires.filter { $0.folder == nil }
        }
        return repertoires.filter { $0.folder?.id == folderId }
    }

    func repertoiresInFolderCount(_ folderId: UUID) -> Int {
        repertoires.filter { $0.folder?.id == folderId }.count
    }

    // MARK: - Lookup

    func repertoire(withId id: UUID) -> Repertoire? {
        var descriptor = FetchDescriptor<Repertoire>(
            predicate: #Predicate<Repertoire> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func folder(withId id: UUID?) -> RepertoireFolder? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<RepertoireFolder>(
            predicate: #Predicate<RepertoireFolder> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Repertoire CRUD

    @discardableResult
    func createRepertoire(name: String,
                          side: RepertoireSide,
                          summary: String = "",
                          startingFEN: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                          startingMoveSequence: [String] = [],
                          folder: RepertoireFolder? = nil) -> Repertoire {
        let repertoire = Repertoire(
            name: name,
            side: side,
            summary: summary,
            startingFEN: startingFEN,
            startingMoveSequence: startingMoveSequence,
            folder: folder
        )
        modelContext.insert(repertoire)

        // Seed the root node so the tree always has an anchor at startingFEN.
        // Normalize through the loader so the stored FEN matches getFEN() output exactly.
        let rootFEN = ChessBoard(fen: startingFEN)?.getFEN() ?? startingFEN
        let root = RepertoireNode(
            repertoire: repertoire,
            parent: nil,
            uciMove: nil,
            san: nil,
            fen: rootFEN,
            isUserMove: false,
            ownership: .opponentCritical,
            isPrimary: false
        )
        modelContext.insert(root)
        repertoire.rootNodeId = root.id

        save()
        return repertoire
    }

    func renameRepertoire(_ repertoire: Repertoire, to newName: String) {
        repertoire.name = newName
        repertoire.dateModified = Date()
        save()
    }

    func updateRepertoire(_ repertoire: Repertoire) {
        repertoire.dateModified = Date()
        save()
    }

    func deleteRepertoire(_ repertoire: Repertoire) {
        modelContext.delete(repertoire)
        save()
    }

    func moveRepertoire(_ repertoire: Repertoire, toFolder folderId: UUID?) {
        repertoire.folder = folder(withId: folderId)
        repertoire.dateModified = Date()
        save()
    }

    // MARK: - Node CRUD

    func insertNode(_ node: RepertoireNode, into repertoire: Repertoire, parent: RepertoireNode?) {
        node.repertoire = repertoire
        node.parent = parent
        modelContext.insert(node)
        repertoire.dateModified = Date()
        save()
    }

    func deleteNode(_ node: RepertoireNode) {
        // Cascade rule on parent → children handles descendants automatically.
        if let rep = node.repertoire {
            rep.dateModified = Date()
        }
        modelContext.delete(node)
        save()
    }

    func updateNode(_ node: RepertoireNode) {
        node.dateModified = Date()
        if let rep = node.repertoire {
            rep.dateModified = Date()
        }
        save()
    }

    /// Persist training-stat mutations only. Does NOT bump `dateModified` (so drilling doesn't
    /// reshuffle the library) and does NOT refresh the cache (training stats don't affect lists).
    func saveTrainingChanges() {
        try? modelContext.save()
    }

    // MARK: - Position schedules (transposition-aware SRS)

    /// All position schedules for a repertoire, keyed by Zobrist positionHash.
    func positionSchedules(for repertoireId: UUID) -> [Int64: PositionSchedule] {
        let descriptor = FetchDescriptor<PositionSchedule>(
            predicate: #Predicate<PositionSchedule> { $0.repertoireId == repertoireId }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        var map: [Int64: PositionSchedule] = [:]
        for r in rows { map[r.positionHash] = r }   // last wins on the rare duplicate
        return map
    }

    private func positionSchedule(repertoireId: UUID, positionHash: Int64) -> PositionSchedule? {
        // Filter positionHash in memory (avoids an Int64-equality predicate).
        let descriptor = FetchDescriptor<PositionSchedule>(
            predicate: #Predicate<PositionSchedule> { $0.repertoireId == repertoireId }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.first { $0.positionHash == positionHash }
    }

    /// Apply a review to the schedule for (repertoire, position), creating it on first sight.
    /// Uses the training-only save path (no `dateModified` bump, no library reshuffle).
    @discardableResult
    func recordReview(repertoireId: UUID, positionHash: Int64, quality: Int, responseMs: Double) -> TrainingStats {
        let schedule: PositionSchedule
        if let existing = positionSchedule(repertoireId: repertoireId, positionHash: positionHash) {
            schedule = existing
        } else {
            schedule = PositionSchedule(repertoireId: repertoireId, positionHash: positionHash)
            modelContext.insert(schedule)
        }
        schedule.stats = schedule.stats.appliedReview(quality: quality, responseMs: responseMs)
        saveTrainingChanges()
        return schedule.stats
    }

    /// One-time seed of position schedules from legacy per-node `training` data. No-op once any
    /// schedule exists for the repertoire. Keys each user decision by the Zobrist hash of the
    /// position it's made from (the parent node's position).
    func migrateTrainingIfNeeded(_ repertoire: Repertoire) {
        guard positionSchedules(for: repertoire.id).isEmpty else { return }
        var created = false
        for node in repertoire.nodes where node.isUserMove && node.isPrimary {
            guard let stats = node.training, (stats.correctCount + stats.wrongCount) > 0 else { continue }
            guard let parent = node.parent, !parent.fen.isEmpty,
                  let board = ChessBoard(fen: parent.fen) else { continue }
            let key = Zobrist.sqliteKey(board)
            if positionSchedule(repertoireId: repertoire.id, positionHash: key) == nil {
                modelContext.insert(PositionSchedule(repertoireId: repertoire.id, positionHash: key, stats: stats))
                created = true
            }
        }
        if created { saveTrainingChanges() }
    }

    // MARK: - Folder CRUD

    @discardableResult
    func createFolder(name: String, accentColorHex: String? = nil) -> RepertoireFolder {
        let newOrder = (folders.map(\.order).max() ?? -1) + 1
        let folder = RepertoireFolder(name: name, accentColorHex: accentColorHex, order: newOrder)
        modelContext.insert(folder)
        save()
        return folder
    }

    func renameFolder(_ folder: RepertoireFolder, to newName: String) {
        folder.name = newName
        save()
    }

    func deleteFolder(_ folder: RepertoireFolder, deleteRepertoires: Bool) {
        if deleteRepertoires {
            let folderId = folder.id
            try? modelContext.delete(model: Repertoire.self, where: #Predicate<Repertoire> {
                $0.folder?.id == folderId
            })
        }
        // When deleteRepertoires == false, @Relationship(deleteRule: .nullify) keeps the repertoires.
        modelContext.delete(folder)
        save()
    }

    // MARK: - Position Lookup (deviation detection)

    /// Reduced FEN that ignores castling rights, en-passant target, and move counts so that
    /// transpositions match. Format: "<pieces> <stm>".
    static func positionKey(fromFEN fen: String) -> String {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count >= 2 { return "\(parts[0]) \(parts[1])" }
        return fen
    }

    /// All repertoires that contain a node at the given board position, optionally filtered by side.
    func repertoires(matching positionKey: String, side: RepertoireSide? = nil) -> [(Repertoire, RepertoireNode)] {
        var results: [(Repertoire, RepertoireNode)] = []
        for rep in repertoires {
            if let side, rep.side != side { continue }
            for node in rep.nodes {
                if node.fen.isEmpty { continue }
                if Self.positionKey(fromFEN: node.fen) == positionKey {
                    results.append((rep, node))
                }
            }
        }
        return results
    }

    /// Walk every repertoire's tree from root, replay UCI moves to compute FEN for any node that
    /// lacks one. Idempotent — already-filled nodes are skipped.
    private func backfillFENs() {
        var dirty = false
        for rep in repertoires {
            guard let rootRepId = rep.rootNodeId,
                  let rootRepNode = rep.nodes.first(where: { $0.id == rootRepId }) else { continue }
            let board = ChessBoard(fen: rep.startingFEN) ?? ChessBoard()
            if rootRepNode.fen.isEmpty {
                rootRepNode.fen = board.getFEN()
                dirty = true
            }
            dirty = backfillFromNode(rootRepNode, board: board) || dirty
        }
        if dirty {
            try? modelContext.save()
        }
    }

    private func backfillFromNode(_ node: RepertoireNode, board: ChessBoard) -> Bool {
        var dirty = false
        for child in node.children {
            guard let uci = child.uciMove,
                  let move = Self.parseUCI(uci, board: board) else { continue }
            let newBoard = board.copy()
            guard newBoard.makeMove(move) else { continue }
            if child.fen.isEmpty {
                child.fen = newBoard.getFEN()
                dirty = true
            }
            if backfillFromNode(child, board: newBoard) { dirty = true }
        }
        return dirty
    }

    private static func parseUCI(_ uci: String, board: ChessBoard) -> Move? {
        guard uci.count >= 4 else { return nil }
        let chars = Array(uci)
        guard let fromFileAscii = chars[0].asciiValue,
              let toFileAscii = chars[2].asciiValue else { return nil }
        let fromFile = Int(fromFileAscii) - Int(Character("a").asciiValue!)
        guard let fromRank = Int(String(chars[1])) else { return nil }
        let toFile = Int(toFileAscii) - Int(Character("a").asciiValue!)
        guard let toRank = Int(String(chars[3])) else { return nil }
        let from = Position(fromFile, fromRank - 1)
        let to = Position(toFile, toRank - 1)
        guard let piece = board.pieceAt(from) else { return nil }
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
        return Move(
            from: from, to: to, piece: piece,
            capturedPiece: isEnPassant ? board.pieceAt(Position(to.file, from.rank)) : capturedPiece,
            isEnPassant: isEnPassant,
            isCastling: isCastling,
            promotionType: promotionType
        )
    }

    // MARK: - PGN Import

    /// Walk the first game's move tree and merge it into the repertoire. Existing nodes (same UCI from
    /// the same parent) are reused; new ones are inserted. Returns the number of nodes added.
    @discardableResult
    func importPGN(from url: URL, into repertoire: Repertoire) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let parser = PGNParser()
        let pgnGames = try parser.parse(file: url)
        guard let firstGame = pgnGames.first,
              let moveTree = firstGame.moveTree
        else { return 0 }

        guard let rootRepId = repertoire.rootNodeId,
              let rootRepNode = repertoire.nodes.first(where: { $0.id == rootRepId })
        else {
            throw NSError(domain: "RepertoireDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Repertoire has no root node"])
        }

        var addedCount = 0
        // Honor the repertoire's starting position so mid-game repertoires import correct FENs.
        let board = ChessBoard(fen: repertoire.startingFEN) ?? ChessBoard()
        importLine(moveTree, into: repertoire, parent: rootRepNode, board: board, addedCount: &addedCount)
        repertoire.dateModified = Date()
        save()
        return addedCount
    }

    private func importLine(_ start: PGNMoveNode?,
                            into repertoire: Repertoire,
                            parent: RepertoireNode,
                            board: ChessBoard,
                            addedCount: inout Int) {
        var pgn: PGNMoveNode? = start
        var currentParent = parent
        var currentBoard = board

        while let node = pgn {
            let notation = NotationEngine(board: currentBoard)
            guard let move = notation.fromAlgebraic(node.move) else { break }

            let newBoard = currentBoard.copy()
            guard newBoard.makeMove(move) else { break }

            let uci = Self.uci(from: move)
            var matched = currentParent.children.first(where: { $0.uciMove == uci })

            if matched == nil {
                let parentTurn = currentBoard.turn
                let isUser = parentTurn == (repertoire.side == .white ? PieceColor.white : PieceColor.black)
                let ownership: NodeOwnership = isUser ? .mineMain : .opponentCritical
                let new = RepertoireNode(
                    repertoire: repertoire,
                    parent: currentParent,
                    uciMove: uci,
                    san: node.move,
                    fen: newBoard.getFEN(),
                    isUserMove: isUser,
                    ownership: ownership,
                    isPrimary: isUser,
                    annotation: node.comment ?? "",
                    evalGlyph: node.annotation.isEmpty ? nil : node.annotation
                )
                modelContext.insert(new)
                addedCount += 1
                matched = new
            }

            // Walk into variations first (siblings to this move, branching from the same currentBoard)
            for variation in node.variations {
                if let variationStart = variation.first {
                    importLine(variationStart, into: repertoire, parent: currentParent, board: currentBoard, addedCount: &addedCount)
                }
            }

            currentParent = matched!
            currentBoard = newBoard
            pgn = node.next
        }
    }

    private static func uci(from move: Move) -> String {
        func sq(_ p: Position) -> String {
            let file = Character(UnicodeScalar(Int(Character("a").asciiValue!) + p.file)!)
            return "\(file)\(p.rank + 1)"
        }
        var s = sq(move.from) + sq(move.to)
        if let promo = move.promotionType {
            switch promo {
            case .queen:  s += "q"
            case .rook:   s += "r"
            case .bishop: s += "b"
            case .knight: s += "n"
            default: break
            }
        }
        return s
    }

    // MARK: - Preview Helper

    @MainActor static func preview() -> RepertoireDatabase {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Repertoire.self, RepertoireFolder.self, RepertoireNode.self,
            configurations: config
        )
        return RepertoireDatabase(modelContext: container.mainContext, container: container)
    }
}
