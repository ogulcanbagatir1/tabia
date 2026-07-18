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

        rebuildPositionIndex()
    }

    /// Depth of nested `performBatch` calls. While non-zero, `save()` is a no-op and the single
    /// commit happens when the outermost batch closes.
    private var batchDepth = 0

    /// Run many mutations as one commit. Node CRUD saves individually, and each save is a SwiftData
    /// commit **plus** `objectWillChange` **plus** a full cache re-fetch — so reconciling a 500-node
    /// repertoire meant 500 of each, and every broadcast re-ran the deviation badge's own scan.
    func performBatch(_ body: () -> Void) {
        batchDepth += 1
        body()
        batchDepth -= 1
        if batchDepth == 0 { save() }
    }

    private func save() {
        guard batchDepth == 0 else { return }   // deferred to the end of the enclosing batch
        modelContext.saveOrReport("your repertoire")
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

    /// Create a repertoire from a PGN (used by "Save as Repertoire" on the analysis screen — the
    /// analysed tree, variations and all, becomes the prep). Reuses the tested PGN importer.
    @discardableResult
    func createRepertoire(named name: String, side: RepertoireSide, importingPGN pgn: String) -> Repertoire {
        let repertoire = createRepertoire(name: name, side: side)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tabia_rep_\(UUID().uuidString).pgn")
        if (try? pgn.write(to: tmp, atomically: true, encoding: .utf8)) != nil {
            _ = try? importPGN(from: tmp, into: repertoire)
            try? FileManager.default.removeItem(at: tmp)
        }
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
        modelContext.saveOrReport("your repertoire")
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
        // Track keys in memory. `positionSchedule(repertoireId:positionHash:)` fetches every row and
        // filters in memory, so calling it per node was O(nodes × schedules) fetches. The guard above
        // already proved the set starts empty, so only what we insert here can collide.
        var seenKeys = Set<Int64>()
        for node in repertoire.nodes where node.isUserMove && node.isPrimary {
            guard let stats = node.training, (stats.correctCount + stats.wrongCount) > 0 else { continue }
            guard let parent = node.parent, !parent.fen.isEmpty,
                  let board = ChessBoard(fen: parent.fen) else { continue }
            let key = Zobrist.sqliteKey(board)
            if seenKeys.insert(key).inserted {
                modelContext.insert(PositionSchedule(repertoireId: repertoire.id, positionHash: key, stats: stats))
                created = true
            }
        }
        if created { saveTrainingChanges() }
    }

    // MARK: - Game Links (repertoire positions you actually reached in your own games)

    /// Recompute `gameLinkIds` across `repertoire`'s nodes by replaying `games` and matching on
    /// Zobrist hash — so transposing into a prepared line counts, not just literal move order.
    /// The root is skipped: every game trivially "reaches" the starting position.
    ///
    /// PGN parsing and replay run off the main thread over plain values; only the SwiftData write
    /// comes back to the context's thread. `completion` reports how many nodes ended up linked.
    func rebuildGameLinks(for repertoire: Repertoire, games: [GameRecord], completion: ((Int) -> Void)? = nil) {
        // One position can sit under several nodes when the repertoire reaches it by two move orders.
        var nodesByKey: [Int64: [RepertoireNode]] = [:]
        for node in repertoire.nodes where node.uciMove != nil && !node.fen.isEmpty {
            guard let board = ChessBoard(fen: node.fen) else { continue }
            nodesByKey[Zobrist.sqliteKey(board), default: []].append(node)
        }
        guard !nodesByKey.isEmpty else { completion?(0); return }

        // Snapshot plain values — @Model objects must not cross threads.
        let wanted = Set(nodesByKey.keys)
        let entries: [(id: UUID, pgn: String)] = games.map { ($0.id, $0.pgn) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var hits: [Int64: Set<UUID>] = [:]
            let parser = PGNParser()
            let replay = IngestBoard()

            for entry in entries {
                guard let parsed = parser.parse(string: entry.pgn).first, !parsed.moves.isEmpty else { continue }
                replay.reset()
                for san in parsed.moves {
                    // An unparseable move means the rest of the replay is untrustworthy — drop it.
                    guard let move = replay.resolve(san) else { break }
                    replay.apply(move)
                    let key = replay.zobristKey()
                    if wanted.contains(key) { hits[key, default: []].insert(entry.id) }
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                var linked = 0
                var changed = false
                for (key, nodes) in nodesByKey {
                    let ids = Array(hits[key] ?? [])
                    for node in nodes {
                        if !ids.isEmpty { linked += 1 }
                        // Only write nodes whose link set actually moved.
                        if Set(node.gameLinkIds) != Set(ids) {
                            node.gameLinkIds = ids
                            changed = true
                        }
                    }
                }
                if changed { self.save() } else { self.objectWillChange.send() }
                completion?(linked)
            }
        }
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

    /// positionKey → the repertoire nodes standing on it. Rebuilt with the cache; makes the deviation
    /// badge an O(1) dictionary hit instead of an O(repertoires × nodes) walk that re-ran — and
    /// re-split every node's FEN — on every single board move.
    private var positionIndex: [String: [(Repertoire, RepertoireNode)]] = [:]

    private func rebuildPositionIndex() {
        var index: [String: [(Repertoire, RepertoireNode)]] = [:]
        for rep in repertoires {
            for node in rep.nodes where !node.fen.isEmpty {
                index[Self.positionKey(fromFEN: node.fen), default: []].append((rep, node))
            }
        }
        positionIndex = index
    }

    /// All repertoires that contain a node at the given board position, optionally filtered by side.
    func repertoires(matching positionKey: String, side: RepertoireSide? = nil) -> [(Repertoire, RepertoireNode)] {
        let hits = positionIndex[positionKey] ?? []
        guard let side else { return hits }
        return hits.filter { $0.0.side == side }
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
            modelContext.saveOrReport("your repertoire")
            // Nodes with an empty FEN were skipped when the index was built in refreshCache();
            // now that they have one, the index has to see them.
            rebuildPositionIndex()
        }
    }

    private func backfillFromNode(_ node: RepertoireNode, board: ChessBoard) -> Bool {
        var dirty = false
        for child in node.children {
            guard let uci = child.uciMove,
                  let move = UCI.move(uci, board: board) else { continue }
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

            let uci = UCI.string(from: move)
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
