import Foundation

// MARK: - Data Structures

struct ChessComStats: Codable, Hashable {
    let totalGames: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let winRate: Double

    let timeControlStats: [String: TimeControlStats]
    let ratingHistory: [RatingPoint]
    let openingStats: [OpeningStats]
    let monthlyActivity: [MonthActivity]
    let streaks: StreakStats
    let colorStats: ColorStats
    let timeOfDayStats: [TimeOfDaySlot]
}

struct TimeOfDaySlot: Identifiable, Codable, Hashable {
    let id: UUID
    let slot: String
    let icon: String
    let games: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let winRate: Double

    init(slot: String, icon: String, games: Int, wins: Int, losses: Int, draws: Int) {
        self.id = UUID()
        self.slot = slot
        self.icon = icon
        self.games = games
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.winRate = games > 0 ? Double(wins) / Double(games) * 100.0 : 0
    }

    enum CodingKeys: String, CodingKey {
        case slot, icon, games, wins, losses, draws, winRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.slot = try container.decode(String.self, forKey: .slot)
        self.icon = try container.decode(String.self, forKey: .icon)
        self.games = try container.decode(Int.self, forKey: .games)
        self.wins = try container.decode(Int.self, forKey: .wins)
        self.losses = try container.decode(Int.self, forKey: .losses)
        self.draws = try container.decode(Int.self, forKey: .draws)
        self.winRate = try container.decode(Double.self, forKey: .winRate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slot, forKey: .slot)
        try container.encode(icon, forKey: .icon)
        try container.encode(games, forKey: .games)
        try container.encode(wins, forKey: .wins)
        try container.encode(losses, forKey: .losses)
        try container.encode(draws, forKey: .draws)
        try container.encode(winRate, forKey: .winRate)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(slot)
        hasher.combine(games)
    }

    static func == (lhs: TimeOfDaySlot, rhs: TimeOfDaySlot) -> Bool {
        lhs.slot == rhs.slot && lhs.games == rhs.games &&
        lhs.wins == rhs.wins && lhs.losses == rhs.losses && lhs.draws == rhs.draws
    }
}

struct TimeControlStats: Codable, Hashable {
    let timeClass: String
    let games: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let winRate: Double
    let currentRating: Int?
    let peakRating: Int?

    var icon: String {
        switch timeClass.lowercased() {
        case "bullet": return "circle.fill"
        case "blitz": return "bolt.fill"
        case "rapid": return "hare.fill"
        case "daily": return "calendar"
        default: return "clock"
        }
    }

    var displayName: String {
        timeClass.capitalized
    }
}

struct RatingPoint: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let rating: Int
    let timeClass: String

    init(date: Date, rating: Int, timeClass: String) {
        self.id = UUID()
        self.date = date
        self.rating = rating
        self.timeClass = timeClass
    }

    enum CodingKeys: String, CodingKey {
        case date, rating, timeClass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.date = try container.decode(Date.self, forKey: .date)
        self.rating = try container.decode(Int.self, forKey: .rating)
        self.timeClass = try container.decode(String.self, forKey: .timeClass)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(rating, forKey: .rating)
        try container.encode(timeClass, forKey: .timeClass)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(rating)
        hasher.combine(timeClass)
    }

    static func == (lhs: RatingPoint, rhs: RatingPoint) -> Bool {
        lhs.date == rhs.date && lhs.rating == rhs.rating && lhs.timeClass == rhs.timeClass
    }
}

struct OpeningStats: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let eco: String?
    let games: Int
    let wins: Int
    let losses: Int
    let draws: Int
    let winRate: Double

    let whiteGames: Int
    let whiteWins: Int
    let whiteLosses: Int
    let whiteDraws: Int
    let blackGames: Int
    let blackWins: Int
    let blackLosses: Int
    let blackDraws: Int

    var whiteWinRate: Double {
        whiteGames > 0 ? Double(whiteWins) / Double(whiteGames) * 100.0 : 0
    }

    var blackWinRate: Double {
        blackGames > 0 ? Double(blackWins) / Double(blackGames) * 100.0 : 0
    }

    init(name: String, eco: String?, games: Int, wins: Int, losses: Int, draws: Int, winRate: Double,
         whiteGames: Int = 0, whiteWins: Int = 0, whiteLosses: Int = 0, whiteDraws: Int = 0,
         blackGames: Int = 0, blackWins: Int = 0, blackLosses: Int = 0, blackDraws: Int = 0) {
        self.id = UUID()
        self.name = name
        self.eco = eco
        self.games = games
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.winRate = winRate
        self.whiteGames = whiteGames
        self.whiteWins = whiteWins
        self.whiteLosses = whiteLosses
        self.whiteDraws = whiteDraws
        self.blackGames = blackGames
        self.blackWins = blackWins
        self.blackLosses = blackLosses
        self.blackDraws = blackDraws
    }

    enum CodingKeys: String, CodingKey {
        case name, eco, games, wins, losses, draws, winRate
        case whiteGames, whiteWins, whiteLosses, whiteDraws
        case blackGames, blackWins, blackLosses, blackDraws
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.eco = try container.decodeIfPresent(String.self, forKey: .eco)
        self.games = try container.decode(Int.self, forKey: .games)
        self.wins = try container.decode(Int.self, forKey: .wins)
        self.losses = try container.decode(Int.self, forKey: .losses)
        self.draws = try container.decode(Int.self, forKey: .draws)
        self.winRate = try container.decode(Double.self, forKey: .winRate)
        self.whiteGames = try container.decodeIfPresent(Int.self, forKey: .whiteGames) ?? 0
        self.whiteWins = try container.decodeIfPresent(Int.self, forKey: .whiteWins) ?? 0
        self.whiteLosses = try container.decodeIfPresent(Int.self, forKey: .whiteLosses) ?? 0
        self.whiteDraws = try container.decodeIfPresent(Int.self, forKey: .whiteDraws) ?? 0
        self.blackGames = try container.decodeIfPresent(Int.self, forKey: .blackGames) ?? 0
        self.blackWins = try container.decodeIfPresent(Int.self, forKey: .blackWins) ?? 0
        self.blackLosses = try container.decodeIfPresent(Int.self, forKey: .blackLosses) ?? 0
        self.blackDraws = try container.decodeIfPresent(Int.self, forKey: .blackDraws) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(eco, forKey: .eco)
        try container.encode(games, forKey: .games)
        try container.encode(wins, forKey: .wins)
        try container.encode(losses, forKey: .losses)
        try container.encode(draws, forKey: .draws)
        try container.encode(winRate, forKey: .winRate)
        try container.encode(whiteGames, forKey: .whiteGames)
        try container.encode(whiteWins, forKey: .whiteWins)
        try container.encode(whiteLosses, forKey: .whiteLosses)
        try container.encode(whiteDraws, forKey: .whiteDraws)
        try container.encode(blackGames, forKey: .blackGames)
        try container.encode(blackWins, forKey: .blackWins)
        try container.encode(blackLosses, forKey: .blackLosses)
        try container.encode(blackDraws, forKey: .blackDraws)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(eco)
        hasher.combine(games)
    }

    static func == (lhs: OpeningStats, rhs: OpeningStats) -> Bool {
        lhs.name == rhs.name && lhs.eco == rhs.eco && lhs.games == rhs.games &&
        lhs.wins == rhs.wins && lhs.losses == rhs.losses && lhs.draws == rhs.draws &&
        lhs.winRate == rhs.winRate &&
        lhs.whiteGames == rhs.whiteGames && lhs.whiteWins == rhs.whiteWins &&
        lhs.whiteLosses == rhs.whiteLosses && lhs.whiteDraws == rhs.whiteDraws &&
        lhs.blackGames == rhs.blackGames && lhs.blackWins == rhs.blackWins &&
        lhs.blackLosses == rhs.blackLosses && lhs.blackDraws == rhs.blackDraws
    }
}

struct MonthActivity: Identifiable, Codable, Hashable {
    let id: UUID
    let year: Int
    let month: Int
    let gameCount: Int

    init(year: Int, month: Int, gameCount: Int) {
        self.id = UUID()
        self.year = year
        self.month = month
        self.gameCount = gameCount
    }

    enum CodingKeys: String, CodingKey {
        case year, month, gameCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.year = try container.decode(Int.self, forKey: .year)
        self.month = try container.decode(Int.self, forKey: .month)
        self.gameCount = try container.decode(Int.self, forKey: .gameCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(gameCount, forKey: .gameCount)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(gameCount)
    }

    static func == (lhs: MonthActivity, rhs: MonthActivity) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.gameCount == rhs.gameCount
    }

    var label: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "\(month)" }
        return formatter.string(from: date)
    }

    var shortLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "\(month)/\(year)" }
        return formatter.string(from: date)
    }
}

struct StreakStats: Codable, Hashable {
    let currentWinStreak: Int
    let bestWinStreak: Int
    let currentLossStreak: Int
    let worstLossStreak: Int
}

struct ColorStats: Codable, Hashable {
    let whiteGames: Int
    let whiteWins: Int
    let whiteLosses: Int
    let whiteDraws: Int
    let whiteWinRate: Double

    let blackGames: Int
    let blackWins: Int
    let blackLosses: Int
    let blackDraws: Int
    let blackWinRate: Double
}

// MARK: - Stats Computer

enum ChessComStatsComputer {

    static func compute(games: [GameRecord], username: String, presorted: Bool = false) -> ChessComStats {
        let lowerUsername = username.lowercased()

        // Classify each game
        var wins = 0, losses = 0, draws = 0
        var whiteWins = 0, whiteLosses = 0, whiteDraws = 0, whiteGames = 0
        var blackWins = 0, blackLosses = 0, blackDraws = 0, blackGames = 0

        // Time control accumulators: timeClass -> (games, wins, losses, draws, ratings)
        var tcGames: [String: Int] = [:]
        var tcWins: [String: Int] = [:]
        var tcLosses: [String: Int] = [:]
        var tcDraws: [String: Int] = [:]
        var tcRatings: [String: [(date: Date, rating: Int)]] = [:]

        // Opening accumulators
        var openingGames: [String: Int] = [:]
        var openingWins: [String: Int] = [:]
        var openingLosses: [String: Int] = [:]
        var openingDraws: [String: Int] = [:]
        var openingEco: [String: String] = [:]
        var openingWhiteGames: [String: Int] = [:]
        var openingWhiteWins: [String: Int] = [:]
        var openingWhiteLosses: [String: Int] = [:]
        var openingWhiteDraws: [String: Int] = [:]
        var openingBlackGames: [String: Int] = [:]
        var openingBlackWins: [String: Int] = [:]
        var openingBlackLosses: [String: Int] = [:]
        var openingBlackDraws: [String: Int] = [:]

        // Time of day accumulators (0=Morning, 1=Afternoon, 2=Evening, 3=Night)
        var todGames = [0, 0, 0, 0]
        var todWins = [0, 0, 0, 0]
        var todLosses = [0, 0, 0, 0]
        var todDraws = [0, 0, 0, 0]

        // Monthly activity
        var monthCounts: [String: (year: Int, month: Int, count: Int)] = [:]

        // Streaks (games sorted by date, oldest first)
        let sortedGames = presorted ? games : games.sorted { $0.dateAdded < $1.dateAdded }

        var currentWinStreak = 0, bestWinStreak = 0
        var currentLossStreak = 0, worstLossStreak = 0

        for game in sortedGames {
            let userPlayedWhite = game.white.lowercased() == lowerUsername
            let result = classifyResult(game: game, userPlayedWhite: userPlayedWhite)

            // Overall
            switch result {
            case .win: wins += 1
            case .loss: losses += 1
            case .draw: draws += 1
            }

            // By color
            if userPlayedWhite {
                whiteGames += 1
                switch result {
                case .win: whiteWins += 1
                case .loss: whiteLosses += 1
                case .draw: whiteDraws += 1
                }
            } else {
                blackGames += 1
                switch result {
                case .win: blackWins += 1
                case .loss: blackLosses += 1
                case .draw: blackDraws += 1
                }
            }

            // Time control
            let tc = game.timeClass ?? "unknown"
            tcGames[tc, default: 0] += 1
            switch result {
            case .win: tcWins[tc, default: 0] += 1
            case .loss: tcLosses[tc, default: 0] += 1
            case .draw: tcDraws[tc, default: 0] += 1
            }

            // Rating extraction
            if let rating = extractUserRating(from: game.pgn, userPlayedWhite: userPlayedWhite) {
                tcRatings[tc, default: []].append((date: game.dateAdded, rating: rating))
            }

            // Openings — try game.opening, then PGN [Opening "..."], then ECOUrl
            let opening = resolveOpening(game: game)
            if let opening = opening, !opening.isEmpty {
                openingGames[opening, default: 0] += 1
                switch result {
                case .win: openingWins[opening, default: 0] += 1
                case .loss: openingLosses[opening, default: 0] += 1
                case .draw: openingDraws[opening, default: 0] += 1
                }
                // Per-color opening tracking
                if userPlayedWhite {
                    openingWhiteGames[opening, default: 0] += 1
                    switch result {
                    case .win: openingWhiteWins[opening, default: 0] += 1
                    case .loss: openingWhiteLosses[opening, default: 0] += 1
                    case .draw: openingWhiteDraws[opening, default: 0] += 1
                    }
                } else {
                    openingBlackGames[opening, default: 0] += 1
                    switch result {
                    case .win: openingBlackWins[opening, default: 0] += 1
                    case .loss: openingBlackLosses[opening, default: 0] += 1
                    case .draw: openingBlackDraws[opening, default: 0] += 1
                    }
                }
                let eco = game.eco ?? extractHeader("ECO", from: game.pgn)
                if let eco = eco {
                    openingEco[opening] = eco
                }
            }

            // Monthly activity
            let cal = Calendar.current
            let year = cal.component(.year, from: game.dateAdded)
            let month = cal.component(.month, from: game.dateAdded)
            let key = "\(year)-\(month)"
            if var entry = monthCounts[key] {
                entry.count += 1
                monthCounts[key] = entry
            } else {
                monthCounts[key] = (year: year, month: month, count: 1)
            }

            // Time of day
            let hour = cal.component(.hour, from: game.dateAdded)
            let todIndex: Int
            switch hour {
            case 6..<12:  todIndex = 0  // Morning
            case 12..<17: todIndex = 1  // Afternoon
            case 17..<21: todIndex = 2  // Evening
            default:      todIndex = 3  // Night
            }
            todGames[todIndex] += 1
            switch result {
            case .win:  todWins[todIndex] += 1
            case .loss: todLosses[todIndex] += 1
            case .draw: todDraws[todIndex] += 1
            }

            // Streaks
            switch result {
            case .win:
                currentWinStreak += 1
                currentLossStreak = 0
                bestWinStreak = max(bestWinStreak, currentWinStreak)
            case .loss:
                currentLossStreak += 1
                currentWinStreak = 0
                worstLossStreak = max(worstLossStreak, currentLossStreak)
            case .draw:
                currentWinStreak = 0
                currentLossStreak = 0
            }
        }

        let totalGames = games.count
        let winRate = totalGames > 0 ? Double(wins) / Double(totalGames) * 100.0 : 0

        // Build TimeControlStats
        var timeControlStats: [String: TimeControlStats] = [:]
        for tc in tcGames.keys {
            let g = tcGames[tc] ?? 0
            let w = tcWins[tc] ?? 0
            let l = tcLosses[tc] ?? 0
            let d = tcDraws[tc] ?? 0
            let ratings = (tcRatings[tc] ?? []).sorted { $0.date < $1.date }
            let currentRating = ratings.last?.rating
            let peakRating = ratings.map(\.rating).max()

            timeControlStats[tc] = TimeControlStats(
                timeClass: tc,
                games: g,
                wins: w,
                losses: l,
                draws: d,
                winRate: g > 0 ? Double(w) / Double(g) * 100.0 : 0,
                currentRating: currentRating,
                peakRating: peakRating
            )
        }

        // Build RatingHistory (all time classes merged, sorted by date)
        var ratingHistory: [RatingPoint] = []
        for (tc, ratings) in tcRatings {
            for entry in ratings.sorted(by: { $0.date < $1.date }) {
                ratingHistory.append(RatingPoint(date: entry.date, rating: entry.rating, timeClass: tc))
            }
        }
        ratingHistory.sort { $0.date < $1.date }

        // Build OpeningStats (top 10 by frequency)
        let openingStatsList = openingGames.keys.map { name -> OpeningStats in
            let g = openingGames[name] ?? 0
            let w = openingWins[name] ?? 0
            let l = openingLosses[name] ?? 0
            let d = openingDraws[name] ?? 0
            return OpeningStats(
                name: name,
                eco: openingEco[name],
                games: g,
                wins: w,
                losses: l,
                draws: d,
                winRate: g > 0 ? Double(w) / Double(g) * 100.0 : 0,
                whiteGames: openingWhiteGames[name] ?? 0,
                whiteWins: openingWhiteWins[name] ?? 0,
                whiteLosses: openingWhiteLosses[name] ?? 0,
                whiteDraws: openingWhiteDraws[name] ?? 0,
                blackGames: openingBlackGames[name] ?? 0,
                blackWins: openingBlackWins[name] ?? 0,
                blackLosses: openingBlackLosses[name] ?? 0,
                blackDraws: openingBlackDraws[name] ?? 0
            )
        }
        .sorted { $0.games > $1.games }
        .prefix(10)

        // Build MonthlyActivity (last 12 months)
        let now = Date()
        let cal = Calendar.current
        var monthlyActivity: [MonthActivity] = []
        for i in (0..<12).reversed() {
            guard let date = cal.date(byAdding: .month, value: -i, to: now) else { continue }
            let year = cal.component(.year, from: date)
            let month = cal.component(.month, from: date)
            let key = "\(year)-\(month)"
            let count = monthCounts[key]?.count ?? 0
            monthlyActivity.append(MonthActivity(year: year, month: month, gameCount: count))
        }

        let colorStats = ColorStats(
            whiteGames: whiteGames,
            whiteWins: whiteWins,
            whiteLosses: whiteLosses,
            whiteDraws: whiteDraws,
            whiteWinRate: whiteGames > 0 ? Double(whiteWins) / Double(whiteGames) * 100.0 : 0,
            blackGames: blackGames,
            blackWins: blackWins,
            blackLosses: blackLosses,
            blackDraws: blackDraws,
            blackWinRate: blackGames > 0 ? Double(blackWins) / Double(blackGames) * 100.0 : 0
        )

        let todSlotInfo: [(String, String)] = [
            ("Morning", "sunrise.fill"),
            ("Afternoon", "sun.max.fill"),
            ("Evening", "sunset.fill"),
            ("Night", "moon.fill"),
        ]
        let timeOfDayStats = todSlotInfo.enumerated().map { i, info in
            TimeOfDaySlot(
                slot: info.0, icon: info.1,
                games: todGames[i], wins: todWins[i],
                losses: todLosses[i], draws: todDraws[i]
            )
        }

        return ChessComStats(
            totalGames: totalGames,
            wins: wins,
            losses: losses,
            draws: draws,
            winRate: winRate,
            timeControlStats: timeControlStats,
            ratingHistory: ratingHistory,
            openingStats: Array(openingStatsList),
            monthlyActivity: monthlyActivity,
            streaks: StreakStats(
                currentWinStreak: currentWinStreak,
                bestWinStreak: bestWinStreak,
                currentLossStreak: currentLossStreak,
                worstLossStreak: worstLossStreak
            ),
            colorStats: colorStats,
            timeOfDayStats: timeOfDayStats
        )
    }

    /// Pre-compute stats for "all" + each individual time class.
    /// Returns a dictionary keyed by "all", "bullet", "blitz", "rapid", "daily", etc.
    static func computeAllVariants(games: [GameRecord], username: String) -> [String: ChessComStats] {
        var result: [String: ChessComStats] = [:]

        // Sort once and reuse. compute() needs oldest-first for streaks, and grouping a sorted array
        // preserves order, so every per-time-class slice is sorted too. Each of the five passes used
        // to re-sort the entire library.
        let sorted = games.sorted { $0.dateAdded < $1.dateAdded }

        // "all" — no filter
        result["all"] = compute(games: sorted, username: username, presorted: true)

        // Group games by time class
        var byTimeClass: [String: [GameRecord]] = [:]
        for game in sorted {
            let tc = game.timeClass ?? "unknown"
            byTimeClass[tc, default: []].append(game)
        }

        for (tc, tcGames) in byTimeClass {
            result[tc] = compute(games: tcGames, username: username, presorted: true)
        }

        return result
    }

    // MARK: - Helpers

    private enum GameResult {
        case win, loss, draw
    }

    private static func classifyResult(game: GameRecord, userPlayedWhite: Bool) -> GameResult {
        let result = game.result
        if result == "1/2-1/2" || result == "1/2" {
            return .draw
        }
        if userPlayedWhite {
            return result == "1-0" ? .win : .loss
        } else {
            return result == "0-1" ? .win : .loss
        }
    }

    /// Compiled header regexes, cached per key. These run once per game per stats variant — five
    /// passes over the whole library — so compiling them inline meant six-figure regex compilations
    /// on the main thread at the end of every sync.
    private static let regexLock = NSLock()
    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]

    private static func headerRegex(_ pattern: String) -> NSRegularExpression? {
        regexLock.lock()
        defer { regexLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = regex
        return regex
    }

    private static func extractUserRating(from pgn: String, userPlayedWhite: Bool) -> Int? {
        let key = userPlayedWhite ? "WhiteElo" : "BlackElo"
        guard let regex = headerRegex("\\[\(key) \"(\\d+)\"\\]"),
              let match = regex.firstMatch(in: pgn, range: NSRange(pgn.startIndex..., in: pgn)),
              let range = Range(match.range(at: 1), in: pgn) else { return nil }
        return Int(pgn[range])
    }

    /// Extract a PGN header value by key (e.g. "Opening", "ECO", "ECOUrl")
    private static func extractHeader(_ key: String, from pgn: String) -> String? {
        guard let regex = headerRegex("\\[\(key) \"([^\"]+)\"\\]"),
              let match = regex.firstMatch(in: pgn, range: NSRange(pgn.startIndex..., in: pgn)),
              let range = Range(match.range(at: 1), in: pgn) else { return nil }
        let value = String(pgn[range])
        return value.isEmpty ? nil : value
    }

    /// Resolve the opening name for a game: game.opening → PGN [Opening] → ECOUrl
    private static func resolveOpening(game: GameRecord) -> String? {
        if let opening = game.opening, !opening.isEmpty {
            return opening
        }
        // Try [Opening "..."] header from PGN
        if let opening = extractHeader("Opening", from: game.pgn) {
            return opening
        }
        // Try [ECOUrl "..."] — Chess.com format:
        // https://www.chess.com/openings/Italian-Game-Giuoco-Piano-4...d6
        if let ecoUrl = extractHeader("ECOUrl", from: game.pgn),
           let lastSlash = ecoUrl.lastIndex(of: "/") {
            let slug = String(ecoUrl[ecoUrl.index(after: lastSlash)...])
            // Remove trailing move info (e.g., "-3...Bc5", "-4.Nf3-d6")
            let cleaned = slug
                .replacingOccurrences(of: "-\\d+\\..*$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "-", with: " ")
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }
}
