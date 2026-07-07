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
                    .font(.system(size: 22, weight: .bold))
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

            Rectangle().fill(DS.glassSeparator).frame(height: 1)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding(DS.spacingLG)
        }
        .frame(width: 600, height: 700)
        .background(.ultraThinMaterial)
    }

    private var settingsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabLabels.enumerated()), id: \.offset) { index, label in
                Button {
                    withAnimation(DS.quickFade) { selectedTab = index }
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: selectedTab == index ? .medium : .regular))
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
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
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
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? Color(hex: 0xFFFFFF, opacity: 0.93) : Color(hex: 0xFFFFFF, opacity: 0.33))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 16)
                                    .contentShape(Rectangle())
                                    .background(
                                        isSelected
                                        ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.125))
                                        : nil
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                                lineWidth: 1
                            )
                    )
                }

                // Board Theme
                VStack(alignment: .leading, spacing: 12) {
                    glassSettingsLabel("BOARD THEME")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 70), spacing: 10)], spacing: 10) {
                        ForEach(BoardTheme.allThemes) { theme in
                            BoardThemePreview(
                                theme: theme,
                                isSelected: settings.boardThemeId == theme.id
                            )
                            .onTapGesture {
                                withAnimation(DS.quickFade) { settings.boardThemeId = theme.id }
                            }
                        }
                    }
                }

                // Piece Style
                VStack(alignment: .leading, spacing: 12) {
                    glassSettingsLabel("PIECE STYLE")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 80), spacing: 12)], spacing: 12) {
                        ForEach(PieceStyle.allStyles) { style in
                            PieceStylePreview(
                                style: style,
                                isSelected: settings.pieceStyleId == style.id
                            )
                            .onTapGesture {
                                withAnimation(DS.quickFade) { settings.pieceStyleId = style.id }
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
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.094))
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.145), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: UnitPoint(x: 0.5, y: 0.4)
                                    )
                                )
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.31), Color.white.opacity(0.06)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
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
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.2))
        .kerning(0.8)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))

                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.33))
                }
            }

            Spacer()

            // Toggle (40x22 capsule)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color(hex: 0x0A84FF) : Color.white.opacity(0.13))
                        .overlay(
                            isOn ? nil : Capsule().strokeBorder(Color.white.opacity(0.19), lineWidth: 1)
                        )
                        .frame(width: 40, height: 22)
                    Circle()
                        .fill(isOn ? .white : Color(hex: 0xFFFFFF, opacity: 0.67))
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
                Rectangle().fill(Color.white.opacity(0.19)).frame(height: 1)
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
                        isSelected
                        ? LinearGradient(colors: [Color(hex: 0x0A84FF, opacity: 0.73), Color(hex: 0x0A84FF, opacity: 0.31)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Color(hex: 0x0A84FF, opacity: 0.15) : Color.black.opacity(0.15), radius: isSelected ? 6 : 4, x: 0, y: 2)

            Text(theme.name)
                .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? Color(hex: 0xFFFFFF, opacity: 0.93) : Color(hex: 0xFFFFFF, opacity: 0.33))
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
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.15))
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
                        isSelected
                        ? LinearGradient(colors: [Color(hex: 0x0A84FF, opacity: 0.73), Color(hex: 0x0A84FF, opacity: 0.31)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.white.opacity(0.125)], startPoint: .top, endPoint: .bottom),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Color(hex: 0x0A84FF, opacity: 0.15) : Color.black.opacity(0.12), radius: isSelected ? 6 : 4, x: 0, y: 2)

            Text(style.name)
                .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? Color(hex: 0xFFFFFF, opacity: 0.93) : Color(hex: 0xFFFFFF, opacity: 0.33))
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
                                    .font(.system(size: 13))
                                    .foregroundColor(DS.textSecondary)
                            case .found(let path):
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Stockfish found")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(DS.textPrimary)
                                    Text(path)
                                        .font(.system(size: 11))
                                        .foregroundColor(DS.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            case .notFound:
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Stockfish not found")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.textPrimary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.glassSeparator).frame(height: 1)
                        }

                        // Custom path
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom Engine Path")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DS.textPrimary)

                            HStack(spacing: 8) {
                                TextField("Path to stockfish binary", text: $settings.stockfishPath)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
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
                                .font(.system(size: 10))
                                .foregroundColor(DS.textTertiary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.glassSeparator).frame(height: 1)
                        }

                        // Analysis depth
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Analysis Depth")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.textPrimary)
                                Text("Higher depth = more accurate but slower")
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.textTertiary)
                            }
                            Spacer()
                            Stepper(value: $settings.engineDepth, in: EngineSettings.depthRange) {
                                Text("\(settings.engineDepth)")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(DS.accent)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.glassSeparator).frame(height: 1)
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
                            .font(.system(size: 12))
                            .foregroundColor(DS.textSecondary)

                        Text("brew install stockfish")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(DS.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DS.bgTertiary)
                            .cornerRadius(6)

                        Button("Open Stockfish Website") {
                            NSWorkspace.shared.open(URL(string: "https://stockfishchess.org/download/")!)
                        }
                        .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(DS.textPrimary)

            Text("Version 1.0.0")
                .font(.system(size: 12))
                .foregroundColor(DS.textTertiary)

            Rectangle().fill(DS.glassSeparator).frame(height: 1)
                .padding(.horizontal, 40)

            Text("A powerful chess analysis tool for macOS")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(DS.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Features:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                Text("Interactive chess board with drag-and-drop")
                Text("Stockfish engine with multi-line analysis")
                Text("PGN import/export with drag-and-drop")
                Text("Game database with search")
                Text("Variation analysis")
                Text("Position evaluation")
            }
            .font(.system(size: 12))
            .foregroundColor(DS.textSecondary)

            Spacer()

            Text("Built with SwiftUI")
                .font(.system(size: 11))
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
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))

                // Tab bar
                HStack(spacing: 0) {
                    ForEach(Array(tabLabels.enumerated()), id: \.offset) { index, label in
                        Button {
                            withAnimation(DS.quickFade) { selectedTab = index }
                        } label: {
                            Text(label)
                                .font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                                .foregroundColor(selectedTab == index ? Color(hex: 0xFFFFFF, opacity: 0.93) : Color(hex: 0xFFFFFF, opacity: 0.33))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if selectedTab == index {
                                        Rectangle()
                                            .fill(Color(hex: 0x0A84FF))
                                            .frame(height: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.19)).frame(height: 1)
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
