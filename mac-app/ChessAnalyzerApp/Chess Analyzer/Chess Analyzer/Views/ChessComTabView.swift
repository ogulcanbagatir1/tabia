import SwiftUI

struct ChessComTabView: View {
    @EnvironmentObject var database: GameDatabase
    @StateObject private var service = ChessComService()
    @AppStorage("chesscom_username") private var savedUsername: String = ""
    @AppStorage("chesscom_last_sync") private var lastSyncTimestamp: Double = 0

    var onGameSelected: ((GameRecord) -> Void)?

    /// Games currently loaded and displayed (after all filters applied)
    @State private var cachedGames: [GameRecord] = []
    @State private var totalGameCount: Int = 0  // unfiltered total in DB
    @State private var isLoadingGames = false
    @State private var dbOffset: Int = 0  // tracks how far we've read from DB
    @State private var allDbGamesExhausted = false
    @State private var reloadTask: Task<Void, Never>?
    private let pageSize = 50
    private let dbBatchSize = 200  // over-fetch when client-side filters are active

    @State private var showStats = false

    @State private var showingImportSheet = false
    @State private var selectedGameIds: Set<UUID> = []
    @State private var lastSelectedGame: GameRecord?
    @State private var showingMoveToFolder = false
    @State private var newFolderName = ""

    // Filters
    @State private var filterTimeControl: String = "All"
    @State private var filterResult: String = "All"
    @State private var filterColor: String = "All"
    @State private var filterOpening: String = ""
    @State private var filterDateFrom: Date? = nil
    @State private var filterDateTo: Date? = nil
    @State private var searchText: String = ""

    private let chessComGreen = DS.chessComGreen

    private var hasMorePages: Bool {
        !allDbGamesExhausted
    }

    /// Whether any client-side filters are active (everything except timeClass is client-side)
    private var hasClientSideFilters: Bool {
        filterResult != "All" || filterColor != "All" ||
        !filterOpening.isEmpty || !searchText.isEmpty ||
        filterDateFrom != nil || filterDateTo != nil
    }

    /// Active time class for the DB query (nil means all)
    private var activeTimeClass: String? {
        filterTimeControl == "All" ? nil : filterTimeControl.lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            if savedUsername.isEmpty {
                emptyStateView
            } else {
                connectedStateView
            }
        }
        .onAppear {
            if cachedGames.isEmpty && !savedUsername.isEmpty {
                reloadGames()
            }
        }
        // Discrete filters — reload immediately (with tiny debounce to coalesce batch changes like clearFilters)
        .onChange(of: filterTimeControl) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterResult) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterColor) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterDateFrom) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: filterDateTo) { _, _ in scheduleReload(debounce: false) }
        // Text filters — debounce to avoid re-querying on every keystroke
        .onChange(of: searchText) { _, _ in scheduleReload(debounce: true) }
        .onChange(of: filterOpening) { _, _ in scheduleReload(debounce: true) }
    }

    /// Schedule a reload, optionally debounced for text input.
    /// A small debounce (50ms) is always used to coalesce batch state changes (e.g. clearFilters sets 6 vars).
    private func scheduleReload(debounce: Bool) {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: debounce ? 300_000_000 : 50_000_000)
            guard !Task.isCancelled else { return }
            reloadGames()
        }
    }

    /// Reset pagination and kick off an async load so the UI renders immediately.
    private func reloadGames() {
        guard !savedUsername.isEmpty else { return }
        cachedGames = []
        dbOffset = 0
        allDbGamesExhausted = false
        isLoadingGames = true

        // Async: let SwiftUI render the loading state before we block on DB fetch
        Task { @MainActor in
            totalGameCount = database.chessComGamesCount(for: savedUsername)
            performLoad(targetCount: pageSize)
        }
    }

    /// Load the next page when the user scrolls near the bottom.
    private func loadNextPage() {
        guard hasMorePages, !isLoadingGames else { return }
        isLoadingGames = true
        Task { @MainActor in
            performLoad(targetCount: cachedGames.count + pageSize)
        }
    }

    /// Fetch games from DB until we have at least `targetCount` displayed games.
    /// Called from within a Task — isLoadingGames is already true.
    private func performLoad(targetCount: Int) {
        let batchSize = hasClientSideFilters ? dbBatchSize : pageSize

        while cachedGames.count < targetCount && !allDbGamesExhausted {
            let batch = database.fetchFilteredChessComGames(
                for: savedUsername,
                timeClass: activeTimeClass,
                limit: batchSize,
                offset: dbOffset
            )

            dbOffset += batch.count
            if batch.count < batchSize {
                allDbGamesExhausted = true
            }

            if hasClientSideFilters {
                cachedGames.append(contentsOf: applyClientFilters(batch))
            } else {
                cachedGames.append(contentsOf: batch)
            }
        }

        isLoadingGames = false
    }

    /// Apply client-side filters (everything except timeClass which is handled at the DB level).
    private func applyClientFilters(_ games: [GameRecord]) -> [GameRecord] {
        var result = games

        // Result filter (from user's perspective)
        if filterResult != "All" {
            let username = savedUsername.lowercased()
            result = result.filter { game in
                let userPlayedWhite = game.white.lowercased() == username
                let gameResult = game.result
                switch filterResult {
                case "Wins":
                    return (userPlayedWhite && gameResult == "1-0") || (!userPlayedWhite && gameResult == "0-1")
                case "Losses":
                    return (userPlayedWhite && gameResult == "0-1") || (!userPlayedWhite && gameResult == "1-0")
                case "Draws":
                    return gameResult == "1/2-1/2" || gameResult == "1/2"
                default: return true
                }
            }
        }

        // Color filter
        if filterColor != "All" {
            let username = savedUsername.lowercased()
            result = result.filter { game in
                let userPlayedWhite = game.white.lowercased() == username
                switch filterColor {
                case "White": return userPlayedWhite
                case "Black": return !userPlayedWhite
                default: return true
                }
            }
        }

        // Opening filter
        if !filterOpening.isEmpty {
            let query = filterOpening.lowercased()
            result = result.filter { game in
                game.opening?.lowercased().contains(query) == true ||
                game.eco?.lowercased().contains(query) == true
            }
        }

        // Search filter (player names)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { game in
                game.white.lowercased().contains(query) ||
                game.black.lowercased().contains(query)
            }
        }

        // Date range filter
        if let dateFrom = filterDateFrom {
            result = result.filter { $0.dateAdded >= dateFrom }
        }
        if let dateTo = filterDateTo {
            result = result.filter { $0.dateAdded <= dateTo }
        }

        return result
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(chessComGreen.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 36))
                    .foregroundColor(chessComGreen)
            }

            VStack(spacing: 8) {
                Text("Connect Chess.com")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Import and sync your games from Chess.com")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Button(action: { showingImportSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .medium))
                    Text("Connect Account")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(chessComGreen)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 40)
        .sheet(isPresented: $showingImportSheet) {
            ChessComConnectSheet(
                service: service,
                savedUsername: $savedUsername,
                lastSyncTimestamp: $lastSyncTimestamp,
                onImport: { games, username in
                    importChessComGames(games, username: username)
                    reloadGames()
                },
                onDismiss: { showingImportSheet = false }
            )
        }
    }

    // MARK: - Connected State

    private var connectedStateView: some View {
        VStack(spacing: 0) {
            accountHeader

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            // Games / Stats toggle
            HStack(spacing: 0) {
                Picker("", selection: $showStats) {
                    Text("Games").tag(false)
                    Text("Stats").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .padding(.vertical, DS.spacingMD)
            }
            .frame(maxWidth: .infinity)
            .background(DS.bg)

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            if showStats {
                ChessComStatsView(
                    username: savedUsername,
                    selectedTimeClass: "all"
                )
            } else {
                filterBar

                Rectangle()
                    .fill(DS.border)
                    .frame(height: 1)

                if cachedGames.isEmpty {
                    emptyGamesView
                } else {
                    gamesList
                }

                statusBar
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            ChessComConnectSheet(
                service: service,
                savedUsername: $savedUsername,
                lastSyncTimestamp: $lastSyncTimestamp,
                onImport: { games, username in
                    importChessComGames(games, username: username)
                    reloadGames()
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

    // MARK: - Account Header

    private var accountHeader: some View {
        HStack(spacing: 16) {
            // Avatar: 48x48, cornerRadius 24 (circle), fill chessComGreen
            ZStack {
                Circle()
                    .fill(chessComGreen)
                    .frame(width: 48, height: 48)
                Text(String(savedUsername.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Info block (vertical, gap 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(savedUsername)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                if lastSyncTimestamp > 0 {
                    Text("Synced \(formatLastSync())")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textTertiary)
                }
            }

            Spacer()

            // Sync button: fill chessComGreen, cornerRadius 6, padding [6, 12], gap 6
            Button(action: refreshGames) {
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Text("Sync Games")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(chessComGreen)
                    .cornerRadius(6)
                }
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
            .help("Refresh games")

            Menu {
                Button(action: { showingImportSheet = true }) {
                    Label("Account Settings", systemImage: "gearshape")
                }
                Divider()
                Button(role: .destructive, action: disconnectAccount) {
                    Label("Disconnect Account", systemImage: "xmark.circle")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg)
    }

    // MARK: - Filter Bar

    @State private var showingFiltersPopover = false

    private var hasActiveFilters: Bool {
        filterTimeControl != "All" || filterResult != "All" || filterColor != "All" ||
        !filterOpening.isEmpty || filterDateFrom != nil || filterDateTo != nil || !searchText.isEmpty
    }

    private var activeFilterCount: Int {
        var count = 0
        if filterTimeControl != "All" { count += 1 }
        if filterResult != "All" { count += 1 }
        if filterColor != "All" { count += 1 }
        if !filterOpening.isEmpty { count += 1 }
        if filterDateFrom != nil || filterDateTo != nil { count += 1 }
        if !searchText.isEmpty { count += 1 }
        return count
    }

    private func clearFilters() {
        filterTimeControl = "All"
        filterResult = "All"
        filterColor = "All"
        filterOpening = ""
        filterDateFrom = nil
        filterDateTo = nil
        searchText = ""
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DS.bgSecondary)
            .cornerRadius(8)
            .frame(maxWidth: .infinity)

            Button(action: { showingFiltersPopover.toggle() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 15))
                        .foregroundColor(hasActiveFilters ? chessComGreen : DS.textSecondary)
                        .frame(width: 28, height: 28)

                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(chessComGreen)
                            .clipShape(Circle())
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Filters")
            .popover(isPresented: $showingFiltersPopover) {
                filtersPopover
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg)
    }

    // MARK: - Filters Popover

    private var filtersPopover: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filters")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if hasActiveFilters {
                    Button(action: clearFilters) {
                        Text("Reset")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(DS.bgSecondary)

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 20) {
                    filterSection(title: "Time Control", icon: "clock") {
                        filterPillGroup(
                            options: ["All", "Bullet", "Blitz", "Rapid", "Daily"],
                            selected: filterTimeControl
                        ) { selected in
                            filterTimeControl = selected
                        }
                    }

                    filterSection(title: "Result", icon: "flag") {
                        filterPillGroup(
                            options: ["All", "Wins", "Losses", "Draws"],
                            selected: filterResult
                        ) { selected in
                            filterResult = selected
                        }
                    }

                    filterSection(title: "Played As", icon: "circle.lefthalf.filled") {
                        filterPillGroup(
                            options: ["All", "White", "Black"],
                            selected: filterColor
                        ) { selected in
                            filterColor = selected
                        }
                    }

                    filterSection(title: "Opening", icon: "book") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.textSecondary)
                                TextField("Search opening or ECO...", text: $filterOpening)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                if !filterOpening.isEmpty {
                                    Button(action: { filterOpening = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(DS.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(DS.bgSecondary)
                            .cornerRadius(8)

                            ChessComFlowLayout(spacing: 6) {
                                ForEach(commonOpenings, id: \.self) { opening in
                                    Button(action: { filterOpening = opening }) {
                                        Text(opening)
                                            .font(.system(size: 11))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(filterOpening == opening ? chessComGreen : DS.bgSecondary)
                                            .foregroundColor(filterOpening == opening ? .white : DS.textPrimary)
                                            .cornerRadius(14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    filterSection(title: "Date Range", icon: "calendar") {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("From")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.textSecondary)
                                HStack(spacing: 6) {
                                    DatePicker("", selection: Binding(
                                        get: { filterDateFrom ?? Date() },
                                        set: { filterDateFrom = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(width: 95)

                                    if filterDateFrom != nil {
                                        Button(action: { filterDateFrom = nil }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(DS.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("To")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.textSecondary)
                                HStack(spacing: 6) {
                                    DatePicker("", selection: Binding(
                                        get: { filterDateTo ?? Date() },
                                        set: { filterDateTo = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(width: 95)

                                    if filterDateTo != nil {
                                        Button(action: { filterDateTo = nil }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(DS.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            HStack {
                if hasActiveFilters {
                    Text("\(activeFilterCount) active")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                }
                Spacer()
                Button(action: { showingFiltersPopover = false }) {
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(chessComGreen)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(DS.bgSecondary)
        }
        .frame(width: 340)
    }

    private var commonOpenings: [String] {
        ["Sicilian", "French", "Caro-Kann", "Italian", "Spanish", "Queen's Gambit", "King's Indian", "English"]
    }

    private func filterSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(chessComGreen)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterPillGroup(options: [String], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        ChessComFlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button(action: { onSelect(option) }) {
                    Text(option)
                        .font(.system(size: 11, weight: selected == option ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected == option ? chessComGreen : DS.bgSecondary)
                        .foregroundColor(selected == option ? .white : DS.textPrimary)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Games List

    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(cachedGames) { game in
                    ChessComGameRowView(
                        game: game,
                        username: savedUsername,
                        isSelected: selectedGameIds.contains(game.id)
                    )
                    .onTapGesture {
                        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                            openGame(game)
                        }
                        if NSEvent.modifierFlags.contains(.command) {
                            if selectedGameIds.contains(game.id) {
                                selectedGameIds.remove(game.id)
                            } else {
                                selectedGameIds.insert(game.id)
                            }
                        } else if NSEvent.modifierFlags.contains(.shift), let last = lastSelectedGame {
                            if let startIdx = cachedGames.firstIndex(where: { $0.id == last.id }),
                               let endIdx = cachedGames.firstIndex(where: { $0.id == game.id }) {
                                let range = min(startIdx, endIdx)...max(startIdx, endIdx)
                                for i in range {
                                    selectedGameIds.insert(cachedGames[i].id)
                                }
                            }
                        } else {
                            selectedGameIds = [game.id]
                        }
                        lastSelectedGame = game
                    }
                    .contextMenu {
                        Button("Open Game") {
                            openGame(game)
                        }

                        Divider()

                        if selectedGameIds.count > 1 {
                            moveToFolderMenu(gameIds: selectedGameIds, label: "Move \(selectedGameIds.count) Games to...")
                        } else {
                            moveToFolderMenu(gameIds: [game.id], label: "Move to...")
                        }

                        Divider()

                        if selectedGameIds.count > 1 {
                            Button("Deselect All") {
                                selectedGameIds.removeAll()
                            }
                        }
                    }
                    .onAppear {
                        if game.id == cachedGames.last?.id && hasMorePages {
                            loadNextPage()
                        }
                    }

                    Divider()
                        .padding(.horizontal, 12)
                }

                // Loading indicator at bottom
                if hasMorePages {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading more games...")
                            .font(.system(size: 11))
                            .foregroundColor(DS.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear {
                        loadNextPage()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(DS.bgSecondary)
    }

    private func moveToFolderMenu(gameIds: Set<UUID>, label: String) -> some View {
        Menu(label) {
            ForEach(database.folders) { folder in
                Button(folder.name) {
                    database.moveGamesByIds(gameIds, toFolder: folder.id)
                    selectedGameIds.removeAll()
                }
            }

            if !database.folders.isEmpty {
                Divider()
            }

            Button("New Database...") {
                showingMoveToFolder = true
            }
        }
    }

    private var emptyGamesView: some View {
        VStack(spacing: 16) {
            Spacer()
            if isLoadingGames {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading games...")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textSecondary)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundColor(DS.textTertiary)
                if cachedGames.isEmpty && totalGameCount == 0 {
                    Text("No games yet")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textSecondary)
                    Button(action: refreshGames) {
                        Text("Refresh")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(chessComGreen)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("No games match filters")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textSecondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 10))
                .foregroundColor(DS.textSecondary)

            if hasActiveFilters {
                Text("\(cachedGames.count)\(allDbGamesExhausted ? "" : "+")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(DS.textPrimary)
                +
                Text(" of \(totalGameCount) games")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)

                Text("\u{2022}")
                    .foregroundColor(DS.textSecondary)
                Text("filtered")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(chessComGreen)
            } else {
                Text("\(totalGameCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(DS.textPrimary)
                +
                Text(" games")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()

            if !selectedGameIds.isEmpty {
                Text("\(selectedGameIds.count) selected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(chessComGreen)

                Menu {
                    ForEach(database.folders) { folder in
                        Button(folder.name) {
                            database.moveGamesByIds(selectedGameIds, toFolder: folder.id)
                            selectedGameIds.removeAll()
                        }
                    }
                    if !database.folders.isEmpty {
                        Divider()
                    }
                    Button("New Database...") {
                        showingMoveToFolder = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 10))
                        Text("Move to...")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(chessComGreen)
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.bg)
    }

    // MARK: - Actions

    private func refreshGames() {
        Task {
            // Fetch existing URLs once (on main — SwiftData is main-bound); dedup in memory per archive.
            var seen = await MainActor.run { database.existingChessComSourceUrls(for: savedUsername) }
            await service.fetchNewGamesProgressive(username: savedUsername) { archiveGames in
                let records = parseChessComGames(archiveGames, username: savedUsername)
                await MainActor.run {
                    let newRecords = records.filter { record in
                        guard let sourceUrl = record.sourceUrl else { return true }
                        if seen.contains(sourceUrl) { return false }
                        seen.insert(sourceUrl)
                        return true
                    }
                    if !newRecords.isEmpty {
                        database.addGames(newRecords, isChessComImport: true)
                    }
                }
            }
            await MainActor.run {
                if service.error == nil {
                    recomputeAndCacheStats(for: savedUsername)
                    lastSyncTimestamp = Date().timeIntervalSince1970
                    reloadGames()
                }
            }
        }
    }

    private func disconnectAccount() {
        database.deleteCachedStats(for: savedUsername)
        service.clearHistory(for: savedUsername)
        savedUsername = ""
        lastSyncTimestamp = 0
        cachedGames = []
        totalGameCount = 0
        dbOffset = 0
        allDbGamesExhausted = false
    }

    private func openGame(_ game: GameRecord) {
        onGameSelected?(game)
    }

    // MARK: - Stats Caching

    private func recomputeAndCacheStats(for username: String) {
        var allGames: [GameRecord] = []
        database.iterateChessComGames(for: username, batchSize: 2000) { batch in
            allGames.append(contentsOf: batch)
        }
        let allVariants = ChessComStatsComputer.computeAllVariants(games: allGames, username: username)
        let cached = ChessComCachedStats(
            username: username.lowercased(),
            statsData: allVariants,
            gameCount: allGames.count
        )
        database.saveCachedStats(cached)
    }

    // MARK: - Import Helper

    private func importChessComGames(_ games: [ChessComGame], username: String) {
        let records = parseChessComGames(games, username: username)
        // Dedup against a single Set of existing URLs (O(1) per game) instead of a DB query per game;
        // insert new URLs into the Set so duplicates across archives are also caught.
        var seen = database.existingChessComSourceUrls(for: username)
        let newRecords = records.filter { record in
            guard let sourceUrl = record.sourceUrl else { return true }
            if seen.contains(sourceUrl) { return false }
            seen.insert(sourceUrl)
            return true
        }

        if !newRecords.isEmpty {
            database.addGames(newRecords, isChessComImport: true)
            recomputeAndCacheStats(for: username)
        }
    }

    private func parseChessComGames(_ games: [ChessComGame], username: String) -> [GameRecord] {
        var records: [GameRecord] = []
        let parser = PGNParser()   // reuse one parser across all games (no per-game allocation)

        for game in games {
            guard let pgn = game.pgn else { continue }

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

    // MARK: - Helpers

    private func formatLastSync() -> String {
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

}

// MARK: - Chess.com Game Row (displays a GameRecord)

struct ChessComGameRowView: View {
    let game: GameRecord
    let username: String
    var isSelected: Bool = false

    private var userPlayedWhite: Bool {
        game.white.lowercased() == username.lowercased()
    }

    private var userWon: Bool {
        (userPlayedWhite && game.result == "1-0") || (!userPlayedWhite && game.result == "0-1")
    }

    private var userLost: Bool {
        (userPlayedWhite && game.result == "0-1") || (!userPlayedWhite && game.result == "1-0")
    }

    private var resultColor: Color {
        if userWon {
            return DS.chessComGreen
        } else if userLost {
            return DS.moveMistake
        } else {
            return DS.textTertiary
        }
    }

    /// Extract a rating from PGN headers like [WhiteElo "1234"]
    private func extractRating(for color: String) -> String? {
        // Read the elo already stored on the record — no per-row PGN regex compile/scan.
        let elo = color.lowercased() == "white" ? game.whiteElo : game.blackElo
        guard let elo, elo > 0 else { return nil }
        return String(elo)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Result indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(resultColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                // Players
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(DS.border, lineWidth: 0.5))
                        Text(game.white)
                            .font(.system(size: 12, weight: game.result == "1-0" ? .semibold : .regular))
                            .lineLimit(1)
                        if let rating = extractRating(for: "White") {
                            Text("(\(rating))")
                                .font(.system(size: 10))
                                .foregroundColor(DS.textSecondary)
                        }
                    }

                    Text("vs")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textSecondary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 8, height: 8)
                        Text(game.black)
                            .font(.system(size: 12, weight: game.result == "0-1" ? .semibold : .regular))
                            .lineLimit(1)
                        if let rating = extractRating(for: "Black") {
                            Text("(\(rating))")
                                .font(.system(size: 10))
                                .foregroundColor(DS.textSecondary)
                        }
                    }

                    Spacer()
                }

                // Event/site + date
                HStack(spacing: 6) {
                    if !eventSiteLabel.isEmpty {
                        Text(eventSiteLabel)
                            .font(.system(size: 10))
                            .foregroundColor(DS.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(game.date)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textSecondary)
                }
            }

            // Time class + result
            VStack(alignment: .trailing, spacing: 4) {
                if let timeClass = game.timeClass {
                    Image(systemName: timeClassIcon(timeClass))
                        .font(.system(size: 12))
                        .foregroundColor(DS.textSecondary)
                        .help(timeClass.capitalized)
                }

                Text(game.result)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DS.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? DS.chessComGreen.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private var eventSiteLabel: String {
        let event = game.event.trimmingCharacters(in: .whitespaces)
        let site = game.site.trimmingCharacters(in: .whitespaces)
        let ignoredValues: Set<String> = ["?", "-", ""]

        let hasEvent = !ignoredValues.contains(event)
        let hasSite = !ignoredValues.contains(site) && site != event

        if hasEvent && hasSite {
            return "\(event) • \(site)"
        } else if hasEvent {
            return event
        } else if hasSite {
            return site
        }
        return ""
    }

    private func timeClassIcon(_ timeClass: String) -> String {
        switch timeClass.lowercased() {
        case "bullet": return "circle.fill"
        case "blitz": return "bolt.fill"
        case "rapid": return "hare.fill"
        case "classical": return "clock.fill"
        case "daily": return "calendar"
        default: return "clock"
        }
    }
}

// MARK: - Connect Sheet

struct ChessComConnectSheet: View {
    @ObservedObject var service: ChessComService
    @Binding var savedUsername: String
    @Binding var lastSyncTimestamp: Double
    var onImport: ([ChessComGame], String) -> Void
    var onDismiss: () -> Void

    @State private var username: String = ""

    private let chessComGreen = DS.chessComGreen

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 20))
                    .foregroundColor(chessComGreen)

                Text(savedUsername.isEmpty ? "Connect Chess.com" : "Account Settings")
                    .font(.headline)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DS.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(DS.bgSecondary)

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chess.com Username")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textSecondary)

                    TextField("Enter username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            username = savedUsername
                        }
                }

                // Progress
                if service.isLoading && service.totalArchives > 0 {
                    VStack(spacing: 10) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DS.bgSecondary)
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(chessComGreen)
                                    .frame(width: geometry.size.width * progressPercentage, height: 8)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("\(Int(progressPercentage * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(chessComGreen)

                            Text("\u{2022}")
                                .foregroundColor(DS.textSecondary)

                            Text("Archive \(service.currentArchive) of \(service.totalArchives)")
                                .font(.system(size: 11))
                                .foregroundColor(DS.textSecondary)

                            if service.gamesFoundSoFar > 0 {
                                Text("\u{2022}")
                                    .foregroundColor(DS.textSecondary)
                                Text("\(service.gamesFoundSoFar) games")
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.textSecondary)
                            }

                            Spacer()
                        }
                    }
                }

                // Error
                if let error = service.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(DS.textSecondary)
                        Spacer()
                    }
                }

                Spacer()
            }
            .padding()

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            // Footer
            HStack {
                if !savedUsername.isEmpty {
                    Button(role: .destructive, action: {
                        savedUsername = ""
                        lastSyncTimestamp = 0
                        onDismiss()
                    }) {
                        Text("Disconnect")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(GlassButtonStyle())

                Button(action: connectAccount) {
                    if service.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(savedUsername.isEmpty ? "Connect" : "Save")
                    }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .tint(chessComGreen)
                .disabled(username.isEmpty || service.isLoading)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }

    private var progressPercentage: CGFloat {
        guard service.totalArchives > 0 else { return 0 }
        return CGFloat(service.currentArchive) / CGFloat(service.totalArchives)
    }

    private func connectAccount() {
        Task {
            service.clearHistory(for: username)

            await service.fetchAllGames(username: username)
            await MainActor.run {
                if service.error == nil {
                    savedUsername = username
                    lastSyncTimestamp = Date().timeIntervalSince1970
                    onImport(service.fetchedGames, username)
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Flow Layout for Wrapping Pills

struct ChessComFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

#Preview {
    ChessComTabView()
        .environmentObject(GameDatabase.preview())
}
