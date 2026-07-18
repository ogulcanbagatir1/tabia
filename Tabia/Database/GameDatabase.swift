import Foundation
import SwiftUI
import SwiftData
import SQLite3

// MARK: - Import Result

struct ImportResult {
    let gamesImported: Int
    let errors: [String]
}

// MARK: - Game Folder

@Model
final class GameFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var dateCreated: Date
    @Relationship(deleteRule: .nullify, inverse: \GameRecord.folder)
    var games: [GameRecord] = []

    init(id: UUID = UUID(), name: String, dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
    }
}

// MARK: - Game Analysis Data

struct GameAnalysisData: Codable, Hashable {
    var evaluations: [Double]       // Eval at each position (centipawns, White's POV)
    var annotations: [String]       // Annotation per move (index 0 = first move, not root)
    var whiteAccuracy: Double
    var blackAccuracy: Double
}

// MARK: - Cached Chess.com Stats

@Model
final class ChessComCachedStats {
    @Attribute(.unique) var username: String
    var statsData: [String: ChessComStats]  // keys: "all", "bullet", "blitz", "rapid", "daily", etc.
    var computedAt: Date
    var gameCount: Int

    init(username: String, statsData: [String: ChessComStats], computedAt: Date = Date(), gameCount: Int) {
        self.username = username
        self.statsData = statsData
        self.computedAt = computedAt
        self.gameCount = gameCount
    }
}

// MARK: - Game Record

@Model
final class GameRecord {
    @Attribute(.unique) var id: UUID
    var event: String
    var site: String
    var date: String
    var round: String
    var white: String
    var black: String
    var result: String
    var eco: String?
    var opening: String?
    var pgn: String
    var tags: [String]
    var dateAdded: Date
    var folder: GameFolder?
    var analysisData: GameAnalysisData?
    var timeClass: String?  // bullet, blitz, rapid, daily (for Chess.com games)
    var sourceUsername: String?  // Chess.com username this game was imported from
    var sourceUrl: String?  // Chess.com game URL, used for dedup on re-sync
    var whiteElo: Int?
    var blackElo: Int?

    var folderId: UUID? { folder?.id }

    /// Derived source platform from sourceUrl
    var sourcePlatform: String? {
        guard let url = sourceUrl else { return nil }
        if url.contains("lichess.org") { return "lichess" }
        if url.contains("chess.com") { return "chesscom" }
        return nil
    }

    init(id: UUID = UUID(),
         event: String = "?",
         site: String = "?",
         date: String = "????.??.??",
         round: String = "?",
         white: String = "?",
         black: String = "?",
         result: String = "*",
         eco: String? = nil,
         opening: String? = nil,
         pgn: String = "",
         tags: [String] = [],
         dateAdded: Date = Date(),
         folder: GameFolder? = nil,
         analysisData: GameAnalysisData? = nil,
         timeClass: String? = nil,
         sourceUsername: String? = nil,
         sourceUrl: String? = nil,
         whiteElo: Int? = nil,
         blackElo: Int? = nil) {
        self.id = id
        self.event = event
        self.site = site
        self.date = date
        self.round = round
        self.white = white
        self.black = black
        self.result = result
        self.eco = eco
        self.opening = opening
        self.pgn = pgn
        self.tags = tags
        self.dateAdded = dateAdded
        self.folder = folder
        self.analysisData = analysisData
        self.timeClass = timeClass
        self.sourceUsername = sourceUsername
        self.sourceUrl = sourceUrl
        self.whiteElo = whiteElo
        self.blackElo = blackElo
    }

    static func from(pgnGame: PGNGame, pgn: String) -> GameRecord {
        // Use opening name from PGN header if present, otherwise resolve from ECO code — unless the
        // user turned off "Classify openings on import", in which case only what the PGN states is kept.
        var openingName = pgnGame.opening
        if (openingName == nil || openingName?.isEmpty == true), let eco = pgnGame.eco, !eco.isEmpty,
           AppSettings.shared.classifyOpeningsOnImport {
            openingName = OpeningBook.shared.findByECO(eco) ?? ECODatabase.openingName(for: eco)
        }

        return GameRecord(
            event: sanitize(pgnGame.event),
            site: sanitize(pgnGame.site),
            date: sanitizeDate(pgnGame.date),
            round: sanitize(pgnGame.round),
            white: sanitizePlayer(pgnGame.white),
            black: sanitizePlayer(pgnGame.black),
            result: pgnGame.result,
            eco: pgnGame.eco,
            opening: openingName,
            pgn: pgn,
            whiteElo: extractEloFromPGN(pgn, color: "White"),
            blackElo: extractEloFromPGN(pgn, color: "Black")
        )
    }

    /// Compiled once — `from(pgnGame:pgn:)` calls this twice per game, so an inline
    /// NSRegularExpression meant two compilations per imported game.
    private static let whiteEloRegex = try? NSRegularExpression(pattern: "\\[WhiteElo \"(\\d+)\"\\]")
    private static let blackEloRegex = try? NSRegularExpression(pattern: "\\[BlackElo \"(\\d+)\"\\]")

    /// Extract Elo rating from PGN header text
    static func extractEloFromPGN(_ pgn: String, color: String) -> Int? {
        guard let regex = color == "White" ? whiteEloRegex : blackEloRegex,
              let match = regex.firstMatch(in: pgn, range: NSRange(pgn.startIndex..., in: pgn)),
              let range = Range(match.range(at: 1), in: pgn) else { return nil }
        return Int(pgn[range])
    }

    /// Returns empty string if the value is a PGN unknown placeholder
    private static func sanitize(_ value: String) -> String {
        if value == "?" || value == "????.??.??" {
            return ""
        }
        return value
    }

    /// Returns "Unknown" only if the player name is "?"
    private static func sanitizePlayer(_ value: String) -> String {
        if value == "?" {
            return "Unknown"
        }
        return value
    }

    /// Strips ?? parts from partial dates like "2024.??.??"
    private static func sanitizeDate(_ value: String) -> String {
        if value == "????.??.??" || value == "?" {
            return ""
        }
        // Remove .?? parts from partial dates
        let cleaned = value.replacingOccurrences(of: ".??", with: "")
        return cleaned
    }
}

// MARK: - Cached Name (for fast picker lookups)

@Model
final class CachedName {
    var key: String      // "player::Magnus Carlsen"
    var type: String     // "player", "event", "opening"
    var name: String     // The display name

    init(type: String, name: String) {
        self.type = type
        self.name = name
        self.key = "\(type)::\(name)"
    }
}

// MARK: - Game Filter

struct GameFilter: Equatable {
    var white: String?
    var black: String?
    var result: String?
    var event: String?
    var opening: String?
    var dateFrom: String?
    var dateTo: String?
    var whiteEloMin: Int?
    var whiteEloMax: Int?
    var blackEloMin: Int?
    var blackEloMax: Int?
}

// MARK: - Game Database
class GameDatabase: ObservableObject {
    private var modelContext: ModelContext
    private let container: ModelContainer

    /// Total count of library games (sourceUsername == nil). Views use paginated fetches for actual data.
    @Published private(set) var libraryGameCount: Int = 0
    @Published private(set) var folders: [GameFolder] = []

    init(modelContext: ModelContext, container: ModelContainer) {
        self.modelContext = modelContext
        self.container = container
        refreshCache()
    }

    /// Kick off background backfills (Elo fields + CachedName table).
    /// Call from `.task {}` on the root view so it runs after first render.
    func startBackgroundBackfills() {
        Task.detached(priority: .utility) { [container] in
            let bgContext = ModelContext(container)
            GameDatabase.backgroundBackfillEloFields(context: bgContext)
            GameDatabase.backgroundBackfillCachedNames(context: bgContext)
        }
    }

    private func refreshCache() {
        let countDescriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == nil }
        )
        libraryGameCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        let foldersDescriptor = FetchDescriptor<GameFolder>(sortBy: [SortDescriptor(\.name)])
        folders = (try? modelContext.fetch(foldersDescriptor)) ?? []
    }

    private func save() {
        modelContext.saveOrReport("your library")
        objectWillChange.send()
        refreshCache()
    }

    /// Persist without refreshing the cache (for updates that don't affect library game lists,
    /// e.g. analysis data updates on a single game).
    private func saveLightly() {
        modelContext.saveOrReport("your library")
    }

    // MARK: - Library Game Queries (paginated)

    /// Count of library games (sourceUsername == nil), optionally filtered to a folder.
    func libraryGamesCount(folderId: UUID? = nil) -> Int {
        let descriptor: FetchDescriptor<GameRecord>
        if let fid = folderId {
            descriptor = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.folder?.id == fid }
            )
        } else {
            descriptor = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername == nil }
            )
        }
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Count of games in a specific folder (O(1) via SQLite COUNT).
    func gamesInFolderCount(_ folderId: UUID) -> Int {
        let descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.folder?.id == folderId }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Paginated fetch of library games with DB-level sort and predicate.
    /// Filters that can be expressed as predicates (result, folder) are pushed to DB;
    /// elo range is applied as a fast post-filter on the fetched batch (to avoid type-checker
    /// timeouts from complex `#Predicate` expressions with `??`).
    /// Remaining filters (white/black contains, event, opening, date range) are applied client-side.
    /// One page of library games plus the pagination bookkeeping the caller needs to page correctly
    /// when an elo post-filter is active (rawConsumed can exceed games.count).
    struct LibraryPage {
        let games: [GameRecord]
        let rawConsumed: Int   // rows the DB actually returned — advance the offset by THIS
        let reachedEnd: Bool   // DB returned fewer rows than requested → nothing more to page
    }

    /// Every game in the store — offline library imports AND synced online games. `fetchLibraryGames`
    /// deliberately excludes synced games (`sourceUsername == nil`); repertoire game-linking wants the
    /// opposite, since your synced games are precisely "real play".
    func allGames() -> [GameRecord] {
        (try? modelContext.fetch(FetchDescriptor<GameRecord>())) ?? []
    }

    func fetchLibraryGames(
        folderId: UUID?,
        sortDescriptor: SortDescriptor<GameRecord>,
        limit: Int,
        offset: Int,
        filter: GameFilter? = nil
    ) -> LibraryPage {
        var descriptor: FetchDescriptor<GameRecord>

        // Build predicate variants for common combos
        let resultFilter = filter?.result
        if let fid = folderId {
            if let r = resultFilter {
                descriptor = FetchDescriptor<GameRecord>(
                    predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.folder?.id == fid && $0.result == r },
                    sortBy: [sortDescriptor]
                )
            } else {
                descriptor = FetchDescriptor<GameRecord>(
                    predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.folder?.id == fid },
                    sortBy: [sortDescriptor]
                )
            }
        } else {
            if let r = resultFilter {
                descriptor = FetchDescriptor<GameRecord>(
                    predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.result == r },
                    sortBy: [sortDescriptor]
                )
            } else {
                descriptor = FetchDescriptor<GameRecord>(
                    predicate: #Predicate<GameRecord> { $0.sourceUsername == nil },
                    sortBy: [sortDescriptor]
                )
            }
        }

        // Over-fetch when an elo filter is active so the post-filter has enough rows to work with.
        let hasEloFilter = filter?.whiteEloMin != nil || filter?.whiteEloMax != nil ||
                           filter?.blackEloMin != nil || filter?.blackEloMax != nil
        let internalLimit = hasEloFilter ? limit * 3 : limit
        descriptor.fetchLimit = internalLimit
        descriptor.fetchOffset = offset

        // rawConsumed = rows the DB actually returned. The caller advances its offset by THIS (not by
        // the post-filtered count) and decides "reached end" from it — otherwise the elo post-filter
        // desyncs pagination, re-reading already-shown rows (duplicates) and stopping early.
        let raw = (try? modelContext.fetch(descriptor)) ?? []
        let reachedEnd = raw.count < internalLimit

        var results = raw

        // Apply elo range as fast post-filter (avoids complex #Predicate with ?? operator)
        if hasEloFilter {
            results = results.filter { game in
                if let wMin = filter?.whiteEloMin {
                    let elo = game.whiteElo ?? -1
                    if elo < 0 || elo < wMin { return false }
                }
                if let wMax = filter?.whiteEloMax {
                    let elo = game.whiteElo ?? -1
                    if elo < 0 || elo > wMax { return false }
                }
                if let bMin = filter?.blackEloMin {
                    let elo = game.blackElo ?? -1
                    if elo < 0 || elo < bMin { return false }
                }
                if let bMax = filter?.blackEloMax {
                    let elo = game.blackElo ?? -1
                    if elo < 0 || elo > bMax { return false }
                }
                return true
            }
        }

        return LibraryPage(games: results, rawConsumed: raw.count, reachedEnd: reachedEnd)
    }

    // MARK: - Cached Name Queries

    /// Query cached names for picker popovers. Filter pushed to SQLite via predicate.
    func cachedNames(type: String, query: String, limit: Int = 200) -> [String] {
        let t = type
        var descriptor: FetchDescriptor<CachedName>

        if query.isEmpty {
            descriptor = FetchDescriptor<CachedName>(
                predicate: #Predicate<CachedName> { $0.type == t },
                sortBy: [SortDescriptor(\.name)]
            )
        } else {
            let q = query
            descriptor = FetchDescriptor<CachedName>(
                predicate: #Predicate<CachedName> { $0.type == t && $0.name.localizedStandardContains(q) },
                sortBy: [SortDescriptor(\.name)]
            )
        }

        descriptor.fetchLimit = limit
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.name)
    }

    /// Insert unique names extracted from a batch of games. Deduplicates in-memory before inserting.
    func cacheNamesFromGames(_ games: [GameRecord]) {
        // Collect unique keys from this batch
        var newKeys = Set<String>()
        var pending: [(type: String, name: String)] = []

        for game in games {
            let w = game.white.trimmingCharacters(in: .whitespaces)
            let b = game.black.trimmingCharacters(in: .whitespaces)
            if !w.isEmpty && w != "?" && w != "Unknown" {
                let key = "player::\(w)"
                if newKeys.insert(key).inserted { pending.append(("player", w)) }
            }
            if !b.isEmpty && b != "?" && b != "Unknown" {
                let key = "player::\(b)"
                if newKeys.insert(key).inserted { pending.append(("player", b)) }
            }

            let e = game.event.trimmingCharacters(in: .whitespaces)
            if !e.isEmpty && e != "?" {
                let key = "event::\(e)"
                if newKeys.insert(key).inserted { pending.append(("event", e)) }
            }

            // Cache opening name; resolve ECO code to name via opening book if needed
            var resolvedOpening = game.opening?.trimmingCharacters(in: .whitespaces) ?? ""
            if resolvedOpening.isEmpty, let eco = game.eco?.trimmingCharacters(in: .whitespaces), !eco.isEmpty {
                resolvedOpening = OpeningBook.shared.findByECO(eco)
                    ?? ECODatabase.openingName(for: eco)
                    ?? eco
            }
            if !resolvedOpening.isEmpty {
                let key = "opening::\(resolvedOpening)"
                if newKeys.insert(key).inserted { pending.append(("opening", resolvedOpening)) }
            }
        }

        // Check only the candidate keys against the DB (O(batch_size) lookups, not O(table_size))
        for entry in pending {
            let key = "\(entry.type)::\(entry.name)"
            let k = key
            var checkDesc = FetchDescriptor<CachedName>(
                predicate: #Predicate<CachedName> { $0.key == k }
            )
            checkDesc.fetchLimit = 1
            let exists = ((try? modelContext.fetchCount(checkDesc)) ?? 0) > 0
            if !exists {
                modelContext.insert(CachedName(type: entry.type, name: entry.name))
            }
        }
        modelContext.saveOrReport("your library")
    }

    // MARK: - Chess.com Queries (on-demand, NOT cached in database)

    /// Fetch Chess.com games for a specific user with pagination.
    func fetchChessComGames(for username: String, limit: Int? = nil, offset: Int = 0) -> [GameRecord] {
        let lowered = username.lowercased()
        var descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == lowered },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        if let limit = limit {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch Chess.com games with optional time class filter at the DB level.
    /// Other filters (result, color, opening, search, date range) should be applied client-side.
    func fetchFilteredChessComGames(
        for username: String,
        timeClass: String? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) -> [GameRecord] {
        let lowered = username.lowercased()

        var descriptor: FetchDescriptor<GameRecord>

        if let tc = timeClass?.lowercased() {
            descriptor = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername == lowered && $0.timeClass == tc },
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername == lowered },
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
            )
        }

        if let limit = limit {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Get total count of Chess.com games for a user (cheap count query).
    func chessComGamesCount(for username: String) -> Int {
        let lowered = username.lowercased()
        let descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == lowered }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Get count of all online games (any sourceUsername).
    func onlineGamesCount() -> Int {
        let descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername != nil }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Fetch all online games with optional time class filter, supporting pagination.
    func fetchFilteredOnlineGames(
        timeClass: String? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) -> [GameRecord] {
        var descriptor: FetchDescriptor<GameRecord>

        if let tc = timeClass?.lowercased() {
            descriptor = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername != nil && $0.timeClass == tc },
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername != nil },
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
            )
        }

        if let limit = limit {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Check whether a specific sourceUrl already exists (fast indexed lookup).
    func sourceUrlExists(_ url: String) -> Bool {
        let u = url
        var descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUrl == u }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// All stored sourceUrls for a Chess.com account as a Set, for O(1) in-memory dedup during import.
    /// Replaces one `sourceUrlExists` fetch per game — sourceUrl is unindexed, so that was a full table
    /// scan per game (quadratic over an import). One fetch here instead of N.
    func existingChessComSourceUrls(for username: String) -> Set<String> {
        let lowered = username.lowercased()
        var descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == lowered }
        )
        descriptor.propertiesToFetch = [\.sourceUrl]
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return Set(rows.compactMap { $0.sourceUrl })
    }

    /// Iterate Chess.com games in batches, calling handler for each batch.
    func iterateChessComGames(for username: String, batchSize: Int = 2000, handler: ([GameRecord]) -> Void) {
        let lowered = username.lowercased()
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername == lowered },
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = (try? modelContext.fetch(descriptor)) ?? []
            if batch.isEmpty { break }
            handler(batch)
            offset += batch.count
            if batch.count < batchSize { break }
        }
    }

    /// Look up a GameFolder by UUID
    func folder(withId id: UUID?) -> GameFolder? {
        guard let id = id else { return nil }
        var descriptor = FetchDescriptor<GameFolder>(predicate: #Predicate { folder in
            folder.id == id
        })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Look up a single game by ID (targeted query, no full scan)
    func game(withId id: UUID) -> GameRecord? {
        var descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate<GameRecord> { game in
            game.id == id
        })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - CRUD Operations

    func addGame(_ game: GameRecord) {
        modelContext.insert(game)
        cacheNamesFromGames([game])
        save()
    }

    /// Add games and optionally skip refreshing the library cache
    /// (useful for Chess.com bulk imports which don't affect library games).
    func addGames(_ newGames: [GameRecord], isChessComImport: Bool = false) {
        for game in newGames {
            modelContext.insert(game)
        }
        if isChessComImport {
            saveLightly()
        } else {
            save()
        }
    }

    /// Insert games in batches, persisting periodically to avoid memory pressure.
    /// Calls `onBatchComplete` on the main thread with the count of games inserted so far.
    /// Must be called from the main thread (SwiftData ModelContext requirement).
    func addGamesBatched(
        _ games: [GameRecord],
        folder: GameFolder? = nil,
        batchSize: Int = 50,
        onBatchComplete: @escaping (Int) -> Void
    ) {
        for (index, game) in games.enumerated() {
            game.folder = folder
            modelContext.insert(game)
            if (index + 1) % batchSize == 0 {
                let batch = Array(games[(index + 1 - batchSize)...index])
                cacheNamesFromGames(batch)
                saveLightly()
                onBatchComplete(index + 1)
            }
        }
        let remainder = games.count % batchSize
        if remainder > 0 {
            let lastBatch = Array(games[(games.count - remainder)...])
            cacheNamesFromGames(lastBatch)
        }
        save()
        onBatchComplete(games.count)
    }

    func updateGame(_ game: GameRecord) {
        // @Model tracks mutations; just persist without full refresh
        saveLightly()
    }

    func deleteGame(_ game: GameRecord) {
        modelContext.delete(game)
        save()
    }

    func deleteAll() {
        try? modelContext.delete(model: GameRecord.self)
        try? modelContext.delete(model: GameFolder.self)
        save()
    }

    // MARK: - Import/Export

    func importPGN(from url: URL, intoFolder folderId: UUID? = nil) throws {
        _ = try importPGNWithResult(from: url, intoFolder: folderId)
    }

    func importPGNWithResult(from url: URL, intoFolder folderId: UUID? = nil) throws -> ImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let parser = PGNParser()
        let pgnGames = try parser.parse(file: url)
        let targetFolder = folder(withId: folderId)

        var newGames: [GameRecord] = []
        var errors: [String] = []

        for pgnGame in pgnGames {
            let pgn = pgnGame.toPGNString()
            let record = GameRecord.from(pgnGame: pgnGame, pgn: pgn)
            record.folder = targetFolder
            newGames.append(record)
        }

        addGames(newGames)
        cacheNamesFromGames(newGames)

        return ImportResult(gamesImported: newGames.count, errors: errors)
    }

    func exportPGN(games: [GameRecord], to url: URL) throws {
        var pgnContent = ""

        for game in games {
            pgnContent += game.pgn
            pgnContent += "\n\n"
        }

        try pgnContent.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Export games as a SQLite .db3 file.
    func exportAsSQLite(games: [GameRecord], to url: URL) throws {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw NSError(domain: "GameDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create database: \(msg)"])
        }
        defer { sqlite3_close(db) }

        // Create table
        let createSQL = """
            CREATE TABLE games (
                id TEXT PRIMARY KEY,
                event TEXT,
                site TEXT,
                date TEXT,
                round TEXT,
                white TEXT,
                black TEXT,
                result TEXT,
                eco TEXT,
                opening TEXT,
                pgn TEXT,
                white_elo INTEGER,
                black_elo INTEGER,
                time_class TEXT
            );
            """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "GameDatabase", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create table: \(msg)"])
        }

        // Prepare insert statement
        let insertSQL = """
            INSERT INTO games (id, event, site, date, round, white, black, result, eco, opening, pgn, white_elo, black_elo, time_class)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "GameDatabase", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement: \(msg)"])
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        for game in games {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            func bindText(_ index: Int32, _ value: String?) {
                if let v = value {
                    sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, index)
                }
            }
            func bindInt(_ index: Int32, _ value: Int?) {
                if let v = value, v >= 0 {
                    sqlite3_bind_int(stmt, index, Int32(v))
                } else {
                    sqlite3_bind_null(stmt, index)
                }
            }

            bindText(1, game.id.uuidString)
            bindText(2, game.event)
            bindText(3, game.site)
            bindText(4, game.date)
            bindText(5, game.round)
            bindText(6, game.white)
            bindText(7, game.black)
            bindText(8, game.result)
            bindText(9, game.eco)
            bindText(10, game.opening)
            bindText(11, game.pgn)
            bindInt(12, game.whiteElo)
            bindInt(13, game.blackElo)
            bindText(14, game.timeClass)

            sqlite3_step(stmt)
        }

        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    /// Export all library games in batches (avoids loading all into memory at once).
    func exportAllLibraryGames(to url: URL) throws {
        var pgnContent = ""
        let batchSize = 500
        var offset = 0
        let sort = SortDescriptor<GameRecord>(\.dateAdded, order: .reverse)

        while true {
            let page = fetchLibraryGames(folderId: nil, sortDescriptor: sort, limit: batchSize, offset: offset)
            for game in page.games {
                pgnContent += game.pgn
                pgnContent += "\n\n"
            }
            offset += page.rawConsumed
            if page.reachedEnd { break }
        }

        try pgnContent.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Folder Operations

    @discardableResult
    func createFolder(name: String) -> GameFolder {
        let folder = GameFolder(name: name)
        modelContext.insert(folder)
        save()
        return folder
    }

    func renameFolder(_ folder: GameFolder, to newName: String) {
        folder.name = newName
        save()
    }

    func deleteFolder(_ folder: GameFolder, deleteGames: Bool) {
        if deleteGames {
            let folderId = folder.id
            try? modelContext.delete(model: GameRecord.self, where: #Predicate<GameRecord> {
                $0.folder?.id == folderId
            })
        }
        // When deleteGames is false, @Relationship(deleteRule: .nullify) handles setting folder to nil
        modelContext.delete(folder)
        save()
    }

    func gamesInFolder(_ folderId: UUID, limit: Int? = nil, offset: Int = 0) -> [GameRecord] {
        var descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.folder?.id == folderId },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        if let limit = limit {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func unfiledGames(limit: Int? = nil, offset: Int = 0) -> [GameRecord] {
        var descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.folder == nil },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        if let limit = limit {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Move games to a different folder. Fetches all selected games in ONE query (predicate IN the id
    /// set) instead of a fetch per id — moving a large multi-selection was previously N round-trips.
    func moveGames(_ gameIds: Set<UUID>, toFolder folderId: UUID?) {
        moveGamesByIds(gameIds, toFolder: folderId)
    }

    /// Library games that were imported without a database (unfiled).
    func unfiledLibraryGameCount() -> Int {
        let d = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.sourceUsername == nil && $0.folder == nil })
        return (try? modelContext.fetchCount(d)) ?? 0
    }

    /// File every unfiled library game into a database (recovers imports that landed without one).
    func moveAllUnfiledLibraryGames(toFolder folderId: UUID) {
        let target = folder(withId: folderId)
        let d = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.sourceUsername == nil && $0.folder == nil })
        let games = (try? modelContext.fetch(d)) ?? []
        for g in games { g.folder = target }
        save()
    }

    /// Move any games (including Chess.com games) to a folder by their IDs, in a single batched fetch.
    func moveGamesByIds(_ gameIds: Set<UUID>, toFolder folderId: UUID?) {
        guard !gameIds.isEmpty else { return }
        let targetFolder = folder(withId: folderId)
        let ids = Array(gameIds)
        let descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { ids.contains($0.id) })
        let games = (try? modelContext.fetch(descriptor)) ?? []
        for game in games {
            game.folder = targetFolder
        }
        save()
    }

    // MARK: - Statistics (library games only)

    func getStatistics() -> DatabaseStatistics {
        let totalGames = libraryGameCount

        // Use fetchCount for result tallies
        let whiteWinDesc = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.result == "1-0" }
        )
        let blackWinDesc = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.result == "0-1" }
        )
        let drawDesc = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.sourceUsername == nil && $0.result == "1/2-1/2" }
        )
        let whiteWins = (try? modelContext.fetchCount(whiteWinDesc)) ?? 0
        let blackWins = (try? modelContext.fetchCount(blackWinDesc)) ?? 0
        let draws = (try? modelContext.fetchCount(drawDesc)) ?? 0

        // Batched iteration for top players/openings — fetch 5K at a time
        var playerCounts: [String: Int] = [:]
        var openingCounts: [String: Int] = [:]
        let statBatchSize = 5000
        var statOffset = 0

        while true {
            var statDesc = FetchDescriptor<GameRecord>(
                predicate: #Predicate<GameRecord> { $0.sourceUsername == nil }
            )
            statDesc.fetchLimit = statBatchSize
            statDesc.fetchOffset = statOffset
            let batch = (try? modelContext.fetch(statDesc)) ?? []
            if batch.isEmpty { break }

            for game in batch {
                playerCounts[game.white, default: 0] += 1
                playerCounts[game.black, default: 0] += 1
                if let opening = game.opening {
                    openingCounts[opening, default: 0] += 1
                }
            }

            statOffset += batch.count
            if batch.count < statBatchSize { break }
        }

        let topPlayers = playerCounts.sorted { $0.value > $1.value }.prefix(10)
        let topOpenings = openingCounts.sorted { $0.value > $1.value }.prefix(10)

        return DatabaseStatistics(
            totalGames: totalGames,
            whiteWins: whiteWins,
            blackWins: blackWins,
            draws: draws,
            topPlayers: Array(topPlayers),
            topOpenings: Array(topOpenings)
        )
    }

    // MARK: - Background Backfills (run on utility thread with dedicated ModelContext)

    /// Backfill whiteElo/blackElo on a background context.
    private static func backgroundBackfillEloFields(context: ModelContext) {
        let batchSize = 500
        var descriptor = FetchDescriptor<GameRecord>(
            predicate: #Predicate<GameRecord> { $0.whiteElo == nil }
        )
        descriptor.fetchLimit = batchSize

        while true {
            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty { break }

            for game in batch {
                game.whiteElo = GameRecord.extractEloFromPGN(game.pgn, color: "White") ?? -1
                game.blackElo = GameRecord.extractEloFromPGN(game.pgn, color: "Black") ?? -1
            }
            context.saveOrReport("your library")

            if batch.count < batchSize { break }
        }
    }

    /// Backfill CachedName table on a background context. Runs once if the table is empty.
    private static func backgroundBackfillCachedNames(context: ModelContext) {
        let countDescriptor = FetchDescriptor<CachedName>()
        let count = (try? context.fetchCount(countDescriptor)) ?? 0
        guard count == 0 else { return }

        let gameCountDesc = FetchDescriptor<GameRecord>()
        let gameCount = (try? context.fetchCount(gameCountDesc)) ?? 0
        guard gameCount > 0 else { return }

        // Maintain in-memory set of seen keys across batches to avoid re-scanning CachedName table per batch
        var seenKeys = Set<String>()
        let batchSize = 1000
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<GameRecord>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty { break }

            for game in batch {
                let entries: [(type: String, name: String)] = {
                    var result: [(String, String)] = []
                    let w = game.white.trimmingCharacters(in: .whitespaces)
                    if !w.isEmpty && w != "?" && w != "Unknown" { result.append(("player", w)) }
                    let b = game.black.trimmingCharacters(in: .whitespaces)
                    if !b.isEmpty && b != "?" && b != "Unknown" { result.append(("player", b)) }
                    let e = game.event.trimmingCharacters(in: .whitespaces)
                    if !e.isEmpty && e != "?" { result.append(("event", e)) }
                    var op = game.opening?.trimmingCharacters(in: .whitespaces) ?? ""
                    if op.isEmpty, let eco = game.eco?.trimmingCharacters(in: .whitespaces), !eco.isEmpty {
                        op = OpeningBook.shared.findByECO(eco) ?? ECODatabase.openingName(for: eco) ?? eco
                    }
                    if !op.isEmpty { result.append(("opening", op)) }
                    return result
                }()
                for entry in entries {
                    let key = "\(entry.type)::\(entry.name)"
                    if seenKeys.insert(key).inserted {
                        context.insert(CachedName(type: entry.type, name: entry.name))
                    }
                }
            }
            context.saveOrReport("your library")
            offset += batch.count
            if batch.count < batchSize { break }
        }
    }

    // MARK: - Cached Chess.com Stats

    func saveCachedStats(_ cached: ChessComCachedStats) {
        // Delete any existing entry for this username
        let username = cached.username
        let descriptor = FetchDescriptor<ChessComCachedStats>(
            predicate: #Predicate<ChessComCachedStats> { $0.username == username }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        modelContext.insert(cached)
        saveLightly()
    }

    func fetchCachedStats(for username: String, timeClass: String) -> ChessComStats? {
        let lowered = username.lowercased()
        var descriptor = FetchDescriptor<ChessComCachedStats>(
            predicate: #Predicate<ChessComCachedStats> { $0.username == lowered }
        )
        descriptor.fetchLimit = 1
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }
        return cached.statsData[timeClass]
    }

    func fetchAllCachedStats(for username: String) -> ChessComCachedStats? {
        let lowered = username.lowercased()
        var descriptor = FetchDescriptor<ChessComCachedStats>(
            predicate: #Predicate<ChessComCachedStats> { $0.username == lowered }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func deleteCachedStats(for username: String) {
        let lowered = username.lowercased()
        let descriptor = FetchDescriptor<ChessComCachedStats>(
            predicate: #Predicate<ChessComCachedStats> { $0.username == lowered }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            saveLightly()
        }
    }

    func cachedStatsTimeClasses(for username: String) -> [String] {
        let lowered = username.lowercased()
        var descriptor = FetchDescriptor<ChessComCachedStats>(
            predicate: #Predicate<ChessComCachedStats> { $0.username == lowered }
        )
        descriptor.fetchLimit = 1
        guard let cached = try? modelContext.fetch(descriptor).first else { return [] }
        let known = ["bullet", "blitz", "rapid", "daily"]
        let keys = Set(cached.statsData.keys).subtracting(["all"])
        let ordered = known.filter { keys.contains($0) }
        let extra = keys.subtracting(known).sorted()
        return ordered + extra
    }

    // MARK: - Preview Helper

    @MainActor static func preview() -> GameDatabase {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: GameRecord.self, GameFolder.self, ChessComCachedStats.self, CachedName.self, configurations: config)
        return GameDatabase(modelContext: container.mainContext, container: container)
    }
}

struct DatabaseStatistics {
    let totalGames: Int
    let whiteWins: Int
    let blackWins: Int
    let draws: Int
    let topPlayers: [(String, Int)]
    let topOpenings: [(String, Int)]
}
