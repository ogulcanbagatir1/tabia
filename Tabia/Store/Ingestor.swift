import Foundation

/// Ingests PGN games into the `GameStore`: parse → replay each move on a real
/// `ChessBoard` → Zobrist-hash every position → write header + position rows.
/// The replay is what makes the position index *real* and transposition-aware.
final class Ingestor {

    let store: GameStore

    /// Index positions only up to this ply (opening + early middlegame). Bounds DB
    /// size where position/transposition search actually matters. Tune later.
    var maxIndexPly: Int = 40

    /// Reused flat replay board (fast; reset per game). Avoids the @Published ChessBoard
    /// copy-on-write thrash that dominated ingest.
    private let replayBoard = IngestBoard()

    init(store: GameStore) { self.store = store }

    // MARK: - Entry points

    /// Parse and ingest a PGN string (may contain many games). Returns games ingested.
    @discardableResult
    func ingest(pgnText: String, onProgress: ((Int) -> Void)? = nil) -> Int {
        let games = PGNParser().parse(string: pgnText)
        return ingest(games: games, onProgress: onProgress)
    }

    /// Parse and ingest a PGN file. Returns games ingested.
    @discardableResult
    func ingest(fileURL: URL, onProgress: ((Int) -> Void)? = nil) throws -> Int {
        let games = try PGNParser().parse(file: fileURL)
        return ingest(games: games, onProgress: onProgress)
    }

    /// Bulk-ingest already-parsed games in one high-throughput transaction.
    /// `onProgress` is called with the running count every `flushEvery` games and once at the end.
    @discardableResult
    func ingest(games: [PGNGame], flushEvery: Int = 20_000, onProgress: ((Int) -> Void)? = nil) -> Int {
        guard !games.isEmpty else { return 0 }
        store.beginBulkLoad()
        var count = 0
        for game in games {
            if ingestGame(game) {                 // dupes are skipped, not counted
                count += 1
                if count % flushEvery == 0 { store.flushBatch(); onProgress?(count) }
            }
        }
        store.finishBulkLoad()
        onProgress?(count)
        return count
    }

    /// Streaming ingest with FULL position index built during load (games + positions, deduped).
    @discardableResult
    func ingest(streamingFileURL url: URL, flushEvery: Int = 20_000, onProgress: ((Int) -> Void)? = nil) -> Int {
        // Full replay writes position rows → the position indexes are (re)built.
        streamIngest(url: url, dedup: true, flushEvery: flushEvery, writesPositions: true,
                     onProgress: onProgress, process: ingestGame)
    }

    /// PHASE 1 — memory-bounded streaming load of GAMES ONLY (headers + SAN moves stored, NO position
    /// replay). Fast; the opening explorer is built separately via `buildPositionIndex`.
    /// `dedup: false` (clean bulk load) suits the pre-deduped hosted database; `dedup: true`
    /// (INSERT OR IGNORE on game_hash) suits user imports that may overlap existing games.
    @discardableResult
    func ingestGames(streamingFileURL url: URL, dedup: Bool = true,
                     flushEvery: Int = 50_000, shouldCancel: (() -> Bool)? = nil,
                     onProgress: ((Int) -> Void)? = nil) -> Int {
        // Header-only load inserts ZERO position rows → don't drop/rebuild the position indexes.
        streamIngest(url: url, dedup: dedup, flushEvery: flushEvery, writesPositions: false,
                     shouldCancel: shouldCancel, onProgress: onProgress, process: storeGameHeader)
    }

    /// Shared memory-bounded PGN streamer (1 MB chunks, one game at a time). `process` returns true
    /// when the game was inserted (for the running count). `shouldCancel` is polled per chunk so a
    /// user cancel stops promptly; the partial load is still committed + indexed for consistency.
    @discardableResult
    private func streamIngest(url: URL, dedup: Bool, flushEvery: Int, writesPositions: Bool = true,
                              shouldCancel: (() -> Bool)? = nil,
                              onProgress: ((Int) -> Void)?, process: (PGNGame) -> Bool) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }

        store.beginBulkLoad(dedup: dedup, writesPositions: writesPositions)
        var count = 0
        var current = ""
        var sawMoves = false

        let decode: (Data) -> String? = {
            String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1)
        }

        func flushGame() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            current.removeAll(keepingCapacity: true)
            sawMoves = false
            guard !text.isEmpty else { return }
            for g in PGNParser().parse(string: text) {
                if process(g) {
                    count += 1
                    if count % flushEvery == 0 { store.flushBatch(); onProgress?(count) }
                }
            }
        }

        func processLines(_ s: String) {
            for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(raw)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && sawMoves { flushGame() }
                if !trimmed.isEmpty && !trimmed.hasPrefix("[") { sawMoves = true }
                current += line
                current += "\n"
            }
        }

        var leftover = Data()
        while true {
            if shouldCancel?() == true { break }
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil
            guard let chunk, !chunk.isEmpty else {
                if !leftover.isEmpty, let s = decode(leftover) { processLines(s) }
                break
            }
            var buf = leftover
            buf.append(chunk)
            if let lastNL = buf.lastIndex(of: 0x0A) {
                let complete = Data(buf[..<buf.index(after: lastNL)])
                leftover = Data(buf[buf.index(after: lastNL)...])
                if let s = decode(complete) { processLines(s) }
            } else {
                leftover = buf
            }
        }
        flushGame()
        store.finishBulkLoad(dedup: dedup, writesPositions: writesPositions)
        onProgress?(count)
        return count
    }

    // MARK: - Per-game replay

    /// Returns true if the game was inserted, false if it was a duplicate (skipped).
    @discardableResult
    private func ingestGame(_ g: PGNGame) -> Bool {
        replayBoard.reset()
        var positions: [(zobrist: Int64, ply: Int32, nextMove: Int32)] = []

        for (ply, san) in g.moves.enumerated() {
            if ply >= maxIndexPly { break }
            guard let r = replayBoard.resolve(san) else { break } // stop at first unparseable move
            // Record the position BEFORE the move, tagged with the move played from it.
            let code = Int32(r.from | (r.to << 6) | (r.promo << 12))
            positions.append((replayBoard.zobristKey(), Int32(ply), code))
            replayBoard.apply(r)
        }

        let gid = store.addGame(
            white: g.white,
            black: g.black,
            event: g.event,
            result: StoredResult(pgn: g.result),
            date: Ingestor.encodeDate(g.date),
            whiteElo: Ingestor.parseElo(g.headers["WhiteElo"]),
            blackElo: Ingestor.parseElo(g.headers["BlackElo"]),
            eco: Ingestor.encodeECO(g.eco),
            round: g.round == "?" ? nil : g.round,
            gameHash: GameDedup.gameHash(g.moves),   // exact-move dedup across sources
            positions: positions
        )
        return gid > 0
    }

    /// PHASE 1 — store a game's header + SAN moves, WITHOUT replaying positions. Fast.
    @discardableResult
    private func storeGameHeader(_ g: PGNGame) -> Bool {
        let movesData = g.moves.joined(separator: " ").data(using: .utf8)
        let gid = store.addGame(
            white: g.white,
            black: g.black,
            event: g.event,
            result: StoredResult(pgn: g.result),
            date: Ingestor.encodeDate(g.date),
            whiteElo: Ingestor.parseElo(g.headers["WhiteElo"]),
            blackElo: Ingestor.parseElo(g.headers["BlackElo"]),
            eco: Ingestor.encodeECO(g.eco),
            round: g.round == "?" ? nil : g.round,
            moves: movesData,
            gameHash: GameDedup.gameHash(g.moves),
            plyCount: Int32(g.moves.count),
            positions: []
        )
        return gid > 0
    }

    // MARK: - Phase 2: build the position index from stored games

    /// Replay the stored SAN moves of the not-yet-indexed games matching `whereSQL` (nil = all),
    /// up to `maxPly` plies, and write their positions into the opening-explorer index.
    /// `onProgress` reports the running count of games indexed. Returns games indexed.
    @discardableResult
    func buildPositionIndex(whereSQL: String?, maxPly: Int, flushEvery: Int = 20_000,
                            onProgress: ((Int) -> Void)? = nil) -> Int {
        store.beginPositionIndexing()
        var count = 0
        var afterId: Int64 = 0
        let pageSize = 5000
        while true {
            let batch = store.unindexedGames(whereSQL: whereSQL, afterId: afterId, limit: pageSize)
            if batch.isEmpty { break }
            for game in batch {
                afterId = game.id
                replayBoard.reset()
                var positions: [(zobrist: Int64, ply: Int32, nextMove: Int32)] = []
                for (ply, sanSub) in game.moves.split(separator: " ").enumerated() {
                    if ply >= maxPly { break }
                    guard let r = replayBoard.resolve(String(sanSub)) else { break }
                    let code = Int32(r.from | (r.to << 6) | (r.promo << 12))
                    positions.append((replayBoard.zobristKey(), Int32(ply), code))
                    replayBoard.apply(r)
                }
                store.addGamePositions(gameId: game.id, result: game.result, positions: positions)
                count += 1
                if count % flushEvery == 0 { store.flushIndexBatch(); onProgress?(count) }
            }
        }
        store.finishPositionIndexing()
        onProgress?(count)
        return count
    }

    // MARK: - Encoders

    /// Move → 16-bit code: from(6) | to(6) | promo(3). Decodable for display.
    static func encodeMove(_ m: Move) -> Int32 {
        let from = m.from.rank * 8 + m.from.file
        let to = m.to.rank * 8 + m.to.file
        let promo: Int
        switch m.promotionType {
        case .queen?:  promo = 1
        case .rook?:   promo = 2
        case .bishop?: promo = 3
        case .knight?: promo = 4
        default:       promo = 0
        }
        return Int32(from | (to << 6) | (promo << 12))
    }

    /// Decode a move code back to from/to squares + promotion (for UCI/SAN display).
    static func decodeMove(_ code: Int32) -> (from: Position, to: Position, promo: PieceType?) {
        let c = Int(code)
        let from = c & 0x3F, to = (c >> 6) & 0x3F
        let promoMap: [Int: PieceType] = [1: .queen, 2: .rook, 3: .bishop, 4: .knight]
        return (Position(from % 8, from / 8), Position(to % 8, to / 8), promoMap[(c >> 12) & 0x7])
    }

    /// "2024.03.17" → 20240317. Partial dates ("2024.??.??") keep the known parts.
    static func encodeDate(_ s: String) -> Int32 {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        func num(_ i: Int) -> Int { i < parts.count ? (Int(parts[i]) ?? 0) : 0 }
        let y = num(0), m = num(1), d = num(2)
        guard y > 0 else { return 0 }
        return Int32(y * 10000 + m * 100 + d)
    }

    /// "B90" → 1*100+90 = 190 (A..E → 0..4). Returns -1 if not a valid ECO code.
    static func encodeECO(_ s: String?) -> Int32 {
        guard let s = s, s.count == 3, let letter = s.uppercased().first,
              let band = "ABCDE".firstIndex(of: letter),
              let n = Int(s.dropFirst()) else { return -1 }
        let b = "ABCDE".distance(from: "ABCDE".startIndex, to: band)
        return Int32(b * 100 + n)
    }

    static func parseElo(_ s: String?) -> Int32 {
        guard let s = s, let v = Int(s.trimmingCharacters(in: .whitespaces)) else { return -1 }
        return Int32(v)
    }
}
