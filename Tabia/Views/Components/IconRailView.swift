import SwiftUI

// MARK: - App Screen

enum AppScreen: String, CaseIterable {
    case analysis
    case explorer
    case repertoire
    case chesscom
    case database
    case engine
    case settings

    /// The five centered masthead nav tabs (Engines + Settings live in separate windows).
    static let navTabs: [AppScreen] = [.analysis, .explorer, .repertoire, .chesscom, .database]

    var icon: String {
        switch self {
        case .analysis:   return "square.grid.2x2"
        case .explorer:   return "book.closed"
        case .database:   return "cylinder"
        case .repertoire: return "books.vertical"
        case .chesscom:   return "globe"
        case .engine:     return "cpu"
        case .settings:   return "gearshape"
        }
    }

    /// Uppercase nav-tab label.
    var navLabel: String {
        switch self {
        case .analysis:   return "Analysis"
        case .explorer:   return "Explorer"
        case .repertoire: return "Repertoire"
        case .chesscom:   return "My Games"
        case .database:   return "Library"
        case .engine:     return "Engines"
        case .settings:   return "Settings"
        }
    }

    var label: String { navLabel }
}

// MARK: - Icon Rail View

struct IconRailView: View {
    @Binding var selected: AppScreen

    /// Top icons (main navigation)
    private static let topScreens: [AppScreen] = [.analysis, .database, .repertoire, .chesscom, .engine]
    /// Bottom icons (utilities)
    private static let bottomScreens: [AppScreen] = [.settings]

    var body: some View {
        VStack(spacing: 6) {
            // Drag region to move window (replacing hidden titlebar)
            Color.clear
                .frame(height: 10)

            ForEach(Self.topScreens, id: \.self) { screen in
                glassIconButton(for: screen)
            }

            Spacer()

            ForEach(Self.bottomScreens, id: \.self) { screen in
                glassIconButton(for: screen)
            }
        }
        .padding(.vertical, 16)
        .frame(width: 64)
        .background(GlassRailBackground())
        .overlay(alignment: .trailing) {
            Rectangle().fill(DS.hairline).frame(width: 1)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private func glassIconButton(for screen: AppScreen) -> some View {
        let isSelected = selected == screen

        return Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = screen } }) {
            Image(systemName: screen.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(isSelected ? DS.ink : DS.ink40)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? DS.selectedWash : Color.clear)
                )
                .shadow(color: isSelected ? Color.white.opacity(0.06) : Color.clear, radius: 8, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(screen.label)
    }
}

#Preview {
    HStack(spacing: 0) {
        IconRailView(selected: .constant(.analysis))
        Color.clear
    }
    .frame(width: 400, height: 500)
}
