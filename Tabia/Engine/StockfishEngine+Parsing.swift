import Foundation
import SwiftUI

// UCI output parsing for StockfishEngine — line assembly, info/bestmove handling, and
// PV-to-notation conversion. Split out of StockfishEngine.swift to keep that file focused
// on process lifecycle and evaluation.

extension StockfishEngine {

    // MARK: - Output Parsing

    /// Accumulate raw pipe chunks and dispatch only COMPLETE lines; a line split across two reads is
    /// held in `readBuffer` until its terminating newline arrives. Without this, a chunk boundary
    /// inside a line (routine at depth with MultiPV, which overflows one pipe buffer) mis-parses the
    /// split tokens and can DROP the terminating `bestmove` — leaving `isThinking` stuck true and
    /// stalling the whole game-analysis pump. Called only from the serial readabilityHandler.
    func handleOutput(_ output: String) {
        readBuffer += output
        while let nl = readBuffer.firstIndex(of: "\n") {
            var line = String(readBuffer[..<nl])
            readBuffer = String(readBuffer[readBuffer.index(after: nl)...])
            if line.hasSuffix("\r") { line.removeLast() }
            if !line.isEmpty { processLine(line) }
        }
    }

    private func processLine(_ line: String) {
        // Log important output (skip verbose info lines without score)
        if line.hasPrefix("bestmove") || line.contains("score") || line.hasPrefix("error") {
            debugLog("<<< UCI: \(line.prefix(200))")
        }

        let parts = line.split(separator: " ")
        guard let first = parts.first else { return }

        switch first {
        case "info":
            parseInfoLine(Array(parts))
        case "bestmove":
            parseBestMove(Array(parts))
        case "uciok":
            debugLog("<<< UCI: uciok - engine ready")
            DispatchQueue.main.async {
                self.isReady = true
            }
        case "readyok":
            debugLog("<<< UCI: readyok - engine fully ready")
            DispatchQueue.main.async {
                self.isEngineAvailable = true
            }
        default:
            break
        }
    }

    private func parseInfoLine(_ parts: [Substring]) {
        // Only process lines with score info
        guard parts.contains("score") else { return }

        // Ignore results from stale analysis (user navigated to different position)
        guard activeAnalysisId == currentAnalysisId else {
            debugLog("parseInfoLine: Ignoring stale result (activeAnalysisId mismatch)")
            return
        }

        // Snapshot the speculative flag ONCE so this whole info line routes consistently, even if a
        // promote/discard flips it mid-parse on another thread.
        let speculative = resultStateQueue.sync { isSpeculative }

        // Parse depth
        var currentDepth = 0
        if let depthIdx = parts.firstIndex(of: "depth"),
           depthIdx + 1 < parts.count,
           let depthValue = Int(parts[depthIdx + 1]) {
            currentDepth = depthValue
            if speculative {
                resultStateQueue.sync { speculativeDepth = depthValue }
            } else {
                // Only hop to main when the depth actually advances — Stockfish emits the
                // same depth once per MultiPV line, so this drops ~2/3 of depth publishes.
                let changed = resultStateQueue.sync { () -> Bool in
                    if lastPublishedDepth == depthValue { return false }
                    lastPublishedDepth = depthValue
                    return true
                }
                if changed {
                    DispatchQueue.main.async {
                        self.depth = depthValue
                    }
                }
            }
        }

        // Parse multipv index
        var pvIndex = 1
        if let mpvIdx = parts.firstIndex(of: "multipv"),
           mpvIdx + 1 < parts.count,
           let mpvValue = Int(parts[mpvIdx + 1]) {
            pvIndex = mpvValue
        }

        // Parse score
        var evalValue: Double = 0
        var isMate = false
        var mateIn = 0

        if let scoreIdx = parts.firstIndex(of: "score"),
           scoreIdx + 2 < parts.count {
            let scoreType = parts[scoreIdx + 1]

            if let scoreValue = Int(parts[scoreIdx + 2]) {
                if scoreType == "cp" {
                    // Stockfish reports score from the perspective of the side to move
                    // We want to always show from White's perspective (positive = good for White)
                    // So when Black is to move, Stockfish's positive = good for Black = bad for White
                    // Therefore we negate when Black is to move
                    let whiteScore = currentBoardTurn == .white
                        ? Double(scoreValue)
                        : Double(-scoreValue)
                    evalValue = whiteScore

                    // Update main evaluation from PV1
                    if pvIndex == 1 {
                        if speculative {
                            resultStateQueue.sync { speculativeEval = whiteScore }
                        } else {
                            let changed = resultStateQueue.sync { () -> Bool in
                                if lastPublishedEval == whiteScore { return false }
                                lastPublishedEval = whiteScore
                                return true
                            }
                            if changed {
                                DispatchQueue.main.async {
                                    self.evaluation = whiteScore
                                }
                            }
                        }
                    }
                } else if scoreType == "mate" {
                    isMate = true
                    mateIn = abs(scoreValue)
                    // Stockfish reports mate from side to move's perspective
                    // Positive mateIn = side to move delivers mate (good for them)
                    // Negative mateIn = side to move gets mated (bad for them)
                    // Encode mate distance: ±(10000 + mateIn) so UI can extract it
                    var mateScore: Double
                    let mateDistance = Double(mateIn)
                    if scoreValue > 0 {
                        // Side to move delivers mate - good for them
                        mateScore = currentBoardTurn == .white ? (10000.0 + mateDistance) : -(10000.0 + mateDistance)
                    } else {
                        // Side to move gets mated - bad for them
                        mateScore = currentBoardTurn == .white ? -(10000.0 + mateDistance) : (10000.0 + mateDistance)
                    }
                    evalValue = mateScore

                    if pvIndex == 1 {
                        if speculative {
                            resultStateQueue.sync { speculativeEval = mateScore }
                        } else {
                            let changed = resultStateQueue.sync { () -> Bool in
                                if lastPublishedEval == mateScore { return false }
                                lastPublishedEval = mateScore
                                return true
                            }
                            if changed {
                                DispatchQueue.main.async {
                                    self.evaluation = mateScore
                                }
                            }
                        }
                    }
                }
            }
        }

        // Parse PV moves
        var pvMoves: [String] = []
        if let pvIdx = parts.firstIndex(of: "pv") {
            for i in (parts.index(after: pvIdx))..<parts.endIndex {
                pvMoves.append(String(parts[i]))
            }
        }

        debugLog("parseInfoLine: depth=\(currentDepth) pv=\(pvIndex) eval=\(evalValue) pvMoves=\(pvMoves.prefix(5).joined(separator: " "))")

        // Build line lazily: only compute SAN if we pass the dedup check below.
        // SAN conversion is expensive (each move runs legal move generation + check
        // detection) so we skip it entirely for info lines that wouldn't change
        // what the user sees.
        func buildLine(with notation: [String]) -> AnalysisLine {
            AnalysisLine(
                id: pvIndex,
                evaluation: evalValue,
                isMate: isMate,
                mateIn: mateIn,
                depth: currentDepth,
                pvMoves: pvMoves,
                pvNotation: notation
            )
        }
        func computeNotation() -> [String] {
            guard let board = currentBoard else { return [] }
            return board.toAlgebraicPV(uciMoves: Array(pvMoves.prefix(Self.pvNotationLimit)))
        }

        if speculative {
            // Route all results to the speculative caches (guarded by resultStateQueue).
            if pvIndex == 1, currentDepth >= minDepthForBestMove, let firstUci = pvMoves.first {
                let sb = convertToAlgebraic(firstUci)
                resultStateQueue.sync { speculativeBestMove = sb }
            }
            // First data for a new position clears the old speculative lines.
            let shouldClear = pendingAnalysisClear
            if shouldClear { pendingAnalysisClear = false }
            resultStateQueue.sync {
                if shouldClear { speculativeLines = [] }
                if let existingIdx = speculativeLines.firstIndex(where: { $0.id == pvIndex }) {
                    // Dedup on raw fields — only rebuild the (expensive) SAN line when it changed.
                    if linesDifferRaw(existing: speculativeLines[existingIdx],
                                      pvMoves: pvMoves, depth: currentDepth,
                                      evaluation: evalValue, isMate: isMate, mateIn: mateIn) {
                        speculativeLines[existingIdx] = buildLine(with: computeNotation())
                    }
                } else {
                    speculativeLines.append(buildLine(with: computeNotation()))
                    speculativeLines.sort { $0.id < $1.id }
                }
            }
        } else {
            // Update best move from PV1 — single-move SAN conversion is cheap
            if pvIndex == 1, currentDepth >= minDepthForBestMove, let firstUci = pvMoves.first {
                let firstMove = convertToAlgebraic(firstUci)
                let changed = resultStateQueue.sync { () -> Bool in
                    if lastPublishedBestMove == firstMove { return false }
                    lastPublishedBestMove = firstMove
                    return true
                }
                if changed {
                    DispatchQueue.main.async {
                        self.bestMove = firstMove
                    }
                }
            }

            // Check if we need to clear old analysis (first data for new position)
            let shouldClear = pendingAnalysisClear
            if shouldClear {
                pendingAnalysisClear = false
            }

            // Dedup against the LAST PUBLISHED line for this pvIndex on the reader thread (guarded),
            // so SAN conversion + the main-thread hop only run when something actually changed.
            var publishedLine: AnalysisLine? = nil
            resultStateQueue.sync {
                if let existing = lastPublishedLines[pvIndex],
                   !linesDifferRaw(existing: existing, pvMoves: pvMoves, depth: currentDepth,
                                   evaluation: evalValue, isMate: isMate, mateIn: mateIn) {
                    return
                }
                let line = buildLine(with: computeNotation())
                lastPublishedLines[pvIndex] = line
                publishedLine = line
            }
            guard let publishedLine else { return }

            DispatchQueue.main.async {
                // Clear old analysis when first new data arrives
                if shouldClear {
                    self.analysisLines = []
                }

                if let existingIdx = self.analysisLines.firstIndex(where: { $0.id == pvIndex }) {
                    self.analysisLines[existingIdx] = publishedLine
                } else {
                    self.analysisLines.append(publishedLine)
                    self.analysisLines.sort { $0.id < $1.id }
                }
            }
        }
    }

    /// Returns true if the new (pvMoves, depth, eval) tuple carries a user-visible
    /// update over `existing`. Used to suppress redundant SAN conversion + @Published
    /// writes when Stockfish emits multiple info lines per depth with unchanged data.
    private func linesDifferRaw(existing: AnalysisLine, pvMoves: [String], depth: Int,
                                evaluation: Double, isMate: Bool, mateIn: Int) -> Bool {
        if existing.depth != depth { return true }
        if existing.evaluation != evaluation { return true }
        if existing.isMate != isMate || existing.mateIn != mateIn { return true }
        if existing.pvMoves.count != pvMoves.count { return true }
        for (x, y) in zip(existing.pvMoves, pvMoves) where x != y { return true }
        return false
    }

    private func parseBestMove(_ parts: [Substring]) {
        guard parts.count >= 2 else { return }

        // Ignore results from stale analysis (user navigated to different position)
        guard activeAnalysisId == currentAnalysisId else { return }

        // Mark that analysis completed naturally — next evaluatePosition() can skip stop/flush
        resultStateQueue.sync { lastCompletedNaturally = true }

        let uciMove = String(parts[1])
        let algebraicMove = convertToAlgebraic(uciMove)

        // Snapshot the flag and record the speculative best move atomically in one block.
        let speculative: Bool = resultStateQueue.sync {
            if isSpeculative { speculativeBestMove = algebraicMove; return true }
            return false
        }
        if speculative {
            DispatchQueue.main.async {
                self.isThinking = false
            }
        } else {
            DispatchQueue.main.async {
                self.bestMove = algebraicMove
                self.isThinking = false
            }
        }
    }
}
