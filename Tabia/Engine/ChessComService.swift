import Foundation

// MARK: - Chess.com API Response Models

struct ChessComArchivesResponse: Codable {
    let archives: [String]
}

struct ChessComGamesResponse: Codable {
    let games: [ChessComGame]
}

struct ChessComGame: Codable, Identifiable {
    let url: String
    let pgn: String?
    let timeControl: String?
    let endTime: Int?
    let rated: Bool?
    let timeClass: String?
    let rules: String?
    let white: ChessComPlayer
    let black: ChessComPlayer

    var id: String { url }

    enum CodingKeys: String, CodingKey {
        case url, pgn, rated, rules, white, black
        case timeControl = "time_control"
        case endTime = "end_time"
        case timeClass = "time_class"
    }

    var endDate: Date? {
        guard let endTime = endTime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(endTime))
    }

    var formattedDate: String {
        guard let date = endDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var result: String {
        if white.result == "win" {
            return "1-0"
        } else if black.result == "win" {
            return "0-1"
        } else {
            return "1/2"
        }
    }

    var timeClassDisplay: String {
        switch timeClass {
        case "rapid": return "Rapid"
        case "blitz": return "Blitz"
        case "bullet": return "Bullet"
        case "daily": return "Daily"
        default: return timeClass ?? "Unknown"
        }
    }
}

struct ChessComPlayer: Codable {
    let rating: Int
    let result: String
    let username: String

    enum CodingKeys: String, CodingKey {
        case rating, result, username
    }
}

// MARK: - Chess.com Service

class ChessComService: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var fetchedGames: [ChessComGame] = []
    @Published var progress: String = ""

    // Progress tracking
    @Published var currentArchive: Int = 0
    @Published var totalArchives: Int = 0
    @Published var gamesFoundSoFar: Int = 0
    @Published var estimatedTimeRemaining: TimeInterval = 0

    private let lastArchiveKey = "chesscom_last_archive"
    private var archiveTimes: [TimeInterval] = []

    // Get last synced archive for a username (e.g., "2024/02")
    func getLastSyncedArchive(for username: String) -> String? {
        let dict = UserDefaults.standard.dictionary(forKey: lastArchiveKey) as? [String: String] ?? [:]
        return dict[username.lowercased()]
    }

    // Save last synced archive for a username
    func saveLastSyncedArchive(_ archive: String, for username: String) {
        var dict = UserDefaults.standard.dictionary(forKey: lastArchiveKey) as? [String: String] ?? [:]
        dict[username.lowercased()] = archive
        UserDefaults.standard.set(dict, forKey: lastArchiveKey)
    }

    // Clear stored archive for a username
    func clearHistory(for username: String) {
        var dict = UserDefaults.standard.dictionary(forKey: lastArchiveKey) as? [String: String] ?? [:]
        dict.removeValue(forKey: username.lowercased())
        UserDefaults.standard.set(dict, forKey: lastArchiveKey)
    }

    // Fetch all games for a username (full import)
    func fetchAllGames(username: String) async {
        await fetchGames(username: username, fromArchive: nil)
    }

    // Fetch new games since last sync
    func fetchNewGames(username: String) async {
        let lastArchive = getLastSyncedArchive(for: username)
        await fetchGames(username: username, fromArchive: lastArchive)
    }

    // Progressive fetch: calls onArchiveFetched after each archive is downloaded
    func fetchAllGamesProgressive(username: String, onArchiveFetched: @escaping ([ChessComGame]) async -> Void) async {
        await fetchGames(username: username, fromArchive: nil, onArchiveFetched: onArchiveFetched)
    }

    func fetchNewGamesProgressive(username: String, onArchiveFetched: @escaping ([ChessComGame]) async -> Void) async {
        let lastArchive = getLastSyncedArchive(for: username)
        await fetchGames(username: username, fromArchive: lastArchive, onArchiveFetched: onArchiveFetched)
    }

    // Core fetch method
    private func fetchGames(username: String, fromArchive: String?, onArchiveFetched: (([ChessComGame]) async -> Void)? = nil) async {
        await MainActor.run {
            isLoading = true
            error = nil
            fetchedGames = []
            progress = "Fetching archives..."
            currentArchive = 0
            totalArchives = 0
            gamesFoundSoFar = 0
            estimatedTimeRemaining = 0
            archiveTimes = []
        }

        do {
            // Step 1: Fetch archives list
            // Sanitize the user-typed username: trim whitespace and percent-encode so a stray space
            // or special character yields a userNotFound error instead of crashing on a force-unwrap.
            let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let encodedUsername = cleanUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let archivesURL = URL(string: "https://api.chess.com/pub/player/\(encodedUsername)/games/archives") else {
                throw ChessComError.userNotFound
            }
            var request = URLRequest(url: archivesURL)
            request.setValue("Tabia/1.0", forHTTPHeaderField: "User-Agent")

            let (archivesData, archivesResponse) = try await URLSession.shared.data(for: request)

            guard let httpResponse = archivesResponse as? HTTPURLResponse else {
                throw ChessComError.invalidResponse
            }

            if httpResponse.statusCode == 404 {
                throw ChessComError.userNotFound
            }

            guard httpResponse.statusCode == 200 else {
                throw ChessComError.httpError(httpResponse.statusCode)
            }

            let archivesResult = try JSONDecoder().decode(ChessComArchivesResponse.self, from: archivesData)

            // Filter archives if we have a starting point
            var archivesToFetch = archivesResult.archives.sorted()

            if let fromArchive = fromArchive {
                // Only fetch archives >= fromArchive
                // Archive URLs look like: https://api.chess.com/pub/player/username/games/2024/02
                // We compare the year/month suffix
                archivesToFetch = archivesToFetch.filter { archiveURL in
                    let suffix = extractArchiveSuffix(from: archiveURL)
                    let fromSuffix = fromArchive
                    return suffix >= fromSuffix
                }
            }

            // Reverse to fetch newest first
            archivesToFetch = Array(archivesToFetch.reversed())

            await MainActor.run {
                totalArchives = archivesToFetch.count
            }

            var allGames: [ChessComGame] = []
            var newestArchive: String?

            // Step 2: Fetch games from each archive
            for (index, archiveURL) in archivesToFetch.enumerated() {
                // Support cancellation
                guard !Task.isCancelled else { break }

                let archiveStartTime = Date()

                await MainActor.run {
                    currentArchive = index + 1
                    progress = "Fetching archive \(index + 1) of \(archivesToFetch.count)..."
                }

                // Fetch this archive with bounded retries: a 429 (rate-limit) or transient 5xx backs
                // off (honoring Retry-After) and, if it persists, we SKIP just this archive with a
                // `continue` — instead of feeding a non-200 body to JSONDecoder and aborting the whole
                // multi-archive sync (which also discarded every archive fetched so far).
                guard let archiveURLValue = URL(string: archiveURL) else { continue }
                var fetched: ChessComGamesResponse?
                for attempt in 0..<4 {
                    var archiveRequest = URLRequest(url: archiveURLValue)
                    archiveRequest.setValue("Tabia/1.0", forHTTPHeaderField: "User-Agent")
                    let (gamesData, archiveResponse) = try await URLSession.shared.data(for: archiveRequest)
                    guard let http = archiveResponse as? HTTPURLResponse else { throw ChessComError.invalidResponse }
                    if http.statusCode == 200 {
                        fetched = try JSONDecoder().decode(ChessComGamesResponse.self, from: gamesData)
                        break
                    }
                    // Only 429/5xx are worth retrying; anything else (e.g. a 404 on a vanished archive)
                    // means skip this archive.
                    guard http.statusCode == 429 || (500...599).contains(http.statusCode) else { break }
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    let backoff = retryAfter ?? pow(2.0, Double(attempt)) * 0.5   // 0.5s, 1s, 2s
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
                guard let gamesResult = fetched else { continue }   // persistent failure → skip archive

                // Add all games with PGN
                let gamesWithPGN = gamesResult.games.filter { $0.pgn != nil }

                // Progressive path: deliver games via callback
                if let callback = onArchiveFetched {
                    await callback(gamesWithPGN)
                } else {
                    allGames.append(contentsOf: gamesWithPGN)
                }

                // Track the newest archive (first one since we're going newest first)
                if newestArchive == nil {
                    newestArchive = extractArchiveSuffix(from: archiveURL)
                }

                // Calculate time for this archive and estimate remaining
                let archiveTime = Date().timeIntervalSince(archiveStartTime)

                await MainActor.run {
                    self.archiveTimes.append(archiveTime)
                    self.gamesFoundSoFar += gamesWithPGN.count

                    // Calculate estimated time remaining
                    let avgTimePerArchive = self.archiveTimes.reduce(0, +) / Double(self.archiveTimes.count)
                    let remainingArchives = archivesToFetch.count - (index + 1)
                    self.estimatedTimeRemaining = avgTimePerArchive * Double(remainingArchives)
                }

                // Small delay to be nice to the API
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if onArchiveFetched != nil {
                // Progressive path: games were already delivered via callback
                await MainActor.run {
                    self.isLoading = false
                    self.progress = self.gamesFoundSoFar == 0 ? "No games found" : "Import complete"
                    self.estimatedTimeRemaining = 0
                }
            } else {
                // Non-progressive path: sort and set fetchedGames
                allGames.sort { game1, game2 in
                    let time1 = game1.endTime ?? 0
                    let time2 = game2.endTime ?? 0
                    return time1 > time2
                }

                await MainActor.run {
                    self.fetchedGames = allGames
                    self.isLoading = false
                    self.progress = allGames.isEmpty ? "No games found" : "Found \(allGames.count) games"
                    self.estimatedTimeRemaining = 0
                }
            }

            // Save the newest archive for next sync
            if let newestArchive = newestArchive {
                saveLastSyncedArchive(newestArchive, for: username)
            }

        } catch let error as ChessComError {
            await MainActor.run {
                self.error = error.message
                self.isLoading = false
                self.progress = ""
                self.estimatedTimeRemaining = 0
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
                self.progress = ""
                self.estimatedTimeRemaining = 0
            }
        }
    }

    // Extract year/month suffix from archive URL (e.g., "2024/02")
    private func extractArchiveSuffix(from archiveURL: String) -> String {
        // URL format: https://api.chess.com/pub/player/username/games/2024/02
        let components = archiveURL.split(separator: "/")
        if components.count >= 2 {
            let year = components[components.count - 2]
            let month = components[components.count - 1]
            return "\(year)/\(month)"
        }
        return archiveURL
    }
}

// MARK: - Errors

enum ChessComError: Error {
    case userNotFound
    case invalidResponse
    case httpError(Int)
    case noGames

    var message: String {
        switch self {
        case .userNotFound:
            return "User not found on Chess.com"
        case .invalidResponse:
            return "Invalid response from Chess.com"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noGames:
            return "No games found"
        }
    }
}
