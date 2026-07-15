import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab = 0

    private let tabLabels = ["Appearance", "Engines", "Accounts & Import", "Shortcuts"]

    var body: some View {
        VStack(spacing: 0) {
            // Header — "Settings" on the left, the three tabs on the right, both sitting on the divider.
            HStack(alignment: .bottom, spacing: 24) {
                Text("Settings")
                    .font(AnnFont.serif(22, .semibold))
                    .foregroundColor(DS.ink)
                    .padding(.bottom, 15)
                Spacer(minLength: 24)
                settingsTabBar
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            // Tab content
            Group {
                switch selectedTab {
                case 0:  AppearanceSettingsView(settings: settings)
                case 1:  EngineSettingsView(settings: settings)
                case 2:  AccountsImportView(settings: settings)
                case 3:  ShortcutsSettingsView()
                default: EmptyView()
                }
            }
        }
        .frame(width: 920, height: 620)
        .background(DS.paper)
    }

    private var settingsTabBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabLabels.enumerated()), id: \.offset) { index, label in
                Button {
                    withAnimation(DS.quickFade) { selectedTab = index }
                } label: {
                    Text(label.uppercased())
                        .font(AnnFont.label(12))
                        .tracking(12 * 0.14)
                        .foregroundColor(selectedTab == index ? DS.ink : DS.ink40)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 15)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selectedTab == index ? DS.redAccent : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Accounts & Import

struct AccountsImportView: View {
    @ObservedObject var settings: AppSettings
    @AppStorage("chesscom_username") private var chessComUsername: String = ""
    @AppStorage("lichess_username") private var lichessUsername: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                accountRow(
                    platform: "Chess.com", username: chessComUsername,
                    count: settings.chessComGameCount, lastSynced: settings.chessComLastSynced,
                    onSync: { NotificationCenter.default.post(name: .tabiaSyncGames, object: nil) },
                    onDisconnect: {
                        chessComUsername = ""
                        settings.chessComGameCount = 0
                        settings.chessComLastSynced = 0
                    }
                )
                rowDivider
                accountRow(
                    platform: "Lichess", username: lichessUsername,
                    count: settings.lichessGameCount, lastSynced: settings.lichessLastSynced,
                    onSync: { NotificationCenter.default.post(name: .tabiaSyncGames, object: nil) },
                    onDisconnect: {
                        lichessUsername = ""
                        settings.lichessToken = ""
                        settings.lichessGameCount = 0
                        settings.lichessLastSynced = 0
                    }
                )
                rowDivider

                settingRow(title: "Auto-sync", subtitle: "PULL NEW GAMES IN THE BACKGROUND") {
                    HStack(spacing: 14) {
                        intervalSegmented
                        redToggle($settings.autoSyncEnabled)
                    }
                }
                rowDivider

                settingRow(title: "Skip duplicates", subtitle: "MATCH BY PLAYERS, DATE AND MOVES") {
                    redToggle($settings.skipDuplicatesOnImport)
                }
                rowDivider

                settingRow(title: "Classify openings on import", subtitle: "ECO CODE + NAME FOR EVERY GAME") {
                    redToggle($settings.classifyOpeningsOnImport)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func accountRow(platform: String, username: String, count: Int, lastSynced: Double,
                            onSync: @escaping () -> Void, onDisconnect: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(username.isEmpty ? DS.ink25 : DS.semOnline)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(username.isEmpty ? platform : "\(platform) — \(username)")
                    .font(AnnFont.serif(17, .medium)).foregroundColor(DS.ink)
                Text(username.isEmpty ? "NOT CONNECTED" : accountSubtitle(count: count, lastSynced: lastSynced))
                    .font(AnnFont.mono(10.5)).tracking(0.5).foregroundColor(DS.ink40)
            }
            Spacer(minLength: 12)
            if username.isEmpty {
                pillButton("Connect", filled: true) {
                    NotificationCenter.default.post(name: .tabiaOpenMyGames, object: nil)
                    dismiss()
                }
            } else {
                pillButton("Sync", filled: false, action: onSync)
                pillButton("Disconnect", filled: false, muted: true, action: onDisconnect)
            }
        }
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private func settingRow<Trailing: View>(title: String, subtitle: String,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AnnFont.serif(17, .medium)).foregroundColor(DS.ink)
                Text(subtitle).font(AnnFont.mono(10.5)).tracking(0.5).foregroundColor(DS.ink40)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 18)
    }

    private var rowDivider: some View { Rectangle().fill(DS.hairline).frame(height: 1) }

    // MARK: Controls

    private var intervalSegmented: some View {
        let options: [(String, String)] = [("15m", "15M"), ("1h", "1H"), ("6h", "6H"), ("daily", "DAILY")]
        return HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt in
                let sel = settings.syncIntervalRaw == opt.0
                Button { withAnimation(DS.quickFade) { settings.syncIntervalRaw = opt.0 } } label: {
                    Text(opt.1).font(AnnFont.label(10)).tracking(10 * 0.1)
                        .foregroundColor(sel ? DS.ink : DS.ink40)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(sel ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.selectedWash) : nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DS.trackBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
        .opacity(settings.autoSyncEnabled ? 1 : 0.4)
    }

    private func redToggle(_ isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isOn.wrappedValue.toggle() }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue ? DS.redInk : DS.trackBg)
                    .overlay(isOn.wrappedValue ? nil : Capsule().strokeBorder(DS.borderChip, lineWidth: 1))
                    .frame(width: 44, height: 24)
                Circle().fill(isOn.wrappedValue ? DS.onRed : DS.ink60)
                    .frame(width: 20, height: 20).padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func pillButton(_ label: String, filled: Bool, muted: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased()).font(AnnFont.label(10)).tracking(10 * 0.12)
                .foregroundColor(filled ? DS.onRed : (muted ? DS.ink40 : DS.ink))
                .padding(.vertical, 7).padding(.horizontal, 16)
                .background((filled ? DS.redAccent : DS.paperRaised), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(filled ? Color.clear : DS.borderChip, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func accountSubtitle(count: Int, lastSynced: Double) -> String {
        let games = count > 0 ? "\(count.formatted()) GAMES" : "CONNECTED"
        let synced: String
        if lastSynced > 0 {
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
            synced = "SYNCED " + f.localizedString(for: Date(timeIntervalSince1970: lastSynced), relativeTo: Date()).uppercased()
        } else {
            synced = "NEVER SYNCED"
        }
        return "\(games) · \(synced)"
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // App colour mode
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("APP COLOUR MODE").font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
                        Text("Follows macOS by default.").font(AnnFont.voice(13)).foregroundColor(DS.ink40)
                    }
                    Color.clear.frame(width: 56)
                    modeSegmented
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 20)

                sectionHeader("Board Theme", count: "\(BoardTheme.allThemes.count) THEMES")
                    .padding(.top, 6)
                themeGrid.padding(.top, 12)

                sectionHeader("Piece Style", count: "\(PieceStyle.allStyles.count) STYLES")
                    .padding(.top, 26)
                pieceGrid.padding(.top, 12)

                Rectangle().fill(DS.hairline).frame(height: 1).padding(.top, 24)

                toggleRow("Show coordinates", "RANK AND FILE LABELS ON THE BOARD EDGE", $settings.showCoordinates)
                rowDivider
                toggleRow("Highlight legal moves", "DOTS ON SQUARES A PIECE CAN REACH", $settings.highlightLegalMoves)
                rowDivider
                toggleRow("Best-move arrow", "DRAW THE ENGINE\u{2019}S CHOICE ON THE BOARD", $settings.showBestMoveArrow)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // MARK: - App colour mode

    private var modeSegmented: some View {
        HStack(spacing: 2) {
            ForEach(AppAppearance.allCases, id: \.self) { mode in
                let sel = settings.appAppearance == mode
                Button { withAnimation(DS.quickFade) { settings.appAppearance = mode } } label: {
                    Text(mode.displayName.uppercased()).font(AnnFont.label(10.5)).tracking(10.5 * 0.1)
                        .foregroundColor(sel ? DS.paper : DS.ink40)
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .background(sel ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.ink) : nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }

    // MARK: - Section header (label + total count, no "more")

    private func sectionHeader(_ title: String, count: String) -> some View {
        HStack {
            Text(title.uppercased()).font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
            Spacer()
            Text(count).font(AnnFont.mono(9.5)).foregroundColor(DS.ink25)
        }
    }

    // MARK: - Board themes (all shown, wrapped)

    private var themeGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(chunked(BoardTheme.allThemes, 10).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row) { theme in
                        BoardThemePreview(theme: theme, isSelected: settings.boardThemeId == theme.id)
                            .onTapGesture { withAnimation(DS.quickFade) { settings.boardThemeId = theme.id } }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Piece styles (all shown, wrapped, horizontal pills)

    private var pieceGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(chunked(PieceStyle.allStyles, 6).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(row) { style in
                        pieceStylePill(style)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func pieceStylePill(_ style: PieceStyle) -> some View {
        let sel = settings.pieceStyleId == style.id
        return Button { withAnimation(DS.quickFade) { settings.pieceStyleId = style.id } } label: {
            HStack(spacing: 10) {
                Group {
                    if let img = loadPieceImage(style.imageFileName(for: Piece(type: .knight, color: .black))) {
                        Image(nsImage: img).resizable().scaledToFit()
                    } else {
                        Text("\u{265E}").font(.system(size: 18))
                    }
                }
                .frame(width: 22, height: 22)
                Text(style.name.uppercased()).font(AnnFont.label(11)).tracking(11 * 0.1)
                    .foregroundColor(sel ? DS.ink : DS.ink60)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(minWidth: 120)
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(sel ? DS.redAccent : DS.borderChip, lineWidth: sel ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toggle rows

    private func toggleRow(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AnnFont.serif(17, .medium)).foregroundColor(DS.ink)
                Text(subtitle).font(AnnFont.mono(10.5)).tracking(0.5).foregroundColor(DS.ink40)
            }
            Spacer(minLength: 12)
            redToggle(isOn)
        }
        .padding(.vertical, 18)
    }

    private var rowDivider: some View { Rectangle().fill(DS.hairline).frame(height: 1) }

    private func redToggle(_ isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isOn.wrappedValue.toggle() }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule().fill(isOn.wrappedValue ? DS.redInk : DS.trackBg)
                    .overlay(isOn.wrappedValue ? nil : Capsule().strokeBorder(DS.borderChip, lineWidth: 1))
                    .frame(width: 44, height: 24)
                Circle().fill(isOn.wrappedValue ? DS.onRed : DS.ink60)
                    .frame(width: 20, height: 20).padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingRow(title: "Default engine", subtitle: "USED FOR ANALYSIS AND GAME REVIEW") {
                    defaultEnginePicker
                }
                rowDivider
                settingRow(title: "Review depth", subtitle: "DEEPER = SLOWER, STRICTER GRADES") {
                    depthSegmented
                }
                rowDivider
                settingRow(title: "Analyze on open", subtitle: "START THE ENGINE WHEN A GAME LOADS") {
                    redToggle($settings.autoAnalyze)
                }
                rowDivider
                settingRow(title: "Cloud fallback", subtitle: "USE LICHESS CLOUD WHEN NO LOCAL ENGINE") {
                    redToggle($settings.cloudFallbackEnabled)
                }
                rowDivider
                settingRow(title: "Engine Room", subtitle: "INSTALL, REMOVE AND TUNE ENGINES — \u{2318}E") {
                    Button { openWindow(id: WindowID.engineRoom) } label: {
                        Text("OPEN ENGINE ROOM \u{2192}")
                            .font(AnnFont.label(10)).tracking(10 * 0.12)
                            .foregroundColor(DS.redAccent)
                            .padding(.vertical, 7).padding(.horizontal, 16)
                            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
    }

    // MARK: Controls

    private var defaultEnginePicker: some View {
        Menu {
            if settings.engines.isEmpty {
                Text("No engines installed")
            } else {
                ForEach(settings.engines) { eng in
                    Button(eng.name) { settings.setDefaultEngine(id: eng.id) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(settings.defaultEngine?.name ?? "None")
                    .font(AnnFont.serif(14)).foregroundColor(DS.ink)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(DS.ink40)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var depthSegmented: some View {
        let opts: [(String, String)] = [("fast", "FAST"), ("balanced", "BALANCED"), ("deep", "DEEP")]
        return HStack(spacing: 2) {
            ForEach(opts, id: \.0) { opt in
                let sel = settings.reviewDepthRaw == opt.0
                Button { withAnimation(DS.quickFade) { settings.reviewDepthRaw = opt.0 } } label: {
                    Text(opt.1).font(AnnFont.label(10.5)).tracking(10.5 * 0.1)
                        .foregroundColor(sel ? DS.paper : DS.ink40)
                        .padding(.vertical, 7).padding(.horizontal, 16)
                        .background(sel ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.ink) : nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }

    private func redToggle(_ isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isOn.wrappedValue.toggle() }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue ? DS.redInk : DS.trackBg)
                    .overlay(isOn.wrappedValue ? nil : Capsule().strokeBorder(DS.borderChip, lineWidth: 1))
                    .frame(width: 44, height: 24)
                Circle().fill(isOn.wrappedValue ? DS.onRed : DS.ink60)
                    .frame(width: 20, height: 20).padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func settingRow<Trailing: View>(title: String, subtitle: String,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AnnFont.serif(17, .medium)).foregroundColor(DS.ink)
                Text(subtitle).font(AnnFont.mono(10.5)).tracking(0.5).foregroundColor(DS.ink40)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 18)
    }

    private var rowDivider: some View { Rectangle().fill(DS.hairline).frame(height: 1) }
}

// MARK: - About View

struct AboutView: View {
    @State private var showingAcknowledgements = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "Version \(v) (\($0))" } ?? "Version \(v)"
    }

    var body: some View {
        VStack(spacing: DS.spacingLG) {
            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundColor(DS.accent)

            Text("Tabia")
                .font(AnnFont.serif(22, .semibold))
                .foregroundColor(DS.textPrimary)

            Text(appVersion)
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

            Button(action: { showingAcknowledgements = true }) {
                Text("Acknowledgements & Licenses")
                    .font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.ink)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("Built with SwiftUI")
                .font(AnnFont.serif(11))
                .foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .sheet(isPresented: $showingAcknowledgements) {
            AcknowledgementsView(onClose: { showingAcknowledgements = false })
        }
    }
}

// MARK: - Full-Screen Settings (for icon rail)

struct SettingsScreenView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab = 0

    private let tabLabels = ["Appearance", "Engine", "About"]

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
