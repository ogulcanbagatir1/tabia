import SwiftUI

struct DatabaseBrowserView: View {
    @EnvironmentObject var database: GameDatabase
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    @ObservedObject private var dbIndex = DatabaseIndex.shared
    var onGameSelected: (GameRecord) -> Void
    var onReferenceGameSelected: (String) -> Void = { _ in }

    @State private var indexingFolder: GameFolder?
    @State private var navigation: Navigation = .allGames
    @State private var selectedGameIds: Set<UUID> = []
    @State private var selectedGame: GameRecord?
    @State private var showingImportPicker = false
    @State private var showingPGNImportSheet = false
    @State private var pendingImportURLs: [URL] = []
    @State private var pendingImportFolderId: UUID? = nil
    @State private var importAlert: ImportAlertInfo?
    @State private var showingNewDatabaseSheet = false
    @State private var newFolderName = ""
    @State private var renamingFolder: GameFolder?
    @State private var showingDeleteFolderAlert = false
    @State private var folderToDelete: GameFolder?
    @State private var exportingFolder: GameFolder?
    @State private var showingExportFormatPicker = false
    @State private var isDropTargeted = false
    @State private var showingFilters = false
    @State private var rootSearchText = ""

    // Filters
    @State private var filterWhite: String = ""
    @State private var filterBlack: String = ""
    @State private var filterResult: String? = nil
    @State private var filterWhiteEloRange: ClosedRange<Double> = 0...3000
    @State private var filterBlackEloRange: ClosedRange<Double> = 0...3000
    @State private var filterDateFrom: String = ""
    @State private var filterDateTo: String = ""
    @State private var filterEvent: String = ""
    @State private var filterOpening: String = ""

    // Picker popovers
    @State private var showingWhitePlayerPicker = false
    @State private var showingBlackPlayerPicker = false
    @State private var showingOpeningPicker = false
    @State private var showingEventPicker = false

    // Applied filter (what's actually used for queries)
    @State private var appliedFilter = GameFilter()

    // Filter card height (measured from tallest card)
    @State private var filterCardHeight: CGFloat = 0

    // Sorting
    @State private var sortColumn: SortColumn = .date
    @State private var sortAscending = false

    // Pagination
    @State private var cachedGames: [GameRecord] = []
    @State private var totalCount: Int = 0
    @State private var dbOffset: Int = 0
    @State private var allExhausted = false
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                librarySidebar
                    .frame(width: 280)
                    .background(DS.chrome)
                    .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }
                Group {
                    switch navigation {
                    case .reference:
                        ReferenceBrowseView(
                            onBack: { navigation = .allGames },
                            onOpen: { onReferenceGameSelected($0) }
                        )
                    default:
                        tableView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            NewDatabaseSheet { name, pgnURLs in
                showingNewDatabaseSheet = false
                let folder = database.createFolder(name: name)
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
        .alert("Rename Database", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Database name", text: $newFolderName)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Rename") {
                if let folder = renamingFolder {
                    database.renameFolder(folder, to: newFolderName)
                }
                renamingFolder = nil
            }
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
        .onChange(of: navigation) { _, _ in reloadGames() }
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

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    AnnLabel("Library", size: 10, tracking: 0.14, bold: true, color: DS.ink40)
                        .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 8)

                    sidebarRow(icon: "tray.full", name: "All Games", count: database.libraryGameCount,
                               isSelected: navigation == .allGames) { navigation = .allGames }

                    ForEach(database.folders.sorted { $0.name < $1.name }, id: \.id) { folder in
                        sidebarRow(icon: "cylinder", name: folder.name, count: database.gamesInFolderCount(folder.id),
                                   subtitle: folderIndexSubtitle(folder),
                                   isSelected: navigation == .folder(folder.id)) { navigation = .folder(folder.id) }
                            .contextMenu {
                                Button(dbIndex.isIndexed(folder.id) ? "Rebuild Opening Index" : "Build Opening Index") {
                                    startIndexing(folder)
                                }
                                .disabled(dbIndex.isIndexing)
                                Button("Rename…") { newFolderName = folder.name; renamingFolder = folder }
                                Button("Export…") { exportingFolder = folder; showingExportFormatPicker = true }
                                Divider()
                                Button("Delete…", role: .destructive) {
                                    folderToDelete = folder
                                    showingDeleteFolderAlert = true
                                }
                            }
                    }

                    if referenceDatabase.gameCount > 0 {
                        sidebarRow(icon: "books.vertical.fill", name: referenceDatabase.displayName,
                                   count: referenceDatabase.gameCount, subtitle: "read-only",
                                   isSelected: navigation == .reference) { navigation = .reference }
                    }

                }
                .padding(.horizontal, 8)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("The reference database is read-only — a re-download replaces it.")
                    .font(AnnFont.voice(11.5)).foregroundColor(DS.ink40)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(database.folders.count + 1) DATABASES · \(formattedGameCount(database.libraryGameCount)) GAMES")
                    .font(AnnFont.mono(9)).foregroundColor(DS.ink25)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
    }

    private func sidebarRow(icon: String, name: String, count: Int, subtitle: String? = nil,
                            isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13))
                    .foregroundColor(isSelected ? DS.redAccent : DS.ink40).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(AnnFont.serif(13.5, .medium)).foregroundColor(DS.ink).lineLimit(1)
                    if let subtitle {
                        Text(subtitle.uppercased()).font(AnnFont.label(8)).tracking(0.8).foregroundColor(DS.ink40)
                    }
                }
                Spacer(minLength: 6)
                Text("\(count)").font(AnnFont.mono(10)).foregroundColor(DS.ink40)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isSelected ? DS.selectedMove : Color.clear, in: RoundedRectangle(cornerRadius: DS.rControl))
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1).fill(DS.redAccent)
                        .frame(width: 2.5).padding(.vertical, 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    private var rootView: some View {
        VStack(spacing: 0) {
            // Card grid or empty state
            if database.libraryGameCount == 0 && database.folders.isEmpty {
                emptyState
            } else {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "cylinder")
                        .font(.system(size: 18))
                        .foregroundColor(DS.ink60)
                    Text("Databases")
                        .font(AnnFont.serif(16, .semibold))
                        .foregroundColor(DS.ink)
                }

                Spacer()

                HStack(spacing: 10) {
                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(DS.ink25)
                        TextField("Search databases...", text: $rootSearchText)
                            .textFieldStyle(.plain)
                            .font(AnnFont.serif(12))
                        if !rootSearchText.isEmpty {
                            Button(action: { rootSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(DS.ink25)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 220, height: 32)
                    .background(DS.fieldBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DS.hairline, lineWidth: 1)
                    )

                    // Create Database button
                    Button(action: { showingNewDatabaseSheet = true }) {
                        Text("Create Database")
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 28)
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 400, maximum: 500), spacing: 20)
                ], spacing: 16) {
                    // All Games card
                    if rootSearchText.isEmpty || "all games".localizedCaseInsensitiveContains(rootSearchText) {
                        rootDatabaseCard(
                            name: "All Games",
                            subtitle: "All databases",
                            icon: "tray.full",
                            gameCount: database.libraryGameCount,
                            color: DS.accent,
                            lastModified: nil
                        ) {
                            navigation = .allGames
                        }
                    }

                    // Reference database (read-only, backed by SQLite) — appears once downloaded.
                    if referenceDatabase.gameCount > 0,
                       rootSearchText.isEmpty || referenceDatabase.displayName.localizedCaseInsensitiveContains(rootSearchText) {
                        rootDatabaseCard(
                            name: referenceDatabase.displayName,
                            subtitle: "Reference · read-only",
                            icon: "books.vertical.fill",
                            gameCount: referenceDatabase.gameCount,
                            color: DS.accent,
                            lastModified: nil
                        ) {
                            navigation = .reference
                        }
                    }

                    ForEach(Array(filteredRootFolders.enumerated()), id: \.element.id) { index, folder in
                        rootDatabaseCard(
                            name: folder.name,
                            subtitle: nil,
                            icon: "cylinder",
                            gameCount: database.gamesInFolderCount(folder.id),
                            color: rootCardColor(for: index),
                            lastModified: folder.dateCreated
                        ) {
                            navigation = .folder(folder.id)
                        }
                        .contextMenu {
                            Button("Rename...") {
                                newFolderName = folder.name
                                renamingFolder = folder
                            }
                            Button("Export...") {
                                exportingFolder = folder
                                showingExportFormatPicker = true
                            }
                            Divider()
                            Button("Delete...", role: .destructive) {
                                folderToDelete = folder
                                showingDeleteFolderAlert = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
            .frame(maxHeight: .infinity)
            } // end else (has games/folders)

            // Status bar
            rootStatusBar
        }
    }

    private var filteredRootFolders: [GameFolder] {
        let sorted = database.folders.sorted(by: { $0.name < $1.name })
        if rootSearchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(rootSearchText) }
    }

    private func rootCardColor(for index: Int) -> Color {
        let colors: [Color] = [DS.accentGreen, DS.accentOrange, DS.accentPurple, DS.accentRed, DS.accentTeal, DS.accent]
        return colors[index % colors.count]
    }

    private func rootDatabaseCard(
        name: String,
        subtitle: String?,
        icon: String,
        gameCount: Int,
        color: Color,
        lastModified: Date?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Card Header
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(AnnFont.serif(14, .semibold))
                            .foregroundColor(DS.ink)
                            .lineLimit(1)
                        if let subtitle = subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(AnnFont.serif(11))
                                .foregroundColor(DS.ink40)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DS.hairline).frame(height: 1)
                }

                // Card Body
                VStack(spacing: 12) {
                    HStack {
                        Text("Games")
                            .font(AnnFont.serif(12))
                            .foregroundColor(DS.ink40)
                        Spacer()
                        Text(formattedGameCount(gameCount))
                            .font(AnnFont.mono(13, bold: true))
                            .foregroundColor(DS.ink)
                    }

                    HStack {
                        Text("Last modified")
                            .font(AnnFont.serif(12))
                            .foregroundColor(DS.ink40)
                        Spacer()
                        Text(lastModified != nil ? relativeTimeString(lastModified!) : "-")
                            .font(AnnFont.mono(12))
                            .foregroundColor(DS.ink60)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.paperRaised)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.19), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var rootStatusBar: some View {
        HStack {
            Text("\(database.folders.count + 1) databases · \(formattedGameCount(database.libraryGameCount)) games")
                .font(AnnFont.mono(11))
                .foregroundColor(DS.ink25)

            Spacer()

            let formatter = DateFormatter()
            let _ = formatter.dateFormat = "MMM d, yyyy"
            Text("Last synced: \(formatter.string(from: Date()))")
                .font(AnnFont.mono(11))
                .foregroundColor(DS.ink25)
        }
        .padding(.horizontal, 28)
        .frame(height: 28)
        .background(DS.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
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
                tableHeaderBar

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
            totalCount = database.libraryGamesCount(folderId: currentFolderId)
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
        dbIndex.isStale(folder.id, currentCount: database.gamesInFolderCount(folder.id))
    }

    private func folderIndexSubtitle(_ folder: GameFolder) -> String? {
        if dbIndex.indexingFolderId == folder.id { return "indexing…" }
        guard dbIndex.isIndexed(folder.id) else { return nil }
        return folderIsStale(folder) ? "index out of date" : "indexed"
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

            // Delete (only when a specific database is selected) + Filter + Import buttons
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

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showingFilters.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                        Text("Filters")
                            .font(AnnFont.label(12))
                            .tracking(12 * 0.1)
                    }
                    .foregroundColor(DS.ink60)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DS.borderChip, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: { showingImportPicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 14))
                        Text("Import PGN")
                            .font(AnnFont.label(12))
                            .tracking(12 * 0.1)
                    }
                    .foregroundColor(DS.ink)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 56)
        .background(DS.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
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
                    // White Player
                    filterSection(title: "White Player") {
                        filterSearchField(text: $filterWhite, placeholder: "Search players...")
                        filterSelectableList(
                            pickerType: .whitePlayer,
                            selectedValue: filterWhite,
                            onSelect: { filterWhite = $0 }
                        )
                    }

                    // Black Player
                    filterSection(title: "Black Player") {
                        filterSearchField(text: $filterBlack, placeholder: "Search players...")
                        filterSelectableList(
                            pickerType: .blackPlayer,
                            selectedValue: filterBlack,
                            onSelect: { filterBlack = $0 }
                        )
                    }

                    // White Elo (eloContent includes its own header row)
                    eloContent(label: "White Elo", range: $filterWhiteEloRange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }

                    // Black Elo
                    eloContent(label: "Black Elo", range: $filterBlackEloRange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }

                    // Tournament
                    filterSection(title: "Tournament") {
                        filterSearchField(text: $filterEvent, placeholder: "Search tournaments...")
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

                        filterSearchField(text: $filterOpening, placeholder: "Search openings...")
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
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(cachedGames.enumerated()), id: \.element.id) { index, game in
                        VStack(spacing: 0) {
                            tableRow(game, isAlternate: index % 2 == 1)
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
                                    } else if NSEvent.modifierFlags.contains(.shift), let last = selectedGame {
                                        let list = cachedGames
                                        if let startIdx = list.firstIndex(where: { $0.id == last.id }),
                                           let endIdx = list.firstIndex(where: { $0.id == game.id }) {
                                            let range = min(startIdx, endIdx)...max(startIdx, endIdx)
                                            for i in range {
                                                selectedGameIds.insert(list[i].id)
                                            }
                                        }
                                    } else {
                                        selectedGameIds = [game.id]
                                    }
                                    selectedGame = game
                                }
                                .onAppear {
                                    if game.id == cachedGames.last?.id && !allExhausted {
                                        loadNextPage()
                                    }
                                }
                                .contextMenu {
                                    Button("Open") { onGameSelected(game) }
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
                        }
                    }

                    // Loading indicator at bottom
                    if !allExhausted {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                        .onAppear { loadNextPage() }
                    }
                } header: {
                    tableHeader
                }
            }
        }
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

    private var tableHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) { Text("White").font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.textSecondary); sortArrow(.white) }
                .padding(.horizontal, 8)
                .frame(width: 180, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { toggleSort(.white) }

            HStack(spacing: 4) { Text("Black").font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.textSecondary); sortArrow(.black) }
                .padding(.horizontal, 8)
                .frame(width: 180, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { toggleSort(.black) }

            HStack(spacing: 4) { Text("Result").font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.textSecondary); sortArrow(.result) }
                .padding(.horizontal, 8)
                .frame(width: 80, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { toggleSort(.result) }

            HStack(spacing: 4) { Text("Opening").font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.textSecondary); sortArrow(.opening) }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { toggleSort(.opening) }

            HStack(spacing: 4) { Text("Event").font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.textSecondary); sortArrow(.event) }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { toggleSort(.event) }

            HStack(spacing: 4) { Text("Date").font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.textSecondary); sortArrow(.date) }
                .padding(.horizontal, 8)
                .frame(width: 100, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { toggleSort(.date) }
        }
        .padding(.horizontal, 24)
        .frame(height: 34)
        .background(DS.bgSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private func tableRow(_ game: GameRecord, isAlternate: Bool = false) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(DS.boardWhitePiece).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(DS.borderStrong, lineWidth: 1))
                Text(game.white).font(AnnFont.serif(12)).foregroundColor(DS.textPrimary).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: 180, alignment: .leading)

            HStack(spacing: 6) {
                Circle().fill(DS.boardBlackPiece).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(DS.borderStrong, lineWidth: 1))
                Text(game.black).font(AnnFont.serif(12)).foregroundColor(DS.textPrimary).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: 180, alignment: .leading)

            Text(resultDisplay(game.result))
                .font(AnnFont.mono(12, bold: true))
                .foregroundColor(resultColor(game.result))
                .padding(.horizontal, 8)
                .frame(width: 80, alignment: .leading)

            Text(game.opening ?? game.eco ?? "-")
                .font(AnnFont.serif(12)).foregroundColor(DS.textSecondary).lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(cleanField(game.event))
                .font(AnnFont.serif(12)).foregroundColor(DS.textSecondary).lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(game.date.isEmpty ? formatDate(game.dateAdded) : game.date)
                .font(AnnFont.mono(11)).foregroundColor(DS.textTertiary).lineLimit(1)
                .padding(.horizontal, 8)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .frame(height: 38)
        .background(selectedGameIds.contains(game.id) ? DS.accentLight : (isAlternate ? DS.bgSurface : Color.clear))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.borderSubtle).frame(height: 1)
        }
        .contentShape(Rectangle())
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
            Button("New Database...") {
                showingNewDatabaseSheet = true
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
                    Text("No Games in Library")
                        .font(AnnFont.serif(20, .semibold))
                        .foregroundColor(DS.textPrimary)

                    Text("Import PGN files or create a new database to start organizing your chess games")
                        .font(AnnFont.serif(13))
                        .foregroundColor(DS.textTertiary)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                Button(action: { showingNewDatabaseSheet = true }) {
                    Text("Create Database")
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

    private var statusBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("\(cachedGames.count)\(allExhausted ? "" : "+") games")
                    .font(AnnFont.mono(11))
                    .foregroundColor(DS.ink60)

                if isLoadingGames {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Text("Synced")
                    .font(AnnFont.label(10))
                    .tracking(10 * 0.1)
                    .foregroundColor(DS.semOnline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(DS.semOnline.opacity(0.19), in: RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            if selectedGameIds.count > 1 {
                Text("\(selectedGameIds.count) selected")
                    .font(AnnFont.mono(10))
                    .foregroundColor(DS.redAccent)
            }

            Text("Sorted by date")
                .font(AnnFont.mono(11))
                .foregroundColor(DS.ink25)
        }
        .padding(.horizontal, 28)
        .frame(height: 30)
        .background(DS.chrome)
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

// MARK: - Picker Popover Content

/// Self-contained popover with its own state so data loads reliably on appear.
private struct PickerPopoverContent: View {
    let title: String
    let database: GameDatabase
    let cachedNameType: String
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var items: [String] = []

    /// All unique opening names from the ECO database (computed once)
    private static let allOpeningNames: [String] = {
        var names = Set(ECODatabase.openings.values)
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    private func fetchItems(query: String) -> [String] {
        if cachedNameType == "opening" {
            // Use opening book: merge ECO database names with any cached opening names from imports
            let cached = database.cachedNames(type: "opening", query: query)
            let q = query.lowercased()
            let ecoNames: [String]
            if q.isEmpty {
                ecoNames = Self.allOpeningNames
            } else {
                ecoNames = Self.allOpeningNames.filter { $0.lowercased().contains(q) }
            }
            // Merge and deduplicate, keeping sorted order
            var seen = Set<String>()
            var merged: [String] = []
            for name in (cached + ecoNames) {
                if seen.insert(name).inserted {
                    merged.append(name)
                }
            }
            return merged.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } else {
            return database.cachedNames(type: cachedNameType, query: query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(title)
                .font(AnnFont.serif(12, .semibold))
                .foregroundColor(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AnnFont.serif(12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.bgSecondary)
            .cornerRadius(6)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items, id: \.self) { name in
                        Button(action: { onSelect(name) }) {
                            Text(name)
                                .font(AnnFont.serif(12))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().opacity(0.3)
                    }
                }
            }
            .frame(height: 320)
            .overlay {
                if items.isEmpty {
                    Text("No results")
                        .font(AnnFont.serif(11))
                        .foregroundColor(DS.textSecondary)
                }
            }
        }
        .frame(width: 280)
        .onAppear {
            items = fetchItems(query: "")
        }
        .onChange(of: searchText) { _, newValue in
            items = fetchItems(query: newValue)
        }
    }
}

// MARK: - Filter Inline List

private struct FilterInlineList: View {
    let database: GameDatabase
    let cachedNameType: String
    let searchQuery: String
    let selectedValue: String
    let onSelect: (String) -> Void

    @State private var items: [String] = []

    private static let allOpeningNames: [String] = {
        var names = Set(ECODatabase.openings.values)
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    private func fetchItems(query: String) -> [String] {
        if cachedNameType == "opening" {
            let cached = database.cachedNames(type: "opening", query: query)
            let q = query.lowercased()
            let ecoNames: [String]
            if q.isEmpty {
                ecoNames = Array(Self.allOpeningNames.prefix(6))
            } else {
                ecoNames = Self.allOpeningNames.filter { $0.lowercased().contains(q) }
            }
            var seen = Set<String>()
            var merged: [String] = []
            for name in (cached + ecoNames) {
                if seen.insert(name).inserted {
                    merged.append(name)
                }
            }
            return Array(merged.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.prefix(6))
        } else {
            return Array(database.cachedNames(type: cachedNameType, query: query).prefix(6))
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items, id: \.self) { name in
                FilterListItem(
                    name: name,
                    isSelected: selectedValue == name,
                    onSelect: { onSelect(name) }
                )
            }
        }
        .onAppear { items = fetchItems(query: "") }
        .onChange(of: searchQuery) { _, newValue in
            items = fetchItems(query: newValue)
        }
    }
}

private struct FilterListItem: View {
    let name: String
    let isSelected: Bool
    let count: Int?
    let onSelect: () -> Void

    @State private var isHovered = false

    init(name: String, isSelected: Bool, count: Int? = nil, onSelect: @escaping () -> Void) {
        self.name = name
        self.isSelected = isSelected
        self.count = count
        self.onSelect = onSelect
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Checkbox
                if isSelected {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.rBar)
                            .fill(DS.accent)
                            .frame(width: 13, height: 13)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(DS.paper)
                    }
                } else {
                    RoundedRectangle(cornerRadius: DS.rBar)
                        .strokeBorder(DS.borderStrong, lineWidth: 1)
                        .frame(width: 13, height: 13)
                }

                Text(name)
                    .font(AnnFont.serif(13.5, isSelected ? .medium : .regular))
                    .foregroundColor(DS.ink)
                    .lineLimit(1)

                Spacer()

                if let count = count {
                    Text("\(count)")
                        .font(AnnFont.mono(11))
                        .foregroundColor(DS.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? DS.bgHover : (isHovered ? DS.bgHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Dual Slider

struct DualSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = bounds.upperBound - bounds.lowerBound
            let loFrac = (range.lowerBound - bounds.lowerBound) / span
            let hiFrac = (range.upperBound - bounds.lowerBound) / span

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.trackBg)
                    .frame(height: 3)

                // Active range fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.accent)
                    .frame(width: max(0, CGFloat(hiFrac - loFrac) * width), height: 3)
                    .offset(x: CGFloat(loFrac) * width)

                // Low thumb
                sliderThumb
                    .offset(x: CGFloat(loFrac) * width - 7.5)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let raw = bounds.lowerBound + Double(v.location.x / width) * span
                        let snapped = (raw / step).rounded() * step
                        let clamped = max(bounds.lowerBound, min(snapped, range.upperBound - step))
                        range = clamped...range.upperBound
                    })

                // High thumb
                sliderThumb
                    .offset(x: CGFloat(hiFrac) * width - 7.5)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let raw = bounds.lowerBound + Double(v.location.x / width) * span
                        let snapped = (raw / step).rounded() * step
                        let clamped = min(bounds.upperBound, max(snapped, range.lowerBound + step))
                        range = range.lowerBound...clamped
                    })
            }
            .frame(height: 20)
        }
    }

    private var sliderThumb: some View {
        Circle()
            .fill(DS.fieldBg)
            .frame(width: 15, height: 15)
            .overlay(Circle().stroke(DS.accent, lineWidth: 1.5))
    }
}

// MARK: - New Database Sheet

struct NewDatabaseSheet: View {
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    let onCreate: (String, [URL]) -> Void
    let onCancel: () -> Void
    var onDownloadReference: (() -> Void)? = nil

    @State private var name = ""
    @State private var pgnURLs: [URL] = []
    @State private var isDropTargeted = false
    @State private var showingFilePicker = false
    @State private var downloadStarted = false

    /// Show the in-sheet progress panel while a hosted download is active (also when the sheet is
    /// reopened during an in-flight download — `isDownloading` stays true for the whole operation).
    private var showingProgress: Bool { downloadStarted || referenceDatabase.isDownloading }
    private var downloadActive: Bool { referenceDatabase.isDownloading || referenceDatabase.isImporting }
    private var downloadDone: Bool { downloadStarted && !downloadActive && referenceDatabase.gameCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text("New ").font(AnnFont.serif(18, .semibold))
                     + Text("Database").font(AnnFont.voice(18)))
                        .foregroundColor(DS.ink)
                    Text("Download the master reference, or start your own from PGN files.")
                        .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                }

                Spacer()

                Button(action: { onCancel() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.ink40)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            if showingProgress {
                downloadProgressPanel
            } else {
            // Body
            VStack(alignment: .leading, spacing: 20) {
                // Reference database — one-click download of the big master OTB database
                if let onDownloadReference {
                    Button(action: {
                        referenceDatabase.setDisplayName(name)   // name the reference DB from this field
                        downloadStarted = true
                        onDownloadReference()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(DS.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download reference database")
                                    .font(AnnFont.serif(13, .semibold))
                                    .foregroundColor(DS.textPrimary)
                                Text("9.6M master over-the-board games · ~2 GB")
                                    .font(AnnFont.serif(11))
                                    .foregroundColor(DS.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DS.textTertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(DS.accentLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusMD)
                                .strokeBorder(DS.accent.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(DS.radiusMD)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Rectangle().fill(DS.border).frame(height: 1)
                        Text("or create your own")
                            .font(AnnFont.serif(10))
                            .foregroundColor(DS.textTertiary)
                            .fixedSize()
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }

                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("DATABASE NAME")
                        .font(AnnFont.label(10)).tracking(10 * 0.14)
                        .foregroundColor(DS.ink40)

                    TextField("My Tournament Games", text: $name)
                        .textFieldStyle(.plain)
                        .font(AnnFont.serif(13))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(DS.bg)
                        .cornerRadius(DS.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSM)
                                .strokeBorder(DS.border, lineWidth: 1)
                        )
                }

                // Import PGN section
                VStack(alignment: .leading, spacing: 8) {
                    Text("IMPORT PGN  ·  OPTIONAL")
                        .font(AnnFont.label(10)).tracking(10 * 0.14)
                        .foregroundColor(DS.ink40)

                    if pgnURLs.isEmpty {
                        // Drop zone
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 24))
                                .foregroundColor(isDropTargeted ? DS.accent : DS.textTertiary)

                            Text("Drop PGN file here or click to browse")
                                .font(AnnFont.serif(12))
                                .foregroundColor(DS.textSecondary)
                                .multilineTextAlignment(.center)

                            Text(".pgn files supported")
                                .font(AnnFont.serif(10))
                                .foregroundColor(DS.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusMD)
                                .fill(isDropTargeted ? DS.accentLight : DS.bg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusMD)
                                .strokeBorder(
                                    isDropTargeted ? DS.accent : DS.border,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { showingFilePicker = true }
                        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                            handleDrop(providers: providers)
                        }
                    } else {
                        // File list
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(pgnURLs, id: \.absoluteString) { url in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 12))
                                        .foregroundColor(DS.accent)
                                    Text(url.lastPathComponent)
                                        .font(AnnFont.serif(12))
                                        .foregroundColor(DS.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        pgnURLs.removeAll(where: { $0 == url })
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(DS.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(DS.accentLight)
                                .cornerRadius(DS.radiusSM)
                            }

                            Button(action: { showingFilePicker = true }) {
                                Label("Add more...", systemImage: "plus")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DS.accent)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(24)

            Spacer()

            // Footer
            HStack(spacing: 10) {
                Spacer()

                Button(action: { onCancel() }) { Text("Cancel") }
                    .buttonStyle(GlassButtonStyle())

                Button(action: {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let finalName = trimmed.isEmpty ? "Untitled" : trimmed
                    onCreate(finalName, pgnURLs)
                }) {
                    Text(pgnURLs.isEmpty ? "Create Database" : "Create & Import")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
            }  // end else (form section)
        }
        .frame(width: 480)
        .background(DS.paper)
        .clipShape(RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous)
                .strokeBorder(DS.borderStrong, lineWidth: 1)
        )
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls where !pgnURLs.contains(url) {
                    pgnURLs.append(url)
                }
            }
        }
    }

    /// In-sheet feedback for the one-click hosted download: active phase (bar + games count),
    /// a success state, or an error with retry — so the button never just "goes into the void".
    private var downloadProgressPanel: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            if let err = referenceDatabase.downloadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34)).foregroundColor(DS.moveBlunder)
                Text("Download failed")
                    .font(AnnFont.serif(15, .semibold)).foregroundColor(DS.textPrimary)
                Text(err).font(AnnFont.serif(11)).foregroundColor(DS.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360).lineLimit(4)
                HStack(spacing: 10) {
                    Button("Close") { onCancel() }.buttonStyle(.bordered)
                    Button("Retry") { onDownloadReference?() }.buttonStyle(.borderedProminent)
                }.padding(.top, 4)
            } else if downloadDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34)).foregroundColor(DS.accent)
                Text("\(formatted(referenceDatabase.gameCount)) games ready")
                    .font(AnnFont.serif(15, .semibold)).foregroundColor(DS.textPrimary)
                Text("Open the Reference tab and tap “Build opening index” to make positions searchable — you choose scope and depth.")
                    .font(AnnFont.serif(11)).foregroundColor(DS.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                Button("Done") { onCancel() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
            } else {
                KnightLoader(size: 52)
                Text(referenceDatabase.downloadPhase.isEmpty ? "Starting…" : referenceDatabase.downloadPhase)
                    .font(AnnFont.serif(14, .semibold)).foregroundColor(DS.textPrimary)
                    .padding(.top, 4)
                if referenceDatabase.downloadPhase == "Downloading…" {
                    ProgressView(value: referenceDatabase.downloadProgress).frame(maxWidth: 320)
                    Text("\(Int(referenceDatabase.downloadProgress * 100))%  ·  ~2 GB")
                        .font(AnnFont.mono(11)).foregroundColor(DS.textTertiary)
                } else if referenceDatabase.importProgress > 0 {
                    Text("\(formatted(referenceDatabase.importProgress)) games loaded")
                        .font(AnnFont.mono(11)).foregroundColor(DS.textTertiary)
                }
                Text("You can keep using the app — this continues in the background.")
                    .font(AnnFont.serif(10)).foregroundColor(DS.textTertiary)
                HStack(spacing: 10) {
                    Button("Continue in background") { onCancel() }
                        .buttonStyle(.bordered)
                    Button(role: .destructive) { referenceDatabase.cancelDownload() } label: {
                        Text(referenceDatabase.isCancellingDownload ? "Cancelling…" : "Cancel Download")
                    }
                    .buttonStyle(.bordered)
                    .disabled(referenceDatabase.isCancellingDownload)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity).frame(height: 300).padding(24)
        // After a clean cancel that loaded no games, return to the create-database options.
        .onChange(of: referenceDatabase.isDownloading) { _, downloading in
            if !downloading && referenceDatabase.downloadError == nil && referenceDatabase.gameCount == 0 {
                downloadStarted = false
            }
        }
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                handled = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        if !pgnURLs.contains(url) {
                            pgnURLs.append(url)
                        }
                    }
                }
            }
        }
        return handled
    }
}

#Preview {
    DatabaseBrowserView(onGameSelected: { _ in })
        .environmentObject(GameDatabase.preview())
        .environmentObject(ReferenceDatabase())
        .frame(width: 900, height: 600)
}

// MARK: - Opening Index Progress Sheet

/// Progress while a database's opening index is built. Reuses the reference-DB pipeline per folder.
struct DatabaseIndexProgressSheet: View {
    let folderName: String
    let onDone: () -> Void

    @ObservedObject private var dbIndex = DatabaseIndex.shared

    private var done: Bool { !dbIndex.isIndexing }
    private var fraction: Double {
        dbIndex.indexTotal > 0 ? min(1, Double(dbIndex.indexProgress) / Double(dbIndex.indexTotal)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                (Text("Opening ").font(AnnFont.serif(18, .semibold))
                 + Text("Index").font(AnnFont.voice(18)))
                    .foregroundColor(DS.ink)
                Text(folderName).font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            // Body
            VStack(alignment: .leading, spacing: 14) {
                Text(done
                     ? "This database is now searchable in the Opening Explorer."
                     : "Replaying games and hashing opening positions…")
                    .font(AnnFont.voice(13.5)).foregroundColor(DS.ink60)
                    .fixedSize(horizontal: false, vertical: true)

                // Progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.trackBg)
                        Capsule().fill(DS.redInk)
                            .frame(width: max(4, geo.size.width * (done ? 1 : fraction)))
                    }
                }
                .frame(height: 6)

                Text("\(dbIndex.indexProgress) / \(dbIndex.indexTotal) games")
                    .font(AnnFont.mono(10)).foregroundColor(DS.ink40)
            }
            .padding(24)

            // Footer
            HStack {
                Spacer()
                Button(action: onDone) { Text(done ? "Done" : "Run in Background") }
                    .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
        .frame(width: 440)
        .background(DS.paper)
    }
}
