import Foundation

class LichessGameService: ObservableObject {
    @Published var isLoading = false
    @Published var progress = ""
    @Published var error: String?
    @Published var gamesFoundSoFar = 0

    func fetchGamesProgressive(
        username: String,
        token: String?,
        since: Date?,
        onBatch: @escaping ([LichessGameData]) async -> Void
    ) async {
        await MainActor.run {
            isLoading = true
            error = nil
            progress = "Connecting to Lichess..."
            gamesFoundSoFar = 0
        }

        defer {
            Task { @MainActor in self.isLoading = false }
        }

        // Build URL — sanitize the user-typed username (trim + percent-encode) so a stray space or
        // special char yields an error instead of trapping on a force-unwrapped URLComponents.
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let encodedUsername = cleanUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: "https://lichess.org/api/games/user/\(encodedUsername)") else {
            await MainActor.run { self.error = "Invalid username" }
            return
        }
        var queryItems: [URLQueryItem] = [
            // NDJSON response → embed each game's PGN (with moves) in its JSON object.
            // (pgnInBody is for the plain-PGN response; it leaves `pgn` nil here, so games arrive moveless.)
            URLQueryItem(name: "pgnInJson", value: "true"),
            URLQueryItem(name: "opening", value: "true"),
            URLQueryItem(name: "clocks", value: "true"),
        ]
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: String(Int(since.timeIntervalSince1970 * 1000))))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            await MainActor.run { self.error = "Invalid URL" }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue("Tabia/1.0", forHTTPHeaderField: "User-Agent")
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { self.error = "Invalid response" }
                return
            }

            if httpResponse.statusCode == 404 {
                await MainActor.run { self.error = "User not found" }
                return
            }

            guard httpResponse.statusCode == 200 else {
                await MainActor.run { self.error = "HTTP error \(httpResponse.statusCode)" }
                return
            }

            await MainActor.run { self.progress = "Downloading games..." }

            var batch: [LichessGameData] = []
            let batchSize = 100

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                guard let data = trimmed.data(using: .utf8),
                      let game = try? JSONDecoder().decode(LichessGameData.self, from: data) else {
                    continue
                }

                batch.append(game)

                if batch.count >= batchSize {
                    let toSend = batch
                    batch = []
                    await MainActor.run {
                        self.gamesFoundSoFar += toSend.count
                        self.progress = "\(self.gamesFoundSoFar) games found..."
                    }
                    await onBatch(toSend)
                }
            }

            // Send remaining
            if !batch.isEmpty && !Task.isCancelled {
                let toSend = batch
                await MainActor.run {
                    self.gamesFoundSoFar += toSend.count
                    self.progress = "\(self.gamesFoundSoFar) games found"
                }
                await onBatch(toSend)
            }

            if !Task.isCancelled {
                await MainActor.run {
                    self.progress = "Done — \(self.gamesFoundSoFar) games"
                }
            }
        } catch is CancellationError {
            // Cancelled
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Lichess Game Data Models

struct LichessGameData: Codable {
    let id: String
    let rated: Bool?
    let variant: String?
    let speed: String?
    let perf: String?
    let createdAt: Int64?
    let lastMoveAt: Int64?
    let status: String?
    let players: LichessGamePlayers
    let winner: String?
    let pgn: String?
    let opening: LichessGameOpening?

    var url: String { "https://lichess.org/\(id)" }

    var timeClass: String {
        speed ?? perf ?? "unknown"
    }

    var result: String {
        guard let winner = winner else {
            if status == "draw" || status == "stalemate" {
                return "1/2-1/2"
            }
            return "1/2-1/2"
        }
        return winner == "white" ? "1-0" : "0-1"
    }

    var endDate: Date? {
        guard let ts = lastMoveAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
    }

    var formattedDate: String {
        guard let date = endDate else { return "????.??.??" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

struct LichessGamePlayers: Codable {
    let white: LichessGamePlayer
    let black: LichessGamePlayer
}

struct LichessGamePlayer: Codable {
    let user: LichessGameUser?
    let rating: Int?
    let ratingDiff: Int?
    let aiLevel: Int?

    var username: String {
        user?.name ?? (aiLevel != nil ? "Stockfish level \(aiLevel!)" : "Anonymous")
    }
}

struct LichessGameUser: Codable {
    let name: String
    let id: String?
}

struct LichessGameOpening: Codable {
    let eco: String?
    let name: String?
    let ply: Int?
}
