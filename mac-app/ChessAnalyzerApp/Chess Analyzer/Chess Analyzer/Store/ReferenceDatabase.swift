import Foundation

/// One next-move entry of the reference opening explorer, with the move already
/// rendered to SAN for the current board.
struct ReferenceExplorerEntry: Identifiable {
    let san: String
    let uci: String
    let white: Int
    let draw: Int
    let black: Int
    var id: String { uci }
    var total: Int { white + draw + black }
    var scorePercent: Double { total > 0 ? (Double(white) + 0.5 * Double(draw)) / Double(total) * 100 : 0 }
}

struct ReferenceExplorerResult {
    var white = 0, draw = 0, black = 0
    var moves: [ReferenceExplorerEntry] = []
    var total: Int { white + draw + black }
}

/// App-level owner of the large reference database (`GameStore`). Provides a
/// background PGN import (via `Ingestor`) and a transposition-aware opening
/// explorer query over the whole database for the current board position.
///
/// SQLite on macOS is built in serialized mode, so the single connection is safe
/// to read from the main thread while a background import writes to it; bulk-insert
/// transactions don't hold the connection mutex across the whole transaction, so
/// main-thread explorer queries interleave without freezing the UI.
final class ReferenceDatabase: ObservableObject {

    @Published private(set) var gameCount: Int = 0
    /// User-facing name of the reference DB in the Library (chosen at download time). Persisted.
    @Published var displayName: String = UserDefaults.standard.string(forKey: "reference_db_name") ?? "Reference Database"
    @Published private(set) var isImporting: Bool = false
    @Published private(set) var importProgress: Int = 0
    @Published private(set) var lastImportCount: Int = 0

    // One-click download of the hosted reference database.
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var downloadProgress: Double = 0     // 0…1 (download phase)
    @Published private(set) var downloadPhase: String = ""
    @Published private(set) var downloadError: String?
    /// True from the moment Cancel is tapped until the download task fully unwinds — lets the UI show
    /// a "Cancelling…" state, since an in-flight phase may take a moment to notice the request.
    @Published private(set) var isCancellingDownload: Bool = false

    // Phase-2 opening-explorer index build (games load fast; positions built on demand).
    @Published private(set) var indexedGameCount: Int = 0        // games in the explorer
    @Published private(set) var isIndexing: Bool = false
    @Published private(set) var indexProgress: Int = 0           // games indexed this run

    /// Any ingest operation is in flight. All three ingest paths (download, import, index build) share
    /// ONE SQLite connection and its prepared-statement pointers + single active transaction, so they
    /// MUST NOT overlap — every entry point rejects while this is true. Read/written on the main thread.
    var isBusy: Bool { isImporting || isDownloading || isIndexing }

    /// The hosted manifest URL. Set this to your Cloudflare R2 (or any static host) manifest.json.
    /// Empty = the in-app "Download reference database" button is disabled.
    static let defaultManifestURLString = "https://tabiadb.ultravian.com/manifest.json"

    private let store: GameStore?

    /// The downloader backing the active hosted download, so `cancelDownload()` can stop the
    /// URLSession transfer immediately. Assigned/cleared on the main thread only.
    private var activeDownloader: ReferenceDownloader?

    /// Cancellation flag, polled by the streaming ingest (per chunk) and checked at every download
    /// phase boundary. Lock-guarded: written on main (Cancel tap), read on the download/ingest threads.
    private let cancelLock = NSLock()
    private var _cancelRequested = false
    private var cancelRequested: Bool {
        get { cancelLock.lock(); defer { cancelLock.unlock() }; return _cancelRequested }
        set { cancelLock.lock(); _cancelRequested = newValue; cancelLock.unlock() }
    }

    /// Sentinel thrown to unwind the download flow at a phase boundary after a cancel request.
    private struct DownloadCancelled: Error {}

    /// Programmatic access for views that only need to TRIGGER a download (not observe progress),
    /// so they don't have to hold an @EnvironmentObject and re-render on every progress tick.
    private(set) static weak var shared: ReferenceDatabase?

    init() {
        store = try? GameStore(path: ReferenceDatabase.databasePath())
        ReferenceDatabase.shared = self
        refreshCount()
    }

    static func databasePath() -> String { GameStore.defaultURL().path }

    var isAvailable: Bool { store != nil }

    private func refreshCount() {
        guard let store else { return }
        DispatchQueue.global(qos: .utility).async {
            let c = store.gameCount
            let ic = store.indexedGameCount
            DispatchQueue.main.async { self.gameCount = c; self.indexedGameCount = ic }
        }
    }

    // MARK: - Index queries (for the indexing screen)

    /// Games matching an optional SQL predicate (e.g. "white_elo>=2400 OR black_elo>=2400").
    func matchingGameCount(whereSQL: String?) -> Int { store?.gameCount(whereSQL: whereSQL) ?? 0 }

    /// Estimated positions a build would add for the not-yet-indexed games matching the filter+depth.
    func estimatedPositions(whereSQL: String?, maxPly: Int) -> Int {
        store?.estimatedPositions(whereSQL: whereSQL, maxPly: maxPly) ?? 0
    }

    /// Build the opening-explorer index for games matching `whereSQL` (nil = all), `maxPly` deep.
    func buildIndex(whereSQL: String?, maxPly: Int) {
        // Reject if ANY ingest is running (shared connection). Flag set synchronously (called on main)
        // to close the check-then-set race between two rapid triggers.
        guard let store, !isBusy else { return }
        isIndexing = true; indexProgress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Ingestor(store: store).buildPositionIndex(whereSQL: whereSQL, maxPly: maxPly, onProgress: { done in
                DispatchQueue.main.async { self.indexProgress = done }
            })
            let total = store.gameCount
            let indexed = store.indexedGameCount
            DispatchQueue.main.async {
                self.isIndexing = false
                self.gameCount = total
                self.indexedGameCount = indexed
            }
        }
    }

    // MARK: - Import

    /// Import a PGN file (may contain millions of games) into the reference DB on a
    /// background queue. PHASE 1 only — stores headers + SAN moves fast; the opening
    /// explorer index is built afterwards on demand via the indexing screen (same as the
    /// hosted download). Publishes progress flags + the new total on the main thread.
    func importPGN(url: URL, completion: ((Int) -> Void)? = nil) {
        guard let store, !isBusy else { completion?(0); return }
        isImporting = true; importProgress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let n = Ingestor(store: store).ingestGames(streamingFileURL: url, onProgress: { done in
                DispatchQueue.main.async { self.importProgress = done }
            })
            let total = store.gameCount
            let indexed = store.indexedGameCount
            DispatchQueue.main.async {
                self.isImporting = false
                self.lastImportCount = n
                self.gameCount = total
                self.indexedGameCount = indexed
                completion?(n)
            }
        }
    }

    // MARK: - One-click hosted download

    /// Fetch the manifest, download the compressed PGN (resumable, integrity-checked), decompress
    /// natively (gzip), and ingest it (deduping via game_hash). Publishes phase + progress.
    func downloadReferenceDatabase(manifestURL: URL) {
        guard let store, !isBusy else { return }
        cancelRequested = false
        // Set the flag synchronously (called on main) so a second trigger can't slip past isBusy.
        isDownloading = true; downloadProgress = 0
        downloadError = nil; downloadPhase = "Fetching manifest…"; isCancellingDownload = false
        Task {
            let downloader = ReferenceDownloader()
            await MainActor.run { self.activeDownloader = downloader }
            let tmpGz = FileManager.default.temporaryDirectory.appendingPathComponent("tabia-refdb.gz")
            var pgnURL: URL?
            do {
                try checkCancelled()
                let manifest = try await downloader.fetchManifest(manifestURL)
                guard manifest.base.format == "pgn.gz" else {
                    throw ReferenceDownloader.DownloadError.unsupportedFormat
                }
                try checkCancelled()
                let base = Self.resolveBase(manifest.base, relativeTo: manifestURL)

                // Reuse an already-downloaded file of the expected size (integrity is re-checked by
                // the sha256 step below), so a retry doesn't re-download the whole thing.
                let cachedSize = (try? FileManager.default.attributesOfItem(atPath: tmpGz.path)[.size]) as? Int64
                if cachedSize == manifest.base.bytes {
                    await MainActor.run { self.downloadPhase = "Using downloaded file…"; self.downloadProgress = 1 }
                } else {
                    await MainActor.run { self.downloadPhase = "Downloading…" }
                    var lastPublished = -1.0
                    try await downloader.download(base: base, to: tmpGz) { p in
                        // Throttle: publish at most on ~0.5% changes so the UI doesn't re-render many times/sec.
                        if p - lastPublished >= 0.005 || p >= 1.0 {
                            lastPublished = p
                            DispatchQueue.main.async { self.downloadProgress = p }
                        }
                    }
                }
                try checkCancelled()

                await MainActor.run { self.downloadPhase = "Verifying…" }
                let sha = try ReferenceDownloader.sha256(of: tmpGz)
                guard sha.lowercased() == manifest.base.sha256.lowercased() else {
                    throw ReferenceDownloader.DownloadError.checksumMismatch
                }
                try checkCancelled()

                await MainActor.run { self.downloadPhase = "Decompressing…" }
                let pgn = try ReferenceDownloader.decompressToPGN(tmpGz, format: manifest.base.format)
                pgnURL = pgn
                try? FileManager.default.removeItem(at: tmpGz)
                try checkCancelled()

                // The hosted DB is a COMPLETE snapshot, so a download REPLACES the reference content
                // wholesale. Wiping before the load makes it idempotent: neither a re-download nor a
                // cancel-then-redownload can duplicate games or corrupt the game_hash unique index
                // (a plain dedup:false INSERT has no uniqueness guard). Reset only happens once we're
                // committed to loading — a cancel during download/verify/decompress leaves any existing
                // DB untouched. Must run outside the ingest's bulk-load transaction (it is, here).
                store.resetAll()

                // PHASE 1: load games fast (no position index). The opening explorer is built later
                // on demand via the indexing screen, so the download is usable in minutes. The ingest
                // polls `cancelRequested` per chunk; a cancel here keeps the games already committed —
                // now a clean partial set (reset ran first), safely superseded by the next download.
                await MainActor.run { self.downloadPhase = "Loading games…"; self.isImporting = true; self.importProgress = 0 }
                let n = Ingestor(store: store).ingestGames(
                    streamingFileURL: pgn, dedup: false,
                    shouldCancel: { [weak self] in self?.cancelRequested ?? false },
                    onProgress: { done in
                        DispatchQueue.main.async { self.importProgress = done }
                    })
                try? FileManager.default.removeItem(at: pgn)
                let total = store.gameCount
                let indexed = store.indexedGameCount
                await MainActor.run {
                    self.isImporting = false; self.isDownloading = false; self.downloadPhase = ""
                    self.isCancellingDownload = false; self.activeDownloader = nil
                    self.lastImportCount = n; self.gameCount = total; self.indexedGameCount = indexed
                }
            } catch {
                // Clean up any partial temp artifacts regardless of cause.
                try? FileManager.default.removeItem(at: tmpGz)
                if let pgnURL { try? FileManager.default.removeItem(at: pgnURL) }
                let cancelled = self.isCancellation(error)
                let total = store.gameCount
                let indexed = store.indexedGameCount
                await MainActor.run {
                    self.isDownloading = false; self.isImporting = false; self.downloadPhase = ""
                    self.isCancellingDownload = false; self.activeDownloader = nil
                    self.gameCount = total; self.indexedGameCount = indexed
                    // A user cancel isn't an error — unwind silently. Real failures surface a message.
                    self.downloadError = cancelled ? nil : "\(error)"
                }
            }
        }
    }

    /// Cancel an in-flight hosted download/import. Stops the URLSession transfer immediately and
    /// signals the streaming ingest to stop at the next chunk. Games already committed are kept
    /// (partial loads are consistent); no error is surfaced — the flow just unwinds.
    func cancelDownload() {
        guard isDownloading else { return }
        cancelRequested = true
        isCancellingDownload = true
        activeDownloader?.cancel()
    }

    /// Throw the cancel sentinel if a cancel was requested — used at each download phase boundary.
    private func checkCancelled() throws { if cancelRequested { throw DownloadCancelled() } }

    /// Whether an error represents a user cancellation (our sentinel, or the URLSession `.cancelled`).
    private func isCancellation(_ error: Error) -> Bool {
        if error is DownloadCancelled { return true }
        if let urlErr = error as? URLError, urlErr.code == .cancelled { return true }
        return false
    }

    /// Resolve a possibly-relative base URL against the manifest's location.
    private static func resolveBase(_ base: ReferenceManifest.Base, relativeTo manifestURL: URL) -> ReferenceManifest.Base {
        if base.url.hasPrefix("http") { return base }
        let abs = manifestURL.deletingLastPathComponent().appendingPathComponent(base.file).absoluteString
        return ReferenceManifest.Base(file: base.file, url: abs, format: base.format,
                                      sha256: base.sha256, bytes: base.bytes, games: base.games)
    }

    // MARK: - Explorer

    /// Opening explorer for the current board, transposition-aware across the whole
    /// reference database. Move codes are rendered to SAN against `board`.
    func explorer(board: ChessBoard) -> ReferenceExplorerResult {
        guard let store, store.gameCount > 0 else { return ReferenceExplorerResult() }
        let key = Zobrist.sqliteKey(board)
        let rows = store.explorer(key)
        guard !rows.isEmpty else { return ReferenceExplorerResult() }

        var result = ReferenceExplorerResult()
        for r in rows {
            let uci = ReferenceDatabase.uci(from: r.nextMove)
            let san = board.toAlgebraicPV(uciMoves: [uci]).first ?? uci
            result.moves.append(ReferenceExplorerEntry(
                san: san, uci: uci, white: r.white, draw: r.draw, black: r.black))
            result.white += r.white; result.draw += r.draw; result.black += r.black
        }
        result.moves.sort { $0.total > $1.total }
        return result
    }

    /// How many games in the reference DB reach the current position.
    func positionGameCount(board: ChessBoard) -> Int {
        store?.positionGameCount(Zobrist.sqliteKey(board)) ?? 0
    }

    // MARK: - Read-only browsing (the reference DB as a browsable Library entry)

    /// Set (and persist) the display name for the reference DB shown in the Library.
    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = trimmed.isEmpty ? "Reference Database" : trimmed
        displayName = final
        UserDefaults.standard.set(final, forKey: "reference_db_name")
    }

    /// One page of games (headers only) for the read-only browser.
    func browse(limit: Int, offset: Int) -> [GameHeader] {
        store?.search(GameStoreFilter(), limit: limit, offset: offset) ?? []
    }

    /// Reconstruct a PGN string for one reference game so it opens through the standard PGN loader.
    func pgn(forGameId id: Int64) -> String? {
        guard let store, let g = store.loadGame(id: id) else { return nil }
        let h = g.header
        let resultStr = ReferenceDatabase.pgnResult(h.result)
        var s = ""
        s += "[White \"\(h.white)\"]\n"
        s += "[Black \"\(h.black)\"]\n"
        if let eco = ReferenceDatabase.decodeECO(h.eco) { s += "[ECO \"\(eco)\"]\n" }
        if h.whiteElo >= 0 { s += "[WhiteElo \"\(h.whiteElo)\"]\n" }
        if h.blackElo >= 0 { s += "[BlackElo \"\(h.blackElo)\"]\n" }
        s += "[Result \"\(resultStr)\"]\n\n"
        for (i, m) in g.moves.enumerated() {
            if i % 2 == 0 { s += "\(i / 2 + 1). " }
            s += m + " "
        }
        s += resultStr
        return s
    }

    static func pgnResult(_ r: StoredResult) -> String {
        switch r {
        case .whiteWin: return "1-0"
        case .blackWin: return "0-1"
        case .draw:     return "1/2-1/2"
        case .unknown:  return "*"
        }
    }

    /// Decode the packed ECO code (band*100 + number) back to e.g. "B12".
    static func decodeECO(_ code: Int32) -> String? {
        guard code >= 0, code < 500 else { return nil }
        let bands = Array("ABCDE")
        let b = Int(code) / 100, n = Int(code) % 100
        guard b < bands.count else { return nil }
        return "\(bands[b])\(String(format: "%02d", n))"
    }

    // MARK: - Helpers

    /// Decode a 16-bit move code (from|to<<6|promo<<12) back to a UCI string.
    static func uci(from code: Int32) -> String {
        let c = Int(code)
        let from = c & 0x3F, to = (c >> 6) & 0x3F
        let promo = (c >> 12) & 0x7
        let files = Array("abcdefgh")
        func sq(_ x: Int) -> String { "\(files[x % 8])\(x / 8 + 1)" }
        let promoChars = ["", "q", "r", "b", "n"]
        return sq(from) + sq(to) + (promo < promoChars.count ? promoChars[promo] : "")
    }
}
