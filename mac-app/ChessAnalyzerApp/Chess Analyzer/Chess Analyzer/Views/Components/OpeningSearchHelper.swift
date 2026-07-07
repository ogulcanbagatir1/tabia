import SwiftUI

// MARK: - Opening Search Helper

/// Search the opening book tree for nodes matching a query (by name or ECO code).
func findMatchingOpenings(in node: OpeningNode, query: String) -> [OpeningNode] {
    var results: [OpeningNode] = []

    if let name = node.name, name.lowercased().contains(query) {
        results.append(node)
    }
    if let eco = node.eco, eco.lowercased().contains(query),
       !results.contains(where: { $0.id == node.id }) {
        results.append(node)
    }

    for child in node.children {
        results.append(contentsOf: findMatchingOpenings(in: child, query: query))
    }

    // Remove duplicates preserving order
    var seen = Set<UUID>()
    return results.filter { node in
        if seen.contains(node.id) { return false }
        seen.insert(node.id)
        return true
    }
}

/// Format a SAN sequence with move numbers (e.g. "1. e4 e5 2. Nf3 Nc6").
func formatSANSequence(_ sans: [String]) -> String {
    var result = ""
    for (i, san) in sans.enumerated() {
        let moveNum = i / 2 + 1
        if i % 2 == 0 {
            if i > 0 { result += " " }
            result += "\(moveNum). \(san)"
        } else {
            result += " \(san)"
        }
    }
    return result
}

// MARK: - Opening Search Result Row

struct OpeningSearchResultRow: View {
    let node: OpeningNode
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    if let name = node.name {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    Text(formatSANSequence(node.sanSequence))
                        .font(DS.monoSmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let eco = node.eco {
                    Text(eco)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.accent)
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, DS.spacingMD)
            .padding(.vertical, DS.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Opening Search Bar

struct OpeningSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.textTertiary)
                .font(.system(size: 12))

            TextField("Search openings...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.textTertiary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DS.bg)
        .cornerRadius(DS.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSM)
                .strokeBorder(DS.border, lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
}

// MARK: - Opening Search Results List

struct OpeningSearchResultsList: View {
    let openingBook: OpeningBook
    let searchText: String
    let onOpeningSelected: ([String]) -> Void
    @Binding var searchBinding: String

    private var searchResults: [OpeningNode] {
        guard !searchText.isEmpty else { return [] }
        return findMatchingOpenings(in: openingBook.root, query: searchText.lowercased())
    }

    var body: some View {
        let results = searchResults

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results, id: \.id) { node in
                    OpeningSearchResultRow(node: node) {
                        onOpeningSelected(node.moveSequence)
                        searchBinding = ""
                    }

                    Divider()
                        .padding(.leading, DS.spacingMD)
                }

                if results.isEmpty {
                    Text("No openings found")
                        .font(DS.captionFont)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, DS.spacingSM)
        }
    }
}

// MARK: - Current Opening Display (for right sidebar)

struct CurrentOpeningView: View {
    let openingName: String?
    let eco: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OPENING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.textTertiary)
                .kerning(0.8)

            if let name = openingName {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let eco = eco {
                    Text(eco)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.accent)
                }
            } else {
                Text("Starting Position")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}
