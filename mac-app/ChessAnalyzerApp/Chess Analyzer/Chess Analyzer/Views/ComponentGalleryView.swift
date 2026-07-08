import SwiftUI

// Dev harness — renders every Annotator primitive for visual comparison against HTML §00.
// Reachable via the Window menu → "Component Gallery" (DEBUG builds).

struct ComponentGalleryView: View {
    @State private var seg = 0
    @State private var source = 0
    @State private var toggleA = true
    @State private var toggleB = false
    @State private var check = true
    @State private var threads = 4
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Components — every control")
                    .font(AnnFont.serif(24, .semibold)).foregroundColor(DS.ink)

                group("Buttons — one red per screen, max") {
                    HStack(spacing: 12) {
                        Button("Run Review") {}.buttonStyle(AnnButtonStyle(kind: .primary))
                        Button("Import PGN") {}.buttonStyle(AnnButtonStyle(kind: .secondary))
                        Button("Disabled") {}.buttonStyle(AnnButtonStyle(kind: .disabled)).disabled(true)
                        AnnLink(text: "Open in database →") {}
                    }
                }

                group("Segmented & sources") {
                    HStack(spacing: 14) {
                        AnnSegmented(options: [(0, "Ledger"), (1, "Grid")], selection: $seg)
                        AnnSourceChip(label: "Stockfish 17", active: true, dot: DS.semOnline) {}
                        AnnSourceChip(label: "Leela 0.31", active: false) {}
                    }
                }

                group("Chips & marks") {
                    HStack(spacing: 10) {
                        AnnChip(text: "Main")
                        AnnGapBadge()
                        AnnDueBadge(count: 8)
                        AnnECOChip(eco: "B90")
                        AnnResultChip(text: "1–0")
                        AnnToMoveChip()
                        HStack(spacing: 6) { ForEach(AnnMoveQuality.allCases, id: \.self) { QualityMark(quality: $0) } }
                    }
                }

                group("Inputs & toggles") {
                    HStack(spacing: 14) {
                        AnnSearchField(text: $search, placeholder: "players, events, ECO…").frame(width: 210)
                        AnnToggle(isOn: $toggleA)
                        AnnToggle(isOn: $toggleB)
                        AnnCheckbox(checked: $check, label: "Drill as primary")
                        HStack(spacing: 6) {
                            AnnRadioDot(filled: true); Text("MAIN").font(AnnFont.mono(11)).foregroundColor(DS.inkPV)
                            AnnRadioDot(filled: false); Text("ALT").font(AnnFont.mono(11)).foregroundColor(DS.inkPV)
                        }
                        AnnStepper(value: threads, range: 1...16) { threads = $0 }
                    }
                }

                group("Data — W/D/L, evals, move rows") {
                    VStack(alignment: .leading, spacing: 10) {
                        AnnWDLBar(white: 38, draw: 41, black: 21).frame(width: 340)
                        AnnPVRow(eval: "+0.32", line: "12…cxd4 13.cxd4 Nc6 14.Nb3 a5")
                        HStack(spacing: 4) {
                            Text("12.").font(AnnFont.mono(11)).foregroundColor(DS.ink25)
                            Text("Nbd2").font(AnnFont.mono(12.5, bold: true)).foregroundColor(DS.ink)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(DS.selectedMove, in: RoundedRectangle(cornerRadius: DS.rChip))
                            Text("Nc6").font(AnnFont.mono(12.5)).foregroundColor(DS.ink).padding(.horizontal, 8).padding(.vertical, 3)
                            HStack(spacing: 1) {
                                Text("16…Nb7").font(AnnFont.mono(12.5)).foregroundColor(DS.ink)
                                QualityMark(quality: .inaccuracy)
                            }.padding(.horizontal, 8).padding(.vertical, 3)
                            HStack(spacing: 1) {
                                Text("24.Ba7").font(AnnFont.mono(12.5)).foregroundColor(DS.ink)
                                QualityMark(quality: .best)
                            }.padding(.horizontal, 8).padding(.vertical, 3)
                        }
                    }
                }

                group("Patterns — empty state · sheet") {
                    HStack(alignment: .top, spacing: 14) {
                        AnnEmptyState(title: "Nothing here yet",
                                      sentence: "One quiet sentence. Never a lecture.",
                                      actionTitle: "One action", action: {}) {
                            Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .light))
                        }
                        .frame(width: 260)

                        AnnSheet(title: "Sheet title", confirmTitle: "Confirm", onCancel: {}, onConfirm: {}) {
                            Text("Form rows, hairline separated…")
                                .font(AnnFont.voice(12)).foregroundColor(DS.ink60)
                                .padding(16)
                        }
                        .frame(width: 320)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.paper)
    }

    @ViewBuilder private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AnnLabel(title, size: 10, tracking: 0.14, bold: true, color: DS.ink40)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rPanel))
        .overlay(RoundedRectangle(cornerRadius: DS.rPanel).strokeBorder(DS.hairline, lineWidth: 1))
    }
}
