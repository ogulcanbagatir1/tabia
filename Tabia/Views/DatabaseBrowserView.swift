import SwiftUI

struct DatabaseBrowserView: View {
    @EnvironmentObject var database: GameDatabase
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    @ObservedObject private var dbIndex = DatabaseIndex.shared
    var onGameSelected: (GameRecord) -> Void
    var onReferenceGameSelected: (String) -> Void = { _ in }
    /// Load the game into Analysis and immediately run a full game review.
    var onReviewGame: (GameRecord) -> Void = { _ in }

    /// Survives leaving the screen. See BrowserStates.swift for the ownership rule.
    @ObservedObject var state: DatabaseBrowserState

    // Forwarding accessors: the body reads and writes these exactly as before, they just live in
    // `state` now. `nonmutating set` works because `state` is a reference.
    private var navigation: Navigation {
        get { state.navigation } nonmutating set { state.navigation = newValue }
    }
    private var selectedGameIds: Set<UUID> {
        get { state.selectedGameIds } nonmutating set { state.selectedGameIds = newValue }
    }
    private var selectedGame: GameRecord? {
        get { state.selectedGame } nonmutating set { state.selectedGame = newValue }
    }
    private var filterWhite: String {
        get { state.filterWhite } nonmutating set { state.filterWhite = newValue }
    }
    private var filterBlack: String {
        get { state.filterBlack } nonmutating set { state.filterBlack = newValue }
    }
    private var filterResult: String? {
        get { state.filterResult } nonmutating set { state.filterResult = newValue }
    }
    private var filterWhiteEloRange: ClosedRange<Double> {
        get { state.filterWhiteEloRange } nonmutating set { state.filterWhiteEloRange = newValue }
    }
    private var filterBlackEloRange: ClosedRange<Double> {
        get { state.filterBlackEloRange } nonmutating set { state.filterBlackEloRange = newValue }
    }
    private var filterDateFrom: String {
        get { state.filterDateFrom } nonmutating set { state.filterDateFrom = newValue }
    }
    private var filterDateTo: String {
        get { state.filterDateTo } nonmutating set { state.filterDateTo = newValue }
    }
    private var filterEvent: String {
        get { state.filterEvent } nonmutating set { state.filterEvent = newValue }
    }
    private var filterOpening: String {
        get { state.filterOpening } nonmutating set { state.filterOpening = newValue }
    }
    private var appliedFilter: GameFilter {
        get { state.appliedFilter } nonmutating set { state.appliedFilter = newValue }
    }
    private var sortColumn: SortColumn {
        get { state.sortColumn } nonmutating set { state.sortColumn = newValue }
    }
    private var sortAscending: Bool {
        get { state.sortAscending } nonmutating set { state.sortAscending = newValue }
    }
    private var cachedGames: [GameRecord] {
        get { state.cachedGames } nonmutating set { state.cachedGames = newValue }
    }
    private var totalCount: Int {
        get { state.totalCount } nonmutating set { state.totalCount = newValue }
    }
    private var dbOffset: Int {
        get { state.dbOffset } nonmutating set { state.dbOffset = newValue }
    }
    private var allExhausted: Bool {
        get { state.allExhausted } nonmutating set { state.allExhausted = newValue }
    }

    // Transient UI — deliberately still @State, so it resets when you come back.
    @State private var indexingFolder: GameFolder?
    @State private var showingImportPicker = false
    @State private var showingPGNImportSheet = false
    @State private var pendingImportURLs: [URL] = []
    @State private var pendingImportFolderId: UUID? = nil
    @State private var importAlert: ImportAlertInfo?
    @State private var showingNewDatabaseSheet = false
    @State private var showingNewDatabaseForGames = false
    @State private var newDatabaseGameIds: Set<UUID> = []
    @State private var newDatabaseName = ""
    @State private var fileUnfiledIntoNew = false
    @State private var newFolderName = ""
    @State private var newFolderSummary = ""
    @State private var renamingFolder: GameFolder?
    @State private var showingDeleteFolderAlert = false
    @State private var folderToDelete: GameFolder?
    @State private var exportingFolder: GameFolder?
    @State private var showingExportFormatPicker = false
    @State private var isDropTargeted = false
    @State private var showingFilters = false
    /// Held, not observed — ⌘⇧O fires it and only the pill re-renders.
    @State private var switcherTrigger = SwitcherTrigger()

    // Filters

    // Picker popovers
    @State private var showingWhitePlayerPicker = false
    @State private var showingBlackPlayerPicker = false
    @State private var showingOpeningPicker = false
    @State private var showingEventPicker = false

    // Applied filter (what's actually used for queries)

    // Filter card height (measured from tallest card)
    @State private var filterCardHeight: CGFloat = 0

    // Sorting

    // Pagination
    @State private var isLoadingGames = false
    @State private var reloadTask: Task<Void, Never>?
    private let pageSize = 50
    private let dbBatchSize = 200

    enum Navigation: Hashable {
        case root
        case allGames
        case folder(UUID)
        case reference
    }

    enum SortColumn: String {
        case white, black, date, result, event, site, opening
    }

    struct ImportAlertInfo: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    private var hasActiveFilters: Bool {
        appliedFilter != GameFilter()
    }

    private var activeFilterCount: Int {
        var count = 0
        if appliedFilter.white != nil { count += 1 }
        if appliedFilter.black != nil { count += 1 }
        if appliedFilter.result != nil { count += 1 }
        if appliedFilter.whiteEloMin != nil || appliedFilter.whiteEloMax != nil { count += 1 }
        if appliedFilter.blackEloMin != nil || appliedFilter.blackEloMax != nil { count += 1 }
        if appliedFilter.dateFrom != nil || appliedFilter.dateTo != nil { count += 1 }
        if appliedFilter.event != nil { count += 1 }
        if appliedFilter.opening != nil { count += 1 }
        return count
    }

    private var hasPendingChanges: Bool {
        buildGameFilter() != appliedFilter
    }

    /// Changes whenever the library gains/loses games or databases — the trigger for recounting.
    private var libraryRevision: Int {
        database.libraryGameCount &* 1000 &+ database.folders.count
    }

    /// The module's content plus the commands that drive it. Split out of `body` because the full
    /// modifier chain — sheets, alerts, importers, drop targets — is one expression, and past a
    /// certain length Swift's type checker gives up on it.
    private var navigationContent: some View {
        // No sidebar: the module is a Shelf ↔ Ledger swap. One to three databases could never fill a
        // 300px panel, so that width goes to the content instead.
        Group {
            switch navigation {
            case .root:
                shelfView
            case .reference:
                ReferenceBrowseView(
                    onBack: { navigation = .root },
                    onOpen: { onReferenceGameSelected($0) }
                )
            default:
                tableView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .tabiaLibraryToggleFilters)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showingFilters.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabiaLibraryImportPGN)) { _ in
            showingImportPicker = true
        }
        // ⌘⇧O anywhere in the module opens the switcher; inside a database ⌘[ goes back to the shelf.
        .background {
            Group {
                Button("") { if navigation != .root { switcherTrigger.fire() } }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("") { if navigation != .root { navigation = .root } }
                    .keyboardShortcut("[", modifiers: .command)
            }
            .opacity(0)
        }
    }

    var body: some View {
        navigationContent
        .onReceive(NotificationCenter.default.publisher(for: .tabiaNewDatabase)) { _ in
            showingNewDatabaseSheet = true
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.plainText, .text, .data],
            allowsMultipleSelection: true,
            onCompletion: handleFileImporterResult
        )
        .sheet(isPresented: $showingPGNImportSheet) {
            PGNImportView(
                database: database,
                fileURLs: pendingImportURLs,
                onImport: { folderId in
                    showingPGNImportSheet = false
                    pendingImportURLs = []
                    pendingImportFolderId = nil
                    if let folderId = folderId {
                        navigation = .folder(folderId)
                    }
                    // Delay reload to ensure sheet dismissal completes
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        reloadGames()
                    }
                },
                onCancel: {
                    showingPGNImportSheet = false
                    pendingImportURLs = []
                    pendingImportFolderId = nil
                },
                preselectedFolderId: pendingImportFolderId
            )
        }
        .alert(item: $importAlert) { info in
            Alert(
                title: Text(info.isError ? "Import Error" : "Import Successful"),
                message: Text(info.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingNewDatabaseSheet) {
            NewDatabaseSheet { name, summary, pgnURLs in
                showingNewDatabaseSheet = false
                let folder = database.createFolder(name: name, summary: summary)
                if !pgnURLs.isEmpty {
                    pendingImportURLs = pgnURLs
                    pendingImportFolderId = folder.id
                    navigation = .folder(folder.id)
                    showingPGNImportSheet = true
                } else {
                    navigation = .folder(folder.id)
                }
            } onCancel: {
                showingNewDatabaseSheet = false
            } onDownloadReference: {
                // Keep the sheet open — it shows live download progress in-place.
                if let url = URL(string: ReferenceDatabase.defaultManifestURLString) {
                    ReferenceDatabase.shared?.downloadReferenceDatabase(manifestURL: url)
                }
            }
        }
        .alert("Edit Database", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Database name", text: $newFolderName)
            TextField("Description (optional)", text: $newFolderSummary)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Save") {
                if let folder = renamingFolder {
                    let summary = newFolderSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                    database.updateFolder(folder, name: newFolderName, summary: summary.isEmpty ? nil : summary)
                }
                renamingFolder = nil
            }
        } message: {
            Text("The description appears under the name on the shelf.")
        }
        .alert("Delete Database", isPresented: $showingDeleteFolderAlert) {
            Button("Delete", role: .destructive) {
                if let folder = folderToDelete {
                    dbIndex.removeIndex(folderId: folder.id)
                    database.deleteFolder(folder, deleteGames: true)
                    navigation = .allGames
                }
                folderToDelete = nil
            }
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: {
            Text("This will permanently delete this database and all its games.")
        }
        .alert("New Database", isPresented: $showingNewDatabaseForGames) {
            TextField("Database name", text: $newDatabaseName)
            Button("Cancel", role: .cancel) { newDatabaseGameIds = []; fileUnfiledIntoNew = false }
            Button("Create") {
                let name = newDatabaseName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let folder = database.createFolder(name: name)
                    if fileUnfiledIntoNew {
                        database.moveAllUnfiledLibraryGames(toFolder: folder.id)
                    } else if !newDatabaseGameIds.isEmpty {
                        database.moveGames(newDatabaseGameIds, toFolder: folder.id)
                    }
                    selectedGameIds.removeAll()
                    navigation = .folder(folder.id)
                }
                newDatabaseGameIds = []; fileUnfiledIntoNew = false
            }
        } message: {
            let n = fileUnfiledIntoNew ? database.unfiledLibraryGameCount() : newDatabaseGameIds.count
            Text("Move \(n) game\(n == 1 ? "" : "s") into a new database.")
        }
        .sheet(item: $indexingFolder) { folder in
            DatabaseIndexProgressSheet(folderName: folder.name) { indexingFolder = nil }
        }
        .confirmationDialog(
            "Export \"\(exportingFolder?.name ?? "")\"",
            isPresented: $showingExportFormatPicker,
            titleVisibility: .visible
        ) {
            Button("PGN (.pgn)") {
                if let folder = exportingFolder {
                    exportFolder(folder, format: .pgn)
                }
            }
            Button("SQLite (.db3)") {
                if let folder = exportingFolder {
                    exportFolder(folder, format: .sqlite)
                }
            }
            Button("Cancel", role: .cancel) { exportingFolder = nil }
        }
        .onAppear {
            if case .allGames = navigation, cachedGames.isEmpty {
                reloadGames()
            } else if case .folder(_) = navigation, cachedGames.isEmpty {
                reloadGames()
            }
        }
        // Data loading is deliberately NOT in onAppear: it runs after the screen is on screen, so a
        // transition is never waiting on a query.
        .task(id: libraryRevision) {
            await Task.yield()               // let the screen paint first
            await refreshFolderCountsIfNeeded()
            measureStoreSizeIfNeeded()       // one file stat, cheap, and last in line
        }
        // Filters belong to the database you're inside, not the module: leaving one ledger (back to
        // the shelf, or into a different database) clears them so database A's filter never carries
        // into database B. resetFilters runs BEFORE reloadGames so the reload sees the cleared state.
        .onChange(of: navigation) { _, _ in resetFilters(); reloadGames() }
        .onChange(of: sortColumn) { _, _ in scheduleReload(debounce: false) }
        .onChange(of: sortAscending) { _, _ in scheduleReload(debounce: false) }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(DS.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(DS.accentLight.cornerRadius(8))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 32))
                                .foregroundColor(DS.accent)
                            Text("Drop to import")
                                .font(AnnFont.serif(13, .medium))
                                .foregroundColor(DS.accent)
                        }
                    )
                    .padding(8)
            }
        }
    }

    // MARK: - Root View (Database List)

    // MARK: - Library sidebar (D1) — the old "Databases" grid folded into a sidebar

    // Thin rail shown when the library sidebar is collapsed — one tap brings it back.
    /// Count each database once, not once per render. Refreshed when the library size changes.
    /// Fill in the per-database numbers AFTER the screen is on screen, one database at a time.
    ///
    /// Navigation must never wait on data. These are unindexed relationship queries — two per
    /// database — so doing them in one synchronous pass blocked the transition for 50–90 ms with a
    /// single small library, and would scale linearly with the number of databases. Yielding between
    /// each keeps every main-actor turn short: the shelf paints immediately, counts land as they
    /// arrive, and a hundred databases cost a hundred short turns instead of one long freeze.
    private func refreshFolderCountsIfNeeded() async {
        guard state.countsRevision != libraryRevision else { return }
        state.countsRevision = libraryRevision

        for folder in database.folders {
            guard !Task.isCancelled else { return }
            state.folderCounts[folder.id] = database.gamesInFolderCount(folder.id)
            // Sorted dateAdded-descending, so one row is the newest.
            state.folderLastChanged[folder.id] = database.gamesInFolder(folder.id, limit: 1).first?.dateAdded
            await Task.yield()
        }

        guard !Task.isCancelled else { return }
        state.libraryLastChanged = database.fetchLibraryGames(
            folderId: nil,
            sortDescriptor: SortDescriptor(\.dateAdded, order: .reverse),
            limit: 1, offset: 0
        ).games.first?.dateAdded
    }

    private func folderCount(_ id: UUID) -> Int { state.folderCounts[id] ?? 0 }

    /// "EDITED 3 DAYS AGO" from the newest game, falling back to when the database was made.
    private func shelfFootnote(for folder: GameFolder) -> String {
        if let changed = state.folderLastChanged[folder.id] {
            return "EDITED \(relativeTimeString(changed).uppercased())"
        }
        return "CREATED \(relativeTimeString(folder.dateCreated).uppercased())"
    }

    /// Stat the SwiftData store once per window. Includes the -wal/-shm siblings, which can hold a
    /// meaningful share of the total right after a big import.
    private func measureStoreSizeIfNeeded() {
        guard state.storeSizeText == nil else { return }
        let realHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let base = URL(fileURLWithPath: realHome, isDirectory: true)
            .appendingPathComponent("Library/Containers/com.ogulcan.Tabia/Data/Library/Application Support/default.store")

        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let path = base.path + suffix
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        guard total > 0 else { return }
        state.storeSizeText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    // MARK: - Shelf (D6)

    private var shelfView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    shelfHeader
                    shelfGrid
                }
                .padding(.horizontal, 40).padding(.vertical, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            shelfStatusBar
        }
        .background(DS.paper)
    }

    private var shelfHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text("Library").font(AnnFont.serif(26, .semibold)).foregroundColor(DS.ink)
             + Text(" — every game you keep, shelved.").font(AnnFont.voice(24)).foregroundColor(DS.ink60))
            Text(shelfStatLine)
                .font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
        }
    }

    /// Databases here means real stores — the folders plus the reference DB. "All Games" is a view
    /// across them, not one of them.
    private var databaseCount: Int {
        database.folders.count + (referenceDatabase.gameCount > 0 ? 1 : 0)
    }

    private var shelfStatLine: String {
        var parts = ["\(databaseCount) DATABASES",
                     "\(database.libraryGameCount.formatted()) GAMES"]
        if let size = state.storeSizeText { parts.append("LOCAL — \(size)") }
        return parts.joined(separator: " · ")
    }

    private var shelfGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
            ShelfCard(name: "All Games",
                      summary: "Everything in the library, across every database.",
                      gameCount: database.libraryGameCount,
                      footnote: state.libraryLastChanged.map { "EDITED \(relativeTimeString($0).uppercased())" }) {
                navigation = .allGames
            }

            if referenceDatabase.gameCount > 0 {
                ShelfCard(name: referenceDatabase.displayName,
                          badge: .readOnly,
                          summary: "Master games for opening research. Replaced wholesale on re-download.",
                          gameCount: referenceDatabase.gameCount) {
                    navigation = .reference
                }
            }

            ForEach(database.folders.sorted { $0.name < $1.name }, id: \.id) { folder in
                ShelfCard(name: folder.name,
                          summary: folder.summary,
                          gameCount: state.folderCounts[folder.id],
                          footnote: shelfFootnote(for: folder)) {
                    navigation = .folder(folder.id)
                }
                .contextMenu {
                    Button("Edit…") { newFolderName = folder.name; newFolderSummary = folder.summary ?? ""; renamingFolder = folder }
                    Button("Export…") { exportingFolder = folder; showingExportFormatPicker = true }
                    Divider()
                    Button("Delete…", role: .destructive) {
                        folderToDelete = folder
                        showingDeleteFolderAlert = true
                    }
                }
            }

            NewShelfCard { showingNewDatabaseSheet = true }
        }
    }

    private var shelfStatusBar: some View {
        HStack {
            Text("\(databaseCount) DATABASES · \(database.libraryGameCount.formatted()) GAMES")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(height: DS.statusBarHeight)
        .background(DS.paperRaised)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }
    private func formattedGameCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Table View (drill-in)

    private var tableView: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                ledgerHeaderBar
                if hasContextActions { tableHeaderBar }

                if cachedGames.isEmpty && !isLoadingGames {
                    emptyState
                } else {
                    gamesTable
                }

                statusBar
            }

            if showingFilters {
                // Dimming backdrop
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { showingFilters = false }
                    }
                    .transition(.opacity)
            }

            filterPanel
                .padding(.vertical, 14)
                .padding(.trailing, 14)
                .offset(x: showingFilters ? 0 : 400)
                .animation(.easeInOut(duration: 0.25), value: showingFilters)
        }
    }

    // MARK: - Pagination

    /// Whether any client-side filters are active (everything except result is client-side)
    private var hasClientSideFilters: Bool {
        appliedFilter.white != nil || appliedFilter.black != nil ||
        appliedFilter.whiteEloMin != nil || appliedFilter.whiteEloMax != nil ||
        appliedFilter.blackEloMin != nil || appliedFilter.blackEloMax != nil ||
        appliedFilter.dateFrom != nil || appliedFilter.dateTo != nil ||
        appliedFilter.event != nil || appliedFilter.opening != nil
    }

    private var currentFolderId: UUID? {
        if case .folder(let id) = navigation { return id }
        return nil
    }

    private var activeSortDescriptor: SortDescriptor<GameRecord> {
        let ascending = sortAscending
        switch sortColumn {
        case .white:   return SortDescriptor(\.white, order: ascending ? .forward : .reverse)
        case .black:   return SortDescriptor(\.black, order: ascending ? .forward : .reverse)
        case .date:    return SortDescriptor(\.dateAdded, order: ascending ? .forward : .reverse)
        case .result:  return SortDescriptor(\.result, order: ascending ? .forward : .reverse)
        case .event:   return SortDescriptor(\.event, order: ascending ? .forward : .reverse)
        case .site:    return SortDescriptor(\.site, order: ascending ? .forward : .reverse)
        case .opening: return SortDescriptor(\.opening, order: ascending ? .forward : .reverse)
        }
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
        switch navigation {
        case .root, .reference: return   // reference browser paginates itself
        case .allGames, .folder: break
        }
        cachedGames = []
        dbOffset = 0
        allExhausted = false
        isLoadingGames = true

        Task { @MainActor in
            // Yield first so opening a database paints the empty ledger immediately; the count and
            // the first page arrive right after instead of holding up the transition.
            await Task.yield()
            totalCount = database.libraryGamesCount(folderId: currentFolderId)
            await Task.yield()
            performLoad(targetCount: pageSize)
        }
    }

    private func loadNextPage() {
        guard !allExhausted, !isLoadingGames else { return }
        isLoadingGames = true
        Task { @MainActor in
            performLoad(targetCount: cachedGames.count + pageSize)
        }
    }

    private func performLoad(targetCount: Int) {
        let batchSize = hasClientSideFilters ? dbBatchSize : pageSize

        while cachedGames.count < targetCount && !allExhausted {
            let page = database.fetchLibraryGames(
                folderId: currentFolderId,
                sortDescriptor: activeSortDescriptor,
                limit: batchSize,
                offset: dbOffset,
                filter: GameFilter(
                    result: appliedFilter.result,
                    whiteEloMin: appliedFilter.whiteEloMin,
                    whiteEloMax: appliedFilter.whiteEloMax,
                    blackEloMin: appliedFilter.blackEloMin,
                    blackEloMax: appliedFilter.blackEloMax
                )
            )

            // Advance by RAW rows consumed and end on the DB signal — not on the elo-filtered count,
            // which would re-read rows (duplicates) and stop early.
            dbOffset += page.rawConsumed
            if page.reachedEnd {
                allExhausted = true
            }

            if hasClientSideFilters {
                cachedGames.append(contentsOf: applyClientFilters(page.games, filter: appliedFilter))
            } else {
                cachedGames.append(contentsOf: page.games)
            }
        }

        isLoadingGames = false
    }

    private func buildGameFilter() -> GameFilter {
        GameFilter(
            white: filterWhite.isEmpty ? nil : filterWhite,
            black: filterBlack.isEmpty ? nil : filterBlack,
            result: filterResult,
            event: filterEvent.isEmpty ? nil : filterEvent,
            opening: filterOpening.isEmpty ? nil : filterOpening,
            dateFrom: filterDateFrom.isEmpty ? nil : filterDateFrom,
            dateTo: filterDateTo.isEmpty ? nil : filterDateTo,
            whiteEloMin: filterWhiteEloRange.lowerBound > 0 ? Int(filterWhiteEloRange.lowerBound) : nil,
            whiteEloMax: filterWhiteEloRange.upperBound < 3000 ? Int(filterWhiteEloRange.upperBound) : nil,
            blackEloMin: filterBlackEloRange.lowerBound > 0 ? Int(filterBlackEloRange.lowerBound) : nil,
            blackEloMax: filterBlackEloRange.upperBound < 3000 ? Int(filterBlackEloRange.upperBound) : nil
        )
    }

    private func applyClientFilters(_ games: [GameRecord], filter: GameFilter) -> [GameRecord] {
        games.filter { game in
            if let w = filter.white, !game.white.localizedCaseInsensitiveContains(w) { return false }
            if let b = filter.black, !game.black.localizedCaseInsensitiveContains(b) { return false }
            // Elo filters are now pushed to DB predicate — no client-side check needed
            if let df = filter.dateFrom, game.date < df { return false }
            if let dt = filter.dateTo, game.date > dt { return false }
            if let ev = filter.event, !game.event.localizedCaseInsensitiveContains(ev) { return false }
            if let op = filter.opening {
                let opening = game.opening ?? ""
                let eco = game.eco ?? ""
                let ecoName = eco.isEmpty ? "" : (ECODatabase.openingName(for: eco) ?? "")
                if !opening.localizedCaseInsensitiveContains(op)
                    && !eco.localizedCaseInsensitiveContains(op)
                    && !ecoName.localizedCaseInsensitiveContains(op) { return false }
            }
            return true
        }
    }

    // MARK: - Ledger header (D7)

    /// A quiet toolbar, not a hero: back to the shelf, the database name as a switcher, and the
    /// live count. The pill is the primary navigation — you jump sideways without going back first.
    private var ledgerHeaderBar: some View {
        HStack(spacing: 8) {
            Button(action: { navigation = .root }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.ink40)
                    // A fixed box centres the glyph both ways — the old text chevron sat high on its
                    // line and the uneven top/bottom padding never lined it up.
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DS.borderChip, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to the shelf — ⌘[")

            DatabaseSwitcherPill(title: currentFolderName,
                                 entries: switcherEntries,
                                 onNewDatabase: { showingNewDatabaseSheet = true },
                                 trigger: switcherTrigger)

            Text(ledgerMeta)
                .font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)

            Spacer(minLength: 8)

            filterChip
        }
        .padding(.horizontal, 28).padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    /// Clear the filter panel — its editing fields, the applied query, and the open panel — so filters
    /// don't leak across ledger sessions. Called on navigation change.
    private func resetFilters() {
        guard hasActiveFilters || hasPendingChanges || showingFilters else { return }
        filterWhite = ""; filterBlack = ""; filterResult = nil
        filterWhiteEloRange = 0...3000; filterBlackEloRange = 0...3000
        filterDateFrom = ""; filterDateTo = ""
        filterEvent = ""; filterOpening = ""
        appliedFilter = GameFilter()
        showingFilters = false
    }

    /// Filters live in the ledger header, not the masthead: they only mean anything inside a database.
    private var filterChip: some View {
        let active = hasActiveFilters
        let label = active ? "FILTERS · \(activeFilterCount)" : "FILTERS"
        let tint: Color = active ? DS.redAccent : DS.ink60
        let border: Color = active ? DS.redAccent : DS.borderChip

        return Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showingFilters.toggle() } }) {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .regular))
                Text(label).font(AnnFont.mono(10.5, bold: active))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Filter this database — ⌥⌘F")
    }

    /// Built from the cached counts, so opening the switcher costs no queries.
    private var switcherEntries: [SwitcherEntry] {
        var entries: [SwitcherEntry] = [
            SwitcherEntry(id: "all", name: "All Games", count: database.libraryGameCount,
                          isCurrent: navigation == .allGames, select: { navigation = .allGames })
        ]
        for folder in database.folders.sorted(by: { $0.name < $1.name }) {
            entries.append(SwitcherEntry(id: folder.id.uuidString, name: folder.name,
                                         count: folderCount(folder.id),
                                         isCurrent: navigation == .folder(folder.id),
                                         select: { navigation = .folder(folder.id) }))
        }
        if referenceDatabase.gameCount > 0 {
            entries.append(SwitcherEntry(id: "reference", name: referenceDatabase.displayName,
                                         count: referenceDatabase.gameCount, readOnly: true,
                                         isCurrent: navigation == .reference,
                                         select: { navigation = .reference }))
        }
        return entries
    }

    private var ledgerMeta: String {
        let n = navigation == .allGames ? database.libraryGameCount : totalCount
        var parts = ["\(n.formatted()) GAMES"]
        if navigation == .reference { parts.append("READ-ONLY") }
        return parts.joined(separator: " · ")
    }

    /// Jump straight to another database without returning to the shelf.
    // MARK: - Data

    private var currentFolderName: String {
        switch navigation {
        case .root: return "Databases"
        case .allGames: return "All Games"
        case .reference: return referenceDatabase.displayName
        case .folder(let id):
            return database.folders.first(where: { $0.id == id })?.name ?? "Database"
        }
    }

    private enum PickerType {
        case whitePlayer, blackPlayer, event, opening
    }

    // MARK: - Opening index (per-database)

    private func folderIsStale(_ folder: GameFolder) -> Bool {
        dbIndex.isStale(folder.id, currentCount: folderCount(folder.id))
    }
    @ViewBuilder
    private func indexToolbarButton(_ folder: GameFolder) -> some View {
        let building = dbIndex.indexingFolderId == folder.id
        let indexed = dbIndex.isIndexed(folder.id)
        let stale = indexed && folderIsStale(folder)
        Button(action: { startIndexing(folder) }) {
            HStack(spacing: 6) {
                if building {
                    ProgressView().controlSize(.small).tint(DS.redAccent)
                } else {
                    Image(systemName: stale ? "exclamationmark.arrow.triangle.2.circlepath"
                          : (indexed ? "checkmark.seal" : "square.stack.3d.up")).font(.system(size: 14))
                }
                Text(building ? "Indexing…" : (stale ? "Update Index" : (indexed ? "Reindex" : "Build Index")))
                    .font(AnnFont.label(12)).tracking(12 * 0.1)
            }
            .foregroundColor(stale ? DS.redAccent : (indexed ? DS.ink60 : DS.ink))
            .padding(.vertical, 6).padding(.horizontal, 14)
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(stale ? DS.redAccent.opacity(0.45) : DS.borderChip, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(dbIndex.isIndexing)
        .help(stale ? "This database changed since it was indexed — rebuild to include the new games"
              : (indexed ? "Rebuild the opening index for this database"
                 : "Index this database so it's searchable in the Opening Explorer"))
    }

    private func startIndexing(_ folder: GameFolder) {
        guard !dbIndex.isIndexing else { return }
        let games = database.gamesInFolder(folder.id)
        let pgns = games.map(\.pgn).filter { !$0.isEmpty }
        guard !pgns.isEmpty else { return }
        indexingFolder = folder
        dbIndex.buildIndex(folderId: folder.id, pgns: pgns, sourceCount: games.count)
    }

    // MARK: - Table Header Bar

    private var tableHeaderBar: some View {
        HStack(spacing: 12) {
            Spacer()

            // Situational actions for a selected database (index + delete).
            HStack(spacing: 8) {
                if case .folder(let id) = navigation,
                   let folder = database.folders.first(where: { $0.id == id }) {
                    indexToolbarButton(folder)

                    Button(action: {
                        folderToDelete = folder
                        showingDeleteFolderAlert = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash").font(.system(size: 14))
                            Text("Delete").font(AnnFont.label(12)).tracking(12 * 0.1)
                        }
                        .foregroundColor(DS.redAccent)
                        .padding(.vertical, 6).padding(.horizontal, 14)
                        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.redAccent.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

            }
        }
        .padding(.horizontal, 28)
        .frame(height: 52)
        .background(DS.paper)
    }

    /// The content toolbar only carries situational actions now (Filters + Import live in the masthead).
    private var hasContextActions: Bool {
        if case .folder = navigation { return true }
        return false
    }

    // MARK: - Filter Panel (slide-in side panel)

    private var filterPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Filters")
                    .font(AnnFont.serif(18, .semibold))
                    .foregroundColor(DS.ink)

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) { showingFilters = false }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(DS.ink40)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(DS.chrome)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            // Body
            ScrollView {
                VStack(spacing: 0) {
                    // Result — the most common quick filter, so it sits at the top.
                    filterSection(title: "Result") {
                        HStack(spacing: 6) {
                            resultOption("All", nil)
                            resultOption("1-0", "1-0")
                            resultOption("½-½", "1/2-1/2")
                            resultOption("0-1", "0-1")
                        }
                    }

                    // White Player
                    filterSection(title: "White Player") {
                        filterSearchField(text: $state.filterWhite, placeholder: "Search players...")
                        filterSelectableList(
                            pickerType: .whitePlayer,
                            selectedValue: filterWhite,
                            onSelect: { filterWhite = $0 }
                        )
                    }

                    // Black Player
                    filterSection(title: "Black Player") {
                        filterSearchField(text: $state.filterBlack, placeholder: "Search players...")
                        filterSelectableList(
                            pickerType: .blackPlayer,
                            selectedValue: filterBlack,
                            onSelect: { filterBlack = $0 }
                        )
                    }

                    // White Elo (eloContent includes its own header row)
                    eloContent(label: "White Elo", range: $state.filterWhiteEloRange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }

                    // Black Elo
                    eloContent(label: "Black Elo", range: $state.filterBlackEloRange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }

                    // Tournament
                    filterSection(title: "Tournament") {
                        filterSearchField(text: $state.filterEvent, placeholder: "Search tournaments...")
                        filterSelectableList(
                            pickerType: .event,
                            selectedValue: filterEvent,
                            onSelect: { filterEvent = $0 }
                        )
                    }

                    // Opening (last section, no bottom border)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Opening")
                            .font(AnnFont.label(9.5))
                            .foregroundColor(DS.ink40)
                            .kerning(1.3)

                        filterSearchField(text: $state.filterOpening, placeholder: "Search openings...")
                        filterSelectableList(
                            pickerType: .opening,
                            selectedValue: filterOpening,
                            onSelect: { filterOpening = $0 }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }

            // Footer
            HStack(spacing: 12) {
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { clearFilters() } }) {
                    Text("CLEAR ALL")
                        .font(AnnFont.label(10))
                        .tracking(10 * 0.1)
                        .foregroundColor(DS.ink60)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { applyFilters() }) {
                    Text(activeFilterCount > 0
                         ? "Apply — \(activeFilterCount) Filter\(activeFilterCount == 1 ? "" : "s")"
                         : "Apply")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
            .background(DS.chrome)
        }
        .frame(width: 340)
        .background(DS.paper)
        .clipShape(RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous)
                .strokeBorder(DS.windowBorder, lineWidth: 1)
        )
        // Flat aesthetic: one soft, downward drop shadow — no horizontal "wall" offset, no glass.
        .shadow(color: DS.glassShadowColor, radius: 22, x: 0, y: 10)
    }

    // MARK: - Filter Section

    /// One segment of the Result filter. `value` matches GameRecord.result ("1-0"/"1/2-1/2"/"0-1"),
    /// or nil for "All". Selecting toggles the pending filterResult; Apply commits it like the rest.
    private func resultOption(_ label: String, _ value: String?) -> some View {
        let selected = filterResult == value
        return Button(action: { filterResult = value }) {
            Text(label)
                .font(AnnFont.mono(12, bold: selected))
                .foregroundColor(selected ? DS.onInk : DS.ink60)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? DS.ink : DS.fieldBg,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.clear : DS.borderChip, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AnnFont.label(9.5))
                .foregroundColor(DS.ink40)
                .kerning(1.3)

            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    // MARK: - Filter Search Field

    private func filterSearchField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.ink25)
                .font(.system(size: 13))

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(AnnFont.mono(10.5))

            if !text.wrappedValue.isEmpty {
                Button(action: { text.wrappedValue = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.ink25)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                .fill(DS.fieldBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                .strokeBorder(DS.borderChip, lineWidth: 1)
        )
    }

    // MARK: - Filter Selectable List

    private func filterSelectableList(pickerType: PickerType, selectedValue: String, onSelect: @escaping (String) -> Void) -> some View {
        FilterInlineList(
            database: database,
            cachedNameType: pickerNameType(pickerType),
            searchQuery: selectedValue,
            selectedValue: selectedValue,
            onSelect: onSelect
        )
    }

    // MARK: - Elo Content

    private func eloContent(label: String, range: Binding<ClosedRange<Double>>) -> some View {
        let lo = Int(range.wrappedValue.lowerBound)
        let hi = Int(range.wrappedValue.upperBound)
        let isActive = !(lo == 0 && hi == 3000)

        return VStack(spacing: 10) {
            // Title + range on same row (matches Pencil whiteEloHeader/blackEloHeader)
            HStack {
                Text(label)
                    .font(AnnFont.label(9.5))
                    .foregroundColor(DS.ink40)
                    .kerning(1.3)
                Spacer()
                Text("\(lo) – \(hi)")
                    .font(AnnFont.mono(10.5))
                    .foregroundColor(isActive ? DS.accent : DS.ink60)
            }

            DualSlider(range: range, bounds: 0...3000, step: 50)
                .frame(height: 20)
        }
    }

    private func pickerNameType(_ type: PickerType) -> String {
        switch type {
        case .whitePlayer, .blackPlayer: return "player"
        case .event: return "event"
        case .opening: return "opening"
        }
    }

    private func applyFilters() {
        appliedFilter = buildGameFilter()
        reloadGames()
    }

    private func clearFilters() {
        filterWhite = ""
        filterBlack = ""
        filterResult = nil
        filterWhiteEloRange = 0...3000
        filterBlackEloRange = 0...3000
        filterDateFrom = ""
        filterDateTo = ""
        filterEvent = ""
        filterOpening = ""
        appliedFilter = GameFilter()
        reloadGames()
    }

    // MARK: - Table

    private var gamesTable: some View {
        // One width read drives both the header and every row, so their columns can't drift apart.
        GeometryReader { geo in
            gamesTable(cols: LedgerColumns(totalWidth: geo.size.width))
        }
    }

    private func gamesTable(cols: LedgerColumns) -> some View {
        GameTableList(
            games: cachedGames,
            selectedGameIds: $state.selectedGameIds,
            selectionAnchor: $state.selectedGame,
            hasMore: !allExhausted,
            onOpen: onGameSelected,
            onLoadMore: loadNextPage,
            header: { tableHeader(cols) },
            row: { game, isAlternate in tableRow(game, isAlternate: isAlternate, cols: cols) },
            menu: { game in
                Button("Open") { onGameSelected(game) }
                Button("Analyze Game") { onReviewGame(game) }
                Divider()
                moveToFolderMenu(gameIds: selectedGameIds.count > 1 ? selectedGameIds : [game.id])
                Divider()
                Button("Delete", role: .destructive) {
                    if selectedGameIds.count > 1 {
                        for id in selectedGameIds {
                            if let g = database.game(withId: id) {
                                database.deleteGame(g)
                            }
                        }
                        selectedGameIds.removeAll()
                        reloadGames()
                    } else {
                        database.deleteGame(game)
                        reloadGames()
                    }
                }
            }
        )
    }

    private func toggleSort(_ column: SortColumn) {
        if sortColumn == column { sortAscending.toggle() }
        else { sortColumn = column; sortAscending = column != .date }
    }

    @ViewBuilder
    private func sortArrow(_ column: SortColumn) -> some View {
        if sortColumn == column {
            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DS.accent)
        }
    }

    // Header and row use the EXACT same frame modifiers per column.
    // Fixed columns: .frame(width: X, alignment: .leading)
    // Flex columns:  .frame(maxWidth: .infinity, alignment: .leading)

    /// "(91.4)" accuracy suffix shown next to a player's name for a reviewed game (empty otherwise).
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

    /// Opening name for the row (ECO is shown separately as a chip), or "—" when nothing is known.
    private func openingText(_ game: GameRecord) -> String {
        if let o = game.opening, !o.isEmpty { return o }
        if let e = game.eco, !e.isEmpty { return "" }   // ECO chip stands alone
        return "—"
    }
    // MARK: - Ledger table (D7)

    private func tableHeader(_ cols: LedgerColumns) -> some View {
        HStack(spacing: LedgerColumns.gap) {
            headerCell("WHITE", .white, width: cols.white)
            headerCell("BLACK", .black, width: cols.black)
            headerCell("RESULT", .result, width: cols.result)
            headerCell("OPENING", .opening, width: cols.opening)
            headerCell("EVENT", .event, width: cols.event)
            headerCell("DATE", .date, width: cols.date)
            // Annotation mark and the action button carry no label.
            Color.clear.frame(width: cols.mark, height: 1)
            Color.clear.frame(width: cols.action, height: 1)
        }
        .padding(.horizontal, LedgerColumns.hPadding)
        .padding(.top, 12).padding(.bottom, 8)
        .background(DS.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private func headerCell(_ title: String, _ column: SortColumn, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(AnnFont.label(9)).tracking(9 * 0.14)
                .foregroundColor(DS.ink40)
            if sortColumn == column {
                Text(sortAscending ? "↑" : "↓")
                    .font(AnnFont.mono(9)).foregroundColor(DS.ink40)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { toggleSort(column) }
    }

    private func tableRow(_ game: GameRecord, isAlternate: Bool = false, cols: LedgerColumns) -> some View {
        LedgerRowChrome(isAlternate: isAlternate, isSelected: state.selectedGameIds.contains(game.id)) {
            tableRowCells(game, cols: cols)
        }
    }

    private func tableRowCells(_ game: GameRecord, cols: LedgerColumns) -> some View {
        HStack(spacing: LedgerColumns.gap) {
            playerCell(game.white, isWhite: true, width: cols.white)
            playerCell(game.black, isWhite: false, width: cols.black)

            Text(resultDisplay(game.result))
                .font(AnnFont.mono(11, bold: true))
                .foregroundColor(DS.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(DS.borderChip, lineWidth: 1))
                .frame(width: cols.result)

            HStack(spacing: 6) {
                if let eco = game.eco, !eco.isEmpty {
                    Text(eco)
                        .font(AnnFont.mono(10, bold: true))
                        .foregroundColor(DS.ink60)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(DS.borderChip, lineWidth: 1))
                }
                Text(openingText(game))
                    .font(AnnFont.voice(13.5)).foregroundColor(DS.inkSoft)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(width: cols.opening, alignment: .leading)

            Text(cleanField(game.event))
                .font(AnnFont.serif(13.5)).foregroundColor(DS.ink60)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: cols.event, alignment: .leading)

            Text(game.date.isEmpty ? formatDate(game.dateAdded) : game.date)
                .font(AnnFont.mono(10.5)).foregroundColor(DS.ink60)
                .lineLimit(1)
                .frame(width: cols.date, alignment: .leading)

            // Annotation mark — present only when the game carries notes.
            Text(game.tags.isEmpty ? "" : "※")
                .font(AnnFont.mono(11)).foregroundColor(DS.redAccent)
                .frame(width: cols.mark)

            analyzeCell(game).frame(width: cols.action)
        }
    }

    private func playerCell(_ name: String, isWhite: Bool, width: CGFloat) -> some View {
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

    /// Reviewed games show their accuracy dots; unreviewed ones offer the review.
    @ViewBuilder
    private func analyzeCell(_ game: GameRecord) -> some View {
        if let data = game.analysisData {
            accDotsBadge(white: data.whiteAccuracy, black: data.blackAccuracy)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Button(action: { onReviewGame(game) }) {
                Text("ANALYZE")
                    .font(AnnFont.label(9)).tracking(9 * 0.1)
                    .foregroundColor(DS.redAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DS.redAccent.opacity(0.45), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    private func moveToFolderMenu(gameIds: Set<UUID>) -> some View {
        Menu("Move to...") {
            ForEach(database.folders.sorted(by: { $0.name < $1.name })) { folder in
                Button(folder.name) {
                    database.moveGames(gameIds, toFolder: folder.id)
                    selectedGameIds.removeAll()
                }
            }
            Divider()
            Button("New Database…") {
                newDatabaseGameIds = gameIds
                newDatabaseName = ""
                showingNewDatabaseForGames = true
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if totalCount == 0 && !hasActiveFilters {
                Image(systemName: "cylinder")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(DS.textTertiary)

                VStack(spacing: 8) {
                    Text(currentFolderId == nil ? "No Games in Library" : "This database is empty")
                        .font(AnnFont.serif(20, .semibold))
                        .foregroundColor(DS.textPrimary)

                    Text(currentFolderId == nil
                         ? "Import PGN files to start organizing your chess games"
                         : "Import a PGN file to fill it.")
                        .font(AnnFont.serif(13))
                        .foregroundColor(DS.textTertiary)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                // Inside an empty database you want to fill THIS one, not make another.
                Button(action: {
                    pendingImportFolderId = currentFolderId
                    showingImportPicker = true
                }) {
                    Text("Import PGN")
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(DS.accent)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(DS.textTertiary)

                Text("No games match your filters")
                    .font(AnnFont.serif(13))
                    .foregroundColor(DS.textSecondary)

                Button("Clear Filters") { clearFilters() }
                    .font(AnnFont.label(12))
                    .tracking(12 * 0.1)
                    .buttonStyle(GlassButtonStyle())
                    .controlSize(.small)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var sortColumnLabel: String {
        switch sortColumn {
        case .white: return "WHITE"
        case .black: return "BLACK"
        case .date: return "DATE"
        case .result: return "RESULT"
        case .event: return "EVENT"
        case .site: return "SITE"
        case .opening: return "OPENING"
        }
    }

    /// "MY GAMES — 1,031 GAMES · 2 FILTERS ACTIVE · SEARCH · SORTED BY DATE"
    private var statusLeftText: String {
        var parts = ["\(currentFolderName.uppercased()) — \(totalCount.formatted()) GAMES"]
        if activeFilterCount > 0 {
            parts.append("\(activeFilterCount) FILTER\(activeFilterCount == 1 ? "" : "S") ACTIVE")
        }
        parts.append("SORTED BY \(sortColumnLabel)")
        return parts.joined(separator: " · ")
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(statusLeftText)
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
                .lineLimit(1)

            if isLoadingGames { ProgressView().scaleEffect(0.45) }

            Spacer()

            if selectedGameIds.count > 1 {
                Text("\(selectedGameIds.count) SELECTED")
                    .font(AnnFont.mono(9.5)).foregroundColor(DS.redAccent)
            }

            Text("⌘⇧O  SWITCH DATABASE")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink25)
        }
        .padding(.horizontal, 28)
        .frame(height: DS.statusBarHeight)
        .background(DS.paperRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private func resultDisplay(_ result: String) -> String {
        switch result {
        case "1/2-1/2": return "1/2"
        default: return result
        }
    }

    private func resultColor(_ result: String) -> Color {
        switch result {
        case "1-0": return DS.textPrimary
        case "0-1": return DS.textPrimary
        case "1/2-1/2": return DS.textTertiary
        default: return DS.textTertiary
        }
    }

    private func cleanField(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed == "?" || trimmed == "-" || trimmed.isEmpty { return "-" }
        return trimmed
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private enum ExportFormat {
        case pgn, sqlite
    }

    private func exportFolder(_ folder: GameFolder, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = folder.name

        switch format {
        case .pgn:
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "\(folder.name).pgn"
        case .sqlite:
            panel.allowedContentTypes = [.database]
            panel.nameFieldStringValue = "\(folder.name).db3"
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let batchSize = 500
                var offset = 0
                var totalExported = 0

                switch format {
                case .pgn:
                    // Write in batches using FileHandle append
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: url)
                    defer { handle.closeFile() }
                    while true {
                        let batch = database.gamesInFolder(folder.id, limit: batchSize, offset: offset)
                        if batch.isEmpty { break }
                        for game in batch {
                            if let data = (game.pgn + "\n\n").data(using: .utf8) {
                                handle.write(data)
                            }
                        }
                        totalExported += batch.count
                        offset += batch.count
                        if batch.count < batchSize { break }
                    }

                case .sqlite:
                    // Fetch in batches and insert incrementally
                    var allGames: [GameRecord] = []
                    while true {
                        let batch = database.gamesInFolder(folder.id, limit: batchSize, offset: offset)
                        if batch.isEmpty { break }
                        allGames.append(contentsOf: batch)
                        totalExported += batch.count
                        offset += batch.count
                        if batch.count < batchSize { break }
                    }
                    try database.exportAsSQLite(games: allGames, to: url)
                }

                importAlert = ImportAlertInfo(message: "Exported \(totalExported) games to \(url.lastPathComponent)", isError: false)
            } catch {
                importAlert = ImportAlertInfo(message: error.localizedDescription, isError: true)
            }
        }
        exportingFolder = nil
    }

    // MARK: - Actions

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            pendingImportURLs = urls
            showingPGNImportSheet = true
        case .failure(let error):
            importAlert = ImportAlertInfo(message: error.localizedDescription, isError: true)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                handled = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        collectedURLs.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !collectedURLs.isEmpty {
                pendingImportURLs = collectedURLs
                showingPGNImportSheet = true
            }
        }

        return handled
    }
}
