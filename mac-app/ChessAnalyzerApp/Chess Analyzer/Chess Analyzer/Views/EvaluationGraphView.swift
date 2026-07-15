import SwiftUI

// MARK: - Evaluation Graph

struct EvaluationGraphView: View {
    @ObservedObject var gameAnalyzer: GameAnalyzer
    @ObservedObject var gameTree: GameTree

    private let graphHeight: CGFloat = 56
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
                .stroke(DS.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                if points.count >= 2 {
                    // Eval line — a single clean stroke on paper (no area fills)
                    Path { path in
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            path.addLine(to: points[i])
                        }
                    }
                    .stroke(DS.ink, lineWidth: 1.3)

                    // Current move indicator — a single green marker on the line
                    if currentMoveIndex < points.count {
                        Circle()
                            .fill(DS.paperRaised)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(DS.moveBrilliant, lineWidth: 2))
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
    var timeClass: String? = nil

    private var resultText: String {
        if gameAnalyzer.whiteAccuracy > gameAnalyzer.blackAccuracy + 5 {
            return "1-0 White wins"
        } else if gameAnalyzer.blackAccuracy > gameAnalyzer.whiteAccuracy + 5 {
            return "0-1 Black wins"
        }
        return "1/2-1/2 Draw"
    }

    var body: some View {
        VStack(spacing: 0) {
                // Header — GAME REVIEW · N MOVES
                HStack(alignment: .firstTextBaseline) {
                    Text("GAME REVIEW")
                        .font(AnnFont.label(11)).tracking(11 * 0.14)
                        .foregroundColor(DS.ink40)
                    Spacer()
                    Text(moveCountLabel)
                        .font(AnnFont.mono(10)).foregroundColor(DS.ink40)
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

                // Accuracies — big serif numbers, grouped to the left
                HStack(alignment: .firstTextBaseline, spacing: 40) {
                    accuracyBlock("White Accuracy", gameAnalyzer.whiteAccuracy, color: DS.ink)
                    accuracyBlock("Black Accuracy", gameAnalyzer.blackAccuracy, color: DS.ink60)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)

                // Evaluation graph — kept low so it never crowds out the moves below
                EvaluationGraphView(gameAnalyzer: gameAnalyzer, gameTree: gameTree)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                    .padding(.horizontal, 16).padding(.bottom, 14)

                // Grade table (grades across the top; White / Black rows)
                gradeTable
                    .padding(.horizontal, 16).padding(.bottom, 14)

                // Move of the game
                if let motg = moveOfTheGame {
                    moveOfGameCallout(motg)
                        .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
    }

    private var moveCountLabel: String {
        let plies = max(0, gameAnalyzer.totalMoves - 1)
        let full = (plies + 1) / 2
        let cls = (timeClass?.isEmpty == false ? timeClass! : "classical").uppercased()
        return "\(full) MOVE\(full == 1 ? "" : "S") · \(cls)"
    }

    private func accuracyBlock(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(format: "%.1f", value))
                .font(AnnFont.serif(30, .semibold)).foregroundColor(color)
            Text(label.uppercased())
                .font(AnnFont.label(9.5)).tracking(9.5 * 0.12).foregroundColor(DS.ink40)
        }
    }

    // MARK: - Grade table

    private struct GradeCol { let sym: String; let qualities: [MoveQuality]; let color: Color }
    private var gradeCols: [GradeCol] {
        [
            GradeCol(sym: "‼", qualities: [.brilliant, .great], color: DS.moveBrilliant),
            GradeCol(sym: "!", qualities: [.best, .good, .okay], color: DS.moveBest),
            GradeCol(sym: "□", qualities: [.book, .neutral], color: DS.moveBook),
            GradeCol(sym: "?!", qualities: [.inaccuracy], color: DS.moveInaccuracy),
            GradeCol(sym: "?", qualities: [.mistake], color: DS.moveMistake),
            GradeCol(sym: "??", qualities: [.blunder], color: DS.moveBlunder),
        ]
    }

    private func gradeSum(_ counts: [MoveQuality: Int], _ qs: [MoveQuality]) -> Int {
        qs.reduce(0) { $0 + (counts[$1] ?? 0) }
    }

    private var gradeTable: some View {
        let w = gameAnalyzer.classificationCounts(forWhite: true)
        let b = gameAnalyzer.classificationCounts(forWhite: false)
        return VStack(spacing: 11) {
            HStack(spacing: 0) {
                Text("GRADE").font(AnnFont.label(8.5)).tracking(0.5).foregroundColor(DS.ink40)
                    .frame(width: 52, alignment: .leading)
                ForEach(gradeCols, id: \.sym) { c in
                    Text(c.sym).font(AnnFont.mono(12, bold: true)).foregroundColor(c.color)
                        .frame(maxWidth: .infinity)
                }
            }
            gradeRow(label: "WHITE", filled: false, counts: w)
            gradeRow(label: "BLACK", filled: true, counts: b)
        }
        .padding(.vertical, 14).padding(.horizontal, 12)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    private func gradeRow(label: String, filled: Bool, counts: [MoveQuality: Int]) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(filled ? DS.ink : DS.onRed).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(DS.ink40, lineWidth: 1))
                Text(label).font(AnnFont.label(9.5)).tracking(0.5).foregroundColor(DS.ink60)
            }
            .frame(width: 52, alignment: .leading)
            ForEach(gradeCols, id: \.sym) { c in
                let n = gradeSum(counts, c.qualities)
                Text("\(n)")
                    .font(AnnFont.mono(13, bold: n > 0))
                    .foregroundColor(n > 0 ? DS.ink : DS.ink25)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Move of the game

    private var moveOfTheGame: (label: String, sym: String, color: Color, note: String)? {
        let cls = gameAnalyzer.moveClassifications
        func swing(_ c: MoveClassification) -> Double { c.isWhiteMove ? c.evalAfter - c.evalBefore : c.evalBefore - c.evalAfter }
        let picks = cls.filter { $0.quality == .brilliant || $0.quality == .great }
        guard let top = picks.max(by: { a, b in
            if a.quality == b.quality { return swing(a) < swing(b) }
            return a.quality == .great   // brilliant outranks great
        }) else { return nil }

        let nodes = gameTree.mainLine
        guard top.moveIndex >= 0, top.moveIndex < nodes.count,
              let san = nodes[top.moveIndex].cachedNotation, !san.isEmpty else { return nil }

        let num = (top.moveIndex + 1) / 2
        let sym = top.quality == .brilliant ? "‼" : "!"
        let color = top.quality == .brilliant ? DS.moveBrilliant : DS.moveGood
        let s = swing(top)
        let note = s >= 0.5
            ? "move of the game — the review's standout, swinging \(String(format: "%+.1f", s))."
            : "move of the game — the review's standout."
        return (label: "\(num).\(san)", sym: sym, color: color, note: note)
    }

    private func moveOfGameCallout(_ m: (label: String, sym: String, color: Color, note: String)) -> some View {
        (Text("\(m.label)\(m.sym)  ").font(AnnFont.mono(12.5, bold: true)).foregroundColor(m.color)
         + Text(m.note).font(AnnFont.voice(13)).foregroundColor(DS.ink60))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    side == .black ? Circle().strokeBorder(DS.borderChip, lineWidth: 1) : nil
                )
                .frame(width: 12, height: 12)

            // Side label
            Text(side == .white ? "White" : "Black")
                .font(AnnFont.label(10))
                .tracking(10 * 0.1)
                .foregroundColor(DS.ink40)

            // Accuracy score
            Text(String(format: "%.1f", accuracy))
                .font(AnnFont.mono(22, bold: true))
                .foregroundColor(DS.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DS.hairline, lineWidth: 1)
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
                .font(AnnFont.serif(12, .medium))
                .foregroundColor(DS.ink)

            Spacer()

            Text("\(whiteCount)")
                .font(AnnFont.mono(12))
                .foregroundColor(DS.ink60)
                .frame(width: 40, alignment: .trailing)

            Text("\(blackCount)")
                .font(AnnFont.mono(12))
                .foregroundColor(DS.ink60)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 28)
    }
}
