import Foundation

/// A snapshot of how well a repertoire is known, derived from the transposition-aware position
/// schedules. This is the highest-value screen for an improving player: what you know, what's due,
/// and which lines keep tripping you up.
struct RepertoireKnowledge {
    /// Distinct user decisions (deduped across transpositions).
    let totalDecisions: Int
    /// Decisions that have been reviewed at least once.
    let drilledDecisions: Int
    /// Decisions due now (reviewed & overdue, or never drilled).
    let dueNow: Int
    /// Decisions whose interval has reached maturity (≥ 21 days).
    let matureDecisions: Int
    /// Mean estimated retention over the drilled decisions (0–100).
    let knowledgePercent: Double
    /// Fraction of decisions that have been drilled at all (0–100).
    let coveragePercent: Double
    /// Decisions flagged "Important for me".
    let importantDecisions: Int
    /// Lines that keep getting missed, worst first.
    let leeches: [Leech]

    struct Leech: Identifiable {
        let id = UUID()
        /// The correct move at the leech decision.
        let san: String
        /// SAN moves leading to the decision position.
        let pathSAN: [String]
        let wrongCount: Int
        let correctCount: Int
        let isImportant: Bool
    }

    static let empty = RepertoireKnowledge(
        totalDecisions: 0, drilledDecisions: 0, dueNow: 0, matureDecisions: 0,
        knowledgePercent: 0, coveragePercent: 0, importantDecisions: 0, leeches: [])
}

enum RepertoireStatsBuilder {

    /// Build the knowledge snapshot. Call on the main thread (reads SwiftData model objects);
    /// `schedules` is the position-keyed stats map from `RepertoireDatabase.positionSchedules`.
    static func build(repertoire: Repertoire,
                      schedules: [Int64: TrainingStats],
                      now: Date = Date(),
                      leechThreshold: Int = 3,
                      matureDays: Double = 21) -> RepertoireKnowledge {
        guard let root = repertoire.nodes.first(where: { $0.id == repertoire.rootNodeId })
                ?? repertoire.nodes.first(where: { $0.parent == nil }) else {
            return .empty
        }

        // Collect distinct decisions, keyed by the position they're made from, keeping one
        // representative node (move + line + importance) per key.
        var representative: [Int64: (san: String, path: [String], important: Bool)] = [:]
        collect(node: root, path: [], into: &representative)

        var drilled = 0, due = 0, mature = 0, important = 0
        var retentionSum = 0.0
        var leeches: [RepertoireKnowledge.Leech] = []

        for (key, rep) in representative {
            if rep.important { important += 1 }
            let stats = schedules[key]
            if let s = stats, s.lastReviewed != nil {
                drilled += 1
                retentionSum += retention(s, now: now)
                if s.intervalDays >= matureDays { mature += 1 }
                if (s.nextDue ?? .distantPast) <= now { due += 1 }
                if s.wrongCount >= leechThreshold {
                    leeches.append(.init(san: rep.san, pathSAN: rep.path,
                                         wrongCount: s.wrongCount, correctCount: s.correctCount,
                                         isImportant: rep.important))
                }
            } else {
                // Never drilled → due to learn.
                due += 1
            }
        }

        let total = representative.count
        let knowledge = drilled > 0 ? (retentionSum / Double(drilled)) * 100 : 0
        let coverage = total > 0 ? (Double(drilled) / Double(total)) * 100 : 0
        // Important leeches first, then by miss count.
        leeches.sort { ($0.isImportant ? 1 : 0, $0.wrongCount) > ($1.isImportant ? 1 : 0, $1.wrongCount) }

        return RepertoireKnowledge(
            totalDecisions: total,
            drilledDecisions: drilled,
            dueNow: due,
            matureDecisions: mature,
            knowledgePercent: knowledge,
            coveragePercent: coverage,
            importantDecisions: important,
            leeches: leeches)
    }

    /// Estimated current retention for a scheduled item: the SM-2 interval targets ~90% retention at
    /// its due date, so R decays as `0.9^(elapsed / interval)` — >0.9 before due, <0.9 when overdue.
    private static func retention(_ s: TrainingStats, now: Date) -> Double {
        guard let last = s.lastReviewed, s.intervalDays > 0 else { return 0 }
        let elapsedDays = now.timeIntervalSince(last) / 86_400
        let r = pow(0.9, elapsedDays / s.intervalDays)
        return min(1, max(0, r))
    }

    private static func collect(node: RepertoireNode,
                                path: [String],
                                into representative: inout [Int64: (san: String, path: [String], important: Bool)]) {
        if node.isUserMove, node.isPrimary,
           let parent = node.parent, !parent.fen.isEmpty, let board = ChessBoard(fen: parent.fen) {
            let key = Zobrist.sqliteKey(board)
            if let existing = representative[key] {
                // Another node reaches the same decision (transposition): OR the importance flag.
                if node.isImportant && !existing.important {
                    representative[key] = (existing.san, existing.path, true)
                }
            } else {
                // `path` includes this node's own move (the answer); the line to the decision
                // position is everything before it.
                representative[key] = (node.san ?? node.uciMove ?? "?", Array(path.dropLast()), node.isImportant)
            }
        }
        for child in node.children {
            collect(node: child,
                    path: path + [child.san ?? child.uciMove ?? "?"],
                    into: &representative)
        }
    }
}
