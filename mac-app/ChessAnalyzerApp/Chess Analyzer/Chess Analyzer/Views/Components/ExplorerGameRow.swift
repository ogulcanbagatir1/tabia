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
            VStack(alignment: .leading, spacing: 2) {
                // Players line: "Name (rating) vs Name (rating)"
                HStack(spacing: 0) {
                    Text(playerString)
                        .font(AnnFont.serif(11, .medium))
                        .foregroundColor(DS.ink)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    }
                }

                // Result + date
                HStack(spacing: 0) {
                    Text(resultDateString)
                        .font(AnnFont.mono(10))
                        .foregroundColor(DS.ink60)

                    Spacer()
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var playerString: String {
        var s = white
        if let r = whiteRating { s += " (\(r))" }
        s += " vs "
        s += black
        if let r = blackRating { s += " (\(r))" }
        return s
    }

    private var resultDateString: String {
        var s = result
        if let d = date, !d.isEmpty {
            s += " · \(d)"
        }
        return s
    }
}
