import Foundation
import SwiftData

// MARK: - Repertoire Side (color)

enum RepertoireSide: String, Codable, CaseIterable {
    case white
    case black

    var displayName: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        }
    }
}

// MARK: - Node Ownership

/// Tags a node with who owns the move and its strategic weight.
/// User-side moves: `mineMain` is the chosen line, `mineAlternative` is a backup option.
/// Opponent-side moves: branched by likelihood / importance.
enum NodeOwnership: String, Codable, CaseIterable {
    case mineMain         = "mine_main"
    case mineAlternative  = "mine_alt"
    case opponentCritical = "opp_critical"
    case opponentSideline = "opp_sideline"
    case opponentUnusual  = "opp_unusual"

    var isUserSide: Bool {
        self == .mineMain || self == .mineAlternative
    }

    var displayName: String {
        switch self {
        case .mineMain:         return "Main"
        case .mineAlternative:  return "Alternative"
        case .opponentCritical: return "Critical"
        case .opponentSideline: return "Sideline"
        case .opponentUnusual:  return "Unusual"
        }
    }
}

// MARK: - Training Stats (FSRS-lite spaced repetition)

/// Spaced-repetition state for one decision. Uses an FSRS-lite model (stability + difficulty) rather
/// than SM-2: difficulty is mean-reverting so correct answers can't ratchet a card into "ease hell",
/// and post-lapse stability is estimated from history instead of blindly reset — fewer reviews for
/// the same retention. `stability`/`difficulty` are optional so pre-FSRS stored data still decodes
/// (a nil stability means "new, first review"). SM-2's `easeFactor` is retained only for decode
/// compatibility and is no longer used.
struct TrainingStats: Codable, Hashable {
    var lastReviewed: Date?
    var nextDue: Date?
    var intervalDays: Double = 0
    var easeFactor: Double = 2.5      // legacy (SM-2); unused by FSRS
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var avgResponseTimeMs: Double?
    var stability: Double?            // FSRS memory stability (days)
    var difficulty: Double?          // FSRS difficulty [1, 10]

    // FSRS-5 default parameters + curve constants.
    private static let w: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
        0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621
    ]
    private static let DECAY = -0.5
    private static let FACTOR = 19.0 / 81.0
    private static let R_TARGET = 0.9

    private static func clampD(_ d: Double) -> Double { min(10, max(1, d)) }
    /// Initial difficulty for a first review at grade `g` (1…4).
    private static func initialDifficulty(_ g: Int) -> Double {
        clampD(w[4] - exp(w[5] * Double(g - 1)) + 1)
    }
    /// Interval (days) that lands the item at the target retention given its stability.
    private static func interval(forStability s: Double) -> Double {
        max(1, (s / FACTOR) * (pow(R_TARGET, 1 / DECAY) - 1))
    }

    /// Grade scale (Anki-style), mapped by the drill from move correctness + response latency:
    /// 1 = Again (wrong / relapse), 2 = revealed answer (soft lapse), 3 = Hard (correct but slow),
    /// 4 = Good (correct, normal), 5 = Easy (correct, instant).
    /// Applies one FSRS-lite review and returns the updated stats.
    func appliedReview(quality: Int, responseMs: Double? = nil, at now: Date = Date()) -> TrainingStats {
        var s = self
        // Map the 5-point drill grade to an FSRS grade 1…4 (Again/Hard/Good/Easy).
        let g = quality <= 2 ? 1 : min(4, quality - 1)
        let w = TrainingStats.w

        // Bookkeeping used by the dashboard / adaptive latency (not by the scheduler itself).
        if quality < 3 { s.wrongCount += 1 } else { s.correctCount += 1 }
        if let ms = responseMs {
            s.avgResponseTimeMs = s.avgResponseTimeMs.map { 0.8 * $0 + 0.2 * ms } ?? ms
        }

        let newS: Double
        let newD: Double

        if let stab = s.stability, let diff = s.difficulty, let last = s.lastReviewed {
            // Review of an existing item.
            let elapsed = max(0, now.timeIntervalSince(last) / 86_400)
            let r = pow(1 + TrainingStats.FACTOR * elapsed / stab, TrainingStats.DECAY)  // retrievability

            // Difficulty: linear damping toward the update, then mean-reversion to the "easy" anchor.
            let deltaD = -w[6] * Double(g - 3)
            var d = diff + deltaD * (10 - diff) / 9
            d = w[7] * TrainingStats.initialDifficulty(4) + (1 - w[7]) * d
            newD = TrainingStats.clampD(d)

            if g == 1 {
                // Lapse: post-lapse stability is estimated, never above the current stability.
                let est = w[11] * pow(newD, -w[12]) * (pow(stab + 1, w[13]) - 1) * exp(w[14] * (1 - r))
                newS = max(0.1, min(est, stab))
            } else {
                let hardPenalty = g == 2 ? w[15] : 1.0
                let easyBonus = g == 4 ? w[16] : 1.0
                let inc = exp(w[8]) * (11 - newD) * pow(stab, -w[9])
                        * (exp(w[10] * (1 - r)) - 1) * hardPenalty * easyBonus
                newS = stab * (1 + inc)
            }
        } else {
            // First review of a new item.
            newS = max(0.1, w[g - 1])
            newD = TrainingStats.initialDifficulty(g)
        }

        s.stability = newS
        s.difficulty = newD
        var days = TrainingStats.interval(forStability: newS)
        if g == 1 { days = max(10.0 / 1440.0, min(days, 2.0)) }   // relearn soon after a lapse
        s.intervalDays = days
        s.lastReviewed = now
        s.nextDue = now.addingTimeInterval(days * 86_400)
        return s
    }
}

// MARK: - Repertoire Folder

@Model
final class RepertoireFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Optional hex string (e.g. "0x30D158") used for the card accent. Nil = auto-rotate by index.
    var accentColorHex: String?
    var dateCreated: Date
    var order: Int

    @Relationship(deleteRule: .nullify, inverse: \Repertoire.folder)
    var repertoires: [Repertoire] = []

    init(id: UUID = UUID(),
         name: String,
         accentColorHex: String? = nil,
         dateCreated: Date = Date(),
         order: Int = 0) {
        self.id = id
        self.name = name
        self.accentColorHex = accentColorHex
        self.dateCreated = dateCreated
        self.order = order
    }
}

// MARK: - Repertoire

/// A single, focused opening repertoire for one color (e.g. "Najdorf Sicilian").
/// The repertoire's tree starts from `startingFEN`, not necessarily move 1.
@Model
final class Repertoire {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Raw value of RepertoireSide. Stored as String for SwiftData compatibility.
    var sideRaw: String
    var summary: String

    /// The position the repertoire tree starts from. Allows mid-game starts (e.g. Najdorf after 5...a6).
    var startingFEN: String
    /// Move sequence (UCI) from initial position leading to startingFEN. Used to detect when
    /// a played game has reached this repertoire's starting position.
    var startingMoveSequence: [String]

    /// Optional ECO range bounds (e.g. "B90"…"B99"). Either may be nil.
    var ecoRangeStart: String?
    var ecoRangeEnd: String?

    var tags: [String]
    var dateCreated: Date
    var dateModified: Date

    /// Source string: "manual" / "lichess-study:xyz" / "chess.com:@user" / "pgn:filename.pgn"
    var importSource: String?

    var folder: RepertoireFolder?

    /// All nodes belonging to this repertoire. Tree shape is encoded via RepertoireNode.parent / children.
    @Relationship(deleteRule: .cascade, inverse: \RepertoireNode.repertoire)
    var nodes: [RepertoireNode] = []

    /// Pointer to the root node id in `nodes`. The root represents `startingFEN`; its children are
    /// the first moves from that position.
    var rootNodeId: UUID?

    var side: RepertoireSide {
        get { RepertoireSide(rawValue: sideRaw) ?? .white }
        set { sideRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(),
         name: String,
         side: RepertoireSide,
         summary: String = "",
         startingFEN: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
         startingMoveSequence: [String] = [],
         ecoRangeStart: String? = nil,
         ecoRangeEnd: String? = nil,
         tags: [String] = [],
         dateCreated: Date = Date(),
         dateModified: Date = Date(),
         importSource: String? = nil,
         folder: RepertoireFolder? = nil) {
        self.id = id
        self.name = name
        self.sideRaw = side.rawValue
        self.summary = summary
        self.startingFEN = startingFEN
        self.startingMoveSequence = startingMoveSequence
        self.ecoRangeStart = ecoRangeStart
        self.ecoRangeEnd = ecoRangeEnd
        self.tags = tags
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.importSource = importSource
        self.folder = folder
    }

    /// Total node count (cheap — relationship array length).
    var nodeCount: Int { nodes.count }

    /// Number of your-side decision points in the tree.
    var userMoveCount: Int { nodes.filter { $0.isUserMove }.count }

    /// ECO range display ("B90–B99" or "B90" or nil).
    var ecoRangeDisplay: String? {
        switch (ecoRangeStart, ecoRangeEnd) {
        case (nil, nil): return nil
        case (let s?, nil): return s
        case (nil, let e?): return e
        case (let s?, let e?): return s == e ? s : "\(s)–\(e)"
        }
    }
}

// MARK: - Repertoire Node (tree)

@Model
final class RepertoireNode {
    @Attribute(.unique) var id: UUID
    var repertoire: Repertoire?

    var parent: RepertoireNode?
    @Relationship(deleteRule: .cascade, inverse: \RepertoireNode.parent)
    var children: [RepertoireNode] = []

    /// UCI move that led to this node from its parent's position. Nil for the root node.
    var uciMove: String?
    /// Standard algebraic notation cache.
    var san: String?
    /// FEN of the resulting position (cached so we can FEN-index without recomputing).
    var fen: String

    /// True when the side-to-move at the PARENT position is the repertoire owner.
    /// I.e. this move was played by the user. Cached for fast filtering.
    var isUserMove: Bool

    var ownershipRaw: String
    /// For user-side moves: the single primary choice the drill expects. Backup moves have isPrimary == false.
    /// For opponent-side moves: always false (concept doesn't apply).
    var isPrimary: Bool

    var annotation: String
    /// PGN-style glyph: "!", "?!", "!!", "??", "!?", "?!"
    var evalGlyph: String?
    var ideaTags: [String]
    var linkedECO: String?
    /// "Important for me" (ChessBase double-asterisk): flags a decision the user especially wants to
    /// nail. Surfaced in the knowledge dashboard's weak-spots.
    var isImportant: Bool = false

    /// Game IDs (UUID string form) where the user reached this position in real play.
    var gameLinkIdStrings: [String]

    /// Embedded training stats (Codable struct, not separate @Model).
    /// Only meaningful when `isUserMove == true`.
    var training: TrainingStats?

    /// Date this node was last edited (for change tracking).
    var dateModified: Date

    var ownership: NodeOwnership {
        get { NodeOwnership(rawValue: ownershipRaw) ?? (isUserMove ? .mineMain : .opponentCritical) }
        set { ownershipRaw = newValue.rawValue }
    }

    var gameLinkIds: [UUID] {
        get { gameLinkIdStrings.compactMap { UUID(uuidString: $0) } }
        set { gameLinkIdStrings = newValue.map { $0.uuidString } }
    }

    init(id: UUID = UUID(),
         repertoire: Repertoire? = nil,
         parent: RepertoireNode? = nil,
         uciMove: String? = nil,
         san: String? = nil,
         fen: String,
         isUserMove: Bool,
         ownership: NodeOwnership,
         isPrimary: Bool = true,
         annotation: String = "",
         evalGlyph: String? = nil,
         ideaTags: [String] = [],
         linkedECO: String? = nil,
         gameLinkIds: [UUID] = [],
         training: TrainingStats? = nil,
         dateModified: Date = Date()) {
        self.id = id
        self.repertoire = repertoire
        self.parent = parent
        self.uciMove = uciMove
        self.san = san
        self.fen = fen
        self.isUserMove = isUserMove
        self.ownershipRaw = ownership.rawValue
        self.isPrimary = isPrimary
        self.annotation = annotation
        self.evalGlyph = evalGlyph
        self.ideaTags = ideaTags
        self.linkedECO = linkedECO
        self.gameLinkIdStrings = gameLinkIds.map { $0.uuidString }
        self.training = training
        self.dateModified = dateModified
    }
}

// MARK: - Position Schedule (transposition-aware SRS unit)

/// The spaced-repetition unit for a repertoire DECISION, keyed by the Zobrist hash of the position
/// where the user is to move — NOT by tree node. The same position reached via different move
/// orders collapses to one schedule, so a decision isn't drilled twice and updating one branch
/// doesn't leave a transposing branch stale. Replaces the legacy per-node `RepertoireNode.training`
/// for scheduling (that field is retained only so old data can be migrated once).
@Model
final class PositionSchedule {
    @Attribute(.unique) var id: UUID
    /// Owning repertoire. Schedules are scoped per repertoire (the same position in two repertoires
    /// is trained independently).
    var repertoireId: UUID
    /// Zobrist bit-pattern (Int64) of the position where the decision is made.
    var positionHash: Int64
    var stats: TrainingStats

    init(id: UUID = UUID(), repertoireId: UUID, positionHash: Int64, stats: TrainingStats = TrainingStats()) {
        self.id = id
        self.repertoireId = repertoireId
        self.positionHash = positionHash
        self.stats = stats
    }
}
