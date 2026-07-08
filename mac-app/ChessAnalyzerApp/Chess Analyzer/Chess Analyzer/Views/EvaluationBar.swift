import SwiftUI

struct EvaluationBar: View {
    @ObservedObject var engine: StockfishEngine
    var barHeight: CGFloat? = nil

    private let barWidth: CGFloat = 24
    private let minDepthForDisplay: Int = 16

    // Track the last stable evaluation (depth >= 16 or from cache)
    @State private var displayedEval: Double = 0
    @State private var lastEvalUpdateDepth: Int = 0

    // Use displayed evaluation which only updates at sufficient depth
    private var currentEval: Double {
        displayedEval
    }

    var body: some View {
        GeometryReader { geometry in
            let height = barHeight ?? geometry.size.height
            let whiteH = whiteHeight(totalHeight: height)

            ZStack(alignment: .bottom) {
                // Black side (top) - flat
                Rectangle()
                    .fill(Color(white: 0.2))

                // White side (bottom) - flat with smooth animation
                Rectangle()
                    .fill(Color(white: 0.92))
                    .frame(height: whiteH)
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: whiteH)


                // Evaluation text inside the bar
                VStack {
                    if !isPositiveEval {
                        // Black side - show at top
                        Text(evaluationText)
                            .font(AnnFont.mono(8, bold: true))
                            .foregroundColor(.white)
                            .padding(.horizontal, 2)
                            .padding(.top, 8)
                        Spacer()
                    } else {
                        // White side - show at bottom
                        Spacer()
                        Text(evaluationText)
                            .font(AnnFont.mono(8, bold: true))
                            .foregroundColor(.black)
                            .padding(.horizontal, 2)
                            .padding(.bottom, 8)
                    }
                }
                .frame(height: height)
            }
            .frame(width: barWidth, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(DS.hairline, lineWidth: 0.5)
            )
            .shadow(color: DS.glassShadowColor, radius: 3, x: 0, y: 1)
        }
        .frame(width: barWidth)
        .onChange(of: engine.depth) { oldDepth, newDepth in
            // When depth resets (new position), allow immediate update from cache
            if newDepth < oldDepth {
                lastEvalUpdateDepth = 0
            }
            // Update displayed eval when depth reaches threshold
            if newDepth >= minDepthForDisplay, let eval = engine.evaluation {
                displayedEval = eval
                lastEvalUpdateDepth = newDepth
            }
        }
        .onChange(of: engine.evaluation) { _, newEval in
            guard let eval = newEval else { return }

            // If depth is 0 or very low, this is likely a cached value - show immediately
            if engine.depth == 0 || !engine.isThinking {
                displayedEval = eval
                lastEvalUpdateDepth = 0
            }
            // Otherwise only update if we've reached sufficient depth
            else if engine.depth >= minDepthForDisplay {
                displayedEval = eval
                lastEvalUpdateDepth = engine.depth
            }
        }
        .onAppear {
            // Initialize with current evaluation if available
            if let eval = engine.evaluation {
                displayedEval = eval
            }
        }
    }

    private var isPositiveEval: Bool {
        return currentEval >= 0
    }

    private var evaluationText: String {
        let eval = currentEval

        if abs(eval) >= 10000 {
            let mateIn = Int(abs(eval) - 10000)
            if mateIn == 0 {
                // Game over - show result
                return eval > 0 ? "1-0" : "0-1"
            }
            let sign = eval > 0 ? "+" : "-"
            return "\(sign)M\(mateIn)"
        } else {
            let pawnValue = eval / 100.0
            if abs(pawnValue) < 0.05 {
                return "0.0"
            }
            return String(format: "%+.1f", pawnValue)
        }
    }

    private func whiteHeight(totalHeight: CGFloat) -> CGFloat {
        let eval = currentEval

        // Mate scores: fill completely
        if abs(eval) >= 10000 {
            return eval > 0 ? totalHeight : 0
        }

        let pawnValue = min(max(eval / 100.0, -10), 10)
        let normalized = (pawnValue + 10) / 20.0
        return CGFloat(normalized) * totalHeight
    }
}

#Preview {
    HStack(spacing: 20) {
        let engine1 = StockfishEngine()
        EvaluationBar(engine: engine1, barHeight: 400)
            .frame(height: 400)

        let engine2 = StockfishEngine()
        let _ = { engine2.evaluation = 150 }()
        EvaluationBar(engine: engine2, barHeight: 400)
            .frame(height: 400)

        let engine3 = StockfishEngine()
        let _ = { engine3.evaluation = -200 }()
        EvaluationBar(engine: engine3, barHeight: 400)
            .frame(height: 400)
    }
    .padding()
    .background(DS.bg)
}
