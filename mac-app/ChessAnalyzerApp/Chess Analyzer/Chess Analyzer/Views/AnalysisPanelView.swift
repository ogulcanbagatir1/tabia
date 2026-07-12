import SwiftUI

struct AnalysisPanelView: View {
    @ObservedObject var multiEngine: MultiEngineManager
    @ObservedObject var gameTree: GameTree
    @Binding var autoAnalyze: Bool
    @ObservedObject var gameAnalyzer: GameAnalyzer
    var onStartAnalysis: () -> Void
    var onCancelAnalysis: () -> Void
    var onNavigateToEngines: () -> Void
    /// Hides the Analyze/Cancel button — useful in contexts (e.g. repertoire editor) where running
    /// a full game analysis is meaningless.
    var showAnalyzeButton: Bool = true

    @ObservedObject private var settings = AppSettings.shared

    private var currentMoveNumber: Int { gameTree.currentNode.boardState.fullMoveNumber }
    private var currentTurn: PieceColor { gameTree.currentNode.boardState.turn }

    private var analysisPercentage: Int {
        guard gameAnalyzer.totalMoves > 0 else { return 0 }
        return Int(Double(gameAnalyzer.currentMoveIndex) / Double(gameAnalyzer.totalMoves) * 100)
    }

    private var selectedEngine: StockfishEngine {
        multiEngine.primaryEngine
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            engineHeader

            // Content
            if gameAnalyzer.isAnalyzing {
                analysisProgress
            } else if settings.engines.isEmpty && !multiEngine.anyEngineAvailable && multiEngine.slots.isEmpty {
                noEnginePrompt
            } else {
                // Engine eval list (compact: just eval per engine)
                if multiEngine.slots.count > 1 {
                    engineEvalList
                }

                // PV lines for selected engine
                engineLines
            }
        }
        .clipped()
    }

    // MARK: - Engine Header

    private var headerEvalText: String {
        guard let eval = selectedEngine.evaluation else { return "—" }
        if abs(eval) >= 10000 {
            let mateIn = Int(abs(eval) - 10000)
            if mateIn == 0 { return eval > 0 ? "1-0" : "0-1" }
            return "\(eval > 0 ? "+" : "-")M\(mateIn)"
        }
        let pv = eval / 100.0
        if abs(pv) < 0.05 { return "0.00" }
        return String(format: "%+.2f", pv)
    }

    private var headerEvalColor: Color {
        guard let eval = selectedEngine.evaluation else { return DS.evalNeutral }
        let pv = eval / 100.0
        if abs(pv) < 0.3 { return DS.evalNeutral }
        return eval > 0 ? DS.evalWhiteWinning : DS.evalBlackWinning
    }

    private var headerEvalTextColor: Color {
        guard let eval = selectedEngine.evaluation else { return .white }
        let pv = eval / 100.0
        if abs(pv) < 0.3 { return .white }
        return eval > 0 ? .black : .white
    }

    private var engineHeader: some View {
        HStack(spacing: 6) {
            // Engine name + depth
            Text(multiEngine.selectedConfig?.name ?? "Engine")
                .font(AnnFont.serif(12, .semibold))
                .foregroundColor(DS.textPrimary)

            if !gameAnalyzer.isAnalyzing && selectedEngine.depth > 0 {
                Text("d\(selectedEngine.depth)")
                    .font(AnnFont.mono(9, bold: true))
                    .foregroundColor(DS.textTertiary)
            }

            if !gameAnalyzer.isAnalyzing && selectedEngine.isThinking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.5)
            }

            Spacer()

            // Eval badge
            if !gameAnalyzer.isAnalyzing {
                Text(headerEvalText)
                    .font(AnnFont.mono(11, bold: true))
                    .foregroundColor(headerEvalTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(headerEvalColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            // Add engine menu + Analyze button
            if !multiEngine.availableToAdd.isEmpty {
                Menu {
                    ForEach(multiEngine.availableToAdd) { config in
                        Button(action: { multiEngine.addEngine(config) }) {
                            Label(config.name, systemImage: "plus")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add engine to analysis")
            }

            if showAnalyzeButton {
                if gameAnalyzer.isAnalyzing {
                    Button(action: onCancelAnalysis) {
                        Text("Cancel")
                            .glassButtonDestructive()
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onStartAnalysis) {
                        Text("Analyze")
                            .glassButtonSmallPrimary()
                    }
                    .buttonStyle(.plain)
                    .disabled(!multiEngine.anyEngineAvailable)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    // MARK: - Engine Eval List (compact rows for each active engine)

    private var engineEvalList: some View {
        VStack(spacing: 0) {
            ForEach(multiEngine.slots) { slot in
                EngineEvalRow(
                    slot: slot,
                    isSelected: slot.id == multiEngine.selectedId,
                    onSelect: { multiEngine.selectEngine(id: slot.id) },
                    onRemove: { multiEngine.removeEngine(id: slot.id) },
                    canRemove: multiEngine.slots.count > 1
                )
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    // MARK: - Engine Lines (PV for selected engine only)

    private var engineLines: some View {
        VStack(spacing: 0) {
            ForEach(1...3, id: \.self) { lineId in
                if let line = selectedEngine.analysisLines.first(where: { $0.id == lineId }) {
                    AnalysisLineRow(line: line, moveNumber: currentMoveNumber, sideToMove: currentTurn, isTopLine: lineId == 1)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(lineId % 2 != 0 ? DS.hoverWash : Color.clear)
                } else {
                    AnalysisLinePlaceholder(isLoading: selectedEngine.isThinking)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Analysis Progress

    private var analysisProgress: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Analyzing game...")
                    .font(AnnFont.serif(11, .medium))
                    .foregroundColor(DS.textPrimary)
                Spacer()
                Text("\(analysisPercentage)%")
                    .font(AnnFont.mono(11, bold: true))
                    .foregroundColor(DS.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.glassSeparator)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.accent)
                        .frame(width: geo.size.width * CGFloat(analysisPercentage) / 100)
                        .animation(.easeInOut(duration: 0.3), value: analysisPercentage)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    // MARK: - No Engine Prompt

    private var noEnginePrompt: some View {
        VStack(spacing: DS.spacingMD) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 24))
                .foregroundColor(DS.textSecondary)

            Text("No Engine Installed")
                .font(DS.bodyFont)
                .fontWeight(.medium)

            Text("Download a chess engine to enable\nposition analysis and game review.")
                .font(DS.captionFont)
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onNavigateToEngines) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download Engine")
                }
                .glassButtonPrimary()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.spacingLG)
    }
}

// MARK: - Engine Eval Row (compact row per engine showing just eval)

struct EngineEvalRow: View {
    let slot: MultiEngineManager.EngineSlot
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let canRemove: Bool

    private var engine: StockfishEngine { slot.engine }

    /// Build an eval text from the engine's current evaluation
    private var evalText: String {
        guard let eval = engine.evaluation else { return "—" }

        if abs(eval) >= 10000 {
            let mateIn = Int(abs(eval) - 10000)
            if mateIn == 0 {
                return eval > 0 ? "1-0" : "0-1"
            }
            let sign = eval > 0 ? "+" : "-"
            return "\(sign)M\(mateIn)"
        }
        let pawnValue = eval / 100.0
        if abs(pawnValue) < 0.05 { return "0.00" }
        return String(format: "%+.2f", pawnValue)
    }

    private var evalColor: Color {
        guard let eval = engine.evaluation else { return DS.evalNeutral }
        if abs(eval) >= 10000 {
            let mateIn = Int(abs(eval) - 10000)
            if mateIn == 0 { return DS.evalGameOver }
        }
        let pawnValue = eval / 100.0
        if abs(pawnValue) < 0.3 { return DS.evalNeutral }
        return eval > 0 ? DS.evalWhiteWinning : DS.evalBlackWinning
    }

    private var evalTextColor: Color {
        guard let eval = engine.evaluation else { return .white }
        if abs(eval) >= 10000 {
            let mateIn = Int(abs(eval) - 10000)
            if mateIn == 0 { return .white }
        }
        if abs(eval / 100.0) < 0.3 { return .white }
        return eval > 0 ? .black : .white
    }

    var body: some View {
        HStack(spacing: 8) {
            // Selection indicator
            Circle()
                .fill(isSelected ? DS.accent : Color.clear)
                .frame(width: 6, height: 6)

            // Engine name
            Image(systemName: slot.config.source == .cloud ? "cloud" : "cpu")
                .font(.system(size: 10))
                .foregroundColor(DS.textTertiary)

            Text(slot.config.name)
                .font(AnnFont.serif(11, isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? DS.textPrimary : DS.textSecondary)
                .lineLimit(1)

            // Depth badge
            if engine.depth > 0 {
                Text("d\(engine.depth)")
                    .font(AnnFont.mono(8, bold: true))
                    .foregroundColor(DS.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 2))
            }

            // Thinking spinner
            if engine.isThinking {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.5)
            }

            Spacer()

            // Eval badge
            Text(evalText)
                .font(AnnFont.mono(10, bold: true))
                .foregroundColor(evalTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(evalColor)
                )

            // Remove button (only if more than one engine)
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Remove \(slot.config.name)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? DS.accent.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Analysis Line Row

struct AnalysisLineRow: View {
    let line: AnalysisLine
    var moveNumber: Int = 1
    var sideToMove: PieceColor = .white
    var isTopLine: Bool = false

    private var formattedPV: String {
        let moves = line.pvNotation
        guard !moves.isEmpty else { return "" }

        var result = ""
        var num = moveNumber
        var isWhite = sideToMove == .white

        for move in moves {
            if isWhite {
                if !result.isEmpty { result += " " }
                result += "\(num). \(move)"
            } else {
                if result.isEmpty {
                    result += "\(num)... \(move)"
                } else {
                    result += " \(move)"
                }
                num += 1
            }
            isWhite.toggle()
        }
        return result
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Eval text
            Text(line.evaluationText)
                .font(AnnFont.mono(13, bold: true))
                .foregroundColor(DS.ink)

            // PV text
            if !line.isGameOver {
                Text(formattedPV)
                    .font(AnnFont.mono(13))
                    .foregroundColor(DS.inkPV)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(line.isPositive ? "White wins by checkmate" : "Black wins by checkmate")
                    .font(AnnFont.serif(13, .regular))
                    .foregroundColor(DS.ink60)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Analysis Line Placeholder

struct AnalysisLinePlaceholder: View {
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(DS.glassSeparator)
                .frame(width: 40, height: 20)

            if isLoading {
                Text("...")
                    .font(AnnFont.mono(13))
                    .foregroundColor(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(" ")
                    .font(AnnFont.mono(13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    let multiEngine = MultiEngineManager()
    let gameTree = GameTree()
    let analyzer = GameAnalyzer()

    return AnalysisPanelView(
        multiEngine: multiEngine,
        gameTree: gameTree,
        autoAnalyze: .constant(true),
        gameAnalyzer: analyzer,
        onStartAnalysis: {},
        onCancelAnalysis: {},
        onNavigateToEngines: {}
    )
    .frame(width: 300, height: 300)
}
