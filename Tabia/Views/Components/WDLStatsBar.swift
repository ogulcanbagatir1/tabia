import SwiftUI

/// Win / Draw / Loss distribution as a monochrome paper→ink stack (never green/red).
///
/// The Annotator design: white wins = paper (`wdlWin`), draws = tan (`wdlDraw`),
/// black wins = ink (`wdlLoss`), framed with `wdlFrame`.
/// - `showLabels: true`  → framed 22px bar with the percentage centered inside each segment.
/// - `showLabels: false` → slim 6px mini bar over a track ground (inline in move rows).
struct WDLStatsBar: View {
    let white: Int
    let draws: Int
    let black: Int
    var showLabels: Bool = true

    private var total: Int { white + draws + black }
    private var wPct: Double { total > 0 ? Double(white) / Double(total) * 100 : 0 }
    private var dPct: Double { total > 0 ? Double(draws) / Double(total) * 100 : 0 }
    private var bPct: Double { total > 0 ? Double(black) / Double(total) * 100 : 0 }

    // Segment backgrounds are near-constant across modes, so the in-segment text colours are fixed
    // to the segment they sit on: dark ink on the cream/tan segments, light on the ink segment.
    private let winText  = Color(hex: 0x4A4130)   // on paper (cream)
    private let lossText = Color(hex: 0xD9CFB8)   // on ink

    var body: some View {
        if showLabels { framedBar } else { miniBar }
    }

    // 22px framed bar — percentage centered inside each segment.
    private var framedBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                segment(pct: wPct, width: w, fill: DS.wdlWin,  text: winText)
                segment(pct: dPct, width: w, fill: DS.wdlDraw, text: DS.ink)
                segment(pct: bPct, width: w, fill: DS.wdlLoss, text: lossText)
            }
        }
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.rBar))
        .overlay(RoundedRectangle(cornerRadius: DS.rBar).strokeBorder(DS.wdlFrame, lineWidth: 1))
    }

    @ViewBuilder
    private func segment(pct: Double, width: CGFloat, fill: Color, text: Color) -> some View {
        if pct > 0 {
            Rectangle()
                .fill(fill)
                .frame(width: max(width * pct / 100, 2))
                .overlay {
                    if pct >= 9 {
                        Text("\(Int(pct.rounded()))%")
                            .font(AnnFont.mono(10.5, bold: true))
                            .foregroundColor(text)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
        }
    }

    // 6px mini bar — track ground, hairline between the paper (win) and tan (draw) segments.
    private var miniBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                if wPct > 0 {
                    Rectangle().fill(DS.wdlWin).frame(width: w * wPct / 100)
                        .overlay(alignment: .trailing) { Rectangle().fill(DS.wdlFrame).frame(width: 1) }
                }
                if dPct > 0 { Rectangle().fill(DS.wdlDraw).frame(width: w * dPct / 100) }
                if bPct > 0 { Rectangle().fill(DS.wdlLoss).frame(width: w * bPct / 100) }
            }
            .frame(width: w, alignment: .leading)
        }
        .frame(height: 6)
        .frame(maxWidth: .infinity)
        .background(DS.trackBg)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
