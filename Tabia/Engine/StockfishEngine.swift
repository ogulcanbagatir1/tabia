import Foundation
import SwiftUI

// MARK: - Analysis Line

struct AnalysisLine: Identifiable {
    let id: Int // PV index (1-based)
    var evaluation: Double // centipawns, from White's perspective
    var isMate: Bool
    var mateIn: Int
    var depth: Int
    var pvMoves: [String] // UCI moves — may contain more than pvNotation if capped
    // Precomputed SAN for the first `pvNotationLimit` moves. Computed off-main on
    // the pipe reader queue so SwiftUI renders never block on notation conversion.
    // Capped because the UI only shows ~20 moves and each toAlgebraic runs legal
    // move generation + check detection (expensive).
    var pvNotation: [String]

    var isGameOver: Bool {
        isMate && mateIn == 0
    }

    var evaluationText: String {
        if isMate {
            if mateIn == 0 {
                // Game is over - show result
                return evaluation > 0 ? "1-0" : "0-1"
            }
            let sign = evaluation > 0 ? "+" : "-"
            return "\(sign)M\(abs(mateIn))"
        }
        let pawnValue = evaluation / 100.0
        if abs(pawnValue) < 0.05 {
            return "0.00"
        }
        return String(format: "%+.2f", pawnValue)
    }

    var isPositive: Bool {
        evaluation >= 0
    }

    /// Color for the evaluation badge
    var evalColor: Color {
        if isGameOver {
            return DS.evalGameOver
        }
        let pawnValue = evaluation / 100.0
        if abs(pawnValue) < 0.3 {
            return DS.evalNeutral
        }
        return evaluation > 0 ? DS.evalWhiteWinning : DS.evalBlackWinning
    }

    /// Text color for the evaluation badge
    var evalTextColor: Color {
        if isGameOver {
            return .white
        }
        if abs(evaluation / 100.0) < 0.3 {
            return .white
        }
        return evaluation > 0 ? .black : .white
    }
}

class StockfishEngine: ObservableObject {
    // MARK: - Published Properties
    @Published var evaluation: Double?  // Centipawns, ALWAYS from White's perspective
    @Published var bestMove: String?
    @Published var isThinking: Bool = false
    @Published var depth: Int = 0
    @Published var analysisLines: [AnalysisLine] = []
    @Published var isEngineAvailable: Bool = false
    @Published var enginePath: String? = nil
    /// True when the search was paused (tab/section left) but the last result is kept on screen,
    /// frozen. Drives the `‖` tab indicator and the 60%-opacity eval styling (TABS-AND-RAIL §3.2).
    @Published var isFrozen: Bool = false

    // MARK: - Debug Logging
    private static let logFile: URL = {
        // Use temp directory which is accessible to sandboxed apps
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("tabia_debug.log")
        // Clear old log on startup
        try? "=== Tabia Debug Log ===\nLog file: \(tempPath.path)\nStarted: \(Date())\n\n".write(to: tempPath, atomically: true, encoding: .utf8)
        print("Debug log: \(tempPath.path)")
        return tempPath
    }()

    /// Off by default. debugLog is called once per scored info line, and each call was a full
    /// open→seek→write→close file-syscall cycle on the pipe-reader thread — dozens per second
    /// during analysis, throttling the very thread that delivers eval updates to the UI. This flag
    /// gates it so normal runs (including Debug builds) pay nothing; flip it on to capture a trace.
    static var verboseLogging = false

    func debugLog(_ message: String) {
        guard Self.verboseLogging else { return }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: Self.logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        }
    }

    // MARK: - Private Properties
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    /// Line-assembly buffer for UCI output; holds a partial line between pipe reads. Touched only on
    /// the serial readabilityHandler queue.
    var readBuffer = ""
    var isReady: Bool = false

    // Current position info for evaluation conversion
    // Protected by boardStateQueue for thread safety
    private var _currentBoardTurn: PieceColor = .white
    private var _currentBoard: ChessBoard?
    private let boardStateQueue = DispatchQueue(label: "com.tabia.boardstate")

    // Thread-safe accessors
    var currentBoardTurn: PieceColor {
        get { boardStateQueue.sync { _currentBoardTurn } }
        set { boardStateQueue.sync { _currentBoardTurn = newValue } }
    }

    var currentBoard: ChessBoard? {
        get { boardStateQueue.sync { _currentBoard } }
        set { boardStateQueue.sync { _currentBoard = newValue } }
    }

    // Track if we need to clear old analysis when new data arrives
    // Protected by analysisIdQueue for thread safety
    private var _pendingAnalysisClear: Bool = false

    // Position tracking to ignore stale results
    // Protected by analysisIdQueue for thread safety
    private var _currentAnalysisId: UUID = UUID()
    private var _activeAnalysisId: UUID?
    private let analysisIdQueue = DispatchQueue(label: "com.tabia.analysisid")

    // Thread-safe accessors for analysis IDs
    var currentAnalysisId: UUID {
        get { analysisIdQueue.sync { _currentAnalysisId } }
        set { analysisIdQueue.sync { _currentAnalysisId = newValue } }
    }

    var activeAnalysisId: UUID? {
        get { analysisIdQueue.sync { _activeAnalysisId } }
        set { analysisIdQueue.sync { _activeAnalysisId = newValue } }
    }

    var pendingAnalysisClear: Bool {
        get { analysisIdQueue.sync { _pendingAnalysisClear } }
        set { analysisIdQueue.sync { _pendingAnalysisClear = newValue } }
    }

    // Track whether the last analysis completed naturally (received bestmove)
    // When true, we can skip sending "stop" and the 50ms flush delay
    var lastCompletedNaturally = false

    // MARK: - Speculative (Look-ahead) Analysis
    var isSpeculative = false
    var speculativeEval: Double?
    var speculativeLines: [AnalysisLine] = []
    var speculativeBestMove: String?
    var speculativeDepth: Int = 0

    /// Serializes the analysis result-state group (isSpeculative + speculative* caches +
    /// lastPublishedLines + lastCompletedNaturally) between the pipe-reader thread (parse*) and the
    /// main/caller thread (evaluate/stop/promote/discard). MUST stay distinct from analysisIdQueue /
    /// boardStateQueue to avoid re-entrant deadlock, and must never be nested within itself.
    let resultStateQueue = DispatchQueue(label: "com.tabia.stockfish.resultstate")

    // MARK: - Cloud Eval

    private var isCloudEngine: Bool {
        resolvedConfig?.source == .cloud
    }

    // Cloud eval response models
    private struct CloudEvalResponse: Decodable {
        let fen: String
        let knodes: Int
        let depth: Int
        let pvs: [CloudPV]
    }

    private struct CloudPV: Decodable {
        let moves: String
        let cp: Int?
        let mate: Int?
    }

    // Analysis settings
    private(set) var multiPV: Int = 3

    /// Temporarily override MultiPV (e.g. set to 1 for game analysis speed)
    func setMultiPV(_ value: Int) {
        multiPV = max(1, min(value, 5))
    }

    /// Explicit engine configuration. When set, the engine uses this config
    /// instead of AppSettings.shared.defaultEngine. Used by MultiEngineManager
    /// to run multiple engines with different configs in parallel.
    var engineConfig: EngineConfig?

    /// Resolved config: explicit config if set, otherwise the global default.
    private var resolvedConfig: EngineConfig? {
        engineConfig ?? AppSettings.shared.defaultEngine
    }

    init() {}

    deinit {
        // Cannot call stop() here because it captures self in DispatchQueue.main.async,
        // which is illegal during deallocation (causes swift_deallocClassInstance crash).
        // Do synchronous cleanup only.
        if !isCloudEngine {
            try? inputPipe?.fileHandleForWriting.write(contentsOf: "quit\n".data(using: .utf8)!)
            process?.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil
    }

    // MARK: - Engine Lifecycle

    /// Finds Stockfish binary in configured path, bundle, or common system locations
    private func findStockfishPath() -> String? {
        let fm = FileManager.default

        // Helper: check path is a regular executable file (not a directory)
        func isRegularExecutable(_ path: String) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue && fm.isExecutableFile(atPath: path)
        }

        // 1. Check explicit or default engine config
        if let defaultEngine = resolvedConfig {
            if isRegularExecutable(defaultEngine.path) {
                return defaultEngine.path
            }
            // Stored path may be stale (e.g. binary has platform suffix) — search the directory
            // Also search if the path turned out to be a directory (tar extraction artifact)
            let searchDirs: [String]
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: defaultEngine.path, isDirectory: &isDir), isDir.boolValue {
                // The stored path IS a directory — search inside it
                searchDirs = [defaultEngine.path, (defaultEngine.path as NSString).deletingLastPathComponent]
            } else {
                searchDirs = [(defaultEngine.path as NSString).deletingLastPathComponent]
            }
            let binaryName = (defaultEngine.path as NSString).lastPathComponent
            for dir in searchDirs {
                if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                    for file in contents {
                        let fullPath = (dir as NSString).appendingPathComponent(file)
                        if file.hasPrefix(binaryName) && isRegularExecutable(fullPath) {
                            return fullPath
                        }
                    }
                }
            }
        }

        // 2. Check user-configured path (legacy)
        let userPath = AppSettings.shared.stockfishPath
        if !userPath.isEmpty && isRegularExecutable(userPath) {
            return userPath
        }

        // 3. Check app bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = resourcePath + "/stockfish"
            if isRegularExecutable(bundledPath) {
                return bundledPath
            }
        }

        // 4. Check common system locations (Homebrew, etc.)
        let commonPaths = [
            "/usr/local/bin/stockfish",           // Intel Mac Homebrew
            "/opt/homebrew/bin/stockfish",        // Apple Silicon Homebrew
            "/usr/bin/stockfish",                 // System-wide
            "/Applications/Stockfish.app/Contents/MacOS/stockfish"  // Stockfish app
        ]

        for path in commonPaths {
            if isRegularExecutable(path) {
                return path
            }
        }

        return nil
    }

    func start() {
        // Cloud engine: no local process needed
        if isCloudEngine {
            DispatchQueue.main.async {
                self.isEngineAvailable = true
                self.enginePath = nil
            }
            return
        }

        guard process == nil else { return }

        let stockfishPath = findStockfishPath()

        guard let path = stockfishPath else {
            print("Stockfish binary not found. Checked:")
            print("  - User configured path: \(AppSettings.shared.stockfishPath)")
            print("  - Bundle resources")
            print("  - /usr/local/bin/stockfish")
            print("  - /opt/homebrew/bin/stockfish")
            DispatchQueue.main.async {
                self.isEngineAvailable = false
                self.enginePath = nil
            }
            return
        }

        debugLog("Using Stockfish at: \(path)")
        DispatchQueue.main.async {
            self.enginePath = path
        }

        process = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()
        readBuffer = ""   // drop any partial line from a previous process before wiring the new pipe

        process?.executableURL = URL(fileURLWithPath: path)
        process?.standardInput = inputPipe
        process?.standardOutput = outputPipe
        process?.standardError = Pipe()

        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self?.handleOutput(output)
            }
        }

        // Handle process termination (crash or normal exit)
        process?.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            let reason = terminatedProcess.terminationReason
            self?.debugLog("!!! Stockfish TERMINATED - status: \(status), reason: \(reason == .exit ? "normal exit" : "CRASH/SIGNAL")")
            if reason == .uncaughtSignal {
                self?.debugLog("!!! Stockfish crashed with uncaught signal (likely stack overflow or segfault)")
            }
            DispatchQueue.main.async {
                self?.isEngineAvailable = false
                self?.isThinking = false
                self?.process = nil
                self?.inputPipe = nil
                self?.outputPipe = nil
            }
        }

        do {
            try process?.run()

            sendCommand("uci")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Read per-engine settings (fall back to sensible defaults)
                let engineSettings = self.resolvedConfig?.settings ?? .default
                self.multiPV = engineSettings.multiPV
                self.sendCommand("setoption name Threads value \(engineSettings.threads)")
                self.sendCommand("setoption name Hash value \(engineSettings.hashMB)")
                self.sendCommand("setoption name MultiPV value \(engineSettings.multiPV)")
                self.sendCommand("isready")
                // isEngineAvailable will be set to true when "readyok" is received
            }
        } catch {
            print("Failed to start Stockfish: \(error)")
            process = nil
            DispatchQueue.main.async {
                self.isEngineAvailable = false
                self.enginePath = nil
            }
        }
    }

    /// Restart the engine (useful after changing settings)
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.start()
        }
    }

    func stop() {
        // Invalidate any in-flight analysis (prevents cloud Task callbacks
        // from updating @Published properties after the engine is removed).
        activeAnalysisId = nil

        if isCloudEngine {
            DispatchQueue.main.async {
                self.isEngineAvailable = false
                self.isThinking = false
            }
            return
        }
        sendCommand("quit")
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        isReady = false
        DispatchQueue.main.async {
            self.isEngineAvailable = false
        }
    }

    // MARK: - UCI Commands

    private func sendCommand(_ command: String) {
        guard let pipe = inputPipe,
              let proc = process,
              proc.isRunning else {
            debugLog("sendCommand: Process not running, cannot send: \(command)")
            return
        }

        debugLog(">>> UCI: \(command)")
        let data = (command + "\n").data(using: .utf8)!

        // Write safely - catch any pipe errors
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            debugLog("Failed to send command '\(command)': \(error)")
            // Process likely crashed, clean up
            DispatchQueue.main.async {
                self.isEngineAvailable = false
                self.isThinking = false
            }
        }
    }

    func stopAnalysis() {
        if !isCloudEngine {
            sendCommand("stop")
        }
        // Invalidate current analysis so stale results are ignored
        activeAnalysisId = nil
        // Clear speculative mode + published-line cache so next evaluatePosition() publishes normally.
        resultStateQueue.sync {
            lastCompletedNaturally = false
            isSpeculative = false
            speculativeEval = nil
            speculativeLines = []
            speculativeBestMove = nil
            speculativeDepth = 0
            lastPublishedLines.removeAll(keepingCapacity: true)
            lastPublishedDepth = nil
            lastPublishedEval = nil
            lastPublishedBestMove = nil
        }
        DispatchQueue.main.async {
            self.isThinking = false
        }
    }

    /// Pause the search but keep the last result frozen on screen — used when this tab/window loses
    /// focus (TABS-AND-RAIL §3.2). stopAnalysis() already sends UCI "stop", nils the analysis id, and
    /// deliberately preserves the @Published eval/PV/depth/bestMove, so the display stays put.
    /// Cloud engines are exempt (they run on someone else's CPU) and keep going.
    func pauseAnalysis() {
        guard !isCloudEngine else { return }
        stopAnalysis()
        DispatchQueue.main.async { self.isFrozen = true }
    }

    /// Resume from the frozen snapshot: restart the search at the same position, keeping the frozen
    /// eval/PV/depth visible until the new search overtakes it.
    func resumeAnalysis() {
        guard !isCloudEngine else { return }
        guard isEngineAvailable, let board = currentBoard else {
            DispatchQueue.main.async { self.isFrozen = false }
            return
        }
        DispatchQueue.main.async { self.isFrozen = false }
        evaluatePosition(board: board, depth: engineConfig?.settings.depth, preserveDisplay: true)
    }

    // Minimum depth before showing best move (avoid bad early suggestions)
    let minDepthForBestMove: Int = 5

    /// Max number of PV moves to convert to SAN per analysis line. The UI only
    /// displays ~20 moves; each conversion runs legal move gen + check detection
    /// so capping here cuts Swift-side CPU during analysis roughly in half.
    static let pvNotationLimit: Int = 20

    /// Snapshot of the last published line per pvIndex, used for dedup on the
    /// pipe reader thread so we skip SAN conversion when nothing changed.
    /// Cleared whenever analysisLines is cleared (new analysis / stop).
    var lastPublishedLines: [Int: AnalysisLine] = [:]

    /// Shadow copies of the scalar @Published values (guarded by resultStateQueue).
    /// Stockfish emits many info lines per depth level (MultiPV=3 → the same depth 3×,
    /// PV1 eval refined many times/sec). Dispatching every one to the main thread fires a
    /// redundant objectWillChange each time. We only hop to main when the value actually
    /// changes, collapsing dozens of no-op publishes per second into a handful.
    var lastPublishedDepth: Int? = nil
    var lastPublishedEval: Double? = nil
    var lastPublishedBestMove: String? = nil

    // MARK: - Evaluation

    func evaluatePosition(board: ChessBoard, depth: Int? = nil, movetime: Int? = nil, continuous: Bool = false, preserveDisplay: Bool = false) {
        if isCloudEngine {
            evaluateCloudPosition(board: board)
            return
        }

        guard let proc = process, proc.isRunning else {
            // Stockfish not running - clear analysis state
            debugLog("Stockfish not running, no analysis available")
            DispatchQueue.main.async {
                self.isEngineAvailable = false
                self.isThinking = false
                self.evaluation = nil
                self.bestMove = nil
                self.analysisLines = []
                self.depth = 0
            }
            return
        }

        // Wait for engine to be fully initialized (received "readyok")
        guard isEngineAvailable else {
            debugLog("Engine not yet ready (waiting for readyok), deferring analysis")
            // Retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.evaluatePosition(board: board, depth: depth, continuous: continuous)
            }
            return
        }

        debugLog("evaluatePosition: Using real Stockfish engine")

        // Check if the previous analysis completed naturally (received bestmove).
        // If so, Stockfish is already idle — no need to send "stop" or wait for flush.
        let skipStopAndFlush: Bool = resultStateQueue.sync {
            let v = lastCompletedNaturally
            lastCompletedNaturally = false
            return v
        }

        if !skipStopAndFlush {
            // Stop any previous analysis and invalidate its results
            sendCommand("stop")
        }
        activeAnalysisId = nil  // Ignore any results that arrive from now until new analysis starts

        // Store the position FEN for this analysis
        let positionFEN = board.getFEN()
        debugLog("evaluatePosition: FEN = \(positionFEN), skipFlush=\(skipStopAndFlush)")

        // Store board info for evaluation conversion IMMEDIATELY
        // This ensures currentBoard is set before any results can arrive
        let boardTurn = board.turn
        let boardCopy = board.copy()
        self.currentBoardTurn = boardTurn
        self.currentBoard = boardCopy
        debugLog("evaluatePosition: Board turn = \(boardTurn), stored currentBoard")

        // Mark as thinking and clear old analysis (keep evaluation to avoid bar flashing to 0).
        // preserveDisplay (a resume after pause): keep the frozen eval/PV/depth on screen and seed
        // the dedup shadows to the frozen values so the new search only republishes once it overtakes
        // the frozen depth (TABS-AND-RAIL §3.2 "goes live when it passes the frozen depth").
        let frozenDepth = self.depth
        let frozenEval = self.evaluation
        let frozenBest = self.bestMove
        resultStateQueue.sync {
            lastPublishedLines.removeAll(keepingCapacity: true)
            lastPublishedDepth = preserveDisplay ? frozenDepth : nil
            lastPublishedEval = preserveDisplay ? frozenEval : nil
            lastPublishedBestMove = preserveDisplay ? frozenBest : nil
        }
        let speculativeNow = resultStateQueue.sync { isSpeculative }
        DispatchQueue.main.async {
            if !speculativeNow && !preserveDisplay {
                self.bestMove = nil
                self.depth = 0
                self.analysisLines = []
            }
            self.isThinking = true
        }

        // Helper to send position and go commands
        let sendPositionAndGo = { [weak self] in
            guard let self = self else { return }

            // Generate new analysis ID
            let newAnalysisId = UUID()
            self.currentAnalysisId = newAnalysisId
            self.activeAnalysisId = newAnalysisId
            self.pendingAnalysisClear = true

            // Ensure MultiPV is set before each analysis
            self.sendCommand("setoption name MultiPV value \(self.multiPV)")

            // Send position and start analysis
            self.sendCommand("position fen \(positionFEN)")

            // Build go command with optional depth and movetime limits
            var goCmd = "go"
            if let d = depth { goCmd += " depth \(d)" }
            if let mt = movetime { goCmd += " movetime \(mt)" }
            if depth == nil && movetime == nil {
                let engineSettings = self.resolvedConfig?.settings ?? .default
                goCmd += " depth \(engineSettings.depth)"
            }
            self.sendCommand(goCmd)
        }

        if skipStopAndFlush {
            // No stale results to flush — send commands immediately
            DispatchQueue.global(qos: .userInteractive).async(execute: sendPositionAndGo)
        } else {
            // Small delay to let stale results from previous analysis flush through
            // before we start accepting results for the new position
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.05, execute: sendPositionAndGo)
        }
    }

    // MARK: - Cloud Evaluation

    private func evaluateCloudPosition(board: ChessBoard) {
        let fen = board.getFEN()
        let boardCopy = board.copy()
        self.currentBoardTurn = board.turn
        self.currentBoard = boardCopy

        // Read multiPV from per-engine settings
        let engineSettings = resolvedConfig?.settings ?? .default
        self.multiPV = engineSettings.multiPV

        DispatchQueue.main.async {
            self.bestMove = nil
            self.depth = 0
            self.analysisLines = []
            self.isThinking = true
        }

        guard var components = URLComponents(string: "https://lichess.org/api/cloud-eval") else {
            DispatchQueue.main.async { self.isThinking = false }
            return
        }
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "multiPv", value: String(multiPV)),
            URLQueryItem(name: "variant", value: "standard")
        ]
        guard let url = components.url else {
            DispatchQueue.main.async { self.isThinking = false }
            return
        }

        let analysisId = UUID()
        self.currentAnalysisId = analysisId
        self.activeAnalysisId = analysisId

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                // Check for stale result
                guard self.activeAnalysisId == analysisId else { return }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        self.evaluation = nil
                        self.analysisLines = []
                        self.bestMove = nil
                        self.depth = 0
                        self.isThinking = false
                    }
                    return
                }

                let cloudResponse = try JSONDecoder().decode(CloudEvalResponse.self, from: data)

                // Check for stale result again after decode
                guard self.activeAnalysisId == analysisId else { return }

                var lines: [AnalysisLine] = []
                var mainEval: Double?

                for (index, pv) in cloudResponse.pvs.enumerated() {
                    let pvIndex = index + 1
                    // Lichess uses "king captures rook" castling notation (e1h1/e1a1)
                    // Normalize to standard UCI (e1g1/e1c1) for our converter
                    let uciMoves = pv.moves.split(separator: " ").map { move -> String in
                        let m = String(move)
                        switch m {
                        case "e1h1": return "e1g1"  // White O-O
                        case "e1a1": return "e1c1"  // White O-O-O
                        case "e8h8": return "e8g8"  // Black O-O
                        case "e8a8": return "e8c8"  // Black O-O-O
                        default: return m
                        }
                    }

                    var evalValue: Double = 0
                    var isMate = false
                    var mateIn = 0

                    if let mate = pv.mate {
                        // mate is already from White's POV
                        isMate = true
                        mateIn = abs(mate)
                        let mateDistance = Double(mateIn)
                        evalValue = mate > 0 ? (10000.0 + mateDistance) : -(10000.0 + mateDistance)
                    } else if let cp = pv.cp {
                        // cp is already from White's POV
                        evalValue = Double(cp)
                    }

                    if pvIndex == 1 {
                        mainEval = evalValue
                    }

                    let pvNotation = boardCopy.toAlgebraicPV(uciMoves: Array(uciMoves.prefix(Self.pvNotationLimit)))

                    lines.append(AnalysisLine(
                        id: pvIndex,
                        evaluation: evalValue,
                        isMate: isMate,
                        mateIn: mateIn,
                        depth: cloudResponse.depth,
                        pvMoves: uciMoves,
                        pvNotation: pvNotation
                    ))
                }

                let bestMoveNotation = lines.first?.pvNotation.first
                let responseDepth = cloudResponse.depth

                await MainActor.run {
                    guard self.activeAnalysisId == analysisId else { return }
                    self.evaluation = mainEval
                    self.depth = responseDepth
                    self.analysisLines = lines
                    self.bestMove = bestMoveNotation
                    self.isThinking = false
                }
            } catch {
                await MainActor.run {
                    guard self.activeAnalysisId == analysisId else { return }
                    self.evaluation = nil
                    self.analysisLines = []
                    self.bestMove = nil
                    self.depth = 0
                    self.isThinking = false
                }
            }
        }
    }

    // MARK: - Move Conversion

    /// UCI (e.g. "g1f3", "e7e8q") → full SAN ("Nf3", "e8=Q+"). Delegates to the board's notation
    /// engine so promotion, disambiguation, and check/mate markers are all handled correctly —
    /// the previous hand-rolled version dropped all three.
    func convertToAlgebraic(_ uci: String) -> String {
        guard let board = currentBoard else { return uci }
        return board.toAlgebraicPV(uciMoves: [uci]).first ?? uci
    }

    // MARK: - Speculative (Look-ahead) Analysis

    /// Start analyzing a position speculatively (look-ahead).
    /// Results are cached instead of published until promoted.
    func evaluatePositionSpeculative(board: ChessBoard, depth: Int) {
        resultStateQueue.sync {
            isSpeculative = true
            speculativeEval = nil
            speculativeLines = []
            speculativeBestMove = nil
            speculativeDepth = 0
        }
        evaluatePosition(board: board, depth: depth)
    }

    /// Promote speculative results to published properties.
    /// Call when the user navigated to the position we were speculatively analyzing.
    func promoteSpeculativeResults() {
        // Snapshot the caches AND flip the flag in ONE atomic block, so the reader thread can't write
        // a speculative field between the read and the flip (which would be lost/torn).
        let (eval, lines, best, d): (Double?, [AnalysisLine], String?, Int) = resultStateQueue.sync {
            let snapshot = (speculativeEval, speculativeLines, speculativeBestMove, speculativeDepth)
            isSpeculative = false
            return snapshot
        }

        DispatchQueue.main.async {
            if let eval = eval {
                self.evaluation = eval
            }
            if !lines.isEmpty {
                self.analysisLines = lines
            }
            if let best = best {
                self.bestMove = best
            }
            self.depth = d
        }
    }

    /// Discard speculative analysis and stop it if running.
    func discardSpeculative() {
        let wasSpeculative = resultStateQueue.sync { isSpeculative }
        if wasSpeculative {
            sendCommand("stop")
            activeAnalysisId = nil
        }
        resultStateQueue.sync {
            if wasSpeculative { lastCompletedNaturally = false }
            isSpeculative = false
            speculativeEval = nil
            speculativeLines = []
            speculativeBestMove = nil
            speculativeDepth = 0
        }
        DispatchQueue.main.async {
            self.isThinking = false
        }
    }
}
