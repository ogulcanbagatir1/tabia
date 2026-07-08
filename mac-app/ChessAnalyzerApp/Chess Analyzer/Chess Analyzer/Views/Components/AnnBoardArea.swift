import SwiftUI

// MARK: - Analysis board area (A1–A3) — players · double-framed board · eval bar · plate line

struct AnnBoardArea: View {
    @ObservedObject var board: ChessBoard
    @ObservedObject var gameTree: GameTree
    @ObservedObject var engine: StockfishEngine
    let boardSize: CGFloat
    let whiteName: String
    let blackName: String
    let whiteRating: String
    let blackRating: String
    let openingName: String?
    let plyCount: Int
    let isFlipped: Bool
    var explorerArrow: BoardArrow? = nil

    var body: some View {
        VStack(spacing: 10) {
            // Top player (black by default; white when flipped)
            playerRow(isWhite: isFlipped).frame(width: boardSize + 31)

            HStack(spacing: 16) {
                board_
                evalBar
            }

            // Bottom player
            playerRow(isWhite: !isFlipped).frame(width: boardSize + 31)

            // Plate line
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("PLATE \(Self.roman(max(plyCount / 2 + 1, 1)))")
                    .font(AnnFont.mono(10, bold: true)).tracking(1.0).foregroundColor(DS.redAccent)
                Text(caption).font(AnnFont.voice(14)).foregroundColor(DS.ink60)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: boardSize + 31)
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
    }

    // The board (BoardView already draws its own aligned border + shadow — no extra frame here).
    private var board_: some View {
        BoardView(board: board, gameTree: gameTree, explorerArrow: explorerArrow, isFlipped: isFlipped, showLabels: false)
            .frame(width: boardSize, height: boardSize)
    }

    // Eval bar — deep well, paper fill from bottom sized to the white win-probability,
    // red hairline at the boundary, mono value below.
    private var evalBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let h = geo.size.height
                let fill = whiteFraction * h
                ZStack(alignment: .bottom) {
                    DS.deepWell
                    Rectangle().fill(DS.wdlWin).frame(height: fill)
                        .overlay(alignment: .top) { Rectangle().fill(DS.redAccent).frame(height: 1.5) }
                }
            }
            .frame(width: 15, height: boardSize)
            .clipShape(RoundedRectangle(cornerRadius: DS.rBar))
            .overlay(RoundedRectangle(cornerRadius: DS.rBar).strokeBorder(DS.borderStrong, lineWidth: 1))

            Text(evalText).font(AnnFont.mono(10.5, bold: true)).foregroundColor(DS.inkData)
        }
    }

    // MARK: Player row

    @ViewBuilder private func playerRow(isWhite: Bool) -> some View {
        let name = isWhite ? whiteName : blackName
        let rating = isWhite ? whiteRating : blackRating
        let display = name.isEmpty ? (isWhite ? "White" : "Black") : name
        let toMove = (board.turn == .white) == isWhite
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
            if toMove { AnnToMoveChip() }
        }
    }

    // MARK: Derived

    private var caption: String {
        if plyCount == 0 { return "The starting position — your move." }
        if let o = openingName, !o.isEmpty { return o }
        return "Move \(plyCount / 2 + 1)."
    }

    private var whiteFraction: CGFloat {
        guard let eval = engine.evaluation else { return 0.5 }
        if abs(eval) >= 10000 { return eval > 0 ? 0.98 : 0.02 }
        let wp = 1.0 / (1.0 + exp(-0.00368 * Double(eval)))
        return CGFloat(min(max(wp, 0.03), 0.97))
    }

    private var evalText: String {
        guard let eval = engine.evaluation else { return "0.0" }
        if abs(eval) >= 10000 {
            let mateIn = Int(abs(eval) - 10000)
            if mateIn == 0 { return eval > 0 ? "1–0" : "0–1" }
            return "\(eval > 0 ? "+" : "-")M\(mateIn)"
        }
        let pv = Double(eval) / 100.0
        if abs(pv) < 0.05 { return "0.0" }
        return String(format: "%+.1f", pv)
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
