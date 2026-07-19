import SwiftUI

// Chess.com / Lichess sync + PGN parsing for ChessComBrowserView. Split out of the view so
// the file stays UI-focused; this is the networking/data layer.

extension ChessComBrowserView {

    /// Seed the dedup set from BOTH handles. The two syncs can now run at the same time and share
    /// this set (every mutation is on the main actor), so seeding it for one handle only would make
    /// the other platform treat everything it already has as new.
    func seedSeenSourceUrls() {
        var urls = Set<String>()
        if !savedUsername.isEmpty { urls.formUnion(database.existingChessComSourceUrls(for: savedUsername)) }
        if !lichessUsername.isEmpty { urls.formUnion(database.existingChessComSourceUrls(for: lichessUsername)) }
        seenSourceUrls = urls
    }

    // MARK: - Progressive Sync

    func startProgressiveSync(fullImport: Bool) {
        isSyncing = true
        importedCount = 0
        syncTimeClassCounts = [:]
        recentlyImportedGames = []
        seedSeenSourceUrls()

        let username = savedUsername

        syncTask = Task {
            if fullImport {
                service.clearHistory(for: username)
                await service.fetchAllGamesProgressive(username: username) { archiveGames in
                    await self.importArchiveGames(archiveGames, username: username)
                }
            } else {
                await service.fetchNewGamesProgressive(username: username) { archiveGames in
                    await self.importArchiveGames(archiveGames, username: username)
                }
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isSyncing = false }
                return
            }

            await MainActor.run {
                self.lastSyncTimestamp = Date().timeIntervalSince1970
                self.isSyncing = false
                self.reloadGames()
            }
        }
    }

    func startImportFromSheet(games: [ChessComGame], username: String) {
        isSyncing = true
        importedCount = 0
        syncTimeClassCounts = [:]
        recentlyImportedGames = []
        seenSourceUrls = database.existingChessComSourceUrls(for: username)

        syncTask = Task {
            // Import games in batches to avoid blocking
            let batchSize = 200
            for batchStart in stride(from: 0, to: games.count, by: batchSize) {
                guard !Task.isCancelled else { break }
                let end = min(batchStart + batchSize, games.count)
                let batch = Array(games[batchStart..<end])
                await self.importArchiveGames(batch, username: username)
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isSyncing = false }
                return
            }

            await MainActor.run {
                self.lastSyncTimestamp = Date().timeIntervalSince1970
                self.isSyncing = false
                self.reloadGames()
            }
        }
    }

    private func importArchiveGames(_ games: [ChessComGame], username: String) async {
        // Parse PGN (runs on background thread in async context)
        let records = parseChessComGames(games, username: username)

        guard !Task.isCancelled else { return }

        // Save to DB on main thread
        await MainActor.run {
            // Dedup: filter out games already in DB
            // In-memory dedup against the set loaded once per sync, plus the urls seen in
            // earlier batches of this run.
            let newRecords = records.filter { record in
                guard let sourceUrl = record.sourceUrl else { return true }
                return !seenSourceUrls.contains(sourceUrl)
            }
            seenSourceUrls.formUnion(newRecords.compactMap { $0.sourceUrl })

            if !newRecords.isEmpty {
                database.addGames(newRecords, isChessComImport: true)
                importedCount += newRecords.count

                // Update time class counts
                for record in newRecords {
                    if let tc = record.timeClass {
                        syncTimeClassCounts[tc, default: 0] += 1
                    }
                }

                // Update recently imported (keep latest 4)
                recentlyImportedGames.insert(contentsOf: Array(newRecords.prefix(4)), at: 0)
                if recentlyImportedGames.count > 4 {
                    recentlyImportedGames = Array(recentlyImportedGames.prefix(4))
                }
            }
        }
    }

    func cancelSync() {
        syncTask?.cancel()
        lichessSyncTask?.cancel()
        isSyncing = false
        isLichessSyncing = false
    }

    // MARK: - Lichess Sync

    func startLichessSync(fullImport: Bool) {
        isLichessSyncing = true
        if !isSyncing {
            isSyncing = true
            importedCount = 0
            syncTimeClassCounts = [:]
            recentlyImportedGames = []
        }
        seedSeenSourceUrls()

        let username = lichessUsername
        let token = settings.lichessToken.isEmpty ? nil : settings.lichessToken
        let since: Date? = fullImport ? nil : (lichessLastSync > 0 ? Date(timeIntervalSince1970: lichessLastSync) : nil)

        lichessSyncTask = Task {
            await lichessService.fetchGamesProgressive(
                username: username,
                token: token,
                since: since
            ) { batch in
                await self.importLichessGames(batch, username: username)
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLichessSyncing = false
                    if !self.service.isLoading { self.isSyncing = false }
                }
                return
            }

            await MainActor.run {
                self.lichessLastSync = Date().timeIntervalSince1970
                self.isLichessSyncing = false
                if !self.service.isLoading { self.isSyncing = false }
                self.reloadGames()
            }
        }
    }

    private func importLichessGames(_ games: [LichessGameData], username: String) async {
        let records = parseLichessGames(games, username: username)

        guard !Task.isCancelled else { return }

        await MainActor.run {
            // In-memory dedup against the set loaded once per sync, plus the urls seen in
            // earlier batches of this run.
            let newRecords = records.filter { record in
                guard let sourceUrl = record.sourceUrl else { return true }
                return !seenSourceUrls.contains(sourceUrl)
            }
            seenSourceUrls.formUnion(newRecords.compactMap { $0.sourceUrl })

            if !newRecords.isEmpty {
                database.addGames(newRecords, isChessComImport: true)
                importedCount += newRecords.count
                lichessImportedCount += newRecords.count

                for record in newRecords {
                    if let tc = record.timeClass {
                        syncTimeClassCounts[tc, default: 0] += 1
                    }
                }

                recentlyImportedGames.insert(contentsOf: Array(newRecords.prefix(4)), at: 0)
                if recentlyImportedGames.count > 4 {
                    recentlyImportedGames = Array(recentlyImportedGames.prefix(4))
                }
            }
        }
    }

    // MARK: - Lichess PGN Parsing

    private func parseLichessGames(_ games: [LichessGameData], username: String) -> [GameRecord] {
        var records: [GameRecord] = []

        for game in games {
            let whitePlayer = game.players.white.username
            let blackPlayer = game.players.black.username

            var openingName = game.opening?.name
            let eco = game.opening?.eco

            // Parse PGN if available for richer data
            var pgn = game.pgn ?? ""
            if pgn.isEmpty {
                // Construct minimal PGN from game data
                pgn = "[Event \"Lichess \(game.timeClass)\"]\n[White \"\(whitePlayer)\"]\n[Black \"\(blackPlayer)\"]\n[Result \"\(game.result)\"]\n"
            }

            let record = GameRecord(
                event: "Lichess \(game.timeClass.capitalized)",
                date: game.formattedDate,
                white: whitePlayer,
                black: blackPlayer,
                result: game.result,
                eco: eco,
                opening: openingName,
                pgn: pgn,
                dateAdded: game.endDate ?? Date(),
                timeClass: game.timeClass,
                sourceUsername: username.lowercased(),
                sourceUrl: game.url,
                whiteElo: game.players.white.rating,
                blackElo: game.players.black.rating
            )
            records.append(record)
        }

        return records
    }

    // MARK: - PGN Parsing (pure function, safe to call from background)

    private func parseChessComGames(_ games: [ChessComGame], username: String) -> [GameRecord] {
        var records: [GameRecord] = []

        for game in games {
            guard let pgn = game.pgn else { continue }

            let parser = PGNParser()
            let parsedGames = parser.parse(string: pgn)
            let parsedGame = parsedGames.first

            var openingName = parsedGame?.headers["Opening"]
            if (openingName == nil || openingName!.isEmpty),
               let ecoUrl = parsedGame?.headers["ECOUrl"],
               let lastSlash = ecoUrl.lastIndex(of: "/") {
                let slug = String(ecoUrl[ecoUrl.index(after: lastSlash)...])
                let cleaned = slug
                    .replacingOccurrences(of: "-\\d+\\..*$", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "-", with: " ")
                if !cleaned.isEmpty { openingName = cleaned }
            }

            let record = GameRecord(
                event: parsedGame?.headers["Event"] ?? "Chess.com \(game.timeClassDisplay)",
                date: game.formattedDate,
                white: game.white.username,
                black: game.black.username,
                result: game.result,
                eco: parsedGame?.headers["ECO"],
                opening: openingName,
                pgn: pgn,
                dateAdded: game.endDate ?? Date(),
                timeClass: game.timeClass,
                sourceUsername: username.lowercased(),
                sourceUrl: game.url,
                whiteElo: game.white.rating,
                blackElo: game.black.rating
            )
            records.append(record)
        }

        return records
    }

    /// Recompute stats for ONE platform's games under `username`.
    ///
    /// Ratings are platform-specific — a 2000 on Lichess is not a 2000 on Chess.com — so the two are
    /// computed and stored separately. `statsData` keys are namespaced `"<platform>.<variant>"`;
    /// unprefixed keys are the legacy single-platform layout and are still read as a fallback.
    /// The row itself stays keyed by username (its unique attribute), so no schema change.
}
