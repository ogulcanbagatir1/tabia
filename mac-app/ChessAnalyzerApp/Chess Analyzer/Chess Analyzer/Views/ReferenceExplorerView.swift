import SwiftUI

/// Opening explorer backed by the large reference database (`GameStore`).
/// Transposition-aware: queries by the current position's Zobrist key over the
/// whole database (any move order), in single-digit milliseconds.
struct ReferenceExplorerView: View {
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    @ObservedObject var board: ChessBoard
    let currentSANs: [String]
    let onMovePlayed: (String) -> Void

    @State private var result = ReferenceExplorerResult()
    @State private var showIndexing = false

    var body: some View {
        VStack(spacing: 0) {
            if !referenceDatabase.isAvailable {
                EmptyStateView(
                    icon: "externaldrive.badge.xmark",
                    title: "Reference DB Unavailable",
                    description: "The reference database could not be opened.",
                    iconSize: 40
                )
            } else if referenceDatabase.gameCount == 0 {
                emptyState
            } else if referenceDatabase.indexedGameCount == 0 {
                notIndexedState
            } else if result.total == 0 && result.moves.isEmpty {
                noGamesInPosition
            } else {
                content
            }
        }
        .background(DS.bgSecondary)
        .sheet(isPresented: $showIndexing) {
            IndexingSheet(referenceDB: referenceDatabase) { showIndexing = false }
        }
        .onAppear { query() }
        .onChange(of: currentSANs) { _, _ in query() }
        .onChange(of: referenceDatabase.gameCount) { _, _ in query() }
        .onChange(of: referenceDatabase.indexedGameCount) { _, _ in query() }
    }

    /// Games are loaded (PHASE 1) but the opening explorer index hasn't been built yet.
    private var notIndexedState: some View {
        VStack(spacing: 14) {
            Spacer()
            if referenceDatabase.isIndexing {
                KnightLoader(size: 44)
                Text("Indexing… \(formatted(referenceDatabase.indexProgress)) games")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.textPrimary)
                Text("Building the opening explorer. This runs in the background.")
                    .font(.system(size: 11)).foregroundColor(DS.textTertiary)
            } else {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 40, weight: .light)).foregroundColor(DS.accent)
                Text("\(formatted(referenceDatabase.gameCount)) games ready")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(DS.textPrimary)
                Text("Build the opening index to search positions. You choose how many games and how deep — with a live size and time estimate.")
                    .font(.system(size: 12)).foregroundColor(DS.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 320)
                Button(action: { showIndexing = true }) {
                    Label("Build opening index", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// The current position isn't found in the indexed subset.
    private var noGamesInPosition: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light)).foregroundColor(DS.textTertiary)
            Text("No Games in Position")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(DS.textPrimary)
            Text("No games reach this position in the indexed set (\(formatted(referenceDatabase.indexedGameCount)) of \(formatted(referenceDatabase.gameCount)) games).")
                .font(.system(size: 12)).foregroundColor(DS.textTertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
            if referenceDatabase.indexedGameCount < referenceDatabase.gameCount {
                Button(action: { showIndexing = true }) {
                    Label("Index more games", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.bordered).controlSize(.regular).padding(.top, 2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            if referenceDatabase.isDownloading {
                KnightLoader(size: 44)
                Text(referenceDatabase.downloadPhase.isEmpty ? "Working…" : referenceDatabase.downloadPhase)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                if referenceDatabase.downloadPhase == "Downloading…" {
                    ProgressView(value: referenceDatabase.downloadProgress).frame(maxWidth: 260)
                    Text("\(Int(referenceDatabase.downloadProgress * 100))%")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(DS.textTertiary)
                } else if referenceDatabase.importProgress > 0 {
                    Text("\(formatted(referenceDatabase.importProgress)) games…")
                        .font(.system(size: 11)).foregroundColor(DS.textTertiary)
                }
                Button(role: .destructive) { referenceDatabase.cancelDownload() } label: {
                    Text(referenceDatabase.isCancellingDownload ? "Cancelling…" : "Cancel")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(referenceDatabase.isCancellingDownload)
                .padding(.top, 2)
            } else if referenceDatabase.isImporting {
                KnightLoader(size: 44)
                Text(referenceDatabase.importProgress > 0
                     ? "Imported \(formatted(referenceDatabase.importProgress)) games…"
                     : "Building the indexed reference database…")
                    .font(.system(size: 12)).foregroundColor(DS.textTertiary)
            } else {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 40, weight: .light)).foregroundColor(DS.accent)
                Text("Empty Reference Database")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(DS.textPrimary)
                Text("Add it from the “＋ New Database” dialog in the Library — choose “Download reference database”.")
                    .font(.system(size: 12)).foregroundColor(DS.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 320)
                if let err = referenceDatabase.downloadError {
                    Text(err).font(.system(size: 10)).foregroundColor(DS.moveBlunder)
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header: total games + W/D/L bar
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("\(formatted(result.total)) games")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                        Spacer()
                        if referenceDatabase.indexedGameCount < referenceDatabase.gameCount {
                            Button(action: { showIndexing = true }) {
                                Label("Index more", systemImage: "plus.square.on.square")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain).foregroundColor(DS.accent)
                        }
                        Text("of \(formatted(referenceDatabase.indexedGameCount)) indexed")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textTertiary)
                    }
                    WDLStatsBar(white: result.white, draws: result.draw, black: result.black)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DS.glassSeparator).frame(height: 1)
                }

                // Moves table
                if !result.moves.isEmpty {
                    movesHeader
                    ForEach(Array(result.moves.enumerated()), id: \.element.id) { index, move in
                        ExplorerMoveRow(
                            san: move.san,
                            totalGames: move.total,
                            whitePercent: percent(move.white, move.total),
                            drawPercent: percent(move.draw, move.total),
                            blackPercent: percent(move.black, move.total),
                            isBookMove: false,
                            isAlternate: index % 2 == 0
                        ) {
                            onMovePlayed(move.uci)
                        }
                    }
                }
            }
        }
    }

    private var movesHeader: some View {
        HStack(spacing: 0) {
            Text("Move")
            Text("Games")
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("W / D / L")
                .frame(width: 90, alignment: .center)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(DS.textTertiary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    // MARK: - Query

    private func query() {
        guard referenceDatabase.isAvailable, referenceDatabase.gameCount > 0 else {
            result = ReferenceExplorerResult()
            return
        }
        result = referenceDatabase.explorer(board: board)
    }

    // MARK: - Helpers

    private func percent(_ n: Int, _ total: Int) -> Double {
        total > 0 ? Double(n) / Double(total) * 100 : 0
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
