import Foundation

// MARK: - Player ratings, straight from the source
//
// Ratings used to be *derived*: every synced game was replayed, the Elo header of the most recent
// one became your "current rating". That is wrong in three ways — it lags behind games you have not
// synced, it is blank for any game whose PGN carries no Elo header, and it made three numbers cost a
// full pass over the library.
//
// Both platforms publish the authoritative number. Ask them.

/// Keys are "<platform>.<timeClass>", e.g. "lichess.blitz".
enum RatingsService {

    static let timeClasses = ["bullet", "blitz", "rapid"]

    /// Fetch ratings for whichever handles are set. Failures are per-platform: if Chess.com is down,
    /// Lichess ratings still come back.
    static func fetch(chessComHandle: String, lichessHandle: String) async -> [String: Int] {
        async let chesscom = fetchChessCom(handle: chessComHandle)
        async let lichess = fetchLichess(handle: lichessHandle)
        return await chesscom.merging(lichess) { a, _ in a }
    }

    // MARK: Chess.com — /pub/player/{user}/stats

    private struct ChessComStatsResponse: Decodable {
        struct Entry: Decodable {
            struct Snapshot: Decodable { let rating: Int? }
            let last: Snapshot?
        }
        let chess_bullet: Entry?
        let chess_blitz: Entry?
        let chess_rapid: Entry?
    }

    private static func fetchChessCom(handle: String) async -> [String: Int] {
        let clean = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.chess.com/pub/player/\(encoded)/stats")
        else { return [:] }

        var request = URLRequest(url: url)
        request.setValue("Tabia/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ChessComStatsResponse.self, from: data)
        else { return [:] }

        var out: [String: Int] = [:]
        if let r = decoded.chess_bullet?.last?.rating { out["chesscom.bullet"] = r }
        if let r = decoded.chess_blitz?.last?.rating  { out["chesscom.blitz"] = r }
        if let r = decoded.chess_rapid?.last?.rating  { out["chesscom.rapid"] = r }
        return out
    }

    // MARK: Lichess — /api/user/{user}

    private struct LichessUserResponse: Decodable {
        struct Perf: Decodable { let rating: Int? }
        let perfs: [String: Perf]?
    }

    private static func fetchLichess(handle: String) async -> [String: Int] {
        let clean = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://lichess.org/api/user/\(encoded)")
        else { return [:] }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(LichessUserResponse.self, from: data),
              let perfs = decoded.perfs
        else { return [:] }

        var out: [String: Int] = [:]
        for tc in timeClasses {
            if let r = perfs[tc]?.rating { out["lichess.\(tc)"] = r }
        }
        return out
    }
}
