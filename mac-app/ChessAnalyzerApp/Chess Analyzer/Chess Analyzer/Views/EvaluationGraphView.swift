import SwiftUI

// MARK: - Evaluation Graph

struct EvaluationGraphView: View {
    @ObservedObject var gameAnalyzer: GameAnalyzer
    @ObservedObject var gameTree: GameTree

    private let graphHeight: CGFloat = 80
    private let evalClamp: Double = 5.0

    private var currentMoveIndex: Int {
        guard let idx = gameTree.mainLine.firstIndex(where: { $0 === gameTree.currentNode }) else {
            return 0
        }
        return idx
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = graphHeight
            let points = evaluationPoints(width: width, height: height)

            ZStack(alignment: .topLeading) {
                // Center line
                Path { path in
                    let centerY = height / 2
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: width, y: centerY))
                }
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                if points.count >= 2 {
                    // White area (above center)
                    Path { path in
                        let centerY = height / 2
                        path.move(to: CGPoint(x: points[0].x, y: centerY))
                        for point in points {
                            path.addLine(to: CGPoint(x: point.x, y: min(point.y, centerY)))
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: centerY))
                        path.closeSubpath()
                    }
                    .fill(Color.white.opacity(0.05))

                    // Black area (below center)
                    Path { path in
                        let centerY = height / 2
                        path.move(to: CGPoint(x: points[0].x, y: centerY))
                        for point in points {
                            path.addLine(to: CGPoint(x: point.x, y: max(point.y, centerY)))
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: centerY))
                        path.closeSubpath()
                    }
                    .fill(Color.white.opacity(0.03))

                    // Eval line
                    Path { path in
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            path.addLine(to: points[i])
                        }
                    }
                    .stroke(Color(hex: 0xFFFFFF, opacity: 0.67), lineWidth: 1.5)

                    // Current move indicator
                    if currentMoveIndex < points.count {
                        let indicatorX = points[currentMoveIndex].x
                        Path { path in
                            path.move(to: CGPoint(x: indicatorX, y: 0))
                            path.addLine(to: CGPoint(x: indicatorX, y: height))
                        }
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.white.opacity(0.4), radius: 3)
                            .position(points[currentMoveIndex])
                    }
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, width: width)
            }
        }
        .frame(height: graphHeight)
    }

    private func evaluationPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let evals = gameAnalyzer.evaluations
        guard evals.count >= 2 else { return [] }

        let count = evals.count
        let centerY = height / 2

        return evals.enumerated().map { index, eval in
            let x = width * CGFloat(index) / CGFloat(count - 1)

            let pawnEval: Double
            if abs(eval) >= 10000 {
                pawnEval = eval > 0 ? evalClamp : -evalClamp
            } else {
                pawnEval = min(max(eval / 100.0, -evalClamp), evalClamp)
            }

            let normalizedY = -pawnEval / evalClamp
            let y = centerY + CGFloat(normalizedY) * centerY

            return CGPoint(x: x, y: y)
        }
    }

    private func handleTap(at location: CGPoint, width: CGFloat) {
        let evals = gameAnalyzer.evaluations
        guard evals.count >= 2 else { return }

        let fraction = location.x / width
        let index = Int(round(fraction * Double(evals.count - 1)))
        let clampedIndex = max(0, min(index, gameTree.mainLine.count - 1))

        gameTree.goToNode(gameTree.mainLine[clampedIndex])
    }
}

// MARK: - Game Analysis Results View

struct GameAnalysisResultsView: View {
    @ObservedObject var gameAnalyzer: GameAnalyzer
    @ObservedObject var gameTree: GameTree

    private var resultText: String {
        if gameAnalyzer.whiteAccuracy > gameAnalyzer.blackAccuracy + 5 {
            return "1-0 White wins"
        } else if gameAnalyzer.blackAccuracy > gameAnalyzer.whiteAccuracy + 5 {
            return "0-1 Black wins"
        }
        return "1/2-1/2 Draw"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0x0A84FF))
                        Text("Game Review")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
                    }
                    Spacer()
                    Text(resultText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }

                // Eval graph
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evaluation")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))

                    EvaluationGraphView(
                        gameAnalyzer: gameAnalyzer,
                        gameTree: gameTree
                    )
                    .frame(height: 120)
                    .background(Color.white.opacity(0.047), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(14)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }

                // Accuracy cards
                HStack(spacing: 12) {
                    PlayerAccuracyCard(
                        side: .white,
                        accuracy: gameAnalyzer.whiteAccuracy
                    )
                    PlayerAccuracyCard(
                        side: .black,
                        accuracy: gameAnalyzer.blackAccuracy
                    )
                }
                .padding(14)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }

                // Move Classification
                VStack(alignment: .leading, spacing: 8) {
                    Text("Move Classification")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))

                    // Column headers
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 8)
                        Text("Type")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.33))
                        Spacer()
                        Text("White")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.33))
                            .frame(width: 40, alignment: .trailing)
                        Text("Black")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.33))
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.bottom, 4)

                    let whiteCounts = gameAnalyzer.classificationCounts(forWhite: true)
                    let blackCounts = gameAnalyzer.classificationCounts(forWhite: false)

                    ForEach(MoveQuality.allCases.filter { $0 != .neutral }, id: \.rawValue) { quality in
                        ClassificationRow(
                            quality: quality,
                            whiteCount: whiteCounts[quality] ?? 0,
                            blackCount: blackCounts[quality] ?? 0
                        )
                    }
                }
                .padding(14)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Player Accuracy Card

struct PlayerAccuracyCard: View {
    let side: PieceColor
    let accuracy: Double

    var body: some View {
        VStack(spacing: 6) {
            // Side dot
            Circle()
                .fill(side == .white ? Color(hex: 0xECECEC) : Color(hex: 0x262626))
                .overlay(
                    side == .black ? Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) : nil
                )
                .frame(width: 12, height: 12)

            // Side label
            Text(side == .white ? "White" : "Black")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.33))

            // Accuracy score
            Text(String(format: "%.1f", accuracy))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.white.opacity(0.047), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Classification Row

struct ClassificationRow: View {
    let quality: MoveQuality
    let whiteCount: Int
    let blackCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(quality.color)
                .frame(width: 8, height: 8)

            Text(quality.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))

            Spacer()

            Text("\(whiteCount)")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                .frame(width: 40, alignment: .trailing)

            Text("\(blackCount)")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 28)
    }
}
