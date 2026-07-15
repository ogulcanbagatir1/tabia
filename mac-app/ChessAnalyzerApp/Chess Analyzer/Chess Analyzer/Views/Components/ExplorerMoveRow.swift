import SwiftUI

/// Shared column geometry so the header row and every move row line up exactly.
/// Wide layout: MOVE · CONTINUATION · GAMES · SHARE · RESULTS.
/// Compact layout (narrow analysis-side panel): MOVE · GAMES · RESULTS.
enum ExplorerCols {
    static func move(_ compact: Bool) -> CGFloat { compact ? 78 : 96 }
    static func games(_ compact: Bool) -> CGFloat { compact ? 78 : 86 }
    static let share: CGFloat = 66
    static func results(_ compact: Bool) -> CGFloat { compact ? 66 : 140 }
    /// Width below which the middle columns (continuation, share) are dropped.
    static let compactThreshold: CGFloat = 460
}

// MARK: - Column header

struct ExplorerColumnHeader: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            label("Move")
                .padding(.horizontal, 8)
                .frame(width: ExplorerCols.move(compact), alignment: .leading)

            if !compact {
                label("Continuation")
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // GAMES header — flexible in compact so it sits above the (now flexible) number column
            gamesHeaderCell

            if !compact {
                label("Share")
                    .padding(.horizontal, 8)
                    .frame(width: ExplorerCols.share, alignment: .trailing)
            }

            label("Results")
                .padding(.horizontal, 8)
                .frame(width: ExplorerCols.results(compact), alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    @ViewBuilder private var gamesHeaderCell: some View {
        let cell = label("Games").padding(.horizontal, 8)
        if compact {
            cell.frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            cell.frame(width: ExplorerCols.games(false), alignment: .trailing)
        }
    }

    private func label(_ s: String) -> some View {
        Text(s.uppercased())
            .font(AnnFont.label(9.5)).tracking(9.5 * 0.12)
            .foregroundColor(DS.ink40)
    }
}

// MARK: - Move row

struct ExplorerMoveRow: View {
    var movePrefix: String = ""
    let san: String
    var continuation: String = ""
    let totalGames: Int
    let whitePercent: Double
    let drawPercent: Double
    let blackPercent: Double
    var share: Double = 0
    var isBookMove: Bool = false
    var isAlternate: Bool = false
    var compact: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // MOVE
                HStack(spacing: 4) {
                    Text(verbatim: "\(movePrefix)\(san)")
                        .font(AnnFont.mono(12.5, bold: true))
                        .foregroundColor(DS.ink)
                    if isBookMove {
                        Image(systemName: "book")
                            .font(.system(size: 8))
                            .foregroundColor(DS.redAccent)
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: ExplorerCols.move(compact), alignment: .leading)

                // CONTINUATION (wide only)
                if !compact {
                    Text(continuation)
                        .font(AnnFont.voice(13))
                        .foregroundColor(DS.ink60)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // GAMES — full number with thousands separators; flexible in compact so a large
                // count uses the free room left by the hidden continuation/share columns.
                gamesCell

                // SHARE (wide only)
                if !compact {
                    Text(sharePercent)
                        .font(AnnFont.mono(11))
                        .foregroundColor(DS.ink40)
                        .padding(.horizontal, 8)
                        .frame(width: ExplorerCols.share, alignment: .trailing)
                }

                // RESULTS — W/D/L bar (monochrome paper→ink stack, never green/red)
                wdlBar
                    .padding(.horizontal, 8)
                    .frame(width: ExplorerCols.results(compact), alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    @ViewBuilder private var gamesCell: some View {
        let cell = Text(formatNumber(totalGames))
            .font(AnnFont.mono(11.5))
            .foregroundColor(DS.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
        if compact {
            cell.frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            cell.frame(width: ExplorerCols.games(false), alignment: .trailing)
        }
    }

    private var wdlBar: some View {
        let barW = ExplorerCols.results(compact) - 16
        return HStack(spacing: 0) {
            if whitePercent > 0 {
                Rectangle()
                    .fill(DS.wdlWin)
                    .frame(width: barW * whitePercent / 100)
                    .overlay(alignment: .trailing) { Rectangle().fill(DS.wdlFrame).frame(width: 1) }
            }
            if drawPercent > 0 {
                Rectangle().fill(DS.wdlDraw).frame(width: barW * drawPercent / 100)
            }
            if blackPercent > 0 {
                Rectangle().fill(DS.wdlLoss).frame(width: barW * blackPercent / 100)
            }
        }
        .frame(width: barW, height: 9, alignment: .leading)
        .background(DS.trackBg)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        // Frame the whole bar so the near-white "wins" segment stays visible on the paper row.
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(DS.wdlFrame, lineWidth: 1))
    }

    private var sharePercent: String {
        share > 0 ? "\(Int(round(share)))%" : ""
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
