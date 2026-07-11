import Foundation
import Combine

/// Per-database (game folder) opening index. Mirrors the reference DB's pipeline for each user
/// database: replay every game → Zobrist-hash the opening positions → SQLite index → a
/// transposition-aware opening explorer. One SQLite file per folder lives under
/// Application Support/com.ogulcan.chess-analyzer/db-index/<folderUUID>.sqlite.
///
/// The full `GameStore` + `Ingestor` machinery is reused verbatim, so a user database becomes as
/// searchable in the Opening Explorer as the hosted reference database.
final class DatabaseIndex: ObservableObject {
    static let shared = DatabaseIndex()

    /// The folder currently being (re)built, or nil when idle. Only one build runs at a time.
    @Published private(set) var indexingFolderId: UUID? = nil
    @Published private(set) var indexProgress: Int = 0
    @Published private(set) var indexTotal: Int = 0
    /// Bumped whenever an index is created or removed, so views re-read `isIndexed` / counts.
    @Published private(set) var revision: Int = 0

    var isIndexing: Bool { indexingFolderId != nil }

    /// Opening + early middlegame only — where transposition search actually pays off.
    private let maxIndexPly = 40

    /// Cached read connections for explorer queries (closed on rebuild).
    private var openStores: [UUID: GameStore] = [:]

    private static let indexDir: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ogulcan.chess-analyzer/db-index", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }()

    private func path(for folderId: UUID) -> String {
        Self.indexDir.appendingPathComponent("\(folderId.uuidString).sqlite").path
    }

    private func fileExists(for folderId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: path(for: folderId))
    }

    // MARK: - State

    /// True once a folder has a built index with at least one game.
    func isIndexed(_ folderId: UUID) -> Bool { indexedGameCount(folderId) > 0 }

    /// Games present in the folder's opening index (0 = not indexed). This is post-dedup, so it can
    /// be lower than the source database's game count — use `isStale` for freshness, not this.
    func indexedGameCount(_ folderId: UUID) -> Int {
        guard fileExists(for: folderId) else { return 0 }
        return (try? readOnlyStore(folderId))?.gameCount ?? 0
    }

    /// Number of source games fed to the index when it was built (persisted). Compared against the
    /// database's current game count to detect that games were added/removed since indexing.
    private var sourceCounts: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "dbIndexSourceCounts") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "dbIndexSourceCounts") }
    }

    /// True when the database has games added/removed since its index was built (index out of date).
    func isStale(_ folderId: UUID, currentCount: Int) -> Bool {
        guard isIndexed(folderId), let built = sourceCounts[folderId.uuidString] else { return false }
        return built != currentCount
    }

    private func readOnlyStore(_ folderId: UUID) throws -> GameStore {
        if let s = openStores[folderId] { return s }
        let s = try GameStore(path: path(for: folderId))
        openStores[folderId] = s
        return s
    }

    private func closeStore(_ folderId: UUID) { openStores[folderId] = nil }

    // MARK: - Build

    /// Build (or rebuild) the opening index for `folderId` from each game's full PGN string.
    /// Runs off the main thread; progress and completion are published on the main thread.
    func buildIndex(folderId: UUID, pgns: [String], sourceCount: Int, completion: (() -> Void)? = nil) {
        guard indexingFolderId == nil else { return }
        indexingFolderId = folderId
        indexProgress = 0
        indexTotal = pgns.count

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Start from a clean file so a rebuild never doubles up positions.
            self.closeStore(folderId)
            let base = self.path(for: folderId)
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: base + suffix)
            }

            do {
                let store = try GameStore(path: base)
                let ingestor = Ingestor(store: store)
                ingestor.maxIndexPly = self.maxIndexPly
                let games = PGNParser().parse(string: pgns.joined(separator: "\n\n"))
                ingestor.ingest(games: games, flushEvery: 500) { done in
                    DispatchQueue.main.async { self.indexProgress = min(done, self.indexTotal) }
                }
                store.createIndexes()
            } catch {
                // A failed build just leaves the folder unindexed.
            }

            DispatchQueue.main.async {
                self.indexProgress = self.indexTotal
                self.sourceCounts[folderId.uuidString] = sourceCount
                self.indexingFolderId = nil
                self.revision += 1
                completion?()
            }
        }
    }

    /// Drop a folder's index (e.g. when the database is deleted).
    func removeIndex(folderId: UUID) {
        closeStore(folderId)
        let base = path(for: folderId)
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: base + suffix)
        }
        var counts = sourceCounts
        counts[folderId.uuidString] = nil
        sourceCounts = counts
        revision += 1
    }

    // MARK: - Explorer

    /// Transposition-aware opening explorer for `board`, merged across the selected indexed folders.
    /// Move codes are rendered to SAN against `board`, mirroring `ReferenceDatabase.explorer`.
    func explorer(folderIds: [UUID], board: ChessBoard) -> ReferenceExplorerResult {
        let key = Zobrist.sqliteKey(board)
        var byUci: [String: (w: Int, d: Int, b: Int)] = [:]

        for fid in folderIds {
            guard fid != indexingFolderId, fileExists(for: fid),
                  let store = try? readOnlyStore(fid) else { continue }
            for r in store.explorer(key) {
                let uci = ReferenceDatabase.uci(from: r.nextMove)
                var e = byUci[uci] ?? (0, 0, 0)
                e.w += r.white; e.d += r.draw; e.b += r.black
                byUci[uci] = e
            }
        }

        guard !byUci.isEmpty else { return ReferenceExplorerResult() }

        var result = ReferenceExplorerResult()
        for (uci, e) in byUci {
            let san = board.toAlgebraicPV(uciMoves: [uci]).first ?? uci
            result.moves.append(ReferenceExplorerEntry(san: san, uci: uci, white: e.w, draw: e.d, black: e.b))
            result.white += e.w; result.draw += e.d; result.black += e.b
        }
        result.moves.sort { $0.total > $1.total }
        return result
    }

    /// How many indexed games across `folderIds` reach the current position.
    func positionGameCount(folderIds: [UUID], board: ChessBoard) -> Int {
        let key = Zobrist.sqliteKey(board)
        var n = 0
        for fid in folderIds where fid != indexingFolderId && fileExists(for: fid) {
            if let store = try? readOnlyStore(fid) { n += store.positionGameCount(key) }
        }
        return n
    }
}
