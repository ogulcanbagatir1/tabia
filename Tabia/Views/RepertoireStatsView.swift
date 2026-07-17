import SwiftUI

/// Knowledge popover (R4) for a repertoire: two donut gauges (Known / Covered), five mono stats,
/// and a red-flagged weak-spots list. Always a dark editorial popover, in both appearances.
struct RepertoireStatsView: View {
    let repertoire: Repertoire
    @ObservedObject var repertoireDB: RepertoireDatabase
    var onClose: () -> Void
    /// The shelf already computes this; pass it in to skip the recompute.
    var preloaded: RepertoireKnowledge? = nil

    @State private var knowledge: RepertoireKnowledge = .empty
    @State private var loaded = false

    // R4 is a fixed dark surface regardless of system appearance.
    private let bg        = Color(hex: 0x211C13)
    private let bgBorder  = Color(hex: 0x4A4130)
    private let cardBg    = Color(hex: 0x241E14)
    private let cardBd    = Color(hex: 0x3A3222)
    private let track     = Color(hex: 0x2A2418)
    private let green     = Color(hex: 0x8FB35B)
    private let red       = Color(hex: 0xC25048)
    private let bright    = Color(hex: 0xF1EADA)
    private let white     = Color(hex: 0xEDE6DA)
    private let muted     = Color(hex: 0xA99C82)
    private let dim       = Color(hex: 0x857A63)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            gauges
            statRow
            weakSpots
        }
        .padding(EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22))
        .frame(width: 430)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(bgBorder, lineWidth: 1))
        .onAppear(perform: computeIfNeeded)
    }

    private var header: some View {
        HStack {
            (Text("Knowledge").font(AnnFont.serif(18, .semibold)).foregroundColor(bright)
             + Text(" — \(repertoire.name)").font(AnnFont.voice(18)).foregroundColor(muted))
            Spacer()
            Button(action: onClose) {
                Text(verbatim: "✕").font(AnnFont.mono(12)).foregroundColor(dim)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Gauges

    private var gauges: some View {
        HStack(spacing: 16) {
            donut(value: knowledge.knowledgePercent, label: "KNOWN", color: green)
            donut(value: knowledge.coveragePercent, label: "COVERED", color: red)
        }
    }

    private func donut(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(track, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, value / 100)))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))%")
                    .font(AnnFont.serif(19, .semibold)).foregroundColor(bright)
            }
            .frame(width: 76, height: 76)
            Text(label).font(AnnFont.mono(9.5)).tracking(9.5 * 0.08).foregroundColor(muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(cardBg))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(cardBd, lineWidth: 1))
    }

    // MARK: - Stat row

    private var statRow: some View {
        HStack(spacing: 6) {
            statCell(knowledge.dueNow, "DUE NOW", knowledge.dueNow > 0 ? red : white)
            statCell(knowledge.drilledDecisions, "DRILLED", white)
            statCell(knowledge.matureDecisions, "MATURE", green)
            statCell(knowledge.importantDecisions, "IMPORTANT", white)
            statCell(knowledge.totalDecisions, "TOTAL", white)
        }
    }

    private func statCell(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(AnnFont.mono(15, bold: true)).foregroundColor(color)
            Text(label).font(AnnFont.mono(8.5)).foregroundColor(dim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weak spots

    private var weakSpots: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "⚑ WEAK SPOTS")
                .font(AnnFont.label(10)).tracking(10 * 0.14).foregroundColor(red)

            if !loaded {
                Text(verbatim: "…").font(AnnFont.mono(11)).foregroundColor(dim)
            } else if knowledge.leeches.isEmpty {
                Text("Nothing is being repeatedly missed — the whole line is holding.")
                    .font(AnnFont.voice(13)).foregroundColor(muted)
            } else {
                ForEach(knowledge.leeches) { leech in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leechLine(leech))
                            .font(AnnFont.voice(13.5)).foregroundColor(white).lineLimit(1)
                        Text("\(leech.wrongCount) misses · \(leech.correctCount) correct")
                            .font(AnnFont.mono(9)).foregroundColor(dim)
                    }
                    .padding(.leading, 12).padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) { Rectangle().fill(red).frame(width: 2) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(cardBd).frame(height: 1) }
    }

    private func leechLine(_ leech: RepertoireKnowledge.Leech) -> String {
        let prefix = leech.pathSAN.isEmpty ? "start" : leech.pathSAN.joined(separator: " ")
        return "\(prefix) → \(leech.san)"
    }

    private func computeIfNeeded() {
        guard !loaded else { return }
        if let preloaded {
            knowledge = preloaded
        } else {
            let schedules = repertoireDB.positionSchedules(for: repertoire.id).mapValues { $0.stats }
            knowledge = RepertoireStatsBuilder.build(repertoire: repertoire, schedules: schedules)
        }
        loaded = true
    }
}
