import SwiftUI

// MARK: - Left Rail (84px) — A6 nav, per TABS-AND-RAIL.md §2.2
// Replaces the centered masthead nav. `T.` wordmark on top, 5 line-icon nav items with a 2px red
// left bar on the active one, gear pinned at the bottom → Settings.

struct RailView: View {
    @Binding var selected: AppScreen
    var onSettings: () -> Void

    /// The five sections, in spec order.
    private static let items: [AppScreen] = [.analysis, .explorer, .repertoire, .chesscom, .database]

    private var railBg: Color { DS.adaptive(light: 0xEFE8D8, dark: 0x17130D) }

    var body: some View {
        VStack(spacing: 0) {
            // Wordmark — the app mark + "Tabia." stacked so it fits the 84px rail.
            VStack(spacing: 3) {
                Image("TabiaMark")
                    .resizable().interpolation(.high)
                    .frame(width: 26, height: 26)
                (Text("Tabia").foregroundColor(DS.ink) + Text(".").foregroundColor(DS.redAccent))
                    .font(AnnFont.serif(15, .semibold))
            }
            .padding(.top, 12).padding(.bottom, 14)

            ForEach(Self.items, id: \.self) { item in
                RailItem(screen: item, active: selected == item) { selected = item }
            }

            Spacer(minLength: 0)

            RailButton(icon: "gearshape", label: "Settings", active: false, action: onSettings)
                .padding(.bottom, 10)
        }
        .frame(width: 84)
        .frame(maxHeight: .infinity)
        .background(railBg)
        .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }
    }
}

private struct RailItem: View {
    let screen: AppScreen
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    /// Rail-specific line icons (SF Symbols approximating the spec's custom glyphs).
    private var icon: String {
        switch screen {
        case .analysis:   return "square.grid.2x2"
        case .explorer:   return "arrow.triangle.branch"
        case .repertoire: return "book"
        case .chesscom:   return "text.alignleft"
        case .database:   return "cylinder"
        default:          return screen.icon
        }
    }

    private var label: String {
        switch screen {
        case .chesscom: return "Games"
        case .database: return "Database"
        default:        return screen.navLabel
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                Text(label.uppercased())
                    .font(AnnFont.label(8.5)).tracking(8.5 * 0.10)
            }
            .foregroundColor(active ? DS.ink : (hover ? DS.ink : DS.ink40))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(alignment: .leading) {
                // The red-underline idiom, rotated 90° → a 2px bar on the active item's left edge.
                Rectangle().fill(active ? DS.redAccent : Color.clear).frame(width: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct RailButton: View {
    let icon: String
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(hover ? DS.ink : DS.ink40)
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(label)
    }
}
