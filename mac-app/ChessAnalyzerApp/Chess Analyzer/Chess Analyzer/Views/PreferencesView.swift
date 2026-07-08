import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    private let tabLabels = ["Appearance", "Engine", "About"]

    var body: some View {
        VStack(spacing: 0) {
            // Header + tabs
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(AnnFont.serif(22, .semibold))
                    .foregroundColor(DS.textPrimary)

                settingsTabBar
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)

            // Tab content
            Group {
                switch selectedTab {
                case 0:  AppearanceSettingsView(settings: settings)
                case 1:  EngineSettingsView(settings: settings)
                case 2:  AboutView()
                default: EmptyView()
                }
            }

            Rectangle().fill(DS.hairline).frame(height: 1)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding(DS.spacingLG)
        }
        .frame(width: 600, height: 700)
        .background(DS.paper)
    }

    private var settingsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabLabels.enumerated()), id: \.offset) { index, label in
                Button {
                    withAnimation(DS.quickFade) { selectedTab = index }
                } label: {
                    Text(label)
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(selectedTab == index ? DS.textPrimary : DS.textTertiary)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .overlay(alignment: .bottom) {
                            if selectedTab == index {
                                Rectangle()
                                    .fill(DS.accent)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    private let gridColumns = [GridItem(.adaptive(minimum: 80, maximum: 90), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Appearance Mode
                VStack(alignment: .leading, spacing: 12) {
                    glassSettingsLabel("APP COLOUR MODE")

                    HStack(spacing: 2) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            let isSelected = settings.appAppearance == mode
                            Button {
                                withAnimation(DS.quickFade) { settings.appAppearance = mode }
                            } label: {
                                Text(mode.displayName)
                                    .font(AnnFont.label(11))
                                    .tracking(11 * 0.1)
                                    .foregroundColor(isSelected ? DS.ink : DS.ink40)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 16)
                                    .contentShape(Rectangle())
                                    .background(
                                        isSelected
                                        ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.selectedWash)
                                        : nil
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(DS.trackBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(DS.borderChip, lineWidth: 1)
                    )
                }

                // Board Theme
                VStack(alignment: .leading, spacing: 12) {
                    glassSettingsLabel("BOARD THEME")

                    // Manual rows (adaptive LazyVGrid-in-ScrollView collapses on current macOS).
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(chunked(BoardTheme.allThemes, 7).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 10) {
                                ForEach(row) { theme in
                                    BoardThemePreview(theme: theme, isSelected: settings.boardThemeId == theme.id)
                                        .onTapGesture {
                                            withAnimation(DS.quickFade) { settings.boardThemeId = theme.id }
                                        }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                // Piece Style
                VStack(alignment: .leading, spacing: 12) {
                    glassSettingsLabel("PIECE STYLE")

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(chunked(PieceStyle.allStyles, 6).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row) { style in
                                    PieceStylePreview(style: style, isSelected: settings.pieceStyleId == style.id)
                                        .onTapGesture {
                                            withAnimation(DS.quickFade) { settings.pieceStyleId = style.id }
                                        }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                // Display Preferences
                VStack(alignment: .leading, spacing: 12) {
                    glassSettingsLabel("DISPLAY PREFERENCES")

                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            label: "Show Coordinates",
                            description: "Display rank and file labels on the board edges",
                            isOn: $settings.showCoordinates,
                            showBorder: true
                        )
                        SettingsToggleRow(
                            label: "Highlight Legal Moves",
                            description: "Show dots on squares where pieces can move",
                            isOn: $settings.highlightLegalMoves,
                            showBorder: true
                        )
                        SettingsToggleRow(
                            label: "Show Best Move Arrow",
                            description: "Display engine's recommended move as an arrow",
                            isOn: $settings.showBestMoveArrow,
                            showBorder: false
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DS.paperRaised)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DS.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.19), radius: 12, x: 0, y: 4)
                    .frame(maxWidth: 600)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 28)
        }
    }
}

// MARK: - Section Label

private func glassSettingsLabel(_ text: String) -> some View {
    Text(text)
        .font(AnnFont.label(10))
        .foregroundColor(DS.ink25)
        .kerning(0.8)
}

/// Split into rows of `n` for manual grid layout.
private func chunked<T>(_ items: [T], _ n: Int) -> [[T]] {
    stride(from: 0, to: items.count, by: n).map { Array(items[$0..<min($0 + n, items.count)]) }
}

private func settingsSectionLabel(_ text: String) -> some View {
    glassSettingsLabel(text)
}

// MARK: - Custom Toggle Row

struct SettingsToggleRow: View {
    let label: String
    var description: String = ""
    @Binding var isOn: Bool
    var showBorder: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AnnFont.serif(13, .medium))
                    .foregroundColor(DS.ink)

                if !description.isEmpty {
                    Text(description)
                        .font(AnnFont.serif(11))
                        .foregroundColor(DS.ink40)
                }
            }

            Spacer()

            // Toggle (40x22 capsule)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? DS.redInk : DS.trackBg)
                        .overlay(
                            isOn ? nil : Capsule().strokeBorder(DS.borderChip, lineWidth: 1)
                        )
                        .frame(width: 40, height: 22)
                    Circle()
                        .fill(isOn ? DS.onRed : DS.ink60)
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .overlay(alignment: .bottom) {
            if showBorder {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
        }
    }
}

// MARK: - Board Theme Preview

struct BoardThemePreview: View {
    let theme: BoardTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let boardImage = theme.loadBoardImage() {
                    Image(nsImage: boardImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Rectangle().fill(theme.lightSquare)
                            Rectangle().fill(theme.darkSquare)
                        }
                        HStack(spacing: 0) {
                            Rectangle().fill(theme.darkSquare)
                            Rectangle().fill(theme.lightSquare)
                        }
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? DS.redAccent : DS.hairline,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? DS.redAccent.opacity(0.2) : Color.black.opacity(0.15), radius: isSelected ? 6 : 4, x: 0, y: 2)

            Text(theme.name)
                .font(AnnFont.serif(10, isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? DS.ink : DS.ink40)
                .lineLimit(1)
        }
    }
}

// MARK: - Piece Style Preview

struct PieceStylePreview: View {
    let style: PieceStyle
    let isSelected: Bool

    private var previewPiece: Piece {
        Piece(type: .knight, color: .black)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.paperRaised)
                }
                .frame(width: 50, height: 50)

                if let nsImage = loadPieceImage(style.imageFileName(for: previewPiece)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                } else {
                    Text("\u{265E}")
                        .font(.system(size: 30))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? DS.redAccent : DS.hairline,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? DS.redAccent.opacity(0.2) : Color.black.opacity(0.12), radius: isSelected ? 6 : 4, x: 0, y: 2)

            Text(style.name)
                .font(AnnFont.serif(10, isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? DS.ink : DS.ink40)
        }
    }
}

// MARK: - Engine Settings

struct EngineSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var detectedPath: String? = nil
    @State private var engineStatus: EngineStatus = .checking

    enum EngineStatus {
        case checking
        case found(String)
        case notFound
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Stockfish Engine
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionLabel("STOCKFISH ENGINE")

                    VStack(spacing: 0) {
                        // Status row
                        HStack(spacing: 10) {
                            switch engineStatus {
                            case .checking:
                                ProgressView().controlSize(.small)
                                Text("Checking for Stockfish...")
                                    .font(AnnFont.serif(13))
                                    .foregroundColor(DS.textSecondary)
                            case .found(let path):
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Stockfish found")
                                        .font(AnnFont.serif(13, .medium))
                                        .foregroundColor(DS.textPrimary)
                                    Text(path)
                                        .font(AnnFont.mono(11))
                                        .foregroundColor(DS.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            case .notFound:
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Stockfish not found")
                                    .font(AnnFont.serif(13, .medium))
                                    .foregroundColor(DS.textPrimary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }

                        // Custom path
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom Engine Path")
                                .font(AnnFont.serif(13, .medium))
                                .foregroundColor(DS.textPrimary)

                            HStack(spacing: 8) {
                                TextField("Path to stockfish binary", text: $settings.stockfishPath)
                                    .textFieldStyle(.plain)
                                    .font(AnnFont.mono(12))
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(DS.bg)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(DS.border, lineWidth: 1)
                                    )

                                Button("Browse...") { selectEngineFile() }
                                    .buttonStyle(GlassButtonStyle())
                            }

                            Text("Leave empty to auto-detect from /usr/local/bin or /opt/homebrew/bin")
                                .font(AnnFont.serif(10))
                                .foregroundColor(DS.textTertiary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }

                        // Analysis depth
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Analysis Depth")
                                    .font(AnnFont.serif(13, .medium))
                                    .foregroundColor(DS.textPrimary)
                                Text("Higher depth = more accurate but slower")
                                    .font(AnnFont.serif(11))
                                    .foregroundColor(DS.textTertiary)
                            }
                            Spacer()
                            Stepper(value: $settings.engineDepth, in: EngineSettings.depthRange) {
                                Text("\(settings.engineDepth)")
                                    .font(AnnFont.mono(13, bold: true))
                                    .foregroundColor(DS.accent)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }

                        // Auto-analyze toggle
                        SettingsToggleRow(
                            label: "Auto-analyze moves",
                            description: "Automatically analyze each move as you play",
                            isOn: $settings.autoAnalyze,
                            showBorder: false
                        )
                    }
                    .background(DS.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.border, lineWidth: 1)
                    )
                    .frame(maxWidth: 500)
                }

                // Installation Help
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionLabel("INSTALLATION HELP")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("To install Stockfish via Homebrew:")
                            .font(AnnFont.serif(12))
                            .foregroundColor(DS.textSecondary)

                        Text("brew install stockfish")
                            .font(AnnFont.mono(12))
                            .foregroundColor(DS.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DS.bgTertiary)
                            .cornerRadius(6)

                        Button("Open Stockfish Website") {
                            NSWorkspace.shared.open(URL(string: "https://stockfishchess.org/download/")!)
                        }
                        .font(AnnFont.label(12))
                        .tracking(12 * 0.1)
                        .foregroundColor(DS.accent)
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .frame(maxWidth: 500, alignment: .leading)
                    .background(DS.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DS.border, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
        .onAppear { checkEngineStatus() }
        .onChange(of: settings.stockfishPath) { _, _ in checkEngineStatus() }
    }

    private func checkEngineStatus() {
        engineStatus = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            let path = findStockfishPath()
            DispatchQueue.main.async {
                if let path = path {
                    engineStatus = .found(path)
                } else {
                    engineStatus = .notFound
                }
            }
        }
    }

    private func findStockfishPath() -> String? {
        let fm = FileManager.default

        let userPath = settings.stockfishPath
        if !userPath.isEmpty && fm.fileExists(atPath: userPath) && fm.isExecutableFile(atPath: userPath) {
            return userPath
        }

        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = resourcePath + "/stockfish"
            if fm.fileExists(atPath: bundledPath) && fm.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }

        let commonPaths = [
            "/usr/local/bin/stockfish",
            "/opt/homebrew/bin/stockfish",
            "/usr/bin/stockfish",
            "/Applications/Stockfish.app/Contents/MacOS/stockfish"
        ]

        for path in commonPaths {
            if fm.fileExists(atPath: path) && fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func selectEngineFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select the Stockfish executable"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                settings.stockfishPath = url.path
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: DS.spacingLG) {
            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundColor(DS.accent)

            Text("Tabia")
                .font(AnnFont.serif(22, .semibold))
                .foregroundColor(DS.textPrimary)

            Text("Version 1.0.0")
                .font(AnnFont.mono(12))
                .foregroundColor(DS.textTertiary)

            Rectangle().fill(DS.hairline).frame(height: 1)
                .padding(.horizontal, 40)

            Text("A powerful chess analysis tool for macOS")
                .font(AnnFont.serif(13))
                .multilineTextAlignment(.center)
                .foregroundColor(DS.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Features:")
                    .font(AnnFont.serif(13, .semibold))
                    .foregroundColor(DS.textPrimary)
                Text("Interactive chess board with drag-and-drop")
                Text("Stockfish engine with multi-line analysis")
                Text("PGN import/export with drag-and-drop")
                Text("Game database with search")
                Text("Variation analysis")
                Text("Position evaluation")
            }
            .font(AnnFont.serif(12))
            .foregroundColor(DS.textSecondary)

            Spacer()

            Text("Built with SwiftUI")
                .font(AnnFont.serif(11))
                .foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }
}

// MARK: - Full-Screen Settings (for icon rail)

struct SettingsScreenView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab = 0

    private let tabLabels = ["Appearance", "Engine", "Import"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(AnnFont.serif(24, .semibold))
                    .foregroundColor(DS.ink)

                // Tab bar
                HStack(spacing: 0) {
                    ForEach(Array(tabLabels.enumerated()), id: \.offset) { index, label in
                        Button {
                            withAnimation(DS.quickFade) { selectedTab = index }
                        } label: {
                            Text(label)
                                .font(AnnFont.label(13))
                                .tracking(13 * 0.1)
                                .foregroundColor(selectedTab == index ? DS.ink : DS.ink40)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if selectedTab == index {
                                        Rectangle()
                                            .fill(DS.accent)
                                            .frame(height: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DS.hairline).frame(height: 1)
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)

            // Tab content
            Group {
                switch selectedTab {
                case 0:  AppearanceSettingsView(settings: settings)
                case 1:  EngineSettingsView(settings: settings)
                case 2:  AboutView()
                default: EmptyView()
                }
            }
        }
    }
}

#Preview {
    PreferencesView()
}
