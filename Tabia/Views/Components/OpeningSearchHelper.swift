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
                            .font(AnnFont.serif(11, .medium))
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
                        .font(AnnFont.mono(9, bold: false))
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
