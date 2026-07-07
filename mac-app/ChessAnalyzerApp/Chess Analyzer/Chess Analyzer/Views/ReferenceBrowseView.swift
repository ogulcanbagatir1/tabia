import SwiftUI

/// Read-only browser over the reference database (the downloaded master games). Those games live in
/// the SQLite `GameStore` — far too many for SwiftData — so this pages through them directly and opens
/// any game on the board via the standard PGN loader. No editing/deleting (a re-download replaces it).
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
                    Text("Databases").font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(DS.accent)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill").font(.system(size: 11)).foregroundColor(DS.accent)
                Text(referenceDatabase.displayName)
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.textPrimary)
                Text("· \(formatted(referenceDatabase.gameCount)) games · read-only")
                    .font(.system(size: 11)).foregroundColor(DS.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.glassSeparator).frame(height: 1) }
    }

    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    ReferenceGameRow(game: game, isAlternate: index % 2 == 0) {
                        if let pgn = referenceDatabase.pgn(forGameId: game.id) { onOpen(pgn) }
                    }
                    .onAppear { if index == games.count - 10 { loadMore() } }
                }
                if isLoading {
                    ProgressView().controlSize(.small).padding(.vertical, 12)
                }
            }
        }
    }

    private func loadMore() {
        guard !exhausted, !isLoading else { return }
        isLoading = true
        let batch = referenceDatabase.browse(limit: pageSize, offset: offset)
        games.append(contentsOf: batch)
        offset += batch.count
        if batch.count < pageSize { exhausted = true }
        isLoading = false
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct ReferenceGameRow: View {
    let game: GameHeader
    let isAlternate: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(game.white)  —  \(game.black)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if game.whiteElo > 0 || game.blackElo > 0 {
                            Text("\(eloText(game.whiteElo)) / \(eloText(game.blackElo))")
                        }
                        if let eco = ReferenceDatabase.decodeECO(game.eco) { Text(eco) }
                        if game.date > 0 { Text(dateText(game.date)) }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(DS.textTertiary)
                }
                Spacer()
                Text(resultText(game.result))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isAlternate ? Color.white.opacity(0.02) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.glassSeparator).frame(height: 1) }
    }

    private func eloText(_ e: Int32) -> String { e > 0 ? "\(e)" : "—" }
    private func dateText(_ d: Int32) -> String {
        let y = d / 10000, m = (d / 100) % 100, day = d % 100
        return String(format: "%04d.%02d.%02d", y, m, day)
    }
    private func resultText(_ r: StoredResult) -> String {
        switch r {
        case .whiteWin: return "1-0"
        case .blackWin: return "0-1"
        case .draw:     return "½-½"
        case .unknown:  return "*"
        }
    }
}
