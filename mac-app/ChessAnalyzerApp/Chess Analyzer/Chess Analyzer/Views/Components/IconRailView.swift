import SwiftUI

// MARK: - App Screen

enum AppScreen: String, CaseIterable {
    case analysis
    case database
    case repertoire
    case chesscom
    case engine
    case settings

    var icon: String {
        switch self {
        case .analysis:   return "square.grid.2x2"
        case .database:   return "cylinder"
        case .repertoire: return "books.vertical"
        case .chesscom:   return "globe"
        case .engine:     return "cpu"
        case .settings:   return "gearshape"
        }
    }

    var label: String {
        switch self {
        case .analysis:   return "Analysis"
        case .database:   return "Database"
        case .repertoire: return "Repertoires"
        case .chesscom:   return "Online Games"
        case .engine:     return "Engine"
        case .settings:   return "Settings"
        }
    }
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
            Rectangle().fill(
                LinearGradient(colors: [Color.white.opacity(0.37), Color.white.opacity(0.09), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
            ).frame(width: 1)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(
                LinearGradient(colors: [Color.white.opacity(0.37), Color.white.opacity(0.05)], startPoint: .leading, endPoint: .trailing)
            ).frame(height: 1)
        }
    }

    private func glassIconButton(for screen: AppScreen) -> some View {
        let isSelected = selected == screen

        return Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = screen } }) {
            Image(systemName: screen.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(isSelected ? Color(hex: 0xFFFFFF, opacity: 0.93) : Color(hex: 0xFFFFFF, opacity: 0.33))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
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
