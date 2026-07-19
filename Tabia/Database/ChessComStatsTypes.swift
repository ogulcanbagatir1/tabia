import Foundation

// MARK: - Persisted stats payload types
//
// These types exist ONLY so the `ChessComCachedStats` @Model still compiles and its stored rows stay
// decodable. Nothing computes or writes them any more: ratings now come straight from each platform's
// profile endpoint (see RatingsService), which is authoritative and does not require replaying the
// library. The model is kept in the schema deliberately — removing an entity is a SwiftData migration
// and this project has no SchemaMigrationPlan, so dropping it risks the user's store.

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

