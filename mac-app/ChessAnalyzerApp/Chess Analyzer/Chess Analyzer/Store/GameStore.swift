import Foundation
import SQLite3

// MARK: - Public value types

/// Game result, stored compactly as an integer.
enum StoredResult: Int32 {
    case unknown = 0, whiteWin = 1, blackWin = 2, draw = 3

    init(pgn: String) {
        switch pgn {
        case "1-0":     self = .whiteWin
        case "0-1":     self = .blackWin
        case "1/2-1/2": self = .draw
        default:        self = .unknown
        }
    }
}

/// One game's header as returned by a search (no movetext in the hot path).
struct GameHeader: Identifiable {
    let id: Int64
    let white: String
    let black: String
    let result: StoredResult
    let date: Int32          // yyyymmdd, 0 if unknown
    let whiteElo: Int32      // -1 if unknown
    let blackElo: Int32
    let eco: Int32           // 0..499, -1 if unknown
}

/// One next-move row of the opening explorer for a position.
struct ExplorerMove: Identifiable {
    let nextMove: Int32
    var white = 0, draw = 0, black = 0
    var id: Int32 { nextMove }
    var total: Int { white + draw + black }
}

/// Multi-criteria header filter. nil fields are ignored.
struct GameStoreFilter {
    var whitePlayerId: Int64?
    var blackPlayerId: Int64?
    var ecoMin: Int32?
    var ecoMax: Int32?
    var whiteEloMin: Int32?
    var blackEloMin: Int32?
    var dateFrom: Int32?
    var dateTo: Int32?
    var result: StoredResult?
}

// MARK: - GameStore

/// Purpose-built SQLite store for the large reference database. Separate from
/// SwiftData (which stays for app state). Designed for ms-level multi-criteria
/// search and transposition-aware position lookup over millions of games.
final class GameStore {

    private var db: OpaquePointer?
    private static let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // Bulk-load prepared statements + intern caches (held only during a load session).
    private var gameInsert: OpaquePointer?
    private var posInsert: OpaquePointer?
    private var markIndexedStmt: OpaquePointer?
    private var playerCache: [String: Int64] = [:]
    private var eventCache: [String: Int64] = [:]

    // MARK: Init

    init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw NSError(domain: "GameStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "open failed: \(msg)"])
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA temp_store=MEMORY;")
        exec("PRAGMA cache_size=-262144;")     // 256 MB page cache
        exec("PRAGMA mmap_size=4294967296;")   // 4 GB
        exec("PRAGMA foreign_keys=ON;")
        createSchema()
        migrateSchema()
    }

    /// Additive migrations for stores created before a column existed. Cheap PRAGMA check + ALTER.
    private func migrateSchema() {
        if !columnExists("games", "game_hash") {
            exec("ALTER TABLE games ADD COLUMN game_hash INTEGER;")
        }
        // `indexed` = 1 once a game's positions have been built (two-phase: games load fast, position
        // index is built on demand). 0 = game present but not in the opening explorer yet.
        if !columnExists("games", "indexed") {
            exec("ALTER TABLE games ADD COLUMN indexed INTEGER DEFAULT 0;")
        }
        exec("CREATE INDEX IF NOT EXISTS idx_games_indexed ON games(indexed);")
        // Partial UNIQUE index: enforces exact-move dedup on insert (INSERT OR IGNORE), while rows
        // without a hash (NULL) are exempt so legacy games don't collide. Present for dedup-on-merge
        // (user imports); dropped during a clean pre-deduped bulk load for speed, then recreated.
        exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_games_hash ON games(game_hash) WHERE game_hash IS NOT NULL;")
    }

    private func columnExists(_ table: String, _ column: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return false }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column { return true }
        }
        return false
    }

    /// Default location alongside the app's other data.
    static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ogulcan.chess-analyzer", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("reference.sqlite")
    }

    deinit {
        sqlite3_finalize(gameInsert)
        sqlite3_finalize(posInsert)
        sqlite3_finalize(markIndexedStmt)
        sqlite3_close(db)
    }

    // MARK: Schema

    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS players (id INTEGER PRIMARY KEY, name TEXT, name_key TEXT);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_players_key ON players(name_key);

        CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, name TEXT, name_key TEXT);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_events_key ON events(name_key);

        CREATE TABLE IF NOT EXISTS games (
          id INTEGER PRIMARY KEY,
          white_id INTEGER, black_id INTEGER,
          result INTEGER, date INTEGER,
          white_elo INTEGER, black_elo INTEGER,
          eco INTEGER, event_id INTEGER, round TEXT,
          ply_count INTEGER, moves BLOB, flags INTEGER,
          game_hash INTEGER
        );

        CREATE TABLE IF NOT EXISTS positions (
          zobrist INTEGER, game_id INTEGER, ply INTEGER,
          result INTEGER, next_move INTEGER
        );
        """)
    }

    /// Create indexes — call AFTER a bulk load (far faster than maintaining them during insert).
    func createIndexes() {
        createHeaderIndexes()
        createPositionIndexes()
    }

    /// Game-header indexes only. Every ingest writes game rows, so these are always (re)built.
    func createHeaderIndexes() {
        exec("CREATE INDEX IF NOT EXISTS idx_games_white ON games(white_id, date);")
        exec("CREATE INDEX IF NOT EXISTS idx_games_black ON games(black_id, date);")
        exec("CREATE INDEX IF NOT EXISTS idx_games_eco   ON games(eco, date);")
        exec("CREATE INDEX IF NOT EXISTS idx_games_welo  ON games(white_elo, date);")
        exec("CREATE INDEX IF NOT EXISTS idx_games_belo  ON games(black_elo, date);")
        exec("CREATE INDEX IF NOT EXISTS idx_games_indexed ON games(indexed);")
    }

    func createPositionIndexes() {
        exec("CREATE INDEX IF NOT EXISTS idx_pos_zobrist ON positions(zobrist);")
        // Covering index: full-DB transposition-aware opening explorer with no join.
        exec("CREATE INDEX IF NOT EXISTS idx_pos_explorer ON positions(zobrist, next_move, result);")
        exec("ANALYZE;")
    }

    func dropPositionIndexes() {
        exec("DROP INDEX IF EXISTS idx_pos_zobrist;")
        exec("DROP INDEX IF EXISTS idx_pos_explorer;")
    }

    /// Drop only the game-header indexes (leaves the position indexes intact).
    func dropHeaderIndexes() {
        for name in ["idx_games_white","idx_games_black","idx_games_eco","idx_games_welo","idx_games_belo"] {
            exec("DROP INDEX IF EXISTS \(name);")
        }
    }

    func dropIndexes() {
        dropHeaderIndexes()
        dropPositionIndexes()
    }

    // MARK: Bulk load

    /// Begin a high-throughput ingest session. Drops indexes, opens one transaction, prepares the
    /// insert statements. `dedup` = enforce exact-move dedup on insert (INSERT OR IGNORE + the unique
    /// game_hash index) — needed when MERGING into an existing DB (user imports); a clean pre-deduped
    /// bulk load passes false to skip that per-insert cost. Pair with `finishBulkLoad(dedup:)`.
    func beginBulkLoad(dedup: Bool = true, writesPositions: Bool = true) {
        dropHeaderIndexes()
        // Only churn the (huge) position indexes when this ingest actually inserts position rows.
        // A header-only merge into an already-indexed reference DB must NOT drop/rebuild them —
        // otherwise the explorer full-scans for the whole import and a minutes-long rebuild follows.
        if writesPositions { dropPositionIndexes() }
        if !dedup { exec("DROP INDEX IF EXISTS idx_games_hash;") }   // plain fast INSERT, no unique check
        exec("PRAGMA synchronous=OFF;")                              // rebuildable download → safe to skip fsyncs
        exec("BEGIN TRANSACTION;")
        let verb = dedup ? "INSERT OR IGNORE" : "INSERT"
        sqlite3_prepare_v2(db,
            "\(verb) INTO games (white_id,black_id,result,date,white_elo,black_elo,eco,event_id,round,ply_count,moves,flags,game_hash) " +
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", -1, &gameInsert, nil)
        sqlite3_prepare_v2(db,
            "INSERT INTO positions (zobrist,game_id,ply,result,next_move) VALUES (?,?,?,?,?)", -1, &posInsert, nil)
    }

    /// Insert one game plus its position rows. `positions` are (zobrist bit-pattern, ply, nextMove encoding).
    @discardableResult
    func addGame(white: String, black: String, event: String?,
                 result: StoredResult, date: Int32,
                 whiteElo: Int32 = -1, blackElo: Int32 = -1, eco: Int32 = -1,
                 round: String? = nil, moves: Data? = nil, flags: Int32 = 0,
                 gameHash: Int64? = nil, plyCount: Int32? = nil,
                 positions: [(zobrist: Int64, ply: Int32, nextMove: Int32)]) -> Int64 {
        let wid = internPlayer(white)
        let bid = internPlayer(black)
        let eid = event.map { internEvent($0) }

        sqlite3_reset(gameInsert); sqlite3_clear_bindings(gameInsert)
        sqlite3_bind_int64(gameInsert, 1, wid)
        sqlite3_bind_int64(gameInsert, 2, bid)
        sqlite3_bind_int(gameInsert, 3, result.rawValue)
        sqlite3_bind_int(gameInsert, 4, date)
        sqlite3_bind_int(gameInsert, 5, whiteElo)
        sqlite3_bind_int(gameInsert, 6, blackElo)
        sqlite3_bind_int(gameInsert, 7, eco)
        if let eid = eid { sqlite3_bind_int64(gameInsert, 8, eid) } else { sqlite3_bind_null(gameInsert, 8) }
        bindText(gameInsert, 9, round)
        sqlite3_bind_int(gameInsert, 10, plyCount ?? Int32(positions.count))
        if let moves = moves {
            _ = moves.withUnsafeBytes { sqlite3_bind_blob(gameInsert, 11, $0.baseAddress, Int32(moves.count), GameStore.TRANSIENT) }
        } else { sqlite3_bind_null(gameInsert, 11) }
        sqlite3_bind_int(gameInsert, 12, flags)
        if let gameHash = gameHash { sqlite3_bind_int64(gameInsert, 13, gameHash) } else { sqlite3_bind_null(gameInsert, 13) }
        sqlite3_step(gameInsert)

        // With INSERT OR IGNORE + the unique game_hash index, a duplicate inserts 0 rows. Skip its
        // positions (they'd be duplicates too) and signal the caller with a 0 id.
        if sqlite3_changes(db) == 0 { return 0 }

        let gid = sqlite3_last_insert_rowid(db)

        for p in positions {
            sqlite3_reset(posInsert); sqlite3_clear_bindings(posInsert)
            sqlite3_bind_int64(posInsert, 1, p.zobrist)
            sqlite3_bind_int64(posInsert, 2, gid)
            sqlite3_bind_int(posInsert, 3, p.ply)
            sqlite3_bind_int(posInsert, 4, result.rawValue)
            sqlite3_bind_int(posInsert, 5, p.nextMove)
            sqlite3_step(posInsert)
        }
        return gid
    }

    /// Periodically flush the open transaction during a long load to bound the WAL.
    func flushBatch() { exec("COMMIT;"); exec("BEGIN TRANSACTION;") }

    /// Finish the ingest session: commit, finalize statements, (re)build indexes.
    func finishBulkLoad(dedup: Bool = true, writesPositions: Bool = true) {
        exec("COMMIT;")
        sqlite3_finalize(gameInsert); gameInsert = nil
        sqlite3_finalize(posInsert);  posInsert = nil
        playerCache.removeAll(); eventCache.removeAll()
        exec("PRAGMA synchronous=NORMAL;")
        if !dedup {
            // Recreate the game_hash unique index we dropped for the clean load, so future user
            // imports still dedup against this base.
            exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_games_hash ON games(game_hash) WHERE game_hash IS NOT NULL;")
        }
        createHeaderIndexes()
        if writesPositions {
            createPositionIndexes()   // rebuilds + full ANALYZE
        } else {
            exec("ANALYZE games;")    // refresh only the just-rebuilt header-index stats
        }
    }

    /// Wipe all content (players, events, games, positions) for a fresh full-snapshot load.
    /// Drop + recreate rather than DELETE, so it's instant regardless of row count. Callable only
    /// outside a bulk-load transaction.
    func resetAll() {
        exec("DROP TABLE IF EXISTS positions;")
        exec("DROP TABLE IF EXISTS games;")
        exec("DROP TABLE IF EXISTS events;")
        exec("DROP TABLE IF EXISTS players;")
        playerCache.removeAll()
        eventCache.removeAll()
        createSchema()
        migrateSchema()
    }

    // MARK: Two-phase position indexing (build the opening explorer on demand)

    /// Games whose positions are in the explorer.
    var indexedGameCount: Int { scalar("SELECT count(*) FROM games WHERE indexed=1") }

    /// Total games matching an optional SQL predicate (for the indexing-screen estimate).
    func gameCount(whereSQL: String? = nil) -> Int {
        scalar("SELECT count(*) FROM games" + (whereSQL.map { " WHERE \($0)" } ?? ""))
    }

    /// Estimated number of position rows a build would produce: Σ min(ply_count, maxPly) over the
    /// not-yet-indexed games matching the filter.
    func estimatedPositions(whereSQL: String?, maxPly: Int) -> Int {
        var clause = "indexed=0"
        if let whereSQL, !whereSQL.isEmpty { clause += " AND (\(whereSQL))" }
        return scalar("SELECT COALESCE(SUM(MIN(ply_count, \(maxPly))), 0) FROM games WHERE \(clause)")
    }

    /// Fetch a page of not-yet-indexed games (id ascending, id > afterId) with their stored SAN moves.
    func unindexedGames(whereSQL: String?, afterId: Int64, limit: Int) -> [(id: Int64, moves: String, result: Int32)] {
        var clause = "indexed=0 AND id>?"
        if let whereSQL, !whereSQL.isEmpty { clause += " AND (\(whereSQL))" }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "SELECT id, moves, result FROM games WHERE \(clause) ORDER BY id LIMIT \(limit)", -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, afterId)
        var out: [(Int64, String, Int32)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let moves = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let res = sqlite3_column_int(stmt, 2)
            out.append((id, moves, res))
        }
        return out
    }

    /// Begin a position-index build (positions only; games already loaded). Pairs with `finishPositionIndexing`.
    func beginPositionIndexing() {
        dropPositionIndexes()
        exec("PRAGMA synchronous=OFF;")
        exec("BEGIN TRANSACTION;")
        sqlite3_prepare_v2(db, "INSERT INTO positions (zobrist,game_id,ply,result,next_move) VALUES (?,?,?,?,?)", -1, &posInsert, nil)
        sqlite3_prepare_v2(db, "UPDATE games SET indexed=1 WHERE id=?", -1, &markIndexedStmt, nil)
    }

    /// Insert one game's positions and mark it indexed.
    func addGamePositions(gameId: Int64, result: Int32, positions: [(zobrist: Int64, ply: Int32, nextMove: Int32)]) {
        for p in positions {
            sqlite3_reset(posInsert); sqlite3_clear_bindings(posInsert)
            sqlite3_bind_int64(posInsert, 1, p.zobrist)
            sqlite3_bind_int64(posInsert, 2, gameId)
            sqlite3_bind_int(posInsert, 3, p.ply)
            sqlite3_bind_int(posInsert, 4, result)
            sqlite3_bind_int(posInsert, 5, p.nextMove)
            sqlite3_step(posInsert)
        }
        sqlite3_reset(markIndexedStmt); sqlite3_clear_bindings(markIndexedStmt)
        sqlite3_bind_int64(markIndexedStmt, 1, gameId)
        sqlite3_step(markIndexedStmt)
    }

    func flushIndexBatch() { exec("COMMIT;"); exec("BEGIN TRANSACTION;") }

    func finishPositionIndexing() {
        exec("COMMIT;")
        sqlite3_finalize(posInsert); posInsert = nil
        sqlite3_finalize(markIndexedStmt); markIndexedStmt = nil
        exec("PRAGMA synchronous=NORMAL;")
        createPositionIndexes()
    }

    // MARK: Interning

    func internPlayer(_ name: String) -> Int64 { intern(name, table: "players", cache: &playerCache) }
    func internEvent(_ name: String) -> Int64 { intern(name, table: "events", cache: &eventCache) }

    private func intern(_ rawName: String, table: String, cache: inout [String: Int64]) -> Int64 {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        if let id = cache[key] { return id }

        // Look up existing.
        var sel: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT id FROM \(table) WHERE name_key=?", -1, &sel, nil)
        bindText(sel, 1, key)
        if sqlite3_step(sel) == SQLITE_ROW {
            let id = sqlite3_column_int64(sel, 0)
            sqlite3_finalize(sel); cache[key] = id; return id
        }
        sqlite3_finalize(sel)

        // Insert new.
        var ins: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO \(table) (name, name_key) VALUES (?,?)", -1, &ins, nil)
        bindText(ins, 1, name); bindText(ins, 2, key)
        sqlite3_step(ins)
        sqlite3_finalize(ins)
        let id = sqlite3_last_insert_rowid(db)
        cache[key] = id
        return id
    }

    // MARK: Queries

    var gameCount: Int { scalar("SELECT count(*) FROM games") }

    func playerId(name: String) -> Int64? {
        let key = name.trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var sel: OpaquePointer?
        defer { sqlite3_finalize(sel) }
        sqlite3_prepare_v2(db, "SELECT id FROM players WHERE name_key=?", -1, &sel, nil)
        bindText(sel, 1, key)
        return sqlite3_step(sel) == SQLITE_ROW ? sqlite3_column_int64(sel, 0) : nil
    }

    /// Player names matching a prefix/substring, for the search-mask picker.
    func searchPlayers(_ term: String, limit: Int = 50) -> [(id: Int64, name: String)] {
        let key = term.trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "SELECT id, name FROM players WHERE name_key LIKE ? ORDER BY name LIMIT ?", -1, &stmt, nil)
        bindText(stmt, 1, key + "%")
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var out: [(Int64, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((sqlite3_column_int64(stmt, 0), columnText(stmt, 1)))
        }
        return out
    }

    /// Multi-criteria header search. Builds a parameterized WHERE from the filter.
    func search(_ f: GameStoreFilter, limit: Int = 200, offset: Int = 0) -> [GameHeader] {
        var conds: [String] = []
        var binders: [(OpaquePointer?) -> Void] = []
        var idx: Int32 = 1
        func add(_ sql: String, _ bind: @escaping (OpaquePointer?, Int32) -> Void) {
            conds.append(sql); let i = idx; idx += 1; binders.append { bind($0, i) }
        }
        if let v = f.whitePlayerId { add("white_id=?") { sqlite3_bind_int64($0, $1, v) } }
        if let v = f.blackPlayerId { add("black_id=?") { sqlite3_bind_int64($0, $1, v) } }
        if let v = f.ecoMin { add("eco>=?") { sqlite3_bind_int($0, $1, v) } }
        if let v = f.ecoMax { add("eco<=?") { sqlite3_bind_int($0, $1, v) } }
        if let v = f.whiteEloMin { add("white_elo>=?") { sqlite3_bind_int($0, $1, v) } }
        if let v = f.blackEloMin { add("black_elo>=?") { sqlite3_bind_int($0, $1, v) } }
        if let v = f.dateFrom { add("date>=?") { sqlite3_bind_int($0, $1, v) } }
        if let v = f.dateTo { add("date<=?") { sqlite3_bind_int($0, $1, v) } }
        if let v = f.result { add("result=?") { sqlite3_bind_int($0, $1, v.rawValue) } }

        let whereSQL = conds.isEmpty ? "" : "WHERE " + conds.joined(separator: " AND ")
        let sql = """
        SELECT g.id, w.name, b.name, g.result, g.date, g.white_elo, g.black_elo, g.eco
        FROM games g
        JOIN players w ON w.id = g.white_id
        JOIN players b ON b.id = g.black_id
        \(whereSQL)
        ORDER BY g.date DESC
        LIMIT ? OFFSET ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        for b in binders { b(stmt) }
        sqlite3_bind_int(stmt, idx, Int32(limit)); idx += 1
        sqlite3_bind_int(stmt, idx, Int32(offset))

        var rows: [GameHeader] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(GameHeader(
                id: sqlite3_column_int64(stmt, 0),
                white: columnText(stmt, 1),
                black: columnText(stmt, 2),
                result: StoredResult(rawValue: sqlite3_column_int(stmt, 3)) ?? .unknown,
                date: sqlite3_column_int(stmt, 4),
                whiteElo: sqlite3_column_int(stmt, 5),
                blackElo: sqlite3_column_int(stmt, 6),
                eco: sqlite3_column_int(stmt, 7)
            ))
        }
        return rows
    }

    /// Load one game's header + SAN move list by id (for the read-only reference browser).
    func loadGame(id: Int64) -> (header: GameHeader, moves: [String])? {
        let sql = """
        SELECT g.id, w.name, b.name, g.result, g.date, g.white_elo, g.black_elo, g.eco, g.moves
        FROM games g
        JOIN players w ON w.id = g.white_id
        JOIN players b ON b.id = g.black_id
        WHERE g.id = ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let header = GameHeader(
            id: sqlite3_column_int64(stmt, 0),
            white: columnText(stmt, 1),
            black: columnText(stmt, 2),
            result: StoredResult(rawValue: sqlite3_column_int(stmt, 3)) ?? .unknown,
            date: sqlite3_column_int(stmt, 4),
            whiteElo: sqlite3_column_int(stmt, 5),
            blackElo: sqlite3_column_int(stmt, 6),
            eco: sqlite3_column_int(stmt, 7)
        )
        let movesText = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""
        let moves = movesText.split(separator: " ").map(String.init)
        return (header, moves)
    }

    /// How many games reached this exact position (transposition-aware).
    func positionGameCount(_ zobristKey: Int64) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "SELECT count(*) FROM positions WHERE zobrist=?", -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, zobristKey)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    /// Opening explorer for a position: every next move with its W/D/L. Pure
    /// covering-index GROUP BY, no join — the whole-DB opening book in one query.
    func explorer(_ zobristKey: Int64) -> [ExplorerMove] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db,
            "SELECT next_move, result, count(*) FROM positions WHERE zobrist=? GROUP BY next_move, result",
            -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, zobristKey)

        var byMove: [Int32: ExplorerMove] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let move = sqlite3_column_int(stmt, 0)
            let res = StoredResult(rawValue: sqlite3_column_int(stmt, 1)) ?? .unknown
            let n = Int(sqlite3_column_int64(stmt, 2))
            var row = byMove[move] ?? ExplorerMove(nextMove: move)
            switch res {
            case .whiteWin: row.white += n
            case .blackWin: row.black += n
            case .draw:     row.draw += n
            case .unknown:  break
            }
            byMove[move] = row
        }
        return byMove.values.sorted { $0.total > $1.total }
    }

    // MARK: - Low-level helpers

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            FileHandle.standardError.write("GameStore SQL error: \(String(cString: sqlite3_errmsg(db)))\n".data(using: .utf8)!)
        }
    }

    private func scalar(_ sql: String) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, idx, v, -1, GameStore.TRANSIENT) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }
}
