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

    // MARK: - Private

    /// Subscriptions for forwarding objectWillChange from each engine.
    private var engineCancellables: [UUID: AnyCancellable] = [:]

    /// Subscription for tracking the selected engine's isThinking.
    private var selectedThinkingCancellable: AnyCancellable?

    /// A dummy engine used as a fallback when no engine is selected,
    /// so views that expect a non-optional StockfishEngine always work.
    private let fallbackEngine = StockfishEngine()

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
        engineCancellables.removeAll()
        selectedThinkingCancellable = nil
        selectedId = nil
        selectedIsThinking = false
    }

    // MARK: - Engine Management

    func addEngine(_ config: EngineConfig) {
        guard !slots.contains(where: { $0.id == config.id }) else { return }

        let engine = StockfishEngine()
        engine.engineConfig = config
        let slot = EngineSlot(id: config.id, config: config, engine: engine)

        // Forward objectWillChange from this engine so SwiftUI re-renders.
        // THROTTLED: Stockfish publishes evaluation/depth/PV lines many times per second
        // during analysis; forwarding each one re-renders the entire MainWindowView (all three
        // columns + board). Coalesce to ~10 Hz (latest wins) so the live eval stays responsive
        // without turning every info line into a full-window relayout. Combined with the
        // source-level dedup in StockfishEngine, this is what keeps the analysis screen fluid.
        let cancellable = engine.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        engineCancellables[config.id] = cancellable

        slots.append(slot)

        if selectedId == nil {
            selectEngine(id: config.id)
        }

        engine.start()
    }

    func removeEngine(id: UUID) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }

        let engine = slots[idx].engine

        // 1. Stop analysis and invalidate analysis IDs first — this prevents
        //    in-flight cloud API Tasks from updating @Published properties later.
        engine.stopAnalysis()

        // 2. Sever objectWillChange forwarding so engine.stop() doesn't
        //    trigger SwiftUI re-renders with stale state.
        engineCancellables.removeValue(forKey: id)

        // 3. Compute new selection before mutating the array.
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

        // 4. Remove the slot from the array.
        slots.remove(at: idx)

        // 5. Apply new selection and rebind thinking in one pass.
        if needsNewSelection {
            selectedId = newSelectedId
            bindSelectedThinking()
        }

        // 6. Stop the engine process last, after all published state is consistent.
        engine.stop()
    }

    func selectEngine(id: UUID) {
        guard slots.contains(where: { $0.id == id }) else { return }
        selectedId = id
        bindSelectedThinking()
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

    private func bindSelectedThinking() {
        selectedThinkingCancellable?.cancel()
        selectedThinkingCancellable = nil

        guard let engine = selectedEngine else {
            selectedIsThinking = false
            return
        }

        // Sync current value
        selectedIsThinking = engine.isThinking

        // Observe future changes
        selectedThinkingCancellable = engine.$isThinking
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.selectedIsThinking = value
            }
    }
}
