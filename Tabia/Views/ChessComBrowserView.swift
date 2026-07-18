import SwiftUI

struct ChessComBrowserView: View {
    @EnvironmentObject var database: GameDatabase
    var onGameSelected: (GameRecord) -> Void
    /// Load the game into Analysis and immediately run a full game review.
    var onReviewGame: (GameRecord) -> Void = { _ in }

    @StateObject var service = ChessComService()
    @StateObject var lichessService = LichessGameService()
    @ObservedObject private var lichessAuth = LichessAuthService.shared
    @ObservedObject var settings = AppSettings.shared
    @AppStorage("chesscom_username") var savedUsername: String = ""
    @AppStorage("chesscom_last_sync") var lastSyncTimestamp: Double = 0
    @AppStorage("lichess_username") var lichessUsername: String = ""
    @AppStorage("lichess_last_sync") var lichessLastSync: Double = 0

    @State private var cachedGames: [GameRecord] = []
    @State private var totalGameCount: Int = 0
    @State private var isLoadingGames = false
    @State private var dbOffset: Int = 0
    @State private var allDbGamesExhausted = false
    @State private var reloadTask: Task<Void, Never>?
    private let pageSize = 50
    private let dbBatchSize = 200

    @State private var cachedRatings: [String: Int] = [:]
    @State private var showingImportSheet = false
    @State private var selectedGameIds: Set<UUID> = []
    @State private var lastSelectedGame: GameRecord?
    @State private var showingMoveToFolder = false
    @State private var newFolderName = ""

    // Syncing state
    @State var isSyncing = false
    @State var importedCount = 0
    @State var syncTimeClassCounts: [String: Int] = [:]
    @State var recentlyImportedGames: [GameRecord] = []
    /// sourceUrls already in the library, loaded once per sync. Dedup used to run one unindexed
    /// fetch per game — a full table scan each time, quadratic over a large import.
    @State var seenSourceUrls: Set<String> = []
    @State var syncTask: Task<Void, Never>?

    // Sorting
    @State private var sortColumn: SortColumn = .date
    @State private var sortAscending = false
    /// Cached sort of `cachedGames`; kept in sync by resortGames().
    @State private var sortedGames: [GameRecord] = []

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
    @State var isLichessSyncing = false
    @State var lichessImportedCount = 0
    @State var lichessSyncTask: Task<Void, Never>?

    // The Annotator has one accent (the red pen); "brand green" is gone. Neutral ink for the
    // places that were tinted green; explicit DS.redAccent where a real accent is wanted.
    private let chessComGreen = DS.ink40
    @State private var syncPulse = false

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
        // Ratings are keyed off the games' account handle — (re)load once the games are in.
        .onChange(of: cachedGames.count) { _, n in
            if n > 0 && cachedRatings.isEmpty { loadRatings() }
            cacheAccountSummaries()
        }
        .onChange(of: isSyncing) { was, now in
            if was && !now {   // a sync just finished — stamp the time and refresh cached counts
                let s = AppSettings.shared
                let stamp = Date().timeIntervalSince1970
                if !savedUsername.isEmpty { s.chessComLastSynced = stamp }
                if !lichessUsername.isEmpty { s.lichessLastSynced = stamp }
                cacheAccountSummaries()
            }
        }
        // The masthead "Sync Now" button drives the sync from here.
        .onReceive(NotificationCenter.default.publisher(for: .tabiaSyncGames)) { _ in
            if hasAnyAccount && !(service.isLoading || lichessService.isLoading) { refreshGames() }
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

    func reloadGames() {
        guard hasAnyAccount else { return }
        cachedGames = []
        sortedGames = []
        dbOffset = 0
        allDbGamesExhausted = false
        isLoadingGames = true

        let tc = activeTimeClass
        let ps = pageSize
        let db = database
        let hasFilters = hasClientSideFilters

        // Read on the main actor — `database.modelContext` is the container's mainContext, which has
        // thread affinity. Reading it from a detached background task silently returns nothing on the
        // on-disk store (the fetch's `try?` swallows the failure), so imported games never appear.
        Task { @MainActor in
            let count = db.onlineGamesCount()
            let batch = db.fetchFilteredOnlineGames(timeClass: tc, limit: ps, offset: 0)
            totalGameCount = count
            dbOffset = batch.count
            if batch.count < ps { allDbGamesExhausted = true }
            if hasFilters {
                cachedGames = applyClientFilters(batch)
            } else {
                cachedGames = batch
            }
            resortGames()
            isLoadingGames = false
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

        // Same as reloadGames: the mainContext read must run on the main actor, not a detached task.
        Task { @MainActor in
            let batch = db.fetchFilteredOnlineGames(timeClass: tc, limit: batchSize, offset: currentOffset)
            dbOffset += batch.count
            if batch.count < batchSize { allDbGamesExhausted = true }
            if hasFilters {
                cachedGames.append(contentsOf: applyClientFilters(batch))
            } else {
                cachedGames.append(contentsOf: batch)
            }
            resortGames()
            isLoadingGames = false
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
                .font(AnnFont.serif(20, .semibold))
                .foregroundColor(DS.textPrimary)

            Text("Import and analyze your online games from Chess.com and Lichess")
                .font(AnnFont.serif(13))
                .foregroundColor(DS.textTertiary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            // Chess.com connect
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(chessComGreen).frame(width: 8, height: 8)
                    Text("Chess.com")
                        .font(AnnFont.serif(13, .semibold))
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
                            .font(AnnFont.serif(13))
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
                    Circle().fill(DS.ink).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(DS.hairline, lineWidth: 0.5))
                    Text("Lichess")
                        .font(AnnFont.serif(13, .semibold))
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
                                .font(AnnFont.serif(13))
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
                                .font(AnnFont.label(11))
                                .tracking(11 * 0.1)
                        }
                        .foregroundColor(DS.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DS.ink40)
                            .font(.system(size: 14))
                        Text("Logged in")
                            .font(AnnFont.serif(13))
                            .foregroundColor(DS.textSecondary)
                        Spacer()
                        Button("Fetch Games") {
                            fetchLichessProfile()
                        }
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
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

    /// The account owner's handle with its real display casing. Chess.com's public archive API
    /// lowercases the handle (so the stored/typed name can be "bidiboy1"), but each game's PGN keeps
    /// the true casing ("BidiBoy1") — recover it from a synced game where sourceUsername matches a side.
    private var displayUsername: String {
        let fallback = !savedUsername.isEmpty ? savedUsername : lichessUsername
        for g in cachedGames.prefix(120) {
            guard let src = g.sourceUsername?.lowercased(), !src.isEmpty else { continue }
            if g.white.lowercased() == src { return g.white }
            if g.black.lowercased() == src { return g.black }
        }
        // No sourceUsername match — try matching the stored handle directly.
        let key = fallback.lowercased()
        if !key.isEmpty {
            for g in cachedGames.prefix(120) {
                if g.white.lowercased() == key { return g.white }
                if g.black.lowercased() == key { return g.black }
            }
        }
        return fallback
    }

    private var normalConnectedContent: some View {
        VStack(spacing: 0) {
            // Profile Header
            HStack(spacing: 14) {
                // Identity — name, "last synced" in the voice, and a source/count meta line
                VStack(alignment: .leading, spacing: 4) {
                    (Text(displayUsername).font(AnnFont.serif(23, .semibold)).foregroundColor(DS.ink)
                     + Text("  — last synced \(lastSyncString)").font(AnnFont.voice(17)).foregroundColor(DS.ink40))
                        .lineLimit(1)
                    Text(headerMeta)
                        .font(AnnFont.mono(10)).tracking(0.5).foregroundColor(DS.ink40)
                }

                Spacer(minLength: 12)

                // Compact rating chips (Sync lives in the masthead now)
                ratingChip("Bullet", cachedRatings["bullet"], dot: DS.qInaccuracy)
                ratingChip("Blitz", cachedRatings["blitz"], dot: DS.ink40)
                ratingChip("Rapid", cachedRatings["rapid"], dot: DS.redAccent)

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

            // Filter Pills
            filterPillsRow
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if showingFilters {
                chessComFilterPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if cachedGames.isEmpty {
                emptyGamesView
            } else {
                gamesList
                Text("Accuracy fills in as games are reviewed — one click from any row.")
                    .font(AnnFont.voice(12)).foregroundColor(DS.ink40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
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
                                .font(AnnFont.label(10))
                                .tracking(10 * 0.1)
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
                    .font(AnnFont.label(10))
                    .tracking(10 * 0.1)
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
                    .font(AnnFont.label(11))
                    .tracking(11 * 0.1)
                    .foregroundColor(isSelected ? DS.textPrimary : DS.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Cards Row

    /// "17,891 GAMES · CHESS.COM + LICHESS" — source + total-count meta under the name.
    private var headerMeta: String {
        var src: [String] = []
        if !savedUsername.isEmpty { src.append("Chess.com") }
        if !lichessUsername.isEmpty { src.append("Lichess") }
        let f = NumberFormatter(); f.numberStyle = .decimal
        let games = (f.string(from: NSNumber(value: totalGameCount)) ?? "\(totalGameCount)") + " GAMES"
        return src.isEmpty ? games : "\(games) · \(src.joined(separator: " + ").uppercased())"
    }

    /// Bullet / Blitz / Rapid rating card for the header.
    private func ratingChip(_ label: String, _ rating: Int?, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 5, height: 5)
                Text(label.uppercased()).font(AnnFont.label(9)).tracking(0.9).foregroundColor(DS.ink40)
            }
            Text(rating.map(String.init) ?? "—")
                .font(AnnFont.serif(27, .semibold)).foregroundColor(DS.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minWidth: 96, alignment: .leading)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }

    private var statsCardsRow: some View {
        HStack(spacing: 16) {
            statsCard(category: "Bullet", dotColor: DS.ink40)
            statsCard(category: "Blitz", dotColor: DS.ink40)
            statsCard(category: "Rapid", dotColor: DS.ink40)
        }
        .frame(maxWidth: .infinity)
    }

    /// The handle the chess.com games were actually synced under — the authoritative key for stats /
    /// rating lookups. The stored/typed @AppStorage handle can drift (e.g. "bidiboy" vs the real
    /// "bidiboy1"), so prefer the games' sourceUsername; fall back to the stored handle pre-load.
    private var accountHandle: String {
        for g in cachedGames.prefix(120) where !(g.sourceUsername ?? "").isEmpty {
            return g.sourceUsername!
        }
        return !savedUsername.isEmpty ? savedUsername : lichessUsername
    }

    /// Persist per-account game counts so the Settings › Accounts page can show them without the DB.
    private func cacheAccountSummaries() {
        let s = AppSettings.shared
        if !savedUsername.isEmpty { s.chessComGameCount = database.chessComGamesCount(for: savedUsername) }
        if !lichessUsername.isEmpty { s.lichessGameCount = database.chessComGamesCount(for: lichessUsername) }
    }

    private func loadRatings() {
        let username = accountHandle
        guard !username.isEmpty else { return }
        // GameDatabase is main-actor-bound, so run this small cached-stats lookup on the main actor
        // rather than a detached task — Swift 6 rejects touching `database` from off-actor.
        Task { @MainActor in
            guard let cached = database.fetchAllCachedStats(for: username) else { return }
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
            cachedRatings = ratings
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
                    .font(AnnFont.label(11))
                    .tracking(11 * 0.1)
                    .foregroundColor(DS.ink40)
                Text(verbatim: rating != nil ? String(rating!) : "-")
                    .font(AnnFont.mono(22, bold: true))
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
        HStack(spacing: 6) {
            ForEach(["All", "Bullet", "Blitz", "Rapid"], id: \.self) { option in
                let isActive = filterTimeControl == option
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.12)) { filterTimeControl = option }
                }) {
                    Text(option)
                        .font(AnnFont.label(11)).tracking(11 * 0.1)
                        .foregroundColor(isActive ? DS.ink : DS.ink40)
                        .padding(.vertical, 5).padding(.horizontal, 12)
                        .background(isActive ? DS.selectedWash : DS.paperRaised,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isActive ? DS.borderStrong : DS.borderChip, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Games List

    /// Sorted view of `cachedGames`, recomputed only when the games or the sort change. As a computed
    /// property this ran on every body evaluation — an n log n sort with ICU collation on a list that
    /// grows toward the whole account, re-run on every hover and every sync tick.
    private func resortGames() {
        sortedGames = cachedGames.sorted { a, b in
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
        GameTableList(
            games: sortedGames,
            selectedGameIds: $selectedGameIds,
            selectionAnchor: $lastSelectedGame,
            hasMore: hasMorePages,
            onOpen: onGameSelected,
            onLoadMore: loadNextPage,
            header: { chessComTableHeader },
            row: { game, isAlternate in chessComTableRow(game, isAlternate: isAlternate) },
            menu: { game in
                Button("Open Game") { onGameSelected(game) }
                Button("Analyze Game") { onReviewGame(game) }
                Divider()
                if selectedGameIds.count > 1 {
                    moveToFolderMenu(gameIds: selectedGameIds, label: "Move \(selectedGameIds.count) Games to...")
                } else {
                    moveToFolderMenu(gameIds: [game.id], label: "Move to...")
                }
            }
        )
    }

    // Shared column widths — the header and rows use these same values so they line up exactly.
    // (Opening is the flexible column; the trailing Review column holds the per-row review action.)
    private enum CCW {
        static let white: CGFloat = 220, black: CGFloat = 220, result: CGFloat = 64
        static let time: CGFloat = 100, source: CGFloat = 100, date: CGFloat = 110, review: CGFloat = 92
    }

    private var chessComTableHeader: some View {
        HStack(spacing: 0) {
            ccHeader("White", .white, width: CCW.white)
            ccHeader("Black", .black, width: CCW.black)
            ccHeader("Result", .result, width: CCW.result)
            ccHeader("Opening", .opening, width: nil)
            ccHeader("Time", .timeControl, width: CCW.time)
            ccHeader("Source", .source, width: CCW.source)
            ccHeader("Date", .date, width: CCW.date)
            Color.clear.frame(width: CCW.review)
        }
        .padding(.horizontal, 28)
        .frame(height: 36)
        .background(DS.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func ccHeader(_ title: String, _ column: SortColumn, width: CGFloat?) -> some View {
        let btn = Button(action: {
            if sortColumn == column { sortAscending.toggle() }
            else { sortColumn = column; sortAscending = column != .date }
            resortGames()
        }) {
            HStack(spacing: 4) {
                Text(title).font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.ink25)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold)).foregroundColor(DS.ink25)
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if let width { btn.frame(width: width, alignment: .leading) }
        else { btn.frame(maxWidth: .infinity, alignment: .leading) }
    }

    /// Player name with the reviewed accuracy in parentheses, e.g. "BidiBoy1 (91.4)".
    private func ccNameCell(_ name: String, primary: Bool, width: CGFloat) -> some View {
        Text(name).font(AnnFont.serif(13, primary ? .medium : .regular)).foregroundColor(primary ? DS.ink : DS.ink60)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: .leading)
    }

    /// White (top) + black (bottom) accuracy dots for a reviewed game, shown in the far-right cell.
    private func accDotsBadge(white: Double, black: Double) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            accDotRow(filled: false, acc: white)
            accDotRow(filled: true, acc: black)
        }
    }

    private func accDotRow(filled: Bool, acc: Double) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(filled ? DS.boardBlackPiece : DS.boardWhitePiece)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(DS.borderStrong, lineWidth: 1))
            Text(acc > 0 ? String(format: "%.1f", acc) : "—")
                .font(AnnFont.mono(10.5)).foregroundColor(DS.ink60)
        }
    }

    private func chessComTableRow(_ game: GameRecord, isAlternate: Bool = false) -> some View {
        HStack(spacing: 0) {
            ccNameCell(game.white, primary: true, width: CCW.white)
            ccNameCell(game.black, primary: false, width: CCW.black)

            Text(chessComResultDisplay(game.result))
                .font(AnnFont.mono(12, bold: true)).foregroundColor(chessComResultColor(game))
                .padding(.horizontal, 8).frame(width: CCW.result, alignment: .leading)

            Text(game.opening ?? game.eco ?? "—")
                .font(AnnFont.voice(12.5)).foregroundColor(DS.ink60).lineLimit(1)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)

            Text(chessComTimeClassLabel(game.timeClass))
                .font(AnnFont.label(11)).tracking(0.5).foregroundColor(DS.ink60).lineLimit(1)
                .padding(.horizontal, 8).frame(width: CCW.time, alignment: .leading)

            Text(game.sourcePlatform == "lichess" ? "Lichess" : "Chess.com")
                .font(AnnFont.label(10)).tracking(0.5).foregroundColor(DS.ink40).lineLimit(1)
                .padding(.horizontal, 8).frame(width: CCW.source, alignment: .leading)

            Text(chessComWhen(game))
                .font(AnnFont.mono(10)).foregroundColor(DS.ink40).lineLimit(1)
                .padding(.horizontal, 8).frame(width: CCW.date, alignment: .leading)

            // Analyze / accuracy — far right; a fixed-width cell (Color.clear holds it) so rows stay
            // aligned. Reviewed games show white/black accuracy dots; unreviewed show the Analyze button.
            Color.clear
                .frame(width: CCW.review, height: 1)
                .overlay(alignment: .trailing) {
                    if game.analysisData == nil {
                        Button(action: { onReviewGame(game) }) {
                            Text("Analyze")
                                .font(AnnFont.label(9)).tracking(0.3)
                                .foregroundColor(DS.redAccent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(DS.redAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.redAccent.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    } else {
                        accDotsBadge(white: game.analysisData?.whiteAccuracy ?? 0,
                                     black: game.analysisData?.blackAccuracy ?? 0)
                            .padding(.trailing, 8)
                    }
                }
        }
        .padding(.horizontal, 28)
        .frame(height: 40)
        .background(
            selectedGameIds.contains(game.id) ? DS.selectedWash : Color.clear
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    /// The account owner's accuracy for a reviewed game, or "—" if it hasn't been analyzed yet.
    private func gameAccuracy(_ game: GameRecord) -> String {
        guard let d = game.analysisData else { return "—" }
        let handle = accountHandle.lowercased()
        let userIsWhite = game.white.lowercased() == handle
        let acc = userIsWhite ? d.whiteAccuracy : d.blackAccuracy
        return acc > 0 ? String(format: "%.1f", acc) : "—"
    }

    /// Relative "when the game was played": TODAY / YDAY / MMM d (/ year for older games).
    private func chessComWhen(_ game: GameRecord) -> String {
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy.MM.dd"
        let date = inFmt.date(from: game.date) ?? game.dateAdded
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YDAY" }
        let out = DateFormatter()
        out.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM d" : "MMM d yyyy"
        return out.string(from: date).uppercased()
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
        // Results stay monochrome (no traffic-light win/loss): the win reads in full ink, the rest muted.
        if userWon { return DS.ink }
        if userLost { return DS.ink40 }
        return DS.ink40
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
                ProgressView().controlSize(.regular).tint(DS.redAccent)
                Text("Loading games...")
                    .font(AnnFont.serif(12))
                    .foregroundColor(DS.textTertiary)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(DS.textTertiary)

                VStack(spacing: 6) {
                    if totalGameCount == 0 {
                        Text("No Games Yet")
                            .font(AnnFont.serif(14, .semibold))
                            .foregroundColor(DS.textSecondary)

                        Text("Sync your accounts to import games")
                            .font(AnnFont.serif(12))
                            .foregroundColor(DS.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 240)

                        Button(action: refreshGames) {
                            Text("Refresh")
                                .font(AnnFont.label(12))
                                .tracking(12 * 0.1)
                                .foregroundColor(chessComGreen)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else {
                        Text("No Games Match Filters")
                            .font(AnnFont.serif(14, .semibold))
                            .foregroundColor(DS.textSecondary)

                        Text("Try adjusting your filter criteria")
                            .font(AnnFont.serif(12))
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
                .font(AnnFont.mono(11))
                .foregroundColor(DS.ink60)

            Spacer()

            HStack(spacing: 6) {
                if hasAnyAccount {
                    Circle().fill(DS.semOnline).frame(width: 6, height: 6)
                }
                Text(hasAnyAccount ? "Connected" : "Not connected")
                    .font(AnnFont.mono(11))
                    .foregroundColor(DS.ink40)
            }
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
        sortedGames = []
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
        sortedGames = []
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
                        .font(AnnFont.serif(22, .semibold))
                        .foregroundColor(DS.textPrimary)

                    // Description
                    Text("Fetching your game history. This may take a moment depending on how many games you have.")
                        .font(AnnFont.serif(13))
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
                            .font(AnnFont.label(13))
                            .tracking(13 * 0.1)
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
                Text("Importing games…")
                    .font(AnnFont.serif(13, .medium))
                    .foregroundColor(DS.ink)
                Spacer()
                Text(verbatim: "\(importedCount)")
                    .font(AnnFont.mono(13, bold: true))
                    .foregroundColor(DS.redAccent)
            }

            // Totals stream in and aren't known up front (and dedup skews any %), so show an honest
            // indeterminate bar — a red pen segment sweeping a flat track — plus the live count below.
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.trackBg)
                    Capsule().fill(DS.redInk)
                        .frame(width: w * 0.3)
                        .offset(x: syncPulse ? w * 0.7 : 0)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { syncPulse = true }
            }

            Text(verbatim: totalGamesFound > importedCount
                 ? "\(importedCount) imported · \(totalGamesFound) found"
                 : "\(importedCount) games imported")
                .font(AnnFont.mono(12))
                .foregroundColor(DS.ink40)
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
                .font(AnnFont.label(11))
                .tracking(11 * 0.1)
                .foregroundColor(DS.textTertiary)
            Text(verbatim: String(count))
                .font(AnnFont.mono(20, bold: true))
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
                    .font(AnnFont.serif(12, .semibold))
                    .foregroundColor(DS.textSecondary)
                Spacer()
                Text("Showing latest")
                    .font(AnnFont.serif(11))
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
                            .font(AnnFont.serif(12))
                            .foregroundColor(DS.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(game.result)
                        .font(AnnFont.mono(11))
                        .foregroundColor(DS.textSecondary)
                    if !game.date.isEmpty {
                        Text(game.date)
                            .font(AnnFont.mono(11))
                            .foregroundColor(DS.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
                    .tint(DS.redAccent)
                Text(verbatim: "Importing… \(importedCount) games")
                    .font(AnnFont.mono(11))
                    .foregroundColor(DS.ink60)
            }

            Spacer()

            if !savedUsername.isEmpty && service.isLoading {
                Text("Chess.com: \(savedUsername)")
                    .font(AnnFont.mono(11))
                    .foregroundColor(chessComGreen)
            }
            if !lichessUsername.isEmpty && lichessService.isLoading {
                Text("Lichess: \(lichessUsername)")
                    .font(AnnFont.mono(11))
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
