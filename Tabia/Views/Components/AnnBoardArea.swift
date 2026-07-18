import SwiftUI

// MARK: - Analysis board area (A1–A3) — players · double-framed board · eval bar · plate line

struct AnnBoardArea: View {
    @ObservedObject var board: ChessBoard
    @ObservedObject var gameTree: GameTree
    // NOT @ObservedObject: the engine publishes evaluation/depth many times per second during
    // analysis. If this view observed it, every tick would re-render the whole area — board grid,
    // both player rows, the plate line. Only the eval bar cares about live eval, so it observes the
    // engine on its own (EvalBarView) and this container stays still during analysis.
    let engine: StockfishEngine
    let boardSize: CGFloat
    let whiteName: String
    let blackName: String
    let whiteRating: String
    let blackRating: String
    let openingName: String?
    let plyCount: Int
    let isFlipped: Bool
    var explorerArrow: BoardArrow? = nil

    // Fixed player-row height so the top and bottom rows are always identical boxes (independent of
    // whose turn it is or whether a rating is present) — this is what keeps them the SAME distance
    // from the board on both sides.
    private let playerRowHeight: CGFloat = 26
    // Equal gap above and below the board. Verified by pixel measurement on a real render: with the
    // board grid now rendering flush in its frame (BoardView's spacers use minLength: 0), the
    // label-center→board distance is exactly gap + 13 (half the row) on BOTH sides, so equal gaps
    // give truly equidistant labels.
    private let topGap: CGFloat = 16
    private let bottomGap: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            // Top player (black by default; white when flipped)
            playerRow(isWhite: isFlipped)
                .frame(width: boardSize + 50, height: playerRowHeight)
                .padding(.bottom, topGap)

            // The board grid now fills its frame flush (BoardView's centering spacers use minLength: 0),
            // so the eval bar aligns simply by being top-aligned at the same height — no offset hack.
            HStack(alignment: .top, spacing: 16) {
                board_
                EvalBarView(engine: engine, boardSize: boardSize)
            }

            // Bottom player — same fixed height + same gap as the top row for exact symmetry.
            playerRow(isWhite: !isFlipped)
                .frame(width: boardSize + 50, height: playerRowHeight)
                .padding(.top, bottomGap)

            // Plate line
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("PLATE \(Self.roman(max(plyCount / 2 + 1, 1)))")
                    .font(AnnFont.mono(10, bold: true)).tracking(1.0).foregroundColor(DS.redAccent)
                Text(caption).font(AnnFont.voice(14)).foregroundColor(DS.ink60)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: boardSize + 50)
            .padding(.top, 20)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
    }

    // The board (BoardView already draws its own aligned border + shadow — no extra frame here).
    private var board_: some View {
        // Labels follow the "Show coordinates" preference — the compact explorer/drill boards opt out
        // explicitly, this one does not.
        BoardView(board: board, gameTree: gameTree, explorerArrow: explorerArrow, isFlipped: isFlipped)
            .frame(width: boardSize, height: boardSize)
    }

    // MARK: Player row

    @ViewBuilder private func playerRow(isWhite: Bool) -> some View {
        let name = isWhite ? whiteName : blackName
        let rating = isWhite ? whiteRating : blackRating
        let display = name.isEmpty ? (isWhite ? "White" : "Black") : name
        HStack(spacing: 10) {
            Circle()
                .fill(isWhite ? DS.boardWhitePiece : DS.boardBlackPiece)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(isWhite ? DS.deepWell : DS.borderStrong, lineWidth: 1))
            Text(display).font(AnnFont.serif(16, .medium)).foregroundColor(DS.ink).lineLimit(1)
            if !rating.isEmpty {
                Text(rating).font(AnnFont.mono(11.5)).foregroundColor(DS.ink60)
            }
            Spacer(minLength: 8)
        }
    }

    // MARK: Derived

    private var caption: String {
        // `gameOver` is set by makeMove, so the expensive status() only runs once the cheap
        // published flag says the game actually ended.
        if board.gameOver {
            let label = board.status().label
            if !label.isEmpty { return label }
        }
        if plyCount == 0 { return "The starting position — your move." }
        if let o = openingName, !o.isEmpty { return o }
        return "Move \(plyCount / 2 + 1)."
    }

    private static func roman(_ n: Int) -> String {
        guard n > 0 else { return "I" }
        let table: [(Int, String)] = [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),
                                       (90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        var num = n, out = ""
        for (v, s) in table { while num >= v { out += s; num -= v } }
        return out
    }
}

// MARK: - Eval bar (the ONLY live-engine observer in the board area)

/// Deep well with a paper fill from the bottom sized to White's win-probability, a red hairline at
/// the boundary, and the absolute advantage printed INSIDE the bar on the winning side. This is the
/// only view in the board column that observes the engine, so eval ticks repaint just this 34pt
/// strip — the board grid, player rows, and plate line above/below stay untouched during analysis.
struct EvalBarView: View {
    @ObservedObject var engine: StockfishEngine
    let boardSize: CGFloat

    // Fill is driven through this so it can travel at a CONSTANT speed (duration scales with the
    // size of the change) rather than snapping or always taking the same time.
    @State private var animFraction: CGFloat = 0.5

    var body: some View {
        let whiteBetter = whiteFraction >= 0.5
        return ZStack {
            GeometryReader { geo in
                let h = geo.size.height
                let fill = animFraction * h
                ZStack(alignment: .bottom) {
                    DS.deepWell
                    Rectangle().fill(DS.wdlWin).frame(height: fill)
                        .overlay(alignment: .top) { Rectangle().fill(DS.redAccent).frame(height: 1.5) }
                }
            }
            VStack(spacing: 0) {
                if !whiteBetter {
                    Text(evalMagnitude).font(AnnFont.label(13.5, bold: true)).foregroundColor(DS.wdlWin)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
                if whiteBetter {
                    Text(evalMagnitude).font(AnnFont.label(13.5, bold: true)).foregroundColor(DS.deepWell)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(width: 34, height: boardSize)
        .clipShape(RoundedRectangle(cornerRadius: DS.rBar))
        .overlay(RoundedRectangle(cornerRadius: DS.rBar).strokeBorder(DS.borderStrong, lineWidth: 1))
        .onAppear { animFraction = whiteFraction }
        .onChange(of: whiteFraction) { _, new in
            // Constant speed: duration grows with how far the bar has to travel.
            let dist = abs(new - animFraction)
            let duration = Double(min(max(dist / 1.1, 0.12), 1.2))
            withAnimation(.linear(duration: duration)) { animFraction = new }
        }
    }

    // Absolute advantage shown on the winning side of the bar (e.g. "1.5", "M3").
    private var evalMagnitude: String {
        guard let eval = engine.evaluation else { return "0.0" }
        if abs(eval) >= 10000 {
            let m = Int(abs(eval) - 10000)
            return m == 0 ? "#" : "M\(m)"
        }
        let pv = abs(Double(eval) / 100.0)
        return pv >= 10 ? String(format: "%.0f", pv) : String(format: "%.1f", pv)
    }

    private var whiteFraction: CGFloat {
        guard let eval = engine.evaluation else { return 0.5 }
        if abs(eval) >= 10000 { return eval > 0 ? 0.98 : 0.02 }
        let wp = 1.0 / (1.0 + exp(-0.00368 * Double(eval)))
        return CGFloat(min(max(wp, 0.03), 0.97))
    }
}
