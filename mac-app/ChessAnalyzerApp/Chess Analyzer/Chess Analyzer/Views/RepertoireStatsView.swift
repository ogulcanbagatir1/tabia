import SwiftUI

/// Knowledge dashboard for a repertoire: how much you know, what's due, and your weak spots.
struct RepertoireStatsView: View {
    let repertoire: Repertoire
    @ObservedObject var repertoireDB: RepertoireDatabase
    var onClose: () -> Void

    @State private var knowledge: RepertoireKnowledge = .empty
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(spacing: 18) {
                    ringRow
                    countRow
                    leechSection
                }
                .padding(18)
            }
        }
        .frame(width: 520, height: 600)
        .background(DS.card)
        .onAppear(perform: computeIfNeeded)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 14))
                .foregroundColor(DS.accent)
            Text("Knowledge")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DS.textPrimary)
            Text(repertoire.name)
                .font(.system(size: 13))
                .foregroundColor(DS.textTertiary)
            Spacer()
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

    private var ringRow: some View {
        HStack(spacing: 14) {
            ring(value: knowledge.knowledgePercent, label: "Known", tint: DS.moveBest)
            ring(value: knowledge.coveragePercent, label: "Covered", tint: DS.accent)
        }
    }

    private func ring(value: Double, label: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, value / 100)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(DS.textPrimary)
            }
            .frame(width: 96, height: 96)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private var countRow: some View {
        HStack(spacing: 10) {
            countCell(value: knowledge.dueNow, label: "Due now", tint: knowledge.dueNow > 0 ? DS.accent : DS.textTertiary)
            countCell(value: knowledge.drilledDecisions, label: "Drilled", tint: DS.textSecondary)
            countCell(value: knowledge.matureDecisions, label: "Mature", tint: DS.moveBest)
            countCell(value: knowledge.importantDecisions, label: "Important", tint: knowledge.importantDecisions > 0 ? DS.accent : DS.textTertiary)
            countCell(value: knowledge.totalDecisions, label: "Total", tint: DS.textSecondary)
        }
    }

    private func countCell(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DS.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    private var leechSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(DS.moveBlunder)
                Text("Weak spots")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                if !knowledge.leeches.isEmpty {
                    Text("\(knowledge.leeches.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.moveBlunder)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(DS.moveBlunder.opacity(0.12), in: Capsule())
                }
            }

            if !loaded {
                Text("…").foregroundColor(DS.textTertiary).font(.system(size: 12))
            } else if knowledge.leeches.isEmpty {
                Text("No leeches — nothing is being repeatedly missed.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(knowledge.leeches) { leech in
                    leechRow(leech)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func leechRow(_ leech: RepertoireKnowledge.Leech) -> some View {
        HStack(spacing: 10) {
            if leech.isImportant {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(DS.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(leechLine(leech))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.textPrimary)
                    .lineLimit(1)
                Text("\(leech.wrongCount) misses · \(leech.correctCount) correct")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textTertiary)
            }
            Spacer()
            Text("\(leech.wrongCount)×")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(DS.moveBlunder)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func leechLine(_ leech: RepertoireKnowledge.Leech) -> String {
        let prefix = leech.pathSAN.isEmpty ? "start" : leech.pathSAN.joined(separator: " ")
        return "\(prefix)  →  \(leech.san)"
    }

    private func computeIfNeeded() {
        guard !loaded else { return }
        let schedules = repertoireDB.positionSchedules(for: repertoire.id).mapValues { $0.stats }
        knowledge = RepertoireStatsBuilder.build(repertoire: repertoire, schedules: schedules)
        loaded = true
    }
}
