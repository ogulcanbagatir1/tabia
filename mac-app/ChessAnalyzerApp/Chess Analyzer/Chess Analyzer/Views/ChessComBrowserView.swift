import SwiftUI

struct ChessComBrowserView: View {
    @EnvironmentObject var database: GameDatabase
    var onGameSelected: (GameRecord) -> Void

    @StateObject private var service = ChessComService()
    @StateObject private var lichessService = LichessGameService()
    @ObservedObject private var lichessAuth = LichessAuthService.shared
    @ObservedObject private var settings = AppSettings.shared
    @AppStorage("chesscom_username") private var savedUsername: String = ""
    @AppStorage("chesscom_last_sync") private var lastSyncTimestamp: Double = 0
    @AppStorage("lichess_username") private var lichessUsername: String = ""
    @AppStorage("lichess_last_sync") private var lichessLastSync: Double = 0

    @State private var cachedGames: [GameRecord] = []
    @State private var totalGameCount: Int = 0
    @State private var isLoadingGames = false
    @State private var dbOffset: Int = 0
    @State private var allDbGamesExhausted = false
    @State private var reloadTask: Task<Void, Never>?
    private let pageSize = 50
    private let dbBatchSize = 200

    @State private var showStats = false
    @State private var cachedRatings: [String: Int] = [:]
    @State private var showingImportSheet = false
    @State private var selectedGameIds: Set<UUID> = []
    @State private var lastSelectedGame: GameRecord?
    @State private var showingMoveToFolder = false
    @State private var newFolderName = ""

    // Syncing state
    @State private var isSyncing = false
    @State private var importedCount = 0
    @State private var syncTimeClassCounts: [String: Int] = [:]
    @State private var recentlyImportedGames: [GameRecord] = []
    @State private var syncTask: Task<Void, Never>?

    // Sorting
    @State private var sortColumn: SortColumn = .date
    @State private var sortAscending = false

    enum SortColumn: String {
        case white, black, date, result, opening, timeControl, source
    }

    // Filters
    @State private var filterTimeControl: String = "All"
    @State private var filterResult: String = "All"
    @State private var filterColor: String = "All"
    @State private var filterOpening: String = ""
    @State private var filterDateFrom: Date? = nil
    @State private var filterDateTo: Date? = nil
    @State private var filterSource: String = "All"

    // Lichess sync state
    @State private var isLichessSyncing = false
    @State private var lichessImportedCount = 0
    @State private var lichessSyncTask: Task<Void, Never>?

    private let chessComGreen = DS.chessComGreen

    private var hasMorePages: Bool { !allDbGamesExhausted }

    private var hasAnyAccount: Bool {
        !savedUsername.isEmpty || !lichessUsername.isEmpty
    }

    private var activeUsername: String {
        // For result color calculations — use chess.com or lichess username
        if !savedUsername.isEmpty { return savedUsername }
        return lichessUsername
    }

    private var lastSyncString: String {
        guard lastSyncTimestamp > 0 else { return "never" }
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var hasClientSideFilters: Bool {
        filterResult != "All" || filterColor != "All" ||
        !filterOpening.isEmpty ||
        filterDateFrom != nil || filterDateTo != nil ||
        filterSource != "All"
    }

    private var activeTimeClass: String? {
        filterTimeControl == "All" ? nil : filterTimeControl.lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasAnyAccount {
                emptyStateView
            } else {
                connectedStateView
            }
        }
        .onAppear {
            if cachedGames.isEmpty && hasAnyAccount {
                reloadGames()
            }
            loadRatings()
        }
        .onChange(of: filterTimeControl) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterResult) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterColor) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterDateFrom) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterDateTo) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterOpening) { _, _ in scheduleReload(debounce: true) }
        .onChange(of: filterSource) { _, _ in scheduleReload(debounce: false) }
    }

    private func scheduleReload(debounce: Bool) {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: debounce ? 300_000_000 : 50_000_000)
            guard !Task.isCancelled else { return }
            reloadGames()
        }
    }

    private func reloadGames() {
        guard hasAnyAccount else { return }
        cachedGames = []
        dbOffset = 0
        allDbGamesExhausted = false
        isLoadingGames = true

        let tc = activeTimeClass
        let ps = pageSize
        let db = database
        let hasFilters = hasClientSideFilters

        Task.detached {
            let count = db.onlineGamesCount()
            let batch = db.fetchFilteredOnlineGames(timeClass: tc, limit: ps, offset: 0)
            await MainActor.run {
                totalGameCount = count
                dbOffset = batch.count
                if batch.count < ps { allDbGamesExhausted = true }
                if hasFilters {
                    cachedGames = applyClientFilters(batch)
                } else {
                    cachedGames = batch
                }
                isLoadingGames = false
            }
        }
    }

    private func loadNextPage() {
        guard hasMorePages, !isLoadingGames else { return }
        isLoadingGames = true

        let tc = activeTimeClass
        let batchSize = hasClientSideFilters ? dbBatchSize : pageSize
        let currentOffset = dbOffset
        let hasFilters = hasClientSideFilters
        let db = database

        Task.detached {
            let batch = db.fetchFilteredOnlineGames(timeClass: tc, limit: batchSize, offset: currentOffset)
            await MainActor.run {
                dbOffset += batch.count
                if batch.count < batchSize { allDbGamesExhausted = true }
                if hasFilters {
                    cachedGames.append(contentsOf: applyClientFilters(batch))
                } else {
                    cachedGames.append(contentsOf: batch)
                }
                isLoadingGames = false
            }
        }
    }

    private func applyClientFilters(_ games: [GameRecord]) -> [GameRecord] {
        var result = games
        if filterSource != "All" {
            let src = filterSource == "Chess.com" ? "chesscom" : "lichess"
            result = result.filter { $0.sourcePlatform == src }
        }
        if filterResult != "All" {
            result = result.filter { game in
                let username = game.sourceUsername ?? ""
                let userPlayedWhite = game.white.lowercased() == username
                switch filterResult {
                case "Wins": return (userPlayedWhite && game.result == "1-0") || (!userPlayedWhite && game.result == "0-1")
                case "Losses": return (userPlayedWhite && game.result == "0-1") || (!userPlayedWhite && game.result == "1-0")
                case "Draws": return game.result == "1/2-1/2" || game.result == "1/2"
                default: return true
                }
            }
        }
        if filterColor != "All" {
            result = result.filter { game in
                let username = game.sourceUsername ?? ""
                let userPlayedWhite = game.white.lowercased() == username
                switch filterColor {
                case "White": return userPlayedWhite
                case "Black": return !userPlayedWhite
                default: return true
                }
            }
        }
        if !filterOpening.isEmpty {
            let query = filterOpening.lowercased()
            result = result.filter { game in
                game.opening?.lowercased().contains(query) == true ||
                game.eco?.lowercased().contains(query) == true
            }
        }
        if let dateFrom = filterDateFrom {
            result = result.filter { $0.dateAdded >= dateFrom }
        }
        if let dateTo = filterDateTo {
            result = result.filter { $0.dateAdded <= dateTo }
        }
        return result
    }

    // MARK: - Empty State

    @State private var connectUsername: String = ""

    @State private var connectLichessUsername: String = ""

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "globe")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.textTertiary)

            Text("Connect Your Accounts")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DS.textPrimary)

            Text("Import and analyze your online games from Chess.com and Lichess")
                .font(.system(size: 13))
                .foregroundColor(DS.textTertiary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            // Chess.com connect
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(chessComGreen).frame(width: 8, height: 8)
                    Text("Chess.com")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.textPrimary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DS.textTertiary)

                        TextField("Chess.com username...", text: $connectUsername)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit {
                                if !connectUsername.isEmpty {
                                    savedUsername = connectUsername
                                    startProgressiveSync(fullImport: true)
                                }
                            }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(DS.bgElevated)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.border, lineWidth: 1))

                    Button(action: {
                        if !connectUsername.isEmpty {
                            savedUsername = connectUsername
                            startProgressiveSync(fullImport: true)
                        }
                    }) {
                        Text("Connect")
                            .glassButtonPrimary()
                    }
                    .buttonStyle(.plain)
                    .disabled(connectUsername.isEmpty)
                }
            }
            .frame(maxWidth: 380)

            // Lichess connect
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(Color.white).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(DS.hairline, lineWidth: 0.5))
                    Text("Lichess")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.textPrimary)
                    Spacer()
                }

                if settings.lichessToken.isEmpty {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(DS.textTertiary)
                            TextField("Lichess username...", text: $connectLichessUsername)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .onSubmit {
                                    if !connectLichessUsername.isEmpty {
                                        lichessUsername = connectLichessUsername
                                        startLichessSync(fullImport: true)
                                    }
                                }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(DS.bgElevated)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.border, lineWidth: 1))

                        Button(action: {
                            if !connectLichessUsername.isEmpty {
                                lichessUsername = connectLichessUsername
                                startLichessSync(fullImport: true)
                            }
                        }) {
                            Text("Connect")
                                .glassButtonPrimary()
                        }
                        .buttonStyle(.plain)
                        .disabled(connectLichessUsername.isEmpty)
                    }

                    Button(action: loginLichess) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 12))
                            Text("Login for faster imports")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(DS.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("Logged in")
                            .font(.system(size: 13))
                            .foregroundColor(DS.textSecondary)
                        Spacer()
                        Button("Fetch Games") {
                            fetchLichessProfile()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .buttonStyle(GlassPrimaryButtonStyle())
                    }
                }
            }
            .frame(maxWidth: 380)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Connected State

    private var connectedStateView: some View {
        Group {
            if isSyncing {
                syncingStateView
            } else {
                normalConnectedContent
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            ChessComConnectSheet(
                service: service,
                savedUsername: $savedUsername,
                lastSyncTimestamp: $lastSyncTimestamp,
                onImport: { games, username in
                    showingImportSheet = false
                    startImportFromSheet(games: games, username: username)
                },
                onDismiss: { showingImportSheet = false }
            )
        }
        .alert("New Database", isPresented: $showingMoveToFolder) {
            TextField("Database name", text: $newFolderName)
            Button("Cancel", role: .cancel) { }
            Button("Create & Move") {
                if !newFolderName.isEmpty {
                    let folder = database.createFolder(name: newFolderName)
                    database.moveGamesByIds(selectedGameIds, toFolder: folder.id)
                    selectedGameIds.removeAll()
                    newFolderName = ""
                }
            }
        } message: {
            Text("Create a new database and move \(selectedGameIds.count) game(s) into it.")
        }
    }

    private var normalConnectedContent: some View {
        VStack(spacing: 0) {
            // Profile Header
            HStack(spacing: 14) {
                // Avatar
                HStack(spacing: 14) {
                    let displayName = !savedUsername.isEmpty ? savedUsername : lichessUsername
                    ZStack {
                        Circle()
                            .fill(DS.paperRaised)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().strokeBorder(
                                    DS.hairline,
                                    lineWidth: 1
                                )
                            )
                        Text(String(displayName.prefix(1)).uppercased())
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(DS.ink)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.ink)
                        Text("Last synced \(lastSyncString)")
                            .font(.system(size: 11))
                            .foregroundColor(DS.ink25)
                    }
                }

                Spacer()

                // Sync button
                Button(action: refreshGames) {
                    if service.isLoading || lichessService.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                            Text("Sync Games")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: 0x30D158))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color(hex: 0x30D158, opacity: 0.094), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(hex: 0x30D158, opacity: 0.31), lineWidth: 1)
                        )
                    }
                }
                .buttonStyle(.plain)
                .disabled(service.isLoading || lichessService.isLoading)

                Menu {
                    if !savedUsername.isEmpty {
                        Button(action: { showingImportSheet = true }) {
                            Label("Chess.com Settings", systemImage: "gearshape")
                        }
                    }

                    if lichessUsername.isEmpty {
                        Button(action: connectLichessFromMenu) {
                            Label("Connect Lichess", systemImage: "plus.circle")
                        }
                    }

                    if settings.lichessToken.isEmpty && !lichessUsername.isEmpty {
                        Button(action: loginLichess) {
                            Label("Login to Lichess", systemImage: "person.badge.key")
                        }
                    } else if !settings.lichessToken.isEmpty {
                        Button(action: logoutLichess) {
                            Label("Logout Lichess", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }

                    Divider()

                    if !savedUsername.isEmpty {
                        Button(role: .destructive, action: disconnectChessComAccount) {
                            Label("Disconnect Chess.com", systemImage: "xmark.circle")
                        }
                    }
                    if !lichessUsername.isEmpty {
                        Button(role: .destructive, action: disconnectLichessAccount) {
                            Label("Disconnect Lichess", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(DS.textSecondary)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 28)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            // Stats Cards Row
            statsCardsRow
                .padding(.vertical, 20)
                .padding(.horizontal, 28)

            // Filter Pills
            filterPillsRow
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            if showStats {
                ChessComStatsView(
                    username: savedUsername,
                    selectedTimeClass: filterTimeControl == "All" ? "all" : filterTimeControl.lowercased()
                )
            } else {
                if showingFilters {
                    chessComFilterPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if cachedGames.isEmpty {
                    emptyGamesView
                } else {
                    gamesList
                }
            }

            statusBar
        }
    }

    // MARK: - Filter Bar

    @State private var showingFilters = false
    @State private var chessComFilterCardHeight: CGFloat = 0

    private var hasActiveFilters: Bool {
        filterTimeControl != "All" || filterResult != "All" || filterColor != "All" ||
        !filterOpening.isEmpty || filterDateFrom != nil || filterDateTo != nil ||
        filterSource != "All"
    }

    private var activeFilterCount: Int {
        var count = 0
        if filterTimeControl != "All" { count += 1 }
        if filterResult != "All" { count += 1 }
        if filterColor != "All" { count += 1 }
        if !filterOpening.isEmpty { count += 1 }
        if filterDateFrom != nil || filterDateTo != nil { count += 1 }
        if filterSource != "All" { count += 1 }
        return count
    }

    private func clearFilters() {
        filterTimeControl = "All"
        filterResult = "All"
        filterColor = "All"
        filterOpening = ""
        filterDateFrom = nil
        filterDateTo = nil
        filterSource = "All"
    }

    private var chessComFilterPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Time Control
                chessComFilterCard(title: "Time Control", icon: "clock", width: 150) {
                    VStack(spacing: 4) {
                        chessComFilterOption("All", current: filterTimeControl) { filterTimeControl = $0 }
                        chessComFilterOption("Bullet", current: filterTimeControl) { filterTimeControl = $0 }
                        chessComFilterOption("Blitz", current: filterTimeControl) { filterTimeControl = $0 }
                        chessComFilterOption("Rapid", current: filterTimeControl) { filterTimeControl = $0 }
                        chessComFilterOption("Daily", current: filterTimeControl) { filterTimeControl = $0 }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Result
                chessComFilterCard(title: "Result", icon: "flag", width: 150) {
                    VStack(spacing: 4) {
                        chessComFilterOption("All", current: filterResult) { filterResult = $0 }
                        chessComFilterOption("Wins", current: filterResult) { filterResult = $0 }
                        chessComFilterOption("Losses", current: filterResult) { filterResult = $0 }
                        chessComFilterOption("Draws", current: filterResult) { filterResult = $0 }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Source
                chessComFilterCard(title: "Source", icon: "globe", width: 150) {
                    VStack(spacing: 4) {
                        chessComFilterOption("All", current: filterSource) { filterSource = $0 }
                        chessComFilterOption("Chess.com", current: filterSource) { filterSource = $0 }
                        chessComFilterOption("Lichess", current: filterSource) { filterSource = $0 }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Played As
                chessComFilterCard(title: "Played As", icon: "circle.lefthalf.filled", width: 150) {
                    VStack(spacing: 4) {
                        chessComFilterOption("All", current: filterColor) { filterColor = $0 }
                        chessComFilterOption("White", current: filterColor) { filterColor = $0 }
                        chessComFilterOption("Black", current: filterColor) { filterColor = $0 }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Reset
                if hasActiveFilters {
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { clearFilters() } }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14))
                            Text("Reset")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 50)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onPreferenceChange(ChessComFilterCardHeightKey.self) { height in
                if height > chessComFilterCardHeight {
                    chessComFilterCardHeight = height
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(DS.bgSecondary)
    }

    private func chessComFilterCard<Content: View>(title: String, icon: String, width: CGFloat = 150, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(DS.textSecondary)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                    .textCase(.uppercase)
            }

            content()
        }
        .frame(width: width)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(GeometryReader { geo in
            Color.clear.preference(key: ChessComFilterCardHeightKey.self, value: geo.size.height)
        })
        .frame(height: chessComFilterCardHeight > 0 ? chessComFilterCardHeight : nil, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    private func chessComFilterOption(_ option: String, current: String, onSelect: @escaping (String) -> Void) -> some View {
        let isSelected = current == option
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) { onSelect(option) }
        }) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isSelected ? chessComGreen : DS.bgSecondary)
                    .frame(width: 14, height: 14)
                    .overlay(
                        isSelected ?
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                        : nil
                    )
                Text(option)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? DS.textPrimary : DS.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Cards Row

    private var statsCardsRow: some View {
        HStack(spacing: 16) {
            statsCard(category: "Bullet", dotColor: DS.timeControlBullet)
            statsCard(category: "Blitz", dotColor: DS.timeControlBlitz)
            statsCard(category: "Rapid", dotColor: DS.timeControlRapid)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadRatings() {
        Task.detached {
            let db = database
            let username = savedUsername
            guard let cached = db.fetchAllCachedStats(for: username) else { return }
            var ratings: [String: Int] = [:]
            for tc in ["bullet", "blitz", "rapid"] {
                if let allStats = cached.statsData["all"],
                   let tcStats = allStats.timeControlStats[tc] {
                    ratings[tc] = tcStats.currentRating
                } else if let stats = cached.statsData[tc],
                          let tcStats = stats.timeControlStats[tc] {
                    ratings[tc] = tcStats.currentRating
                }
            }
            await MainActor.run {
                cachedRatings = ratings
            }
        }
    }

    private func statsCard(category: String, dotColor: Color) -> some View {
        let rating = cachedRatings[category.lowercased()]

        return HStack(spacing: 14) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(category)
                    .font(.system(size: 11))
                    .foregroundColor(DS.ink40)
                Text(verbatim: rating != nil ? String(rating!) : "-")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(DS.ink)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.paperRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.19), radius: 10, x: 0, y: 4)
    }

    // MARK: - Filter Pills

    private var filterPillsRow: some View {
        HStack(spacing: 8) {
            // Time control pills
            HStack(spacing: 6) {
                ForEach(["All", "Bullet", "Blitz", "Rapid"], id: \.self) { option in
                    let isActive = filterTimeControl == option
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            filterTimeControl = option
                        }
                    }) {
                        Text(option)
                            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? DS.ink : DS.ink40)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                            .background(
                                isActive
                                ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.selectedWash)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                                : nil
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Games / Stats toggle
            HStack(spacing: 2) {
                Button(action: { withAnimation(.easeInOut(duration: 0.12)) { showStats = false } }) {
                    Text("Games")
                        .font(.system(size: 11, weight: showStats ? .regular : .medium))
                        .foregroundColor(showStats ? DS.ink40 : DS.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(showStats ? Color.clear : DS.selectedWash)
                        )
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation(.easeInOut(duration: 0.12)) { showStats = true } }) {
                    Text("Stats")
                        .font(.system(size: 11, weight: showStats ? .medium : .regular))
                        .foregroundColor(showStats ? DS.ink : DS.ink40)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(showStats ? DS.selectedWash : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(3)
            .background(DS.trackBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DS.borderChip, lineWidth: 1)
            )
        }
    }

    // MARK: - Games List

    private var sortedCachedGames: [GameRecord] {
        cachedGames.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .white:       result = a.white.localizedCaseInsensitiveCompare(b.white) == .orderedAscending
            case .black:       result = a.black.localizedCaseInsensitiveCompare(b.black) == .orderedAscending
            case .date:        result = a.dateAdded < b.dateAdded
            case .result:      result = a.result < b.result
            case .opening:     result = (a.opening ?? "").localizedCaseInsensitiveCompare(b.opening ?? "") == .orderedAscending
            case .timeControl: result = (a.timeClass ?? "").localizedCaseInsensitiveCompare(b.timeClass ?? "") == .orderedAscending
            case .source:      result = (a.sourcePlatform ?? "").localizedCaseInsensitiveCompare(b.sourcePlatform ?? "") == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    let sorted = sortedCachedGames
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, game in
                        chessComTableRow(game, isAlternate: index % 2 != 0)
                            .onTapGesture {
                                if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                                    onGameSelected(game)
                                }
                                if NSEvent.modifierFlags.contains(.command) {
                                    if selectedGameIds.contains(game.id) {
                                        selectedGameIds.remove(game.id)
                                    } else {
                                        selectedGameIds.insert(game.id)
                                    }
                                } else if NSEvent.modifierFlags.contains(.shift), let last = lastSelectedGame {
                                    if let startIdx = sorted.firstIndex(where: { $0.id == last.id }),
                                       let endIdx = sorted.firstIndex(where: { $0.id == game.id }) {
                                        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
                                        for i in range {
                                            selectedGameIds.insert(sorted[i].id)
                                        }
                                    }
                                } else {
                                    selectedGameIds = [game.id]
                                }
                                lastSelectedGame = game
                            }
                            .contextMenu {
                                Button("Open Game") { onGameSelected(game) }
                                Divider()
                                if selectedGameIds.count > 1 {
                                    moveToFolderMenu(gameIds: selectedGameIds, label: "Move \(selectedGameIds.count) Games to...")
                                } else {
                                    moveToFolderMenu(gameIds: [game.id], label: "Move to...")
                                }
                            }
                            .onAppear {
                                if game.id == cachedGames.last?.id && hasMorePages {
                                    loadNextPage()
                                }
                            }
                    }

                    if hasMorePages {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading more games...")
                                .font(.system(size: 11))
                                .foregroundColor(DS.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .onAppear { loadNextPage() }
                    }
                } header: {
                    chessComTableHeader
                }
            }
        }
    }

    // Columns: White(150) Black(150) Result(60, center) Opening(fill) Time(60, center) Date(100, right)

    private var chessComTableHeader: some View {
        HStack(spacing: 0) {
            chessComColumnHeader("White", column: .white, alignment: .leading)
                .frame(width: 200, alignment: .leading)
            chessComColumnHeader("Black", column: .black, alignment: .leading)
                .frame(width: 200, alignment: .leading)
            chessComColumnHeader("Result", column: .result, alignment: .center)
                .frame(width: 60, alignment: .center)
                .padding(.trailing, 64)
            chessComColumnHeader("Opening", column: .opening, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            chessComColumnHeader("Time", column: .timeControl, alignment: .center)
                .frame(width: 60, alignment: .center)
                .padding(.trailing, 32)
            chessComColumnHeader("Source", column: .source, alignment: .center)
                .frame(width: 70, alignment: .center)
                .padding(.trailing, 32)
            chessComColumnHeader("Date", column: .date, alignment: .leading)
                .frame(width: 130, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .frame(height: 36)
        .background(DS.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private func chessComColumnHeader(_ title: String, column: SortColumn, alignment: Alignment) -> some View {
        Button(action: {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = column != .date
            }
        }) {
            HStack(spacing: 4) {
                if alignment == .trailing, sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.ink25)
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.ink25)

                if alignment != .trailing, sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.ink25)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : (alignment == .center ? .center : .leading))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chessComTableRow(_ game: GameRecord, isAlternate: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // White
                Text(game.white)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.textPrimary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)

                // Black
                Text(game.black)
                    .font(.system(size: 13))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)

                // Result
                Text(chessComResultDisplay(game.result))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(chessComResultColor(game))
                    .frame(width: 60, alignment: .center)
                    .padding(.trailing, 64)

                // Opening
                Text(game.opening ?? game.eco ?? "-")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Time control
                Text(chessComTimeClassLabel(game.timeClass))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.timeControlColor(for: game.timeClass ?? ""))
                    .lineLimit(1)
                    .frame(width: 60, alignment: .center)
                    .padding(.trailing, 32)

                // Source
                Text(game.sourcePlatform == "lichess" ? "Lichess" : "Chess.com")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(game.sourcePlatform == "lichess" ? DS.textSecondary : chessComGreen)
                    .lineLimit(1)
                    .frame(width: 70, alignment: .center)
                    .padding(.trailing, 32)

                // Date
                Text(game.date.isEmpty ? chessComFormatDate(game.dateAdded) : game.date)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textTertiary)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .frame(height: 40)
            .background(
                selectedGameIds.contains(game.id)
                ? DS.selectedWash
                : (isAlternate ? DS.hoverWash : Color.clear)
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
    }

    private func chessComResultDisplay(_ result: String) -> String {
        switch result {
        case "1/2-1/2": return "1/2"
        default: return result
        }
    }

    private func chessComResultColor(_ game: GameRecord) -> Color {
        let username = game.sourceUsername ?? savedUsername.lowercased()
        let userPlayedWhite = game.white.lowercased() == username
        let userWon = (userPlayedWhite && game.result == "1-0") || (!userPlayedWhite && game.result == "0-1")
        let userLost = (userPlayedWhite && game.result == "0-1") || (!userPlayedWhite && game.result == "1-0")
        if userWon { return chessComGreen }
        if userLost { return DS.moveMistake }
        return DS.textTertiary
    }

    private func chessComTimeClassLabel(_ timeClass: String?) -> String {
        guard let tc = timeClass else { return "-" }
        return tc.capitalized
    }

    private func chessComFormatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private func moveToFolderMenu(gameIds: Set<UUID>, label: String) -> some View {
        Menu(label) {
            ForEach(database.folders) { folder in
                Button(folder.name) {
                    database.moveGamesByIds(gameIds, toFolder: folder.id)
                    selectedGameIds.removeAll()
                }
            }
            if !database.folders.isEmpty { Divider() }
            Button("New Database...") { showingMoveToFolder = true }
        }
    }

    private var emptyGamesView: some View {
        VStack(spacing: 12) {
            Spacer()
            if isLoadingGames {
                ProgressView().controlSize(.regular)
                Text("Loading games...")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textTertiary)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(DS.textTertiary)

                VStack(spacing: 6) {
                    if totalGameCount == 0 {
                        Text("No Games Yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.textSecondary)

                        Text("Sync your accounts to import games")
                            .font(.system(size: 12))
                            .foregroundColor(DS.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 240)

                        Button(action: refreshGames) {
                            Text("Refresh")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(chessComGreen)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else {
                        Text("No Games Match Filters")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.textSecondary)

                        Text("Try adjusting your filter criteria")
                            .font(.system(size: 12))
                            .foregroundColor(DS.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private var statusBar: some View {
        HStack {
            Text("\(totalGameCount) games synced")
                .font(.system(size: 11))
                .foregroundColor(DS.ink60)

            Spacer()

            Text(hasAnyAccount ? "Chess.com connected" : "Not connected")
                .font(.system(size: 11))
                .foregroundColor(hasAnyAccount ? DS.semOnline : DS.ink40)
        }
        .padding(.horizontal, 28)
        .frame(height: 30)
        .background(DS.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func refreshGames() {
        // Sync Chess.com if connected
        if !savedUsername.isEmpty {
            startProgressiveSync(fullImport: false)
        }
        // Sync Lichess if connected
        if !lichessUsername.isEmpty && !isSyncing {
            startLichessSync(fullImport: false)
        }
    }

    private func disconnectChessComAccount() {
        database.deleteCachedStats(for: savedUsername)
        service.clearHistory(for: savedUsername)
        savedUsername = ""
        lastSyncTimestamp = 0
        cachedGames = []
        totalGameCount = 0
        dbOffset = 0
        allDbGamesExhausted = false
        if hasAnyAccount { reloadGames() }
    }

    private func disconnectLichessAccount() {
        if !settings.lichessToken.isEmpty {
            lichessAuth.logout()
        }
        lichessUsername = ""
        lichessLastSync = 0
        cachedGames = []
        totalGameCount = 0
        dbOffset = 0
        allDbGamesExhausted = false
        if hasAnyAccount { reloadGames() }
    }

    private func loginLichess() {
        lichessAuth.startOAuth { result in
            switch result {
            case .success(let token):
                AppSettings.shared.lichessToken = token
                fetchLichessProfile()
            case .failure:
                break
            }
        }
    }

    private func logoutLichess() {
        lichessAuth.logout()
    }

    private func connectLichessFromMenu() {
        // Show a simple alert-style inline — for now just set a placeholder to trigger UI
        // The user can type in the empty state or use login
        if settings.lichessToken.isEmpty {
            // No token: prompt login
            loginLichess()
        }
    }

    private func fetchLichessProfile() {
        let token = settings.lichessToken
        guard !token.isEmpty else { return }

        Task {
            var request = URLRequest(url: URL(string: "https://lichess.org/api/account")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let username = json["username"] as? String else { return }

            await MainActor.run {
                lichessUsername = username.lowercased()
                startLichessSync(fullImport: true)
            }
        }
    }

    private func formatLastSync() -> String {
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Syncing State View

    private var syncingStateView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    // Globe icon in circle
                    ZStack {
                        Circle()
                            .fill(chessComGreen.opacity(0.13))
                            .frame(width: 64, height: 64)
                        Image(systemName: "globe")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(chessComGreen)
                    }

                    // Title
                    Text("Importing Games...")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(DS.textPrimary)

                    // Description
                    Text("Fetching your game history. This may take a moment depending on how many games you have.")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textTertiary)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    // Progress section
                    syncProgressSection
                        .frame(maxWidth: 460)

                    // Stats cards
                    syncStatsRow
                        .frame(maxWidth: 460)

                    // Recently imported games
                    if !recentlyImportedGames.isEmpty {
                        syncRecentGamesSection
                            .frame(maxWidth: 460)
                    }

                    // Cancel link
                    Button(action: cancelSync) {
                        Text("Cancel Import")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }

            // Status bar
            syncStatusBar
        }
        .background(DS.bg)
    }

    private var syncProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Importing games...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.textPrimary)
                Spacer()
                Text(verbatim: "\(syncProgressPercent)%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(chessComGreen)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.bgSecondary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(chessComGreen)
                        .frame(width: geo.size.width * CGFloat(syncProgressPercent) / 100)
                        .animation(.easeInOut(duration: 0.3), value: syncProgressPercent)
                }
            }
            .frame(height: 8)

            Text(verbatim: "\(importedCount) of \(totalGamesFound) games imported")
                .font(.system(size: 12))
                .foregroundColor(DS.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var totalGamesFound: Int {
        service.gamesFoundSoFar + lichessService.gamesFoundSoFar
    }

    private var syncProgressPercent: Int {
        let found = totalGamesFound
        if found > 0 {
            return min(Int(Double(importedCount) / Double(found) * 100), 100)
        }
        guard service.totalArchives > 0 else { return 0 }
        return Int(Double(service.currentArchive) / Double(service.totalArchives) * 100)
    }

    private var syncStatsRow: some View {
        HStack(spacing: 16) {
            syncStatCard(category: "Bullet", count: syncTimeClassCounts["bullet"] ?? 0)
            syncStatCard(category: "Blitz", count: syncTimeClassCounts["blitz"] ?? 0)
            syncStatCard(category: "Rapid", count: syncTimeClassCounts["rapid"] ?? 0)
        }
    }

    private func syncStatCard(category: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textTertiary)
            Text(verbatim: String(count))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(DS.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.card)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        )
    }

    private var syncRecentGamesSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recently Imported")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textSecondary)
                Spacer()
                Text("Showing latest")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.borderSubtle).frame(height: 1)
            }

            ForEach(Array(recentlyImportedGames.prefix(4).enumerated()), id: \.element.id) { index, game in
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(chessComGreen)
                        Text("\(game.white) vs \(game.black)")
                            .font(.system(size: 12))
                            .foregroundColor(DS.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(game.result)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                    if !game.date.isEmpty {
                        Text(game.date)
                            .font(.system(size: 11))
                            .foregroundColor(DS.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(index % 2 == 1 ? DS.bgSecondary : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DS.borderSubtle).frame(height: 1)
                }
            }
        }
        .background(DS.card)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        )
    }

    private var syncStatusBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text(verbatim: "Importing... \(importedCount) of \(totalGamesFound) games")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()

            if !savedUsername.isEmpty && service.isLoading {
                Text("Chess.com: \(savedUsername)")
                    .font(.system(size: 11))
                    .foregroundColor(chessComGreen)
            }
            if !lichessUsername.isEmpty && lichessService.isLoading {
                Text("Lichess: \(lichessUsername)")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 28)
        .background(DS.bgSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    // MARK: - Progressive Sync

    private func startProgressiveSync(fullImport: Bool) {
        isSyncing = true
        importedCount = 0
        syncTimeClassCounts = [:]
        recentlyImportedGames = []

        let username = savedUsername

        syncTask = Task {
            if fullImport {
                service.clearHistory(for: username)
                await service.fetchAllGamesProgressive(username: username) { archiveGames in
                    await self.importArchiveGames(archiveGames, username: username)
                }
            } else {
                await service.fetchNewGamesProgressive(username: username) { archiveGames in
                    await self.importArchiveGames(archiveGames, username: username)
                }
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isSyncing = false }
                return
            }

            await MainActor.run {
                self.recomputeAndCacheStats(for: username)
                self.lastSyncTimestamp = Date().timeIntervalSince1970
                self.isSyncing = false
                self.reloadGames()
            }
        }
    }

    private func startImportFromSheet(games: [ChessComGame], username: String) {
        isSyncing = true
        importedCount = 0
        syncTimeClassCounts = [:]
        recentlyImportedGames = []

        syncTask = Task {
            // Import games in batches to avoid blocking
            let batchSize = 200
            for batchStart in stride(from: 0, to: games.count, by: batchSize) {
                guard !Task.isCancelled else { break }
                let end = min(batchStart + batchSize, games.count)
                let batch = Array(games[batchStart..<end])
                await self.importArchiveGames(batch, username: username)
            }

            guard !Task.isCancelled else {
                await MainActor.run { self.isSyncing = false }
                return
            }

            await MainActor.run {
                self.recomputeAndCacheStats(for: username)
                self.lastSyncTimestamp = Date().timeIntervalSince1970
                self.isSyncing = false
                self.reloadGames()
            }
        }
    }

    private func importArchiveGames(_ games: [ChessComGame], username: String) async {
        // Parse PGN (runs on background thread in async context)
        let records = parseChessComGames(games, username: username)

        guard !Task.isCancelled else { return }

        // Save to DB on main thread
        await MainActor.run {
            // Dedup: filter out games already in DB
            let newRecords = records.filter { record in
                guard let sourceUrl = record.sourceUrl else { return true }
                return !database.sourceUrlExists(sourceUrl)
            }

            if !newRecords.isEmpty {
                database.addGames(newRecords, isChessComImport: true)
                importedCount += newRecords.count

                // Update time class counts
                for record in newRecords {
                    if let tc = record.timeClass {
                        syncTimeClassCounts[tc, default: 0] += 1
                    }
                }

                // Update recently imported (keep latest 4)
                recentlyImportedGames.insert(contentsOf: Array(newRecords.prefix(4)), at: 0)
                if recentlyImportedGames.count > 4 {
                    recentlyImportedGames = Array(recentlyImportedGames.prefix(4))
                }
            }
        }
    }

    private func cancelSync() {
        syncTask?.cancel()
        lichessSyncTask?.cancel()
        isSyncing = false
        isLichessSyncing = false
    }

    // MARK: - Lichess Sync

    private func startLichessSync(fullImport: Bool) {
        isLichessSyncing = true
        if !isSyncing {
            isSyncing = true
            importedCount = 0
            syncTimeClassCounts = [:]
            recentlyImportedGames = []
        }

        let username = lichessUsername
        let token = settings.lichessToken.isEmpty ? nil : settings.lichessToken
        let since: Date? = fullImport ? nil : (lichessLastSync > 0 ? Date(timeIntervalSince1970: lichessLastSync) : nil)

        lichessSyncTask = Task {
            await lichessService.fetchGamesProgressive(
                username: username,
                token: token,
                since: since
            ) { batch in
                await self.importLichessGames(batch, username: username)
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isLichessSyncing = false
                    if !self.service.isLoading { self.isSyncing = false }
                }
                return
            }

            await MainActor.run {
                self.lichessLastSync = Date().timeIntervalSince1970
                self.isLichessSyncing = false
                if !self.service.isLoading { self.isSyncing = false }
                self.reloadGames()
            }
        }
    }

    private func importLichessGames(_ games: [LichessGameData], username: String) async {
        let records = parseLichessGames(games, username: username)

        guard !Task.isCancelled else { return }

        await MainActor.run {
            let newRecords = records.filter { record in
                guard let sourceUrl = record.sourceUrl else { return true }
                return !database.sourceUrlExists(sourceUrl)
            }

            if !newRecords.isEmpty {
                database.addGames(newRecords, isChessComImport: true)
                importedCount += newRecords.count
                lichessImportedCount += newRecords.count

                for record in newRecords {
                    if let tc = record.timeClass {
                        syncTimeClassCounts[tc, default: 0] += 1
                    }
                }

                recentlyImportedGames.insert(contentsOf: Array(newRecords.prefix(4)), at: 0)
                if recentlyImportedGames.count > 4 {
                    recentlyImportedGames = Array(recentlyImportedGames.prefix(4))
                }
            }
        }
    }

    // MARK: - Lichess PGN Parsing

    private func parseLichessGames(_ games: [LichessGameData], username: String) -> [GameRecord] {
        var records: [GameRecord] = []

        for game in games {
            let whitePlayer = game.players.white.username
            let blackPlayer = game.players.black.username

            var openingName = game.opening?.name
            let eco = game.opening?.eco

            // Parse PGN if available for richer data
            var pgn = game.pgn ?? ""
            if pgn.isEmpty {
                // Construct minimal PGN from game data
                pgn = "[Event \"Lichess \(game.timeClass)\"]\n[White \"\(whitePlayer)\"]\n[Black \"\(blackPlayer)\"]\n[Result \"\(game.result)\"]\n"
            }

            let record = GameRecord(
                event: "Lichess \(game.timeClass.capitalized)",
                date: game.formattedDate,
                white: whitePlayer,
                black: blackPlayer,
                result: game.result,
                eco: eco,
                opening: openingName,
                pgn: pgn,
                dateAdded: game.endDate ?? Date(),
                timeClass: game.timeClass,
                sourceUsername: username.lowercased(),
                sourceUrl: game.url,
                whiteElo: game.players.white.rating,
                blackElo: game.players.black.rating
            )
            records.append(record)
        }

        return records
    }

    // MARK: - PGN Parsing (pure function, safe to call from background)

    private func parseChessComGames(_ games: [ChessComGame], username: String) -> [GameRecord] {
        var records: [GameRecord] = []

        for game in games {
            guard let pgn = game.pgn else { continue }

            let parser = PGNParser()
            let parsedGames = parser.parse(string: pgn)
            let parsedGame = parsedGames.first

            var openingName = parsedGame?.headers["Opening"]
            if (openingName == nil || openingName!.isEmpty),
               let ecoUrl = parsedGame?.headers["ECOUrl"],
               let lastSlash = ecoUrl.lastIndex(of: "/") {
                let slug = String(ecoUrl[ecoUrl.index(after: lastSlash)...])
                let cleaned = slug
                    .replacingOccurrences(of: "-\\d+\\..*$", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "-", with: " ")
                if !cleaned.isEmpty { openingName = cleaned }
            }

            let record = GameRecord(
                event: parsedGame?.headers["Event"] ?? "Chess.com \(game.timeClassDisplay)",
                date: game.formattedDate,
                white: game.white.username,
                black: game.black.username,
                result: game.result,
                eco: parsedGame?.headers["ECO"],
                opening: openingName,
                pgn: pgn,
                dateAdded: game.endDate ?? Date(),
                timeClass: game.timeClass,
                sourceUsername: username.lowercased(),
                sourceUrl: game.url,
                whiteElo: game.white.rating,
                blackElo: game.black.rating
            )
            records.append(record)
        }

        return records
    }

    private func recomputeAndCacheStats(for username: String) {
        let allGames = database.fetchChessComGames(for: username)
        let allVariants = ChessComStatsComputer.computeAllVariants(games: allGames, username: username)
        let cached = ChessComCachedStats(
            username: username.lowercased(),
            statsData: allVariants,
            gameCount: allGames.count
        )
        database.saveCachedStats(cached)
    }
}

// MARK: - ChessCom Filter Card Height Key

private struct ChessComFilterCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    ChessComBrowserView(onGameSelected: { _ in })
        .environmentObject(GameDatabase.preview())
        .frame(width: 800, height: 600)
}
