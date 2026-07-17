import SwiftUI

struct ExplorerGameRow: View {
    let white: String
    let black: String
    let whiteWeight: Font.Weight
    let blackWeight: Font.Weight
    let result: String
    var whiteRating: String? = nil
    var blackRating: String? = nil
    var date: String? = nil
    var trailingIcon: String? = nil
    var isLoading: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    // Players — surnames, en-dash between them
                    Text(verbatim: "\(surname(white)) – \(surname(black))")
                        .font(AnnFont.serif(12.5, .medium))
                        .foregroundColor(DS.ink)
                        .lineLimit(1)

                    if !metaLine.isEmpty {
                        Text(metaLine.uppercased())
                            .font(AnnFont.mono(8.5)).tracking(0.4)
                            .foregroundColor(DS.ink40)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if isLoading {
                    ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                } else {
                    resultChip
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var resultChip: some View {
        Text(verbatim: result == "1/2-1/2" ? "½–½" : result)
            .font(AnnFont.mono(10, bold: true))
            .foregroundColor(DS.ink60)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
            .fixedSize()
    }

    /// Surname only (chess DBs store "Karpov, Anatoly"; handles like "BidiBoy1" pass through).
    private func surname(_ name: String) -> String {
        let s = name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? name
        return s.isEmpty ? name : s
    }

    /// The muted meta line under the players — event and/or date, ratings as a fallback.
    private var metaLine: String {
        var parts: [String] = []
        if let d = date, !d.isEmpty { parts.append(d) }
        if parts.isEmpty, let w = whiteRating, let b = blackRating { parts.append("\(w) · \(b)") }
        return parts.joined(separator: " · ")
    }
}
