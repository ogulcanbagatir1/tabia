import SwiftUI

struct WDLStatsBar: View {
    let white: Int
    let draws: Int
    let black: Int
    var showLabels: Bool = true

    private var total: Int { white + draws + black }
    private var wPct: Double { total > 0 ? Double(white) / Double(total) * 100 : 0 }
    private var dPct: Double { total > 0 ? Double(draws) / Double(total) * 100 : 0 }
    private var bPct: Double { total > 0 ? Double(black) / Double(total) * 100 : 0 }

    var body: some View {
        VStack(spacing: 6) {
            // Labels above bar
            if showLabels {
                HStack {
                    Text("White \(Int(wPct))%")
                        .font(AnnFont.mono(10))
                        .foregroundColor(DS.ink60)
                    Spacer()
                    Text("Draw \(Int(dPct))%")
                        .font(AnnFont.mono(10))
                        .foregroundColor(DS.ink40)
                    Spacer()
                    Text("Black \(Int(bPct))%")
                        .font(AnnFont.mono(10))
                        .foregroundColor(DS.ink60)
                }
            }

            // WDL bar
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    if wPct > 0 {
                        Rectangle()
                            .fill(DS.semWin)
                            .frame(width: max(w * wPct / 100, 2))
                    }
                    if dPct > 0 {
                        Rectangle()
                            .fill(DS.semDraw)
                            .frame(width: max(w * dPct / 100, 2))
                    }
                    if bPct > 0 {
                        Rectangle()
                            .fill(DS.semLoss)
                            .frame(width: max(w * bPct / 100, 2))
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 8)
            .frame(maxWidth: .infinity)
        }
    }
}
