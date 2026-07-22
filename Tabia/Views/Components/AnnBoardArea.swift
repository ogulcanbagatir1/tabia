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

    // External coordinate gutter: rank digits in a column to the LEFT of the grid, file letters in a
    // row BELOW it. gutterInset = the column width / row height + the gap to the grid. Player rows and
    // the plate line get this as leading padding so their content stays aligned with the grid's left
    // edge (the gutter shifts the grid right).
    private let coordGutter: CGFloat = 15
    private let coordGap: CGFloat = 4
    private var gutterInset: CGFloat { coordGutter + coordGap }
    private var boardSquare: CGFloat { boardSize / 8 }

    var body: some View {
        VStack(spacing: 0) {
            // Top player (black by default; white when flipped)
            playerRow(isWhite: isFlipped)
                .frame(width: boardSize + 48, height: playerRowHeight)
                .padding(.leading, gutterInset)
                .padding(.bottom, topGap)

            // Grid fills its frame flush, so the eval bar aligns by being top-aligned at the same
            // height. The rank column (left) and file row (below) are external, so they neither shrink
            // the grid nor the eval bar — the bar stays exactly boardSize tall, matching the board.
            HStack(alignment: .top, spacing: 14) {
                HStack(alignment: .top, spacing: coordGap) {
                    rankGutter
                    VStack(spacing: coordGap) {
                        board_
                        fileGutter
                    }
                }
                EvalBarView(engine: engine, boardSize: boardSize)
            }

            // Bottom player — same fixed height + same gap as the top row for exact symmetry.
            playerRow(isWhite: !isFlipped)
                .frame(width: boardSize + 48, height: playerRowHeight)
                .padding(.leading, gutterInset)
                .padding(.top, bottomGap)

            // Plate line
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("PLATE \(Self.roman(max(plyCount / 2 + 1, 1)))")
                    .font(AnnFont.mono(10, bold: true)).tracking(1.0).foregroundColor(DS.redAccent)
                Text(caption).font(AnnFont.voice(14)).foregroundColor(DS.ink60)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: boardSize + 48)
            .padding(.top, 20)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
            .padding(.leading, gutterInset)
        }
    }

    // MARK: External coordinate gutters (flip-aware, tracking BoardView's own display order)

    private var displayRanks: [Int] { isFlipped ? Array(0..<8) : Array((0..<8).reversed()) }
    private var displayFiles: [Int] { isFlipped ? Array((0..<8).reversed()) : Array(0..<8) }

    private var showCoords: Bool { AppSettings.shared.showCoordinates }

    @ViewBuilder private var rankGutter: some View {
        if showCoords {
            VStack(spacing: 0) {
                ForEach(displayRanks, id: \.self) { rank in
                    Text("\(rank + 1)")
                        .font(AnnFont.mono(max(9, boardSquare * 0.16)))
                        .foregroundColor(DS.ink40)
                        .frame(width: coordGutter, height: boardSquare)
                }
            }
        } else {
            Color.clear.frame(width: coordGutter, height: boardSize)
        }
    }

    @ViewBuilder private var fileGutter: some View {
        if showCoords {
            HStack(spacing: 0) {
                ForEach(displayFiles, id: \.self) { file in
                    Text(String(UnicodeScalar(UInt8(97 + file))))
                        .font(AnnFont.mono(max(9, boardSquare * 0.16)))
                        .foregroundColor(DS.ink40)
                        .frame(width: boardSquare, height: coordGutter)
                }
            }
        } else {
            Color.clear.frame(width: boardSize, height: coordGutter)
        }
    }

    // The board (BoardView already draws its own aligned border + shadow — no extra frame here).
    // Wrapped in the engine-observing arrow leaf so the best-move arrow updates live WITHOUT this
    // container observing the engine (labels follow the "Show coordinates" preference).
    private var board_: some View {
        EngineArrowBoard(engine: engine, board: board, gameTree: gameTree, isFlipped: isFlipped)
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

// MARK: - Engine best-move arrow (leaf-only engine observer for the board)

/// Supplies BoardView with the engine's best-move arrow. This is the ONLY board-column view that
/// observes the engine, so an eval tick recomputes just the arrow VALUE here; BoardView's stored
/// properties are value-diffable and BoardArrow is Equatable by geometry, so SwiftUI skips
/// BoardView.body whenever the suggested move is unchanged — the 64-square grid is not torn down per
/// tick. Moving this out of MainWindowView is what lets the window stop observing the engine while
/// the arrow stays live.
private struct EngineArrowBoard: View {
    @ObservedObject var engine: StockfishEngine
    @ObservedObject private var settings = AppSettings.shared
    let board: ChessBoard
    let gameTree: GameTree
    let isFlipped: Bool

    var body: some View {
        // showLabels: false — the grid fills its frame flush so the eval bar (same boardSize) matches
        // it exactly. Coordinates are drawn EXTERNALLY by AnnBoardArea (a rank column to the left and a
        // file row below), which keeps them outside the grid without shrinking it or the eval bar.
        BoardView(board: board, gameTree: gameTree, explorerArrow: arrow, isFlipped: isFlipped, showLabels: false)
    }

    /// The engine's top-PV first move as a board arrow, or nil when the arrow is disabled or there is
    /// no line yet. Same conversion the window used to do inline — a bare UCI square pair, no piece.
    private var arrow: BoardArrow? {
        guard settings.showBestMoveArrow,
              let uci = engine.analysisLines.first?.pvMoves.first,
              uci.count >= 4 else { return nil }

        let chars = Array(uci)
        guard let fromFileAscii = chars[0].asciiValue,
              let toFileAscii = chars[2].asciiValue,
              let fromRank = Int(String(chars[1])),
              let toRank = Int(String(chars[3])) else { return nil }

        let a = Int(Character("a").asciiValue!)
        let from = Position(Int(fromFileAscii) - a, fromRank - 1)
        let to = Position(Int(toFileAscii) - a, toRank - 1)
        guard from.isValid() && to.isValid() else { return nil }

        // Only draw the arrow if its origin square actually holds a piece of the side to move on the
        // board CURRENTLY shown. A cloud engine lags behind by its network round-trip, so right after
        // a move its best line is still the previous position's — drawing that on the new board points
        // the arrow from the wrong side. This guard hides the stale arrow until the engine catches up.
        guard let piece = board.pieceAt(from), piece.color == board.turn else { return nil }

        return BoardArrow(from: from, to: to, color: DS.accent.opacity(0.7))
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
