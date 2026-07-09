import SwiftUI

/// Read-only browser over the reference database (the downloaded master games). Those games live in
/// the SQLite `GameStore` — far too many for SwiftData — so this pages through them directly and opens
/// any game on the board via the standard PGN loader. No editing/deleting (a re-download replaces it).
///
/// Uses the same columnar table layout as `DatabaseBrowserView` for a consistent look. Reference games
/// don't store an event, so that column shows Elo instead (these are rated master games).
struct ReferenceBrowseView: View {
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    let onBack: () -> Void
    let onOpen: (String) -> Void   // reconstructed PGN for the tapped game

    @State private var games: [GameHeader] = []
    @State private var offset = 0
    @State private var exhausted = false
    @State private var isLoading = false
    private let pageSize = 100

    var body: some View {
        VStack(spacing: 0) {
            header
            if games.isEmpty && !isLoading {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Games",
                    description: "This reference database is empty.",
                    iconSize: 40
                )
            } else {
                gamesList
            }
        }
        .background(DS.bgSecondary)
        .onAppear { if games.isEmpty { loadMore() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text("Library").font(AnnFont.label(12)).tracking(12 * 0.1)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(DS.accent)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill").font(.system(size: 11)).foregroundColor(DS.accent)
                Text(referenceDatabase.displayName)
                    .font(AnnFont.serif(13, .semibold)).foregroundColor(DS.textPrimary)
                Text("· \(formatted(referenceDatabase.gameCount)) games · read-only")
                    .font(AnnFont.mono(11)).foregroundColor(DS.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.glassSeparator).frame(height: 1) }
    }

    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(header: tableHeader) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        Button {
                            if let pgn = referenceDatabase.pgn(forGameId: game.id) { onOpen(pgn) }
                        } label: {
                            tableRow(game, isAlternate: index % 2 == 1)
                        }
                        .buttonStyle(.plain)
                        .onAppear { if index == games.count - 10 { loadMore() } }
                    }
                    if isLoading {
                        ProgressView().controlSize(.small).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Table (matches DatabaseBrowserView)

    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerCell("White").frame(width: 180, alignment: .leading)
            headerCell("Black").frame(width: 180, alignment: .leading)
            headerCell("Result").frame(width: 80, alignment: .leading)
            headerCell("Opening").frame(maxWidth: .infinity, alignment: .leading)
            headerCell("Elo").frame(maxWidth: .infinity, alignment: .leading)
            headerCell("Date").frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .frame(height: 34)
        .background(DS.bgSecondary)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private func headerCell(_ title: String) -> some View {
        Text(title)
            .font(AnnFont.label(11, bold: false))
            .tracking(11 * 0.1)
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 8)
    }

    private func tableRow(_ g: GameHeader, isAlternate: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: 0xECECEC)).frame(width: 8, height: 8)
                Text(g.white).font(AnnFont.serif(12)).foregroundColor(DS.textPrimary).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: 180, alignment: .leading)

            HStack(spacing: 6) {
                Circle().fill(Color(hex: 0x262626)).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(DS.textTertiary, lineWidth: 1))
                Text(g.black).font(AnnFont.serif(12)).foregroundColor(DS.textPrimary).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: 180, alignment: .leading)

            Text(resultText(g.result))
                .font(AnnFont.mono(12, bold: true))
                .foregroundColor(resultColor(g.result))
                .padding(.horizontal, 8)
                .frame(width: 80, alignment: .leading)

            Text(openingName(g.eco))
                .font(AnnFont.serif(12)).foregroundColor(DS.textSecondary).lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(eloText(g))
                .font(AnnFont.mono(12)).foregroundColor(DS.textSecondary).lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(dateText(g.date))
                .font(AnnFont.mono(11)).foregroundColor(DS.textTertiary).lineLimit(1)
                .padding(.horizontal, 8)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .frame(height: 38)
        .background(isAlternate ? DS.bgSurface : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.borderSubtle).frame(height: 1) }
        .contentShape(Rectangle())
    }

    // MARK: - Data

    private func loadMore() {
        guard !exhausted, !isLoading else { return }
        isLoading = true
        let batch = referenceDatabase.browse(limit: pageSize, offset: offset)
        games.append(contentsOf: batch)
        offset += batch.count
        if batch.count < pageSize { exhausted = true }
        isLoading = false
    }

    // MARK: - Formatting

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func resultText(_ r: StoredResult) -> String {
        switch r {
        case .whiteWin: return "1-0"
        case .blackWin: return "0-1"
        case .draw:     return "1/2"
        case .unknown:  return "*"
        }
    }

    private func resultColor(_ r: StoredResult) -> Color {
        switch r {
        case .whiteWin, .blackWin: return DS.textPrimary
        default:                   return DS.textTertiary
        }
    }

    private func openingName(_ eco: Int32) -> String {
        guard let code = ReferenceDatabase.decodeECO(eco) else { return "-" }
        return ECODatabase.openings[code] ?? code
    }

    private func eloText(_ g: GameHeader) -> String {
        if g.whiteElo <= 0 && g.blackElo <= 0 { return "-" }
        let w = g.whiteElo > 0 ? "\(g.whiteElo)" : "—"
        let b = g.blackElo > 0 ? "\(g.blackElo)" : "—"
        return "\(w) / \(b)"
    }

    private func dateText(_ d: Int32) -> String {
        guard d > 0 else { return "-" }
        let y = d / 10000, m = (d / 100) % 100, day = d % 100
        return String(format: "%04d.%02d.%02d", y, m, day)
    }
}
