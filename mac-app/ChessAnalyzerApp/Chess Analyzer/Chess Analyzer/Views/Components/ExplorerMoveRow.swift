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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DS.textPrimary)

                    if isBookMove {
                        Image(systemName: "book")
                            .font(.system(size: 8))
                            .foregroundColor(DS.accent)
                    }
                }

                // Games count
                Text(formatNumber(totalGames))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                // W/D/L bar — thicker, more visible
                HStack(spacing: 0) {
                    if whitePercent > 0 {
                        Rectangle()
                            .fill(DS.evalWhiteWinning)
                            .frame(width: 80 * whitePercent / 100)
                    }
                    if drawPercent > 0 {
                        Rectangle()
                            .fill(DS.evalNeutral)
                            .frame(width: 80 * drawPercent / 100)
                    }
                    if blackPercent > 0 {
                        Rectangle()
                            .fill(DS.evalBlackWinning)
                            .frame(width: 80 * blackPercent / 100)
                    }
                }
                .frame(width: 80, height: 8)
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
