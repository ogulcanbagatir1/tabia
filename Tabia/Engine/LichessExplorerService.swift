import Foundation

// MARK: - Lichess Explorer Response Models

struct LichessExplorerResponse: Codable {
    let opening: LichessOpening?
    let white: Int
    let draws: Int
    let black: Int
    let moves: [LichessMove]
    let topGames: [LichessGame]?

    var totalGames: Int {
        white + draws + black
    }
}

struct LichessOpening: Codable {
    let eco: String
    let name: String
}

struct LichessMoveGame: Codable {
    let id: String
    let winner: String?
    let year: Int?
    let month: String?
    let white: LichessPlayer
    let black: LichessPlayer
}

struct LichessMove: Codable, Identifiable {
    let uci: String
    let san: String
    let averageRating: Int?
    let white: Int
    let draws: Int
    let black: Int
    let game: LichessMoveGame?
    let opening: LichessOpening?

    var id: String { uci }

    var totalGames: Int {
        white + draws + black
    }

    var whitePercent: Double {
        totalGames > 0 ? Double(white) / Double(totalGames) * 100 : 0
    }

    var drawPercent: Double {
        totalGames > 0 ? Double(draws) / Double(totalGames) * 100 : 0
    }

    var blackPercent: Double {
        totalGames > 0 ? Double(black) / Double(totalGames) * 100 : 0
    }
}

struct LichessGame: Codable, Identifiable {
    let id: String
    let uci: String?  // The move that led to this game being listed
    let winner: String?
    let speed: String?
    let mode: String?
    let year: Int?
    let month: String?
    let white: LichessPlayer
    let black: LichessPlayer
}

struct LichessPlayer: Codable {
    let name: String?
    let rating: Int?
}

// MARK: - Lichess Explorer Service

class LichessExplorerService: ObservableObject {
    @Published var response: LichessExplorerResponse?
    @Published var isLoading = false
    @Published var error: String?
    @Published var needsAuth = false

    private var currentTask: URLSessionTask?
    private let baseURL = "https://explorer.lichess.ovh/masters"

    // Dedicated session to avoid HTTP/2 connection coalescing (421 errors)
    private var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config)
    }()

    var token: String = ""

    // Debounce timer
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.3

    // Cache
    private var cache: [String: LichessExplorerResponse] = [:]

    // Rate limit backoff: don't send requests until this date
    private var rateLimitedUntil: Date?

    func fetchExplorerData(fen: String, moves: [String] = [], since: Int? = nil, until: Int? = nil, moveCount: Int = 12, topGames: Int = 4) {
        // Cancel any pending request
        debounceTimer?.invalidate()

        // Always clear error on new fetch attempt
        self.error = nil
        self.needsAuth = false

        // Create cache key
        let cacheKey = "\(fen)_\(moves.joined(separator: ","))_\(since ?? 0)_\(until ?? 9999)"

        // Check cache
        if let cached = cache[cacheKey] {
            self.response = cached
            return
        }

        // If rate limited, skip the request silently (keep showing previous response)
        if let rateLimitExpiry = rateLimitedUntil, Date() < rateLimitExpiry {
            return
        }

        // Debounce the request
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.performFetch(fen: fen, moves: moves, since: since, until: until, moveCount: moveCount, topGames: topGames, cacheKey: cacheKey)
        }
    }

    private func performFetch(fen: String, moves: [String], since: Int?, until: Int?, moveCount: Int, topGames: Int, cacheKey: String) {
        currentTask?.cancel()

        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "moves", value: String(moveCount)),
            URLQueryItem(name: "topGames", value: String(min(topGames, 15)))
        ]

        if !moves.isEmpty {
            queryItems.append(URLQueryItem(name: "play", value: moves.joined(separator: ",")))
        }

        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: String(since)))
        }

        if let until = until {
            queryItems.append(URLQueryItem(name: "until", value: String(until)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            DispatchQueue.main.async {
                self.error = "Invalid URL"
            }
            return
        }

        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        performRequest(request, cacheKey: cacheKey, retryOn421: true)
    }

    private func performRequest(_ request: URLRequest, cacheKey: String, retryOn421: Bool) {
        currentTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // On 421 (Misdirected Request), reset session and retry once
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 421, retryOn421 {
                self.session.reset {
                    self.session = URLSession(configuration: .ephemeral)
                    self.performRequest(request, cacheKey: cacheKey, retryOn421: false)
                }
                return
            }

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    return
                }

                if let error = error {
                    self.error = error.localizedDescription
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    if httpResponse.statusCode == 429 {
                        self.rateLimitedUntil = Date().addingTimeInterval(60)
                    } else if httpResponse.statusCode == 401 {
                        self.needsAuth = true
                        self.error = "Lichess now requires authentication to access the Masters database."
                    } else {
                        self.error = "Server error (\(httpResponse.statusCode))"
                    }
                    return
                }

                guard let data = data else {
                    self.error = "No data received"
                    return
                }

                do {
                    let explorerResponse = try JSONDecoder().decode(LichessExplorerResponse.self, from: data)
                    self.response = explorerResponse
                    self.cache[cacheKey] = explorerResponse
                    self.rateLimitedUntil = nil
                } catch let decodingError as DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        self.error = "Missing key: \(key.stringValue) in \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                    case .typeMismatch(let type, let context):
                        self.error = "Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                    case .valueNotFound(let type, let context):
                        self.error = "Value not found: \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                    case .dataCorrupted(let context):
                        self.error = "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                    @unknown default:
                        self.error = "Decoding error: \(decodingError.localizedDescription)"
                    }
                } catch {
                    self.error = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }

        currentTask?.resume()
    }

    func cancel() {
        debounceTimer?.invalidate()
        currentTask?.cancel()
        isLoading = false
    }

    func clearCache() {
        cache.removeAll()
    }

    // Fetch PGN for a specific game
    func fetchGamePGN(gameId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let urlString = "https://explorer.lichess.ovh/master/pgn/\(gameId)"

        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "LichessExplorer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/x-chess-pgn", forHTTPHeaderField: "Accept")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            // On 421, reset session and retry once
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 421 {
                self?.session.reset {
                    self?.session = URLSession(configuration: .ephemeral)
                    self?.session.dataTask(with: request) { data, _, error in
                        if let error = error {
                            DispatchQueue.main.async { completion(.failure(error)) }
                            return
                        }
                        guard let data = data, let pgn = String(data: data, encoding: .utf8) else {
                            DispatchQueue.main.async {
                                completion(.failure(NSError(domain: "LichessExplorer", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                            }
                            return
                        }
                        DispatchQueue.main.async { completion(.success(pgn)) }
                    }.resume()
                }
                return
            }

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data, let pgn = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "LichessExplorer", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.success(pgn))
            }
        }.resume()
    }
}
