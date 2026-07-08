import SwiftUI

/// Presents the repertoire's coverage holes: popular opponent replies (from the reference DB) the
/// tree has no answer for, ranked by how much they hurt. An automated repertoire auditor.
struct CoverageGapView: View {
    let repertoire: Repertoire
    @ObservedObject var referenceDB: ReferenceDatabase
    var onClose: () -> Void

    @State private var gaps: [CoverageGap] = []
    @State private var isAuditing = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.hairline)

            if !referenceDB.isAvailable || referenceDB.gameCount == 0 {
                message(icon: "tray", title: "No reference database",
                        detail: "Import a PGN database (File → Import PGN Database…) to audit coverage against real games.")
            } else if isAuditing {
                loading
            } else if gaps.isEmpty {
                message(icon: "checkmark.seal.fill", title: "No holes found",
                        detail: "Every popular opponent reply in the reference DB is covered by your repertoire.")
            } else {
                gapList
            }
        }
        .frame(width: 560, height: 620)
        .background(DS.card)
        .task { await runAudit() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(DS.accent)
            Text("Coverage audit")
                .font(AnnFont.serif(15, .semibold))
                .foregroundColor(DS.textPrimary)
            Text(repertoire.name)
                .font(AnnFont.serif(13, .regular))
                .foregroundColor(DS.textTertiary)
            Spacer()
            if !isAuditing && !gaps.isEmpty {
                Text("\(gaps.count) holes")
                    .font(AnnFont.mono(11, bold: true))
                    .foregroundColor(DS.moveBlunder)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(DS.moveBlunder.opacity(0.12), in: Capsule())
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var loading: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
            Text("Scanning your lines against \(referenceDB.gameCount.formatted()) games…")
                .font(AnnFont.serif(12, .regular))
                .foregroundColor(DS.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gapList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(gaps) { gap in
                    gapRow(gap)
                }
            }
            .padding(16)
        }
    }

    private func gapRow(_ gap: CoverageGap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(gap.missingSAN)
                    .font(AnnFont.mono(14, bold: true))
                    .foregroundColor(DS.textPrimary)
                Text("unanswered")
                    .font(AnnFont.label(10, bold: false))
                    .tracking(10 * 0.1)
                    .foregroundColor(DS.moveBlunder)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(DS.moveBlunder.opacity(0.12), in: Capsule())
                Spacer()
                Text("\(Int(gap.sharePercent.rounded()))%")
                    .font(AnnFont.mono(13, bold: true))
                    .foregroundColor(DS.accent)
            }

            Text(lineText(gap))
                .font(AnnFont.mono(11, bold: false))
                .foregroundColor(DS.textSecondary)
                .lineLimit(2)

            HStack(spacing: 14) {
                statLabel(icon: "chart.bar.fill", text: "\(gap.gameCount.formatted()) games")
                statLabel(icon: "flag.checkered", text: "opp scores \(Int(gap.opponentScorePercent.rounded()))%")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.moveBlunder.opacity(gap.opponentScorePercent >= 52 ? 0.28 : 0.10), lineWidth: 1)
        )
    }

    private func statLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(AnnFont.mono(10, bold: false))
        }
        .foregroundColor(DS.textTertiary)
    }

    private func lineText(_ gap: CoverageGap) -> String {
        let prefix = gap.pathSAN.isEmpty ? "start" : gap.pathSAN.joined(separator: " ")
        return "after  \(prefix)  →  \(gap.missingSAN)"
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundColor(DS.accent)
            Text(title)
                .font(AnnFont.serif(15, .semibold))
                .foregroundColor(DS.textPrimary)
            Text(detail)
                .font(AnnFont.serif(12, .regular))
                .foregroundColor(DS.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runAudit() async {
        // Phase 1 on the main thread (reads SwiftData model objects), phase 2 off-main (ChessBoard + SQLite only).
        let snap = CoverageGapAuditor.snapshot(repertoire)
        let db = referenceDB
        let found = await Task.detached(priority: .userInitiated) {
            CoverageGapAuditor.gaps(userColor: snap.userColor, positions: snap.positions, referenceDB: db)
        }.value
        gaps = found
        isAuditing = false
    }
}
