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
    @Environment(\.openSettings) private var openSettings
    /// Handshake with PreferencesView: set the target tab, then open Settings on it.
    @AppStorage("settingsRequestedTab") private var settingsRequestedTab = -1
    @AppStorage("chesscom_username") var savedUsername: String = ""
    @AppStorage("chesscom_last_sync") var lastSyncTimestamp: Double = 0
    @AppStorage("lichess_username") var lichessUsername: String = ""
    @AppStorage("lichess_last_sync") var lichessLastSync: Double = 0

    /// Survives leaving the screen. See BrowserStates.swift for the ownership rule.
    @ObservedObject var state: ChessComBrowserState

    // Forwarding accessors — the body is unchanged; these fields just live in `state` now.
    private var selectedGameIds: Set<UUID> {
        get { state.selectedGameIds } nonmutating set { state.selectedGameIds = newValue }
    }
    private var lastSelectedGame: GameRecord? {
        get { state.lastSelectedGame } nonmutating set { state.lastSelectedGame = newValue }
    }
    private var cachedRatings: [String: Int] {
        get { state.cachedRatings } nonmutating set { state.cachedRatings = newValue }
    }
    private var sortColumn: SortColumn {
        get { state.sortColumn } nonmutating set { state.sortColumn = newValue }
    }
    private var sortAscending: Bool {
        get { state.sortAscending } nonmutating set { state.sortAscending = newValue }
    }
    private var sortedGames: [GameRecord] {
        get { state.sortedGames } nonmutating set { state.sortedGames = newValue }
    }
    private var filterTimeControl: String {
        get { state.filterTimeControl } nonmutating set { state.filterTimeControl = newValue }
    }
    private var filterResult: String {
        get { state.filterResult } nonmutating set { state.filterResult = newValue }
    }
    private var filterColor: String {
        get { state.filterColor } nonmutating set { state.filterColor = newValue }
    }
    private var filterOpponent: String {
        get { state.filterOpponent } nonmutating set { state.filterOpponent = newValue }
    }
    private var filterOpening: String {
        get { state.filterOpening } nonmutating set { state.filterOpening = newValue }
    }
    private var filterDateDays: Int {
        get { state.filterDateDays } nonmutating set { state.filterDateDays = newValue }
    }
    private var filterSource: String {
        get { state.filterSource } nonmutating set { state.filterSource = newValue }
    }
    private var cachedGames: [GameRecord] {
        get { state.cachedGames } nonmutating set { state.cachedGames = newValue }
    }
    private var totalGameCount: Int {
        get { state.totalGameCount } nonmutating set { state.totalGameCount = newValue }
    }
    private var dbOffset: Int {
        get { state.dbOffset } nonmutating set { state.dbOffset = newValue }
    }
    private var allDbGamesExhausted: Bool {
        get { state.allDbGamesExhausted } nonmutating set { state.allDbGamesExhausted = newValue }
    }

    @State private var isLoadingGames = false
    @State private var reloadTask: Task<Void, Never>?
    private let pageSize = 50
    private let dbBatchSize = 200

    @State private var showingImportSheet = false
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
    /// Cached sort of `cachedGames`; kept in sync by resortGames().

    enum SortColumn: String {
        case white, black, date, result, opening, timeControl, source
    }

    // Filters

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
        !filterOpponent.isEmpty || !filterOpening.isEmpty ||
        filterDateDays > 0 || filterSource != "All"
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
            // An account connected from the Settings window while My Games was never open didn't fire
            // this view's onChange, so its games were never fetched. Kick off the first import here for
            // any connected platform that has nothing in the DB yet. (The sync guards above prevent a
            // double if onChange already started one.)
            if !savedUsername.isEmpty && database.chessComGamesCount(for: savedUsername) == 0 {
                startProgressiveSync(fullImport: true)
            }
            if !lichessUsername.isEmpty && database.chessComGamesCount(for: lichessUsername) == 0 {
                startLichessSync(fullImport: true)
            }
        }
        // Ratings no longer depend on the loaded games — only the per-account counts do.
        .onChange(of: cachedGames.count) { _, _ in
            cacheAccountSummaries()
        }
        .onChange(of: isSyncing) { was, now in
            if was && !now {   // a sync just finished — stamp the time and refresh cached counts
                let s = AppSettings.shared
                let stamp = Date().timeIntervalSince1970
                if !savedUsername.isEmpty { s.chessComLastSynced = stamp }
                if !lichessUsername.isEmpty { s.lichessLastSynced = stamp }
                cacheAccountSummaries()
                // Stats were just recomputed; the cards read from that cache, and the onChange below
                // only fires while `cachedRatings` is still empty.
                loadRatings()
            }
        }
        // The masthead "Sync Now" button drives the sync from here.
        .onReceive(NotificationCenter.default.publisher(for: .tabiaSyncGames)) { _ in
            if hasAnyAccount && !(service.isLoading || lichessService.isLoading) { refreshGames() }
        }
        // Connecting / disconnecting a platform elsewhere (Settings → Accounts, or the in-page
        // fields) only writes the @AppStorage username. The browser owns the sync/reload machinery,
        // so it reacts here — the single place a username change turns into an import or a refresh.
        .onChange(of: savedUsername) { old, new in
            guard old != new else { return }
            if new.isEmpty { refreshAfterAccountChange() } else { startProgressiveSync(fullImport: true) }
        }
        .onChange(of: lichessUsername) { old, new in
            guard old != new else { return }
            if new.isEmpty { refreshAfterAccountChange() } else { startLichessSync(fullImport: true) }
        }
        .onChange(of: filterTimeControl) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterResult) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterColor) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterOpponent) { _, _ in scheduleReload(debounce: true) }
        .onChange(of: filterDateDays) { _, _ in scheduleReload(debounce: false) }
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
        if !filterOpponent.isEmpty {
            let query = filterOpponent.lowercased()
            result = result.filter { game in
                // The opponent is whichever side isn't the synced account.
                let username = game.sourceUsername ?? ""
                let opponent = game.white.lowercased() == username ? game.black : game.white
                return opponent.lowercased().contains(query)
            }
        }
        if !filterOpening.isEmpty {
            let query = filterOpening.lowercased()
            result = result.filter { game in
                game.opening?.lowercased().contains(query) == true ||
                game.eco?.lowercased().contains(query) == true
            }
        }
        if filterDateDays > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -filterDateDays, to: Date()) {
            result = result.filter { $0.dateAdded >= cutoff }
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
                                // Setting the username is the connect — onChange(savedUsername) runs
                                // the import. Keeps one sync path shared with Settings → Accounts.
                                if !connectUsername.isEmpty { savedUsername = connectUsername }
                            }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(DS.bgElevated)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.border, lineWidth: 1))

                    Button(action: {
                        if !connectUsername.isEmpty { savedUsername = connectUsername }
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
                                    if !connectLichessUsername.isEmpty { lichessUsername = connectLichessUsername }
                                }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(DS.bgElevated)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.border, lineWidth: 1))

                        Button(action: {
                            if !connectLichessUsername.isEmpty { lichessUsername = connectLichessUsername }
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
        ZStack(alignment: .trailing) {
            normalConnectedColumn

            // Slide-in filter panel (same pattern as the Library), dimming the list behind it.
            if showingFilters {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showingFilters = false } }
                    .transition(.opacity)
            }
            gamesFilterPanel
                .padding(.vertical, 14)
                .padding(.trailing, 14)
                .offset(x: showingFilters ? 0 : 400)
                .animation(.easeInOut(duration: 0.25), value: showingFilters)
        }
    }

    private var normalConnectedColumn: some View {
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

                // Compact rating chips, one group per connected platform (Sync lives in the masthead).
                ForEach(connectedPlatforms, id: \.id) { platform in
                    HStack(spacing: 8) {
                        if connectedPlatforms.count > 1 {
                            Text(platform.label.uppercased())
                                .font(AnnFont.label(8.5)).tracking(8.5 * 0.14)
                                .foregroundColor(DS.ink40)
                        }
                        ratingChip("Bullet", cachedRatings["\(platform.id).bullet"], dot: DS.qInaccuracy)
                        ratingChip("Blitz", cachedRatings["\(platform.id).blitz"], dot: DS.ink40)
                        ratingChip("Rapid", cachedRatings["\(platform.id).rapid"], dot: DS.redAccent)
                    }
                }

                gamesFilterButton

                Menu {
                    // The accounts page — where connect status, sync and disconnect all live.
                    Button(action: openAccountsSettings) {
                        Label("Manage Accounts…", systemImage: "gearshape")
                    }

                    Divider()

                    // Add the platform that isn't linked yet. Lichess sign-in fills the username in
                    // for you; without a Chess.com account, point at the connect screen.
                    if lichessUsername.isEmpty {
                        Button(action: connectLichessFromMenu) {
                            Label("Connect Lichess", systemImage: "plus.circle")
                        }
                    } else if settings.lichessToken.isEmpty {
                        Button(action: loginLichess) {
                            Label("Sign in to Lichess for faster imports", systemImage: "person.badge.key")
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

    private var hasActiveFilters: Bool {
        filterTimeControl != "All" || filterResult != "All" || filterColor != "All" ||
        !filterOpponent.isEmpty || !filterOpening.isEmpty || filterDateDays > 0 ||
        filterSource != "All"
    }

    private var activeFilterCount: Int {
        var count = 0
        if filterTimeControl != "All" { count += 1 }
        if filterResult != "All" { count += 1 }
        if filterColor != "All" { count += 1 }
        if !filterOpponent.isEmpty { count += 1 }
        if !filterOpening.isEmpty { count += 1 }
        if filterDateDays > 0 { count += 1 }
        if filterSource != "All" { count += 1 }
        return count
    }

    private func clearFilters() {
        filterTimeControl = "All"
        filterResult = "All"
        filterColor = "All"
        filterOpponent = ""
        filterOpening = ""
        filterDateDays = 0
        filterSource = "All"
    }

    /// Compact icon control in the header row (sits beside the ⋯ menu). A red dot marks active
    /// filters; tapping opens the slide-in panel.
    private var gamesFilterButton: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showingFilters.toggle() } }) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14))
                .foregroundColor(hasActiveFilters ? DS.redAccent : DS.textSecondary)
                .overlay(alignment: .topTrailing) {
                    if hasActiveFilters {
                        Circle().fill(DS.redAccent).frame(width: 6, height: 6).offset(x: 3, y: -2)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hasActiveFilters ? "Filters · \(activeFilterCount) active" : "Filter your games")
    }

    // MARK: - Filter Panel (slide-in, same shape as the Library's)

    private var gamesFilterPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Filters").font(AnnFont.serif(18, .semibold)).foregroundColor(DS.ink)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showingFilters = false } }) {
                    Image(systemName: "xmark").font(.system(size: 14)).foregroundColor(DS.ink40)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(DS.chrome)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            // Body
            ScrollView {
                VStack(spacing: 0) {
                    gamesFilterSection(title: "Result") {
                        gamesChipRow(["All", "Wins", "Draws", "Losses"], current: filterResult) { filterResult = $0 }
                    }
                    gamesFilterSection(title: "Time Control") {
                        gamesChipRow(["All", "Bullet", "Blitz", "Rapid", "Daily"], current: filterTimeControl) { filterTimeControl = $0 }
                    }
                    // Source only means something with more than one platform linked.
                    if connectedPlatforms.count > 1 {
                        gamesFilterSection(title: "Source") {
                            gamesChipRow(["All", "Chess.com", "Lichess"], current: filterSource) { filterSource = $0 }
                        }
                    }
                    gamesFilterSection(title: "Played As") {
                        gamesChipRow(["All", "White", "Black"], current: filterColor) { filterColor = $0 }
                    }
                    gamesFilterSection(title: "Opponent") {
                        gamesSearchField($state.filterOpponent, placeholder: "Search opponents...")
                    }
                    gamesFilterSection(title: "Opening") {
                        gamesSearchField($state.filterOpening, placeholder: "Name or ECO...")
                    }
                    // Date (last section, no bottom border) — recency presets, no fiddly picker.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Date")
                            .font(AnnFont.label(9.5)).foregroundColor(DS.ink40).kerning(1.3)
                        HStack(spacing: 6) {
                            ForEach([("All", 0), ("7d", 7), ("30d", 30), ("90d", 90), ("1y", 365)], id: \.0) { item in
                                gamesChip(item.0, selected: filterDateDays == item.1) {
                                    withAnimation(.easeInOut(duration: 0.12)) { filterDateDays = item.1 }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
            }

            // Footer
            HStack(spacing: 12) {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { clearFilters() } }) {
                    Text("CLEAR ALL").font(AnnFont.label(10)).tracking(10 * 0.1)
                        .foregroundColor(DS.ink60).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasActiveFilters)
                .opacity(hasActiveFilters ? 1 : 0.4)

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showingFilters = false } }) {
                    Text("Done")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
            .background(DS.chrome)
        }
        .frame(width: 340)
        .background(DS.paper)
        .clipShape(RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous)
            .strokeBorder(DS.windowBorder, lineWidth: 1))
        .shadow(color: DS.glassShadowColor, radius: 22, x: 0, y: 10)
    }

    private func gamesFilterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AnnFont.label(9.5)).foregroundColor(DS.ink40).kerning(1.3)
            content()
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private func gamesChipRow(_ options: [String], current: String, onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { opt in
                gamesChip(opt, selected: current == opt) {
                    withAnimation(.easeInOut(duration: 0.12)) { onSelect(opt) }
                }
            }
        }
    }

    private func gamesChip(_ label: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(label)
                .font(AnnFont.mono(11, bold: selected))
                .foregroundColor(selected ? DS.onInk : DS.ink60)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? DS.ink : DS.fieldBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.clear : DS.borderChip, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func gamesSearchField(_ text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(DS.ink25).font(.system(size: 13))
            TextField(placeholder, text: text).textFieldStyle(.plain).font(AnnFont.mono(10.5))
            if !text.wrappedValue.isEmpty {
                Button(action: { text.wrappedValue = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(DS.ink25).font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(DS.fieldBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
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
                .font(AnnFont.serif(23, .semibold)).foregroundColor(DS.ink)
                // Never let a 4-digit rating wrap to two lines ("164" over "5").
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(minWidth: 78, alignment: .leading)
        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }

    struct ConnectedPlatform: Identifiable {
        let id: String      // "chesscom" | "lichess" — also the ratings-key prefix
        let label: String
    }

    /// The platforms with a handle set, in display order. The label only shows when both are
    /// connected; with a single account it would be noise.
    private var connectedPlatforms: [ConnectedPlatform] {
        var out: [ConnectedPlatform] = []
        if !savedUsername.isEmpty { out.append(ConnectedPlatform(id: "chesscom", label: "Chess.com")) }
        if !lichessUsername.isEmpty { out.append(ConnectedPlatform(id: "lichess", label: "Lichess")) }
        return out
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

    /// Current ratings, read from each platform's own profile endpoint. Chess.com and Lichess numbers
    /// are never merged — they are different scales.
    private func loadRatings() {
        let chessCom = savedUsername
        let lichess = lichessUsername
        guard !chessCom.isEmpty || !lichess.isEmpty else { return }
        Task { @MainActor in
            let fetched = await RatingsService.fetch(chessComHandle: chessCom, lichessHandle: lichess)
            // A failed platform returns nothing; keep whatever we already had rather than blanking it.
            guard !fetched.isEmpty else { return }
            cachedRatings = cachedRatings.merging(fetched) { _, new in new }
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
        // One width read drives header + rows so their columns line up (same shape as the Library).
        GeometryReader { geo in
            let cols = MyGamesColumns(totalWidth: geo.size.width)
            GameTableList(
                games: sortedGames,
                selectedGameIds: $state.selectedGameIds,
                selectionAnchor: $state.lastSelectedGame,
                hasMore: hasMorePages,
                onOpen: onGameSelected,
                onLoadMore: loadNextPage,
                header: { chessComTableHeader(cols) },
                row: { game, isAlternate in chessComTableRow(game, isAlternate: isAlternate, cols: cols) },
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
    }

    private func chessComTableHeader(_ cols: MyGamesColumns) -> some View {
        HStack(spacing: MyGamesColumns.gap) {
            mgHeaderCell("WHITE", .white, width: cols.white)
            mgHeaderCell("BLACK", .black, width: cols.black)
            mgHeaderCell("RESULT", .result, width: cols.result)
            mgHeaderCell("OPENING", .opening, width: cols.opening)
            mgHeaderCell("TIME", .timeControl, width: cols.time)
            mgHeaderCell("SOURCE", .source, width: cols.source)
            mgHeaderCell("DATE", .date, width: cols.date)
            Color.clear.frame(width: cols.review, height: 1)
        }
        .padding(.horizontal, MyGamesColumns.hPadding)
        .padding(.top, 12).padding(.bottom, 8)
        .background(DS.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private func mgHeaderCell(_ title: String, _ column: SortColumn, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(title).font(AnnFont.label(9)).tracking(9 * 0.14).foregroundColor(DS.ink40)
            if sortColumn == column {
                Text(sortAscending ? "↑" : "↓").font(AnnFont.mono(9)).foregroundColor(DS.ink40)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if sortColumn == column { sortAscending.toggle() }
            else { sortColumn = column; sortAscending = column != .date }
            resortGames()
        }
    }

    /// Player name + piece dot, matching the Library's player cell so the two tables read identically.
    private func mgPlayerCell(_ name: String, isWhite: Bool, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isWhite ? DS.boardWhitePiece : DS.boardBlackPiece)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(DS.boardBlackPiece, lineWidth: isWhite ? 1.5 : 0))
            Text(name)
                .font(AnnFont.serif(14.5, .medium)).foregroundColor(DS.ink)
                .lineLimit(1).truncationMode(.tail)
        }
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

    private func chessComTableRow(_ game: GameRecord, isAlternate: Bool = false, cols: MyGamesColumns) -> some View {
        LedgerRowChrome(isAlternate: isAlternate, isSelected: selectedGameIds.contains(game.id)) {
            HStack(spacing: MyGamesColumns.gap) {
                mgPlayerCell(game.white, isWhite: true, width: cols.white)
                mgPlayerCell(game.black, isWhite: false, width: cols.black)

                // Result — bordered pill, like the Library.
                Text(chessComResultDisplay(game.result))
                    .font(AnnFont.mono(11, bold: true)).foregroundColor(DS.inkSoft)
                    .frame(maxWidth: .infinity).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(DS.borderChip, lineWidth: 1))
                    .frame(width: cols.result)

                // Opening — ECO chip + name, like the Library.
                HStack(spacing: 6) {
                    if let eco = game.eco, !eco.isEmpty {
                        Text(eco)
                            .font(AnnFont.mono(10, bold: true)).foregroundColor(DS.ink60)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(DS.borderChip, lineWidth: 1))
                    }
                    Text(game.opening ?? "—")
                        .font(AnnFont.voice(13.5)).foregroundColor(DS.inkSoft)
                        .lineLimit(1).truncationMode(.tail)
                }
                .frame(width: cols.opening, alignment: .leading)

                Text(chessComTimeClassLabel(game.timeClass))
                    .font(AnnFont.mono(10.5)).foregroundColor(DS.ink60).lineLimit(1)
                    .frame(width: cols.time, alignment: .leading)

                Text(game.sourcePlatform == "lichess" ? "Lichess" : "Chess.com")
                    .font(AnnFont.mono(10.5)).foregroundColor(DS.ink60).lineLimit(1)
                    .frame(width: cols.source, alignment: .leading)

                Text(chessComWhen(game))
                    .font(AnnFont.mono(10.5)).foregroundColor(DS.ink60).lineLimit(1)
                    .frame(width: cols.date, alignment: .leading)

                // Review — accuracy dots once analysed, otherwise the Analyze button.
                Group {
                    if let ad = game.analysisData {
                        accDotsBadge(white: ad.whiteAccuracy, black: ad.blackAccuracy)
                    } else {
                        Button(action: { onReviewGame(game) }) {
                            Text("Analyze")
                                .font(AnnFont.label(9)).tracking(0.3).foregroundColor(DS.redAccent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(DS.redAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.redAccent.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: cols.review, alignment: .trailing)
            }
        }
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
        // Both accounts sync, independently. The Lichess arm used to be gated on `!isSyncing`, but
        // startProgressiveSync sets that flag synchronously — so whenever Chess.com was connected,
        // Lichess silently never synced at all.
        if !savedUsername.isEmpty && !service.isLoading {
            startProgressiveSync(fullImport: false)
        }
        if !lichessUsername.isEmpty && !lichessService.isLoading {
            startLichessSync(fullImport: false)
        }
    }

    /// Drop the combined game list and rebuild it from whatever accounts remain. Shared by the
    /// onChange handlers above, so a disconnect (from the menu OR Settings) refreshes the same way.
    private func refreshAfterAccountChange() {
        cachedGames = []
        sortedGames = []
        totalGameCount = 0
        dbOffset = 0
        allDbGamesExhausted = false
        if hasAnyAccount { reloadGames() }
    }

    private func disconnectChessComAccount() {
        database.deleteCachedStats(for: savedUsername)
        service.clearHistory(for: savedUsername)
        lastSyncTimestamp = 0
        savedUsername = ""      // fires onChange → refreshAfterAccountChange()
    }

    private func disconnectLichessAccount() {
        if !settings.lichessToken.isEmpty {
            lichessAuth.logout()
        }
        lichessLastSync = 0
        lichessUsername = ""    // fires onChange → refreshAfterAccountChange()
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

    /// Open Settings on the Accounts tab — the one place all account status/sync/disconnect lives.
    private func openAccountsSettings() {
        settingsRequestedTab = 2        // index of "Accounts & Import" in PreferencesView
        openSettings()
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

/// Column widths for the My Games table — same responsive shape as the Library's `LedgerColumns`.
/// Known-size columns are fixed; White/Black split the rest evenly and Opening takes the biggest slice.
struct MyGamesColumns {
    let white, black, result, opening, time, source, date, review: CGFloat

    static let gap: CGFloat = 14
    static let hPadding: CGFloat = 28

    init(totalWidth: CGFloat) {
        result = 52
        time = 56
        source = 78
        date = 82
        review = 104          // "Analyze" button or the two-line accuracy badge

        let fixed = result + time + source + date + review
        let gaps = Self.gap * 7
        let flexible = max(220, totalWidth - fixed - gaps - Self.hPadding * 2)
        let unit = flexible / 3.8      // white 1.0 + black 1.0 + opening 1.8

        white = unit
        black = unit
        opening = unit * 1.8
    }
}

#Preview {
    ChessComBrowserView(onGameSelected: { _ in }, state: ChessComBrowserState())
        .environmentObject(GameDatabase.preview())
        .frame(width: 800, height: 600)
}
