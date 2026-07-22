import Foundation
import SwiftUI
import Combine

/// Manages multiple chess engines running in parallel.
/// Each engine is a separate StockfishEngine instance with its own EngineConfig.
/// One engine is "selected" at a time — its PV lines are shown in detail,
/// while all engines show their evaluation scores.
class MultiEngineManager: ObservableObject {

    struct EngineSlot: Identifiable {
        let id: UUID          // same as config.id
        let config: EngineConfig
        let engine: StockfishEngine
    }

    // MARK: - Published State

    @Published var slots: [EngineSlot] = []
    @Published var selectedId: UUID?

    /// Forwarded from the selected engine so MainWindowView can use
    /// onChange(of:) for the game-analysis pump and look-ahead logic.
    @Published private(set) var selectedIsThinking: Bool = false

    /// Coarse mirror of the selected engine's frozen state, for the titlebar tab indicator. Kept as
    /// a manager-level @Published (like selectedIsThinking) so the window sees frozen transitions
    /// WITHOUT observing the engine's high-frequency eval/PV stream.
    @Published private(set) var selectedIsFrozen: Bool = false

    // MARK: - Private

    /// Coarse per-selection mirrors of the selected engine's thinking/frozen flags. The manager
    /// deliberately does NOT forward the engine's per-tick objectWillChange (evaluation/depth/PV):
    /// those reach only the leaf views that observe the engine directly (EvalBarView,
    /// AnalysisPanelView, EngineEvalRow), so an analysing engine never re-runs MainWindowView.body.
    private var selectedThinkingCancellable: AnyCancellable?
    private var selectedFrozenCancellable: AnyCancellable?

    /// A dummy engine used as a fallback when no engine is selected,
    /// so views that expect a non-optional StockfishEngine always work.
    private let fallbackEngine = StockfishEngine()

    /// The board most recently handed to `evaluateAll` (a copy). Used to give a newly-added engine an
    /// evaluation for the CURRENT position the moment it joins, so it isn't blank until the next move.
    private var lastEvaluatedBoard: ChessBoard?

    // MARK: - Computed Helpers

    var selectedEngine: StockfishEngine? {
        slots.first(where: { $0.id == selectedId })?.engine
    }

    /// Non-optional reference to the selected engine (or a dummy).
    /// Safe to pass to views that require @ObservedObject engine.
    var primaryEngine: StockfishEngine {
        selectedEngine ?? fallbackEngine
    }

    var selectedConfig: EngineConfig? {
        slots.first(where: { $0.id == selectedId })?.config
    }

    var anyEngineAvailable: Bool {
        slots.contains(where: { $0.engine.isEngineAvailable })
    }

    /// Engines configured in AppSettings but not currently active in a slot.
    var availableToAdd: [EngineConfig] {
        let activeIds = Set(slots.map(\.config.id))
        return AppSettings.shared.engines.filter { !activeIds.contains($0.id) }
    }

    // MARK: - Lifecycle

    init() {}

    /// Call once on view appear. Adds the default engine if no slots exist.
    func setup() {
        if slots.isEmpty, let defaultConfig = AppSettings.shared.defaultEngine {
            addEngine(defaultConfig)
        }
    }

    /// Tears down all engines.
    func teardown() {
        for slot in slots {
            slot.engine.stop()
        }
        slots.removeAll()
        selectedThinkingCancellable = nil
        selectedFrozenCancellable = nil
        selectedId = nil
        selectedIsThinking = false
        selectedIsFrozen = false
    }

    // MARK: - Engine Management

    func addEngine(_ config: EngineConfig) {
        guard !slots.contains(where: { $0.id == config.id }) else { return }

        let engine = StockfishEngine()
        engine.engineConfig = config
        let slot = EngineSlot(id: config.id, config: config, engine: engine)

        // The engine's per-tick objectWillChange is NOT forwarded to the manager. Forwarding it (even
        // throttled) re-ran MainWindowView.body ~10x/sec during analysis, because the window observes
        // the manager. Live eval/PV/depth now reaches only the views that observe the engine directly
        // — EvalBarView, AnalysisPanelView, EngineEvalRow — so the rest of the window stays still.
        slots.append(slot)

        if selectedId == nil {
            selectEngine(id: config.id)
        }

        engine.start()

        // Give the new engine an eval for the position on screen RIGHT NOW, instead of leaving it
        // blank until the user makes a move. A cloud engine evaluates synchronously here (no process
        // to wait on); a local engine still launching no-ops and gets picked up by the next
        // evaluateAll(). Skipped before the first evaluateAll (nothing to replay yet).
        if let board = lastEvaluatedBoard {
            engine.evaluatePosition(board: board)
        }
    }

    func removeEngine(id: UUID) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }

        let engine = slots[idx].engine

        // 1. Stop analysis and invalidate analysis IDs first — this prevents
        //    in-flight cloud API Tasks from updating @Published properties later.
        engine.stopAnalysis()

        // 2. Compute new selection before mutating the array.
        let needsNewSelection = selectedId == id
        let newSelectedId: UUID?
        if needsNewSelection {
            if slots.count > 1 {
                let nextIdx = idx + 1 < slots.count ? idx + 1 : idx - 1
                newSelectedId = slots[nextIdx].id
            } else {
                newSelectedId = nil
            }
        } else {
            newSelectedId = selectedId
        }

        // 3. Remove the slot from the array.
        slots.remove(at: idx)

        // 4. Apply new selection and rebind the coarse mirrors in one pass.
        if needsNewSelection {
            selectedId = newSelectedId
            bindSelectedFlags()
        }

        // 5. Stop the engine process last, after all published state is consistent.
        engine.stop()
    }

    func selectEngine(id: UUID) {
        guard slots.contains(where: { $0.id == id }) else { return }
        selectedId = id
        bindSelectedFlags()
    }

    /// Re-adds or restarts all engines. Called when engine configs change globally.
    func reconfigure() {
        // If there's a default engine and no slots, set up
        if slots.isEmpty {
            setup()
            return
        }

        // Restart existing engines (config might have changed settings)
        for slot in slots {
            // Re-read the latest config from AppSettings
            if let updated = AppSettings.shared.engines.first(where: { $0.id == slot.config.id }) {
                slot.engine.engineConfig = updated
            }
            slot.engine.restart()
        }
    }

    // MARK: - Analysis

    /// Send position to all active engines for parallel evaluation.
    func evaluateAll(board: ChessBoard, depth: Int? = nil, movetime: Int? = nil) {
        // Remember the current position so an engine ADDED later (before the next move) can be given
        // an immediate evaluation instead of sitting blank until the user advances a move. Copy so a
        // subsequent in-place board mutation can't retroactively change what we replay.
        lastEvaluatedBoard = board.copy()
        for slot in slots {
            // evaluatePosition() synchronously copies the board before any async work, so the extra
            // per-slot copy here was redundant — one wasted 64-square board allocation per engine
            // per move. Pass the board straight through.
            let d = depth ?? slot.config.settings.depth
            slot.engine.evaluatePosition(board: board, depth: d, movetime: movetime)
        }
    }

    /// Stop analysis on all engines.
    func stopAll() {
        for slot in slots {
            slot.engine.stopAnalysis()
        }
    }

    /// Pause every local engine's search but keep its last result frozen on screen (TABS-AND-RAIL
    /// §3.2). Called when this window/tab loses focus. Cloud engines self-exempt.
    func pauseAll() {
        for slot in slots {
            slot.engine.pauseAnalysis()
        }
    }

    /// Resume every engine at its last position, frozen result staying visible until overtaken.
    func resumeAll() {
        for slot in slots {
            slot.engine.resumeAnalysis()
        }
    }

    /// Stop and shutdown all engine processes.
    func stopAllProcesses() {
        for slot in slots {
            slot.engine.stop()
        }
    }

    // MARK: - Speculative (Look-ahead) — Selected Engine Only

    func evaluateSpeculative(board: ChessBoard, depth: Int) {
        selectedEngine?.evaluatePositionSpeculative(board: board, depth: depth)
    }

    func promoteSpeculative() {
        selectedEngine?.promoteSpeculativeResults()
    }

    func discardSpeculative() {
        selectedEngine?.discardSpeculative()
    }

    // MARK: - Private Helpers

    /// Mirror the selected engine's coarse thinking/frozen flags into the manager's own @Published,
    /// so the window observes only these two transitions — not the engine's per-tick eval stream.
    private func bindSelectedFlags() {
        selectedThinkingCancellable?.cancel()
        selectedFrozenCancellable?.cancel()
        selectedThinkingCancellable = nil
        selectedFrozenCancellable = nil

        guard let engine = selectedEngine else {
            selectedIsThinking = false
            selectedIsFrozen = false
            return
        }

        // Sync current values
        selectedIsThinking = engine.isThinking
        selectedIsFrozen = engine.isFrozen

        // Observe future changes (deduped, so each mirror fires only on a real transition)
        selectedThinkingCancellable = engine.$isThinking
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.selectedIsThinking = value
            }
        selectedFrozenCancellable = engine.$isFrozen
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.selectedIsFrozen = value
            }
    }
}
