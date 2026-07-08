import SwiftUI

/// Inline badge showing whether the current game position appears in any of the user's repertoires.
/// Hidden when there's no match. Use in the analysis layout near the board.
struct RepertoireDeviationBadge: View {
    @ObservedObject var board: ChessBoard
    @EnvironmentObject var repertoireDB: RepertoireDatabase

    private var matches: [(Repertoire, RepertoireNode)] {
        let key = RepertoireDatabase.positionKey(fromFEN: board.getFEN())
        return repertoireDB.repertoires(matching: key)
    }

    var body: some View {
        // Compute the (O(repertoires × nodes)) match scan ONCE per render — the body reads it in two
        // places, and it runs on every board change while analyzing, so recomputing it twice janks.
        let matches = matches
        if matches.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.accent)

                Text("In repertoire")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.accent)
                    .kerning(0.4)

                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(DS.ink40)

                Text(matches.map { $0.0.name }.joined(separator: ", "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DS.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DS.accent.opacity(0.4), lineWidth: 1)
            )
        }
    }
}
