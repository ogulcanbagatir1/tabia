import Foundation
import SwiftUI

// MARK: - Analysis State

enum AnalysisState {
    case idle
    case analyzing
    case completed
    case cancelled
}

// MARK: - Move Quality

enum MoveQuality: String, CaseIterable {
    case brilliant = "!!"
    case great = "!"
    case best = "*"
    case book = "B"
    case good = "+"
    case okay = "o"
    case neutral = ""
    case inaccuracy = "?!"
    case mistake = "?"
    case blunder = "??"

    var label: String {
        switch self {
        case .brilliant: return "Brilliant"
        case .great: return "Great"
        case .best: return "Best"
        case .book: return "Book"
        case .good: return "Good"
        case .okay: return "Okay"
        case .neutral: return "Neutral"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        }
    }

    var color: Color {
        switch self {
        case .brilliant: return DS.moveBrilliant
        case .great: return DS.moveGreat
        case .best: return DS.moveBest
        case .book: return DS.moveBook
        case .good: return DS.moveGood
        case .okay: return DS.moveOkay
        case .neutral: return DS.moveNeutral
        case .inaccuracy: return DS.moveInaccuracy
        case .mistake: return DS.moveMistake
        case .blunder: return DS.moveBlunder
        }
    }

    /// Icon for display (SF Symbol name or nil for text-based annotations)
    var icon: String? {
        switch self {
        case .best: return "star.fill"
        case .book: return "book.fill"
        case .good: return "hand.thumbsup.fill"
        case .okay: return "checkmark"
        default: return nil
        }
    }
}

// MARK: - Move Classification

struct MoveClassification {
    let moveIndex: Int
    let quality: MoveQuality
    let cpLoss: Double
    let evalBefore: Double
    let evalAfter: Double
    let isWhiteMove: Bool
}

// MARK: - Game Analyzer

class GameAnalyzer: ObservableObject {
    @Published var state: AnalysisState = .idle
    @Published var currentMoveIndex: Int = 0
    @Published var totalMoves: Int = 0
    @Published var whiteAccuracy: Double = 0
    @Published var blackAccuracy: Double = 0
    @Published var evaluations: [Double] = []
    @Published var moveClassifications: [MoveClassification] = []

    /// The depth cap for analysis (set per review from the Fast/Balanced/Deep preset).
    var analysisDepth: Int = 22

    /// The movetime cap for analysis, in milliseconds (set per review from the preset).
    var analysisMovetime: Int = 800

    /// Positions to evaluate (board states from the main line)
    private var positions: [ChessBoard] = []

    /// Top 3 moves returned by engine for each position (UCI notation)
    private var topMoves: [[String]] = []

    /// Second-best line evaluation at each position (for ! and !! detection)
    private var secondBestEvals: [Double?] = []

    /// The main line nodes (for applying annotations after analysis)
    private var mainLineNodes: [GameNode] = []

    /// UCI moves played from root to each position (for opening book lookup)
    private var uciMovesAtPosition: [[String]] = []

    var isAnalyzing: Bool { state == .analyzing }
    var isCompleted: Bool { state == .completed }

    // MARK: - Analysis Control

    /// Start analyzing a game. Returns the first board to evaluate, or nil if no moves.
    func startAnalysis(gameTree: GameTree) -> ChessBoard? {
        // Collect main line positions
        mainLineNodes = gameTree.mainLine
        totalMoves = mainLineNodes.count // includes root

        guard totalMoves > 1 else {
            // No moves to analyze
            state = .completed
            whiteAccuracy = 100
            blackAccuracy = 100
            return nil
        }

        // Collect board states for each node in the main line
        positions = mainLineNodes.map { $0.boardState.copy() }

        // Build UCI move sequences for opening book lookup
        uciMovesAtPosition = []
        var uciMoves: [String] = []
        for node in mainLineNodes {
            uciMovesAtPosition.append(uciMoves)
            if let move = node.move {
                uciMoves.append(UCI.string(from: move))
            }
        }

        // Honour Settings › Engines › Review depth. Movetime moves with depth — a deeper cap is
        // pointless if the engine is cut off early. The old budgets (150–800 ms) were too short: the
        // per-position eval was noisy, so a move could look like a blunder from search wobble alone.
        // These give the engine enough time for stable evals, which is what the classifier grades on.
        switch AppSettings.shared.reviewDepthRaw {
        case "fast":
            analysisDepth = 16
            analysisMovetime = 350
        case "deep":
            analysisDepth = 30
            analysisMovetime = 1800
        default:   // "balanced"
            analysisDepth = 22
            analysisMovetime = 800
        }
        currentMoveIndex = 0
        evaluations = []
        topMoves = []
        secondBestEvals = []
        moveClassifications = []
        whiteAccuracy = 0
        blackAccuracy = 0
        state = .analyzing

        // Return first position (root) for evaluation
        return positions[0]
    }

    /// Called when the engine finishes evaluating a position.
    /// Stores the eval, best move, and 2nd-line eval. Advances the index.
    /// Returns the next board to evaluate, or nil when done.
    func onEngineFinished(engine: StockfishEngine) -> ChessBoard? {
        guard state == .analyzing else { return nil }

        // Store evaluation from engine
        let eval = engine.evaluation ?? 0
        evaluations.append(eval)

        // Store top 3 moves (first move from each PV line)
        var top3: [String] = []
        for lineId in 1...3 {
            if let line = engine.analysisLines.first(where: { $0.id == lineId }),
               let firstMove = line.pvMoves.first {
                top3.append(firstMove)
            }
        }
        topMoves.append(top3)

        // Store 2nd-best line eval (for brilliant/great classification)
        let secondEval = engine.analysisLines.first(where: { $0.id == 2 })?.evaluation
        secondBestEvals.append(secondEval)

        currentMoveIndex += 1

        // Check if we have more positions to evaluate
        if currentMoveIndex < positions.count {
            return positions[currentMoveIndex]
        }

        // All positions evaluated — classify moves and compute accuracy
        classifyMoves()
        computeAccuracy()
        applyAnnotations()
        state = .completed
        return nil
    }

    /// Cancel analysis
    func cancel() {
        guard state == .analyzing else { return }
        state = .cancelled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.state = .idle
        }
    }

    /// Reset to idle state (e.g., when loading a new game)
    func reset() {
        state = .idle
        currentMoveIndex = 0
        totalMoves = 0
        whiteAccuracy = 0
        blackAccuracy = 0
        evaluations = []
        moveClassifications = []
        positions = []
        topMoves = []
        secondBestEvals = []
        mainLineNodes = []
        uciMovesAtPosition = []
    }

    // MARK: - Classification

    private func classifyMoves() {
        moveClassifications = []

        for i in 1..<evaluations.count {
            let evalBefore = evaluations[i - 1]
            let evalAfter = evaluations[i]
            let isWhiteMove = mainLineNodes[i - 1].boardState.turn == .white

            // cpLoss: how much eval shifted against the moving side
            let cpLoss: Double
            if isWhiteMove {
                cpLoss = max(0, evalBefore - evalAfter)
            } else {
                cpLoss = max(0, evalAfter - evalBefore)
            }

            // WP loss (win probability change against the moving side)
            let wpBefore = winProbability(cp: evalBefore)
            let wpAfter = winProbability(cp: evalAfter)
            let wpLoss: Double
            if isWhiteMove {
                wpLoss = max(0, (wpBefore - wpAfter) * 100)
            } else {
                wpLoss = max(0, (wpAfter - wpBefore) * 100)
            }

            // Gap between engine's 1st and 2nd best lines at the position BEFORE the move
            let lineGap: Double
            if let secondEval = secondBestEvals[i - 1] {
                lineGap = abs(evaluations[i - 1] - secondEval)
            } else {
                lineGap = 0
            }

            // Second-best eval from the moving player's perspective
            let secondBestPlayerEval: Double?
            if let secondEval = secondBestEvals[i - 1] {
                secondBestPlayerEval = isWhiteMove ? secondEval : -secondEval
            } else {
                secondBestPlayerEval = nil
            }

            // Get UCI of played move
            let playedUCI: String?
            if let move = mainLineNodes[i].move {
                playedUCI = UCI.string(from: move)
            } else {
                playedUCI = nil
            }

            // Which of engine's top moves did player choose? (0 = none, 1 = best, 2 = second, 3 = third)
            let moveRank: Int
            if let played = playedUCI, i - 1 < topMoves.count {
                let top = topMoves[i - 1]
                if let idx = top.firstIndex(of: played) {
                    moveRank = idx + 1
                } else {
                    moveRank = 0
                }
            } else {
                moveRank = 0
            }

            // Is the move a material sacrifice (but NOT a recapture)?
            let sacrifice = isSacrifice(moveIndex: i)
            let recapture = isRecapture(moveIndex: i)

            // Eval from the moving player's perspective (positive = good for them)
            let playerEvalBefore = isWhiteMove ? evalBefore : -evalBefore
            let playerEvalAfter = isWhiteMove ? evalAfter : -evalAfter

            // Did the position flip from favorable/equal to losing?
            let positionFlipped = playerEvalBefore >= -50 && playerEvalAfter <= -150

            // Is this move in the opening book?
            // Check if the exact move sequence (including this move) exists in the opening tree
            let isBookMove: Bool
            if i < uciMovesAtPosition.count, let played = playedUCI {
                var movesIncludingThis = uciMovesAtPosition[i]
                movesIncludingThis.append(played)
                // Use findNode to check if this exact sequence exists in the opening tree
                isBookMove = OpeningBook.shared.findNode(moves: movesIncludingThis) != nil
            } else {
                isBookMove = false
            }

            let quality = classifyMove(
                cpLoss: cpLoss,
                wpLoss: wpLoss,
                lineGap: lineGap,
                moveRank: moveRank,
                isSacrifice: sacrifice,
                isRecapture: recapture,
                positionFlipped: positionFlipped,
                playerEvalBefore: playerEvalBefore,
                playerEvalAfter: playerEvalAfter,
                secondBestPlayerEval: secondBestPlayerEval,
                isBookMove: isBookMove
            )

            moveClassifications.append(MoveClassification(
                moveIndex: i,
                quality: quality,
                cpLoss: cpLoss,
                evalBefore: evalBefore,
                evalAfter: evalAfter,
                isWhiteMove: isWhiteMove
            ))
        }
    }

    private func classifyMove(
        cpLoss: Double,
        wpLoss: Double,
        lineGap: Double,
        moveRank: Int,
        isSacrifice: Bool,
        isRecapture: Bool,
        positionFlipped: Bool,
        playerEvalBefore: Double,
        playerEvalAfter: Double,
        secondBestPlayerEval: Double?,
        isBookMove: Bool
    ) -> MoveQuality {
        let isBestMove = moveRank == 1

        // Negative side — judged by the DROP IN WIN PROBABILITY (the Lichess model), not by raw
        // centipawns. `wpLoss` is already in win-percent points on a 0…100 scale, so the thresholds
        // are Lichess's: a 15/10/5-point drop = blunder/mistake/inaccuracy (their 0.3/0.2/0.1 on the
        // ±1 winning-chances scale). Because the sigmoid saturates in decided positions, a big cp
        // swing there is only a small win% drop — so "you can't blunder a won/lost game" falls out of
        // the math for free, and mate scores (ceiling-mapped in winProbability) land in the right
        // bucket without a special rule. This replaces the old absolute-cp thresholds, which flagged
        // meaningless moves in won games and under-flagged swings near equality.
        if wpLoss >= 15 { return .blunder }
        if wpLoss >= 10 { return .mistake }
        if wpLoss >= 5  { return .inaccuracy }

        // --- win% loss < 5 from here: a sound move. EVERY branch below returns a label, so no move
        //     is ever left blank — it is book, !, !!, or graded best / good / okay. ---

        // Opening theory takes precedence for early moves.
        if isBookMove {
            return .book
        }

        // Brilliant / Great are upgrades over a plain "best" and need the 2nd-best line (MultiPV >= 2).
        // A move that isn't the engine's best, or where the alternatives are also fine, can't be either.
        let isCompetitive = playerEvalBefore > -200 && playerEvalBefore < 500
        let notLosingAfter = playerEvalAfter >= -50

        // Brilliant: the best move AND a sound material sacrifice AND essentially the only good option,
        // in a competitive position where you're not losing after.
        if isBestMove && lineGap >= 150 && isSacrifice && !isRecapture && isCompetitive && notLosingAfter {
            return .brilliant
        }

        // Great: the (near-)only move that holds — alternatives are genuinely worse.
        if !isRecapture && notLosingAfter, let secondBest = secondBestPlayerEval {
            if secondBest <= -50 { return .great }                              // alternatives hand over the advantage
            if playerEvalAfter >= 100 && secondBest <= 0 { return .great }      // only move to keep a clear edge
        }

        // Quality ladder by win-probability loss — grades EVERY remaining move (no MultiPV needed).
        // Graded on win% given up, not engine rank, so a move that costs nothing is "best" even if it
        // wasn't literally the #1 line (e.g. two equally good moves).
        if wpLoss < 1 { return .best }     // gave up essentially nothing — the engine's move
        if wpLoss < 3 { return .good }     // a small, harmless imprecision
        return .okay                        // 3 <= win% loss < 5 — fine, just not the sharpest
    }

    /// Detect a recapture: current move captures on the same square the opponent just captured on
    private func isRecapture(moveIndex i: Int) -> Bool {
        guard i >= 2,
              let currentMove = mainLineNodes[i].move,
              let previousMove = mainLineNodes[i - 1].move,
              currentMove.capturedPiece != nil,
              previousMove.capturedPiece != nil,
              currentMove.to == previousMove.to else {
            return false
        }
        return true
    }

    /// Detect a material sacrifice: moving piece is worth more than captured piece
    /// AND the piece is not immediately protected (would be recaptured for equal/winning trade)
    private func isSacrifice(moveIndex i: Int) -> Bool {
        guard i < mainLineNodes.count,
              let move = mainLineNodes[i].move,
              let captured = move.capturedPiece else { return false }

        let movingPieceValue = pieceValue(move.piece.type)
        let capturedPieceValue = pieceValue(captured.type)

        // Must be capturing something worth less
        guard movingPieceValue > capturedPieceValue + 1 else { return false }

        // Check if opponent recaptures on the same square in the next move
        if i + 1 < mainLineNodes.count,
           let nextMove = mainLineNodes[i + 1].move,
           nextMove.to == move.to,
           nextMove.capturedPiece != nil {
            // Opponent recaptured - check if it's a reasonable trade
            // If we got back material close to what we "sacrificed", it's not a real sacrifice
            let recapturedValue = pieceValue(nextMove.capturedPiece!.type)
            let netLoss = movingPieceValue - capturedPieceValue - recapturedValue

            // Only a sacrifice if we lose significant material (2+ pawns worth)
            return netLoss >= 2
        }

        // No immediate recapture - it's a sacrifice
        return true
    }

    private func pieceValue(_ type: PieceType) -> Int {
        switch type {
        case .pawn: return 1
        case .knight: return 3
        case .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 100
        }
    }

    // MARK: - Accuracy

    private func computeAccuracy() {
        var whiteAccuracies: [Double] = []
        var blackAccuracies: [Double] = []

        for classification in moveClassifications {
            let wpBefore = winProbability(cp: classification.evalBefore)
            let wpAfter = winProbability(cp: classification.evalAfter)

            let wpLoss: Double
            if classification.isWhiteMove {
                wpLoss = max(0, (wpBefore - wpAfter) * 100)
            } else {
                wpLoss = max(0, (wpAfter - wpBefore) * 100)
            }

            // Lichess per-move accuracy curve (exact constants from AccuracyPercent.scala).
            let moveAcc = max(0, min(100, 103.1668 * exp(-0.04354 * wpLoss) - 3.1669))

            if classification.isWhiteMove {
                whiteAccuracies.append(moveAcc)
            } else {
                blackAccuracies.append(moveAcc)
            }
        }

        whiteAccuracy = aggregateAccuracy(whiteAccuracies)
        blackAccuracy = aggregateAccuracy(blackAccuracies)
    }

    /// Combine per-move accuracies into one figure. Lichess averages a volatility-weighted mean with a
    /// harmonic mean; we use the plain arithmetic + harmonic mean — the harmonic term is what makes a
    /// single catastrophe genuinely drag the score down instead of being averaged away.
    private func aggregateAccuracy(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 100 }
        let arithmetic = xs.reduce(0, +) / Double(xs.count)
        let clamped = xs.map { max($0, 0.5) }        // guard the harmonic mean against ~0 values
        let harmonic = Double(clamped.count) / clamped.reduce(0) { $0 + 1 / $1 }
        return (arithmetic + harmonic) / 2
    }

    private func winProbability(cp: Double) -> Double {
        let normalizedCP: Double
        if abs(cp) >= 10000 {
            let mateIn = abs(cp) - 10000
            normalizedCP = cp > 0 ? (10000 - mateIn) : -(10000 - mateIn)
        } else {
            normalizedCP = cp
        }
        return 1.0 / (1.0 + exp(-0.00368208 * normalizedCP))
    }

    // MARK: - Annotations

    private func applyAnnotations() {
        // Save evaluations to each node
        for (index, eval) in evaluations.enumerated() where index < mainLineNodes.count {
            mainLineNodes[index].evaluation = eval
        }

        // Save annotations to nodes
        for classification in moveClassifications {
            let annotation = classification.quality.rawValue
            if !annotation.isEmpty, classification.moveIndex < mainLineNodes.count {
                mainLineNodes[classification.moveIndex].setAnnotation(annotation)
            }
        }
    }

    // MARK: - Statistics

    func classificationCounts() -> [MoveQuality: Int] {
        var counts: [MoveQuality: Int] = [:]
        for q in MoveQuality.allCases { counts[q] = 0 }
        for c in moveClassifications { counts[c.quality, default: 0] += 1 }
        return counts
    }

    func classificationCounts(forWhite: Bool) -> [MoveQuality: Int] {
        var counts: [MoveQuality: Int] = [:]
        for q in MoveQuality.allCases { counts[q] = 0 }
        for c in moveClassifications where c.isWhiteMove == forWhite {
            counts[c.quality, default: 0] += 1
        }
        return counts
    }

    // MARK: - Persistence

    /// Export analysis data for storage
    func exportAnalysisData() -> GameAnalysisData? {
        guard isCompleted, !evaluations.isEmpty else { return nil }

        // Collect annotations (one per move, starting from move 1)
        let annotations = moveClassifications.map { $0.quality.rawValue }

        // Scrub any non-finite value (NaN / ±Inf). JSONEncoder throws on those, and this blob rides
        // along in each tab's persisted state — one stray value used to make the whole open-tabs save
        // un-encodable, silently losing every game on relaunch. Map Inf to the mate ceiling, NaN to 0.
        func finite(_ x: Double) -> Double { x.isFinite ? x : (x > 0 ? 10000 : (x < 0 ? -10000 : 0)) }

        return GameAnalysisData(
            evaluations: evaluations.map(finite),
            annotations: annotations,
            whiteAccuracy: finite(whiteAccuracy),
            blackAccuracy: finite(blackAccuracy)
        )
    }

    /// Restore analysis from stored data
    func restoreFromAnalysisData(_ data: GameAnalysisData, gameTree: GameTree) {
        let nodes = gameTree.mainLine
        guard nodes.count > 1, data.evaluations.count == nodes.count else { return }

        mainLineNodes = nodes
        totalMoves = nodes.count
        evaluations = data.evaluations
        whiteAccuracy = data.whiteAccuracy
        blackAccuracy = data.blackAccuracy

        // Restore evaluations to nodes
        for (index, eval) in evaluations.enumerated() where index < nodes.count {
            nodes[index].evaluation = eval
        }

        // Restore annotations to nodes and build classifications
        moveClassifications = []
        for i in 0..<data.annotations.count {
            let moveIndex = i + 1  // annotations[0] is for move 1, not root
            guard moveIndex < nodes.count else { break }

            let annotation = data.annotations[i]
            let quality = MoveQuality(rawValue: annotation) ?? .good

            // Apply annotation to node
            if !annotation.isEmpty {
                nodes[moveIndex].setAnnotation(annotation)
            }

            let evalBefore = evaluations[moveIndex - 1]
            let evalAfter = evaluations[moveIndex]
            let isWhiteMove = nodes[moveIndex - 1].boardState.turn == .white

            let cpLoss: Double
            if isWhiteMove {
                cpLoss = max(0, evalBefore - evalAfter)
            } else {
                cpLoss = max(0, evalAfter - evalBefore)
            }

            moveClassifications.append(MoveClassification(
                moveIndex: moveIndex,
                quality: quality,
                cpLoss: cpLoss,
                evalBefore: evalBefore,
                evalAfter: evalAfter,
                isWhiteMove: isWhiteMove
            ))
        }

        state = .completed
    }
}
