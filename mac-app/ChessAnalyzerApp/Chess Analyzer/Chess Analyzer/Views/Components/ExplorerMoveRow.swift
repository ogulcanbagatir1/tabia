import SwiftUI

struct ExplorerMoveRow: View {
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
            HStack(spacing: 8) {
                // Move name
                HStack(spacing: 3) {
                    Text(san)
                        .font(AnnFont.mono(12, bold: true))
                        .foregroundColor(DS.textPrimary)

                    if isBookMove {
                        Image(systemName: "book")
                            .font(.system(size: 8))
                            .foregroundColor(DS.accent)
                    }
                }

                // Games count
                Text(formatNumber(totalGames))
                    .font(AnnFont.mono(11))
                    .foregroundColor(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                // W/D/L mini bar — monochrome paper→ink stack (never green/red),
                // track ground with a hairline between the paper (win) and tan (draw) segments.
                HStack(spacing: 0) {
                    if whitePercent > 0 {
                        Rectangle()
                            .fill(DS.wdlWin)
                            .frame(width: 80 * whitePercent / 100)
                            .overlay(alignment: .trailing) { Rectangle().fill(DS.wdlFrame).frame(width: 1) }
                    }
                    if drawPercent > 0 {
                        Rectangle()
                            .fill(DS.wdlDraw)
                            .frame(width: 80 * drawPercent / 100)
                    }
                    if blackPercent > 0 {
                        Rectangle()
                            .fill(DS.wdlLoss)
                            .frame(width: 80 * blackPercent / 100)
                    }
                }
                .frame(width: 80, height: 6, alignment: .leading)
                .background(DS.trackBg)
                .clipShape(RoundedRectangle(cornerRadius: 2))
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
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
