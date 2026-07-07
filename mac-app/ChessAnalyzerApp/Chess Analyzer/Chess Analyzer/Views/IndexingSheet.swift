import SwiftUI

/// Lets the user build the opening-explorer position index on demand: pick a SCOPE (which games) and
/// DEPTH (how many moves), see the live size/time estimate, then build. Reusable for the hosted
/// reference DB and for the user's own imports.
struct IndexingSheet: View {
    @ObservedObject var referenceDB: ReferenceDatabase
    var onClose: () -> Void

    enum Scope: String, CaseIterable, Identifiable {
        case all       = "All games"
        case elite2500 = "Rated 2500+"
        case strong2400 = "Rated 2400+"
        case since2020 = "Since 2020"
        case since2010 = "Since 2010"
        var id: String { rawValue }
        var whereSQL: String? {
            switch self {
            case .all:        return nil
            case .elite2500:  return "white_elo>=2500 OR black_elo>=2500"
            case .strong2400: return "white_elo>=2400 OR black_elo>=2400"
            case .since2020:  return "date>=20200000"
            case .since2010:  return "date>=20100000"
            }
        }
    }

    @State private var scope: Scope = .all
    @State private var movesDepth: Int = 12          // full moves; maxPly = ×2
    @State private var estGames = 0
    @State private var estPositions = 0
    @State private var calculating = false
    @State private var recalcToken = 0

    private var maxPly: Int { movesDepth * 2 }
    private var estBytes: Int { estPositions * 72 }  // ~row + zobrist idx + covering idx
    private var estGB: Double { Double(estBytes) / 1_000_000_000 }
    private var estMinutes: Double { Double(estPositions) / 300_000 / 60 } // rough @~300k pos/s

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))

            if referenceDB.isIndexing {
                indexingProgress
            } else {
                config
            }
        }
        .frame(width: 460, height: 460)
        .background(DS.card)
        .onAppear(perform: recalc)
        .onChange(of: scope) { _, _ in recalc() }
        .onChange(of: movesDepth) { _, _ in recalc() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 14)).foregroundColor(DS.accent)
            Text("Build opening index").font(.system(size: 15, weight: .bold)).foregroundColor(DS.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textSecondary).frame(width: 26, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(referenceDB.isIndexing)
        }
        .padding(.horizontal, 18).frame(height: 52)
    }

    private var config: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(fmt(referenceDB.indexedGameCount)) of \(fmt(referenceDB.gameCount)) games are searchable in the explorer. Choose what to add:")
                .font(.system(size: 12)).foregroundColor(DS.textSecondary).fixedSize(horizontal: false, vertical: true)

            // Scope
            VStack(alignment: .leading, spacing: 8) {
                Text("Which games").font(.system(size: 12, weight: .semibold)).foregroundColor(DS.textPrimary)
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            // Depth
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Depth").font(.system(size: 12, weight: .semibold)).foregroundColor(DS.textPrimary)
                    Spacer()
                    Text("\(movesDepth) moves").font(.system(size: 12, design: .monospaced)).foregroundColor(DS.accent)
                }
                Slider(value: Binding(get: { Double(movesDepth) }, set: { movesDepth = Int($0) }), in: 6...30, step: 2)
                Text("Opening explorer covers the first \(movesDepth) moves. Deeper = bigger + slower; most opening/prep is within ~12–15 moves.")
                    .font(.system(size: 10)).foregroundColor(DS.textTertiary).fixedSize(horizontal: false, vertical: true)
            }

            // Estimate
            HStack(spacing: 18) {
                estCell(fmt(estGames), "games")
                estCell(fmt(estPositions), "positions")
                estCell(String(format: "%.1f GB", estGB), "disk")
                estCell(estMinutes < 1 ? "<1 min" : String(format: "~%.0f min", estMinutes), "time")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .trailing) {
                if calculating { ProgressView().controlSize(.small).padding(.trailing, 10) }
            }

            Spacer()

            Button(action: { referenceDB.buildIndex(whereSQL: scope.whereSQL, maxPly: maxPly) }) {
                Text(estGames == 0 ? "Nothing to index" : "Build index for \(fmt(estGames)) games")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(estGames == 0 || calculating || referenceDB.isBusy)
        }
        .padding(20)
    }

    private var indexingProgress: some View {
        VStack(spacing: 14) {
            Spacer()
            KnightLoader(size: 48)
            Text("Indexing… \(fmt(referenceDB.indexProgress)) games")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(DS.textPrimary)
            Text("You can close this — indexing continues in the background.")
                .font(.system(size: 11)).foregroundColor(DS.textTertiary)
            Button("Close", action: onClose).buttonStyle(.bordered).padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func estCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(DS.textPrimary)
            Text(label).font(.system(size: 10)).foregroundColor(DS.textTertiary)
        }.frame(maxWidth: .infinity)
    }

    private func recalc() {
        recalcToken += 1
        let token = recalcToken
        let sql = scope.whereSQL
        let ply = maxPly
        calculating = true
        DispatchQueue.global(qos: .userInitiated).async {
            let games = referenceDB.matchingGameCount(whereSQL: unindexed(sql))
            let positions = referenceDB.estimatedPositions(whereSQL: sql, maxPly: ply)
            DispatchQueue.main.async {
                guard token == recalcToken else { return }   // ignore stale
                estGames = games; estPositions = positions; calculating = false
            }
        }
    }

    /// Restrict the game-count to not-yet-indexed rows, matching what the build will actually add.
    private func unindexed(_ sql: String?) -> String {
        if let sql, !sql.isEmpty { return "indexed=0 AND (\(sql))" }
        return "indexed=0"
    }

    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
