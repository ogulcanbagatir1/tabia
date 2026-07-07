import Foundation
import SwiftUI

/// Line-based drill. Instead of showing one isolated position and asking for one move, the user
/// plays THEIR side through a whole repertoire line — from the starting position to the leaf —
/// against an auto-replying opponent whose replies are sampled from the tree (weighted toward
/// branches that still contain due material). Any repertoire move is accepted at each decision;
/// a miss reveals the answer and keeps the decision queued for a later play-through.
final class DrillSession: ObservableObject {

    enum Phase {
        case empty            // nothing due
        case userToMove       // waiting for the user's move at `currentNode`
        case opponentThinking // opponent about to auto-reply (View animates the pause)
        case userWrong        // user missed; the answer is revealed
        case lineComplete     // reached a leaf / cutoff
        case completed        // no more due decisions to drill
    }

    private enum Turn { case user, opponent }

    /// How opponent replies are sampled among the tree's covered replies.
    /// - realistic: ∝ real-game frequency (rehearse what you'll actually face)
    /// - critical:  bias toward critical / most-played replies (tournament prep)
    /// - breadth:   over-sample rare replies so nothing rots
    enum ReplyMode: String, CaseIterable {
        case realistic, critical, breadth, opponent
        var label: String {
            switch self {
            case .realistic: return "Realistic"
            case .critical:  return "Critical"
            case .breadth:   return "Breadth"
            case .opponent:  return "Opponent"
            }
        }
    }
    @Published var replyMode: ReplyMode = .realistic

    /// Optional book of a specific opponent's move frequencies (tournament prep). When set and the
    /// mode is `.opponent`, replies are sampled from what THIS opponent actually plays.
    var opponentBook: OpponentBook? {
        didSet { objectWillChange.send() }
    }
    var hasOpponentBook: Bool { !(opponentBook?.isEmpty ?? true) }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .empty
    /// Bumped whenever the display board should be re-synced (advance, revert, new line).
    @Published private(set) var boardVersion: Int = 0
    @Published private(set) var successCount = 0
    @Published private(set) var failCount = 0
    @Published private(set) var lineCount = 0

    // MARK: - Authoritative position

    let repertoire: Repertoire
    private let repertoireDB: RepertoireDatabase
    /// Optional reference game database for frequency-weighted opponent replies. When absent or
    /// empty, opponent replies fall back to the tree's ownership heuristic.
    private let referenceDB: ReferenceDatabase?
    private(set) var board: ChessBoard
    /// The node whose resulting position is currently on the board. Its children are the candidate
    /// next moves (all the same side to move).
    private(set) var currentNode: RepertoireNode

    // MARK: - Feedback (meaningful in .userWrong / .userToMove)

    /// All acceptable user-side moves at the current decision (main + alternatives).
    private(set) var expectedNodes: [RepertoireNode] = []
    /// What the user attempted when wrong ("" when they asked to reveal).
    private(set) var attemptedUCI: String = ""
    /// SAN of the move just played into the line (for the "you played …" nudge).
    private(set) var lastPlayedSAN: String?
    /// True when the last correct answer was an accepted alternative (not the primary).
    private(set) var lastWasAlternative = false

    /// Reference-DB stats for the primary move at the missed decision. Computed only when the answer
    /// is revealed (never during active recall, so it can't cue the answer). Nil when no DB coverage.
    struct ExpectedMoveReference {
        let san: String
        let games: Int
        /// Score from the USER's perspective (0–100).
        let userScorePercent: Double
        let positionGames: Int
    }
    private(set) var expectedReference: ExpectedMoveReference?

    // MARK: - Coverage bookkeeping

    private let rootNode: RepertoireNode
    private let plannedTargets: Int
    /// Decisions are keyed by the Zobrist hash of the position they're made from, so transposing
    /// paths share one target and one schedule.
    private var remainingTargets: Set<Int64> = []
    private var masteredTargets: Set<Int64> = []
    /// user-primary node id → the decision (parent) position key, precomputed once.
    private var decisionKeyByNode: [UUID: Int64] = [:]
    /// Live copy of the position schedules' stats, for adaptive latency grading.
    private var scheduleStats: [Int64: TrainingStats] = [:]
    private var presentedAt = Date()
    private var plyInLine = 0
    private let maxLines: Int
    private let maxPlyPerLine = 60

    var total: Int { plannedTargets }
    var masteredCount: Int { masteredTargets.count }
    var isFinished: Bool { if case .completed = phase { return true } else { return false } }

    /// Compact, comparable snapshot used to drive SwiftUI side-effects (board sync, opponent auto-reply).
    var statePhase: String {
        switch phase {
        case .empty:            return "empty"
        case .userToMove:       return "user:\(currentNode.id):\(boardVersion)"
        case .opponentThinking: return "opp:\(currentNode.id):\(boardVersion)"
        case .userWrong:        return "wrong:\(currentNode.id):\(boardVersion)"
        case .lineComplete:     return "line:\(lineCount)"
        case .completed:        return "done"
        }
    }

    // MARK: - Init

    init(repertoire: Repertoire,
         repertoireDB: RepertoireDatabase,
         referenceDB: ReferenceDatabase? = nil,
         includeUndrilled: Bool = true) {
        self.repertoire = repertoire
        self.repertoireDB = repertoireDB
        self.referenceDB = referenceDB

        let start = ChessBoard(fen: repertoire.startingFEN) ?? ChessBoard()
        self.board = start

        let resolvedRoot = repertoire.nodes.first(where: { $0.id == repertoire.rootNodeId })
            ?? repertoire.nodes.first(where: { $0.parent == nil })
        let root = resolvedRoot ?? RepertoireNode(
            fen: start.getFEN(), isUserMove: false, ownership: .opponentCritical, isPrimary: false)
        self.rootNode = root
        self.currentNode = root

        // Position schedules (transposition-aware). Migrate any legacy per-node training once,
        // then load the schedule stats keyed by position hash.
        repertoireDB.migrateTrainingIfNeeded(repertoire)
        self.scheduleStats = repertoireDB.positionSchedules(for: repertoire.id).mapValues { $0.stats }

        // Enumerate due decisions, keyed by the Zobrist hash of the position they're made from.
        // Distinct positions collapse transpositions; undrilled positions count as due.
        let now = Date()
        var due = Set<Int64>()
        var keyByNode: [UUID: Int64] = [:]
        for n in repertoire.nodes where n.isUserMove && n.isPrimary && n.uciMove != nil {
            guard let parent = n.parent, !parent.fen.isEmpty, let b = ChessBoard(fen: parent.fen) else { continue }
            let key = Zobrist.sqliteKey(b)
            keyByNode[n.id] = key
            let isDue: Bool
            if let s = scheduleStats[key] { isDue = (s.nextDue ?? .distantPast) <= now }
            else { isDue = includeUndrilled }
            if isDue { due.insert(key) }
        }
        self.decisionKeyByNode = keyByNode
        self.remainingTargets = due
        self.plannedTargets = due.count
        self.maxLines = max(20, due.count * 3)

        guard plannedTargets > 0, resolvedRoot != nil else {
            self.phase = .empty
            return
        }
        beginLine()
    }

    // MARK: - Line lifecycle

    private func beginLine() {
        board = ChessBoard(fen: repertoire.startingFEN) ?? ChessBoard()
        currentNode = rootNode
        plyInLine = 0
        lastPlayedSAN = nil
        lastWasAlternative = false
        boardVersion += 1
        advanceToNextDecision()
    }

    /// From `currentNode`, decide what happens next: user to move, opponent to move, or leaf.
    private func advanceToNextDecision() {
        switch classify(currentNode) {
        case .none:
            finishLine()
        case .some(.user):
            presentUserDecision()
        case .some(.opponent):
            phase = .opponentThinking   // the View pauses, then calls playOpponentReply()
        }
    }

    private func presentUserDecision() {
        presentedAt = Date()
        expectedNodes = currentNode.children.filter { $0.isUserMove }
        attemptedUCI = ""
        expectedReference = nil   // don't cue the answer during recall
        phase = .userToMove
    }

    /// Reference-DB stats for the primary expected move at the current decision, from the user's
    /// perspective. Only call when revealing the answer.
    private func computeExpectedReference() -> ExpectedMoveReference? {
        guard let referenceDB, referenceDB.isAvailable, referenceDB.gameCount > 0 else { return nil }
        let userKids = currentNode.children.filter { $0.isUserMove }
        guard let primary = primaryDecision(userKids), let uci = primary.uciMove else { return nil }
        let result = referenceDB.explorer(board: board)
        guard result.total > 0, let entry = result.moves.first(where: { $0.uci == uci }) else { return nil }
        let userColor: PieceColor = repertoire.side == .white ? .white : .black
        let userScore = userColor == .white ? entry.scorePercent : (100.0 - entry.scorePercent)
        return ExpectedMoveReference(san: entry.san, games: entry.total,
                                     userScorePercent: userScore, positionGames: result.total)
    }

    private func finishLine() {
        lineCount += 1
        phase = .lineComplete
    }

    /// Advance to the next play-through, or complete the session when coverage is done.
    func nextLine() {
        if remainingTargets.isEmpty || lineCount >= maxLines {
            phase = .completed
            return
        }
        beginLine()
    }

    // MARK: - User actions

    func attemptUserMove(_ uci: String) {
        guard phase == .userToMove else { return }
        let latencyMs = Date().timeIntervalSince(presentedAt) * 1000
        let userKids = currentNode.children.filter { $0.isUserMove }
        guard let primary = primaryDecision(userKids) else { return }

        let key = decisionKey()   // Zobrist of the current (decision) position
        if let played = userKids.first(where: { $0.uciMove == uci }) {
            // Correct: the primary line or an accepted alternative.
            successCount += 1
            masteredTargets.insert(key)
            remainingTargets.remove(key)
            let quality = gradeForCorrect(playedPrimary: played.isPrimary, latencyMs: latencyMs, key: key)
            record(quality: quality, responseMs: latencyMs, key: key)
            lastPlayedSAN = played.san ?? played.uciMove
            lastWasAlternative = !played.isPrimary
            stepInto(played)
            advanceToNextDecision()
        } else {
            // Not in the repertoire → Again on the decision; reveal and keep it queued.
            failCount += 1
            record(quality: 1, responseMs: latencyMs, key: key)
            attemptedUCI = uci
            expectedNodes = userKids
            expectedReference = computeExpectedReference()
            boardVersion += 1        // force the View to revert the illegal-for-repertoire move
            phase = .userWrong
        }
    }

    /// "Show answer" → soft lapse (grade 2). Gentler than a wrong guess but still a lapse.
    func revealAndFail() {
        guard phase == .userToMove else { return }
        let latencyMs = Date().timeIntervalSince(presentedAt) * 1000
        let userKids = currentNode.children.filter { $0.isUserMove }
        guard primaryDecision(userKids) != nil else { return }
        failCount += 1
        record(quality: 2, responseMs: latencyMs, key: decisionKey())
        attemptedUCI = ""
        expectedNodes = userKids
        expectedReference = computeExpectedReference()
        phase = .userWrong
    }

    /// After a miss, play the main move for the user and continue the line so they see the rest.
    func continueAfterWrong() {
        guard phase == .userWrong else { return }
        let userKids = currentNode.children.filter { $0.isUserMove }
        guard let primary = primaryDecision(userKids) else { finishLine(); return }
        lastPlayedSAN = primary.san ?? primary.uciMove
        lastWasAlternative = false
        stepInto(primary)
        advanceToNextDecision()
    }

    /// Skip = schedule-neutral. Play the main move without grading and keep going.
    func skip() {
        guard phase == .userToMove else { return }
        let userKids = currentNode.children.filter { $0.isUserMove }
        guard let primary = primaryDecision(userKids) else { finishLine(); return }
        lastPlayedSAN = primary.san ?? primary.uciMove
        lastWasAlternative = false
        stepInto(primary)
        advanceToNextDecision()
    }

    // MARK: - Opponent

    /// Called by the View after a short "thinking" pause. Samples and plays the opponent's reply.
    func playOpponentReply() {
        guard phase == .opponentThinking else { return }
        guard plyInLine < maxPlyPerLine, let reply = chooseOpponentReply(at: currentNode) else {
            finishLine()
            return
        }
        lastPlayedSAN = reply.san ?? reply.uciMove
        lastWasAlternative = false
        stepInto(reply)
        advanceToNextDecision()
    }

    /// Weighted opponent-reply selection. First biases toward branches that still contain a due
    /// decision (so the session rehearses what's due), then weights the reply itself by real-game
    /// frequency from the reference database (transposition-aware), per the active `replyMode`.
    /// Falls back to the ownership heuristic when the DB doesn't cover the position.
    private func chooseOpponentReply(at node: RepertoireNode) -> RepertoireNode? {
        let kids = node.children.filter { !$0.isUserMove }
        guard !kids.isEmpty else { return nil }

        let withDue = kids.filter { subtreeHasRemainingTarget($0) }
        let pool = withDue.isEmpty ? kids : withDue

        let dbTotals = replyFrequencies()
        let weights = pool.map { child -> Double in
            let dbTotal = child.uciMove.flatMap { dbTotals[$0] } ?? 0
            let ownershipWeight = weight(for: child.ownership)
            guard !dbTotals.isEmpty else { return ownershipWeight }   // no coverage for this position

            switch replyMode {
            case .realistic, .opponent:
                // ∝ frequency (of games / of this opponent); +0.5 keeps covered-but-rare replies reachable.
                return Double(dbTotal) + 0.5
            case .critical:
                let base = Double(dbTotal) + 0.5
                return base * (child.ownership == .opponentCritical ? 3.0 : 1.0)
            case .breadth:
                // Anti-correlate with frequency so rare/neglected lines get rehearsed.
                return 1.0 / (1.0 + Double(dbTotal))
            }
        }
        return weightedPick(pool, weights)
    }

    /// Frequencies used to weight the opponent's reply at the current position: the opponent book in
    /// `.opponent` mode (falling back to the reference DB where the book is silent), else the reference DB.
    private func replyFrequencies() -> [String: Int] {
        if replyMode == .opponent, let book = opponentBook {
            if let f = book.frequencies(at: Zobrist.sqliteKey(board)), !f.isEmpty { return f }
        }
        return referenceFrequencies()
    }

    /// Reference-DB next-move frequencies for the current position, keyed by UCI. Empty when the
    /// reference database is unavailable, empty, or has no games reaching this position.
    private func referenceFrequencies() -> [String: Int] {
        guard let referenceDB, referenceDB.isAvailable, referenceDB.gameCount > 0 else { return [:] }
        let result = referenceDB.explorer(board: board)
        guard !result.moves.isEmpty else { return [:] }
        var map: [String: Int] = [:]
        for m in result.moves { map[m.uci] = m.total }
        return map
    }

    private func weightedPick(_ pool: [RepertoireNode], _ weights: [Double]) -> RepertoireNode? {
        let totalW = weights.reduce(0, +)
        guard totalW > 0 else { return pool.randomElement() }
        var r = Double.random(in: 0..<totalW)
        for (i, w) in weights.enumerated() {
            if r < w { return pool[i] }
            r -= w
        }
        return pool.last
    }

    private func weight(for ownership: NodeOwnership) -> Double {
        switch ownership {
        case .opponentCritical: return 3
        case .opponentSideline: return 2
        case .opponentUnusual:  return 1
        default:                return 2
        }
    }

    private func subtreeHasRemainingTarget(_ node: RepertoireNode) -> Bool {
        if let key = decisionKeyByNode[node.id], remainingTargets.contains(key) { return true }
        for child in node.children where subtreeHasRemainingTarget(child) { return true }
        return false
    }

    // MARK: - Grading

    private func gradeForCorrect(playedPrimary: Bool, latencyMs: Double, key: Int64) -> Int {
        guard playedPrimary else { return 4 }            // accepted alternative → Good
        if latencyMs < 1500 { return 5 }                 // instant → Easy
        let median = scheduleStats[key]?.avgResponseTimeMs ?? 4000
        if latencyMs > max(8000, 3 * median) { return 3 } // hesitant → Hard
        return 4                                          // normal → Good
    }

    /// Zobrist key of the current (decision) position on the authoritative board.
    private func decisionKey() -> Int64 { Zobrist.sqliteKey(board) }

    /// Apply a review to the transposition-aware position schedule and cache the updated stats.
    private func record(quality: Int, responseMs: Double, key: Int64) {
        let updated = repertoireDB.recordReview(
            repertoireId: repertoire.id, positionHash: key, quality: quality, responseMs: responseMs)
        scheduleStats[key] = updated
    }

    // MARK: - Tree helpers

    private func classify(_ node: RepertoireNode) -> Turn? {
        guard let first = node.children.first else { return nil }  // leaf
        return first.isUserMove ? .user : .opponent
    }

    private func primaryDecision(_ userKids: [RepertoireNode]) -> RepertoireNode? {
        userKids.first(where: { $0.isPrimary }) ?? userKids.first
    }

    /// Apply a node's move to the authoritative board and move the cursor onto it.
    private func stepInto(_ node: RepertoireNode) {
        if let uci = node.uciMove, let move = Self.parseUCI(uci, board: board) {
            _ = board.makeMove(move)
        }
        currentNode = node
        plyInLine += 1
        boardVersion += 1
    }

    // MARK: - UCI ↔ Move

    private static func parseUCI(_ uci: String, board: ChessBoard) -> Move? {
        guard uci.count >= 4 else { return nil }
        let chars = Array(uci)
        guard let fromFileAscii = chars[0].asciiValue,
              let toFileAscii = chars[2].asciiValue else { return nil }
        let fromFile = Int(fromFileAscii) - Int(Character("a").asciiValue!)
        guard let fromRank = Int(String(chars[1])) else { return nil }
        let toFile = Int(toFileAscii) - Int(Character("a").asciiValue!)
        guard let toRank = Int(String(chars[3])) else { return nil }
        let from = Position(fromFile, fromRank - 1)
        let to = Position(toFile, toRank - 1)
        guard let piece = board.pieceAt(from) else { return nil }
        var promotionType: PieceType? = nil
        if chars.count >= 5 {
            switch chars[4] {
            case "q": promotionType = .queen
            case "r": promotionType = .rook
            case "b": promotionType = .bishop
            case "n": promotionType = .knight
            default: break
            }
        }
        let capturedPiece = board.pieceAt(to)
        let isEnPassant = piece.type == .pawn && from.file != to.file && capturedPiece == nil
        let isCastling = piece.type == .king && abs(from.file - to.file) == 2
        return Move(
            from: from, to: to, piece: piece,
            capturedPiece: isEnPassant ? board.pieceAt(Position(to.file, from.rank)) : capturedPiece,
            isEnPassant: isEnPassant,
            isCastling: isCastling,
            promotionType: promotionType
        )
    }

    static func uci(from move: Move) -> String {
        func sq(_ p: Position) -> String {
            let file = Character(UnicodeScalar(Int(Character("a").asciiValue!) + p.file)!)
            return "\(file)\(p.rank + 1)"
        }
        var s = sq(move.from) + sq(move.to)
        if let promo = move.promotionType {
            switch promo {
            case .queen:  s += "q"
            case .rook:   s += "r"
            case .bishop: s += "b"
            case .knight: s += "n"
            default: break
            }
        }
        return s
    }
}
