import SwiftUI

struct ExplorerMoveRow: View {
    var movePrefix: String = ""
    let san: String
    let totalGames: Int
    let whitePercent: Double
    let drawPercent: Double
    let blackPercent: Double
    var isBookMove: Bool = false
    var isAlternate: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Move — number prefix + SAN
                HStack(spacing: 3) {
                    Text(verbatim: "\(movePrefix)\(san)")
                        .font(AnnFont.mono(12.5, bold: true))
                        .foregroundColor(DS.ink)
                        .fixedSize()

                    if isBookMove {
                        Image(systemName: "book")
                            .font(.system(size: 8))
                            .foregroundColor(DS.redAccent)
                    }
                }

                Spacer(minLength: 6)

                // W/D/L mini bar — monochrome paper→ink stack (never green/red).
                HStack(spacing: 0) {
                    if whitePercent > 0 {
                        Rectangle()
                            .fill(DS.wdlWin)
                            .frame(width: 62 * whitePercent / 100)
                            .overlay(alignment: .trailing) { Rectangle().fill(DS.wdlFrame).frame(width: 1) }
                    }
                    if drawPercent > 0 {
                        Rectangle().fill(DS.wdlDraw).frame(width: 62 * drawPercent / 100)
                    }
                    if blackPercent > 0 {
                        Rectangle().fill(DS.wdlLoss).frame(width: 62 * blackPercent / 100)
                    }
                }
                .frame(width: 62, height: 6, alignment: .leading)
                .background(DS.trackBg)
                .clipShape(RoundedRectangle(cornerRadius: 2))

                // Games count — full number with thousands separators
                Text(formatNumber(totalGames))
                    .font(AnnFont.mono(11))
                    .foregroundColor(DS.ink60)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isAlternate ? DS.hoverWash : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
