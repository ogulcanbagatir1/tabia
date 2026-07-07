import SwiftUI
import UniformTypeIdentifiers

// MARK: - Game Transfer Data (for drag and drop)

struct GameTransferData: Codable, Transferable {
    let gameIds: Set<UUID>

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .gameTransfer)
    }
}

extension UTType {
    static let gameTransfer = UTType(exportedAs: "com.tabia.gametransfer")
}

// MARK: - Game Library View

struct GameLibraryView: View {
    @ObservedObject var database: GameDatabase
    var onGameSelected: ((GameRecord) -> Void)?
    var onGameDeleted: ((UUID) -> Void)?
    @State private var searchText = ""
    @State private var selectedGame: GameRecord?
    @State private var selectedGameIds: Set<UUID> = []
    @State private var showingImportPicker = false
    @State private var importAlert: ImportAlertInfo?
    @State private var isDropTargeted = false

    // Folder support
    @State private var selectedFolderView: FolderSelection = .allGames
    @State private var pendingImportURLs: [URL] = []
    @State private var showingPGNImportSheet = false
    @State private var renamingFolder: GameFolder?
    @State private var newFolderName = ""
    @State private var showingDeleteFolderAlert = false
    @State private var folderToDelete: GameFolder?
    @State private var showingNewFolderAlert = false
    @State private var showingDeleteAllAlert = false

    // Filters
    @State private var filterTimeControl: TimeControlFilter = .all
    @State private var filterResult: ResultFilter = .all
    @State private var filterColor: ColorFilter = .all
    @State private var filterOpening: String = ""
    @State private var openingSearchText: String = ""
    @State private var filterDateFrom: Date? = nil
    @State private var filterDateTo: Date? = nil

    // Pagination — paginated state replaces old displayedGames computed property
    @State private var displayedGames: [GameRecord] = []
    @State private var displayedGameCount: Int = 50
    @State private var dbOffset: Int = 0
    @State private var allExhausted = false
    @State private var isLoadingGames = false
    @State private var reloadTask: Task<Void, Never>?
    private let libraryPageSize = 50
    private let dbBatchSize = 200


    enum TimeControlFilter: String, CaseIterable {
        case all = "All"
        case bullet = "Bullet"
        case blitz = "Blitz"
        case rapid = "Rapid"
        case daily = "Daily"
    }

    enum ResultFilter: String, CaseIterable {
        case all = "All"
        case whiteWins = "1-0"
        case blackWins = "0-1"
        case draw = "Draw"
    }

    enum ColorFilter: String, CaseIterable {
        case all = "All"
        case white = "White"
        case black = "Black"
    }

    struct ImportAlertInfo: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    enum FolderSelection: Hashable {
        case allGames
        case unfiled
        case folder(UUID)
    }

    /// Whether any client-side filters are active (result is pushed to DB)
    private var hasClientSideFilters: Bool {
        !searchText.isEmpty || filterTimeControl != .all || filterColor != .all ||
        !filterOpening.isEmpty || filterDateFrom != nil || filterDateTo != nil
    }

    /// Reload games from scratch (reset pagination)
    private func loadGames() {
        displayedGames = []
        dbOffset = 0
        allExhausted = false
        isLoadingGames = true
        displayedGameCount = libraryPageSize
        Task { @MainActor in
            performLibraryLoad(targetCount: libraryPageSize)
        }
    }

    /// Schedule a reload, debounced for text input
    private func scheduleLibraryReload(debounce: Bool) {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: debounce ? 300_000_000 : 50_000_000)
            guard !Task.isCancelled else { return }
            loadGames()
        }
    }

    /// Load more games from DB until we have at least `targetCount` displayed
    private func performLibraryLoad(targetCount: Int) {
        let batchSize = hasClientSideFilters ? dbBatchSize : libraryPageSize
        let resultFilter: String? = {
            switch filterResult {
            case .whiteWins: return "1-0"
            case .blackWins: return "0-1"
            case .draw: return nil  // draw has multiple representations, keep client-side
            case .all: return nil
            }
        }()

        while displayedGames.count < targetCount && !allExhausted {
            let batch: [GameRecord]
            let consumed: Int   // raw rows the DB scanned (advance offset by this)
            let ended: Bool     // DB returned fewer than requested → no more pages
            switch selectedFolderView {
            case .allGames:
                let sort = SortDescriptor<GameRecord>(\.dateAdded, order: .reverse)
                let page = database.fetchLibraryGames(
                    folderId: nil, sortDescriptor: sort,
                    limit: batchSize, offset: dbOffset,
                    filter: GameFilter(result: resultFilter)
                )
                batch = page.games
                consumed = page.rawConsumed
                ended = page.reachedEnd
            case .unfiled:
                batch = database.unfiledGames(limit: batchSize, offset: dbOffset)
                consumed = batch.count
                ended = batch.count < batchSize
            case .folder(let folderId):
                batch = database.gamesInFolder(folderId, limit: batchSize, offset: dbOffset)
                consumed = batch.count
                ended = batch.count < batchSize
            }

            dbOffset += consumed
            if ended { allExhausted = true }

            if hasClientSideFilters || (filterResult == .draw) {
                displayedGames.append(contentsOf: applyLibraryClientFilters(batch))
            } else {
                displayedGames.append(contentsOf: batch)
            }
        }
        isLoadingGames = false
    }

    /// Load more pages when user scrolls
    private func loadMoreLibraryGames() {
        guard !allExhausted, !isLoadingGames else { return }
        isLoadingGames = true
        displayedGameCount += libraryPageSize
        Task { @MainActor in
            performLibraryLoad(targetCount: displayedGameCount)
        }
    }

    /// Apply client-side filters to a batch
    private func applyLibraryClientFilters(_ games: [GameRecord]) -> [GameRecord] {
        games.filter { game in
            // Search filter
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                if !game.white.lowercased().contains(query) &&
                   !game.black.lowercased().contains(query) &&
                   !game.event.lowercased().contains(query) &&
                   !game.date.contains(query) { return false }
            }
            // Time control
            if filterTimeControl != .all {
                if game.timeClass?.lowercased() != filterTimeControl.rawValue.lowercased() { return false }
            }
            // Result (draw has multiple representations)
            if filterResult == .draw {
                if game.result != "1/2-1/2" && game.result != "1/2" { return false }
            }
            // Color
            if filterColor != .all, let username = currentChessComUsername {
                let playedWhite = game.white.lowercased() == username.lowercased()
                switch filterColor {
                case .white: if !playedWhite { return false }
                case .black: if playedWhite { return false }
                case .all: break
                }
            }
            // Opening
            if !filterOpening.isEmpty {
                let query = filterOpening.lowercased()
                if game.opening?.lowercased().contains(query) != true &&
                   game.eco?.lowercased().contains(query) != true { return false }
            }
            // Date range
            if let dateFrom = filterDateFrom {
                if let gameDate = parseGameDate(game.date), gameDate < dateFrom { return false }
            }
            if let dateTo = filterDateTo {
                if let gameDate = parseGameDate(game.date), gameDate > dateTo { return false }
            }
            return true
        }
    }

    /// Get the Chess.com username for filtering (from any game with sourceUsername)
    private var currentChessComUsername: String? {
        UserDefaults.standard.string(forKey: "chesscom_username")
    }

    /// Parse a game date string (formats: "2024.01.15", "Jan 15, 2024", etc.)
    private func parseGameDate(_ dateString: String) -> Date? {
        let formatters: [DateFormatter] = {
            let f1 = DateFormatter()
            f1.dateFormat = "yyyy.MM.dd"
            let f2 = DateFormatter()
            f2.dateFormat = "MMM d, yyyy"
            let f3 = DateFormatter()
            f3.dateStyle = .medium
            return [f1, f2, f3]
        }()
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    /// Check if any filters are active
    private var hasActiveFilters: Bool {
        filterTimeControl != .all ||
        filterResult != .all ||
        filterColor != .all ||
        !filterOpening.isEmpty ||
        filterDateFrom != nil ||
        filterDateTo != nil
    }

    /// Clear all filters
    private func clearFilters() {
        filterTimeControl = .all
        filterResult = .all
        filterColor = .all
        filterOpening = ""
        openingSearchText = ""
        filterDateFrom = nil
        filterDateTo = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
            Rectangle()
                .fill(DS.border)
                .frame(height: 1)
            activeFiltersBar
            mainContentView
            statusBarView
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
                    if let folderId = folderId {
                        selectedFolderView = .folder(folderId)
                    }
                    importAlert = ImportAlertInfo(message: "Games imported successfully.", isError: false)
                },
                onCancel: {
                    showingPGNImportSheet = false
                    pendingImportURLs = []
                }
            )
        }
        .alert(item: $importAlert) { info in
            Alert(
                title: Text(info.isError ? "Import Error" : "Import Successful"),
                message: Text(info.message),
                dismissButton: .default(Text("OK"))
            )
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
            Button("Keep Games") {
                if let folder = folderToDelete {
                    database.deleteFolder(folder, deleteGames: false)
                    if case .folder(let id) = selectedFolderView, id == folder.id {
                        selectedFolderView = .allGames
                    }
                }
                folderToDelete = nil
            }
            Button("Delete Games", role: .destructive) {
                if let folder = folderToDelete {
                    // Notify about games in folder being deleted
                    for game in database.gamesInFolder(folder.id) {
                        onGameDeleted?(game.id)
                    }
                    database.deleteFolder(folder, deleteGames: true)
                    if case .folder(let id) = selectedFolderView, id == folder.id {
                        selectedFolderView = .allGames
                    }
                }
                folderToDelete = nil
            }
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: {
            Text("Delete games in this database or keep them?")
        }
        .alert("New Database", isPresented: $showingNewFolderAlert) {
            TextField("Database name", text: $newFolderName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                if !newFolderName.isEmpty {
                    let folder = database.createFolder(name: newFolderName)
                    selectedFolderView = .folder(folder.id)
                }
            }
        }
        .onAppear { if displayedGames.isEmpty { loadGames() } }
        .onChange(of: searchText) { _, _ in scheduleLibraryReload(debounce: true) }
        .onChange(of: selectedFolderView) { _, _ in scheduleLibraryReload(debounce: false) }
        .onChange(of: filterTimeControl) { _, _ in scheduleLibraryReload(debounce: false) }
        .onChange(of: filterResult) { _, _ in scheduleLibraryReload(debounce: false) }
        .onChange(of: filterColor) { _, _ in scheduleLibraryReload(debounce: false) }
        .onChange(of: filterOpening) { _, _ in scheduleLibraryReload(debounce: true) }
        .onChange(of: filterDateFrom) { _, _ in scheduleLibraryReload(debounce: false) }
        .onChange(of: filterDateTo) { _, _ in scheduleLibraryReload(debounce: false) }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 10) {
            folderMenu
            searchField
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg)
    }

    private var folderMenu: some View {
        Menu {
            Button(action: { selectedFolderView = .allGames }) {
                Label("All Games (\(database.libraryGameCount))", systemImage: "tray.full")
            }

            if !sortedFolders.isEmpty {
                Divider()

                ForEach(sortedFolders) { folder in
                    let count = database.gamesInFolderCount(folder.id)
                    Menu(folder.name) {
                        Button(action: { selectedFolderView = .folder(folder.id) }) {
                            Label("Open (\(count) games)", systemImage: "folder.fill")
                        }
                        Divider()
                        Button("Rename...") {
                            newFolderName = folder.name
                            renamingFolder = folder
                        }
                        Button("Delete...", role: .destructive) {
                            folderToDelete = folder
                            showingDeleteFolderAlert = true
                        }
                    } primaryAction: {
                        selectedFolderView = .folder(folder.id)
                    }
                }
            }

            Divider()

            Button(action: {
                newFolderName = ""
                showingNewFolderAlert = true
            }) {
                Label("New Database...", systemImage: "plus.circle")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: currentFolderIcon)
                    .font(.system(size: 11, weight: .medium))
                Text(currentFolderName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(DS.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DS.bgSecondary)
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Filter Bar

    @State private var showingFiltersPopover = false

    @ViewBuilder
    private var activeFiltersBar: some View {
        if hasActiveFilters {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if filterTimeControl != .all {
                            filterChip(label: filterTimeControl.rawValue, icon: "clock") {
                                filterTimeControl = .all
                            }
                        }
                        if filterResult != .all {
                            filterChip(label: filterResult.rawValue, icon: "flag") {
                                filterResult = .all
                            }
                        }
                        if filterColor != .all {
                            filterChip(label: filterColor.rawValue, icon: "circle.lefthalf.filled") {
                                filterColor = .all
                            }
                        }
                        if !filterOpening.isEmpty {
                            filterChip(label: filterOpening, icon: "book") {
                                filterOpening = ""
                            }
                        }
                        if filterDateFrom != nil || filterDateTo != nil {
                            filterChip(label: dateFilterLabel, icon: "calendar") {
                                filterDateFrom = nil
                                filterDateTo = nil
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                Rectangle()
                    .fill(DS.border)
                    .frame(height: 1)
            }
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if filterTimeControl != .all { count += 1 }
        if filterResult != .all { count += 1 }
        if filterColor != .all { count += 1 }
        if !filterOpening.isEmpty { count += 1 }
        if filterDateFrom != nil || filterDateTo != nil { count += 1 }
        return count
    }

    private func filterChip(label: String, icon: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.accent.opacity(0.15))
        .foregroundColor(DS.accent)
        .cornerRadius(12)
    }

    private var dateFilterLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        if let from = filterDateFrom, let to = filterDateTo {
            return "\(formatter.string(from: from)) - \(formatter.string(from: to))"
        } else if let from = filterDateFrom {
            return "From \(formatter.string(from: from))"
        } else if let to = filterDateTo {
            return "Until \(formatter.string(from: to))"
        }
        return "Date"
    }

    // MARK: - Filters Popover

    private var filtersPopover: some View {
        VStack(spacing: 0) {
            // Header
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
                    // Time Control
                    filterSection(title: "Time Control", icon: "clock") {
                        filterPillGroup(
                            options: TimeControlFilter.allCases.map { $0.rawValue },
                            selected: filterTimeControl.rawValue
                        ) { selected in
                            filterTimeControl = TimeControlFilter(rawValue: selected) ?? .all
                        }
                    }

                    // Result
                    filterSection(title: "Result", icon: "flag") {
                        filterPillGroup(
                            options: ResultFilter.allCases.map { $0.rawValue },
                            selected: filterResult.rawValue
                        ) { selected in
                            filterResult = ResultFilter(rawValue: selected) ?? .all
                        }
                    }

                    // Color (only if Chess.com username available)
                    if currentChessComUsername != nil {
                        filterSection(title: "Played As", icon: "circle.lefthalf.filled") {
                            filterPillGroup(
                                options: ColorFilter.allCases.map { $0.rawValue },
                                selected: filterColor.rawValue
                            ) { selected in
                                filterColor = ColorFilter(rawValue: selected) ?? .all
                            }
                        }
                    }

                    // Opening
                    filterSection(title: "Opening", icon: "book") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.textSecondary)
                                TextField("Search openings...", text: $openingSearchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                if !openingSearchText.isEmpty {
                                    Button(action: { openingSearchText = "" }) {
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

                            if !filterOpening.isEmpty {
                                HStack(spacing: 4) {
                                    Text(filterOpening)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(DS.accent)
                                    Button(action: { filterOpening = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(DS.accent.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DS.accent.opacity(0.12))
                                .cornerRadius(8)
                            }

                            // Opening family chips
                            ScrollView(.vertical, showsIndicators: true) {
                                FlowLayout(spacing: 6) {
                                    ForEach(filteredOpeningFamilies, id: \.self) { opening in
                                        Button(action: {
                                            filterOpening = opening
                                            openingSearchText = ""
                                        }) {
                                            Text(opening)
                                                .font(.system(size: 11))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(filterOpening == opening ? DS.accent : DS.bgSecondary)
                                                .foregroundColor(filterOpening == opening ? .white : DS.textPrimary)
                                                .cornerRadius(14)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                        }
                    }

                    // Date Range
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

            // Footer
            HStack {
                if hasActiveFilters {
                    Text("\(activeFilterCount) active")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                }
                Spacer()
                Button(action: { showingFiltersPopover = false }) {
                    Text("Done")
                        .glassButtonPrimary()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(DS.bgSecondary)
        }
        .frame(width: 340)
    }

    private func filterSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterPillGroup(options: [String], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button(action: { onSelect(option) }) {
                    Text(option)
                        .font(.system(size: 11, weight: selected == option ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected == option ? DS.accent : DS.bgSecondary)
                        .foregroundColor(selected == option ? .white : DS.textPrimary)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredOpeningFamilies: [String] {
        guard !openingSearchText.isEmpty else { return openingFamilies }
        let query = openingSearchText.lowercased()
        return openingFamilies.filter { $0.lowercased().contains(query) }
    }

    private var openingFamilies: [String] {
        var families = Set<String>()
        for node in collectNamedNodes(OpeningBook.shared.root) {
            if let name = node.name {
                // Take the part before ":" as the family name
                let family = name.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? name
                families.insert(family)
            }
        }
        return families.sorted()
    }

    private func collectNamedNodes(_ node: OpeningNode) -> [OpeningNode] {
        var result: [OpeningNode] = []
        if node.name != nil { result.append(node) }
        for child in node.children {
            result.append(contentsOf: collectNamedNodes(child))
        }
        return result
    }

// Flow layout for wrapping pills
struct FlowLayout: Layout {
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DS.textSecondary)
                .font(.system(size: 12, weight: .medium))
            TextField("Search games...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.textSecondary.opacity(0.7))
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.bgSecondary)
        .cornerRadius(8)
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            // Filter button with badge
            Button(action: { showingFiltersPopover.toggle() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 15))
                        .foregroundColor(hasActiveFilters ? DS.accent : DS.textSecondary)
                        .frame(width: 28, height: 28)

                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(DS.accent)
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

            toolbarButton(icon: "square.and.arrow.down", help: "Import PGN") {
                showingImportPicker = true
            }

            toolbarButton(icon: "trash", help: "Delete All") {
                showingDeleteAllAlert = true
            }
            .disabled(database.libraryGameCount == 0 && database.folders.isEmpty)
            .alert("Delete All", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    database.deleteAll()
                    selectedFolderView = .allGames
                }
            } message: {
                Text("Delete all games and databases? This cannot be undone.")
            }
        }
    }

    private func toolbarButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(DS.textSecondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        gameListView
    }

    // MARK: - Folder Helpers

    private var sortedFolders: [GameFolder] {
        database.folders.sorted { $0.name < $1.name }
    }

    private var currentFolderName: String {
        switch selectedFolderView {
        case .allGames:
            return "All Games"
        case .unfiled:
            return "Unfiled"
        case .folder(let id):
            return database.folders.first(where: { $0.id == id })?.name ?? "Database"
        }
    }

    private var currentFolderIcon: String {
        switch selectedFolderView {
        case .allGames:
            return "tray.full"
        case .unfiled:
            return "tray"
        case .folder:
            return "folder.fill"
        }
    }

    // MARK: - Game List

    private var gameListView: some View {
        ZStack {
            if displayedGames.isEmpty {
                emptyStateView
            } else {
                gamesList
            }

            if isDropTargeted {
                dropOverlay
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if selectedFolderView == .allGames && database.libraryGameCount == 0 && searchText.isEmpty && !hasActiveFilters {
                // Empty state for All Games - no games at all
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(DS.accent.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 36))
                            .foregroundColor(DS.accent)
                    }

                    VStack(spacing: 8) {
                        Text("No Games Yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Import PGN files to get started")
                            .font(.system(size: 13))
                            .foregroundColor(DS.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: { showingImportPicker = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .medium))
                            Text("Import")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(DS.accent)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)

            } else if hasActiveFilters {
                // Filtered but no results
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(DS.textSecondary.opacity(0.1))
                            .frame(width: 70, height: 70)
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundColor(DS.textSecondary)
                    }

                    VStack(spacing: 6) {
                        Text("No Matching Games")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                        Text("Try adjusting your filters")
                            .font(.system(size: 12))
                            .foregroundColor(DS.textSecondary)
                    }

                    Button(action: clearFilters) {
                        Text("Clear Filters")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)

            } else {
                // Generic empty state (for folders, search, etc.)
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundColor(DS.textSecondary.opacity(0.5))
                    Text(emptyStateMessage)
                        .font(.system(size: 13))
                        .foregroundColor(DS.textSecondary)
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedGames) { game in
                    GameRowView(game: game, isSelected: selectedGameIds.contains(game.id))
                        .onTapGesture {
                            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                                onGameSelected?(game)
                            }
                            if NSEvent.modifierFlags.contains(.command) {
                                if selectedGameIds.contains(game.id) {
                                    selectedGameIds.remove(game.id)
                                } else {
                                    selectedGameIds.insert(game.id)
                                }
                            } else if NSEvent.modifierFlags.contains(.shift), let lastSelected = selectedGame {
                                let gamesList = displayedGames
                                if let startIndex = gamesList.firstIndex(where: { $0.id == lastSelected.id }),
                                   let endIndex = gamesList.firstIndex(where: { $0.id == game.id }) {
                                    let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                                    for i in range {
                                        selectedGameIds.insert(gamesList[i].id)
                                    }
                                }
                            } else {
                                selectedGameIds = [game.id]
                            }
                            selectedGame = game
                        }
                        .draggable(GameTransferData(gameIds: selectedGameIds.isEmpty ? [game.id] : selectedGameIds)) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                Text(selectedGameIds.count > 1 ? "\(selectedGameIds.count) games" : "\(game.white) vs \(game.black)")
                                    .lineLimit(1)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DS.accent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .contextMenu {
                            Button("Open") {
                                selectedGame = game
                                onGameSelected?(game)
                            }
                            Button("Export...") { exportGame(game) }

                            if selectedGameIds.count > 1 {
                                Divider()
                                Menu("Move \(selectedGameIds.count) games to...") {
                                    Button("Unfiled") {
                                        database.moveGames(selectedGameIds, toFolder: nil)
                                        selectedGameIds.removeAll()
                                    }
                                    Divider()
                                    ForEach(database.folders) { folder in
                                        Button(folder.name) {
                                            database.moveGames(selectedGameIds, toFolder: folder.id)
                                            selectedGameIds.removeAll()
                                        }
                                    }
                                }
                            } else {
                                Divider()
                                Menu("Move to...") {
                                    Button("Unfiled") {
                                        database.moveGames([game.id], toFolder: nil)
                                    }
                                    Divider()
                                    ForEach(database.folders) { folder in
                                        Button(folder.name) {
                                            database.moveGames([game.id], toFolder: folder.id)
                                        }
                                    }
                                }
                            }

                            Divider()
                            Button("Delete", role: .destructive) {
                                if selectedGameIds.count > 1 {
                                    for gameId in selectedGameIds {
                                        if let g = database.game(withId: gameId) {
                                            database.deleteGame(g)
                                            onGameDeleted?(gameId)
                                        }
                                    }
                                    selectedGameIds.removeAll()
                                } else {
                                    let gameId = game.id
                                    database.deleteGame(game)
                                    onGameDeleted?(gameId)
                                }
                            }
                        }

                    Divider()
                        .padding(.horizontal, 12)
                }

                // Load more trigger
                if !allExhausted {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            loadMoreLibraryGames()
                        }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(DS.bgSecondary.opacity(0.5))
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(DS.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
            .background(DS.accent.opacity(0.1).cornerRadius(8))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundColor(DS.accent)
                    Text("Drop to import")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.accent)
                }
            )
            .padding(8)
    }

    // MARK: - Status Bar

    private var statusBarView: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 10))
                .foregroundColor(DS.textSecondary)

            Text("\(displayedGames.count)\(allExhausted ? "" : "+")")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(DS.textPrimary)
            +
            Text(" games")
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)

            if isLoadingGames {
                ProgressView()
                    .scaleEffect(0.5)
            }

            if hasActiveFilters {
                Text("•")
                    .foregroundColor(DS.textSecondary)
                Text("filtered")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.accent)
            }

            Spacer()

            if selectedGameIds.count > 1 {
                Text("\(selectedGameIds.count) selected")
                    .font(.system(size: 10))
                    .foregroundColor(DS.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.bg)
    }

    private var emptyStateMessage: String {
        if hasActiveFilters { return "No games match filters" }
        if !searchText.isEmpty { return "No games found" }
        switch selectedFolderView {
        case .allGames, .unfiled: return "No games"
        case .folder: return "No games in database"
        }
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
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, error in
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

    private func performImport(urls: [URL], intoFolder folderId: UUID?) {
        var totalImported = 0
        var errors: [String] = []

        for url in urls {
            do {
                let result = try database.importPGNWithResult(from: url, intoFolder: folderId)
                totalImported += result.gamesImported
                errors.append(contentsOf: result.errors)
            } catch {
                errors.append("Error: \(error.localizedDescription)")
            }
        }

        if errors.isEmpty {
            importAlert = ImportAlertInfo(message: "Imported \(totalImported) game(s).", isError: false)
        } else {
            importAlert = ImportAlertInfo(message: "Imported \(totalImported) game(s) with errors.", isError: true)
        }

        if let folderId = folderId {
            selectedFolderView = .folder(folderId)
        }
    }

    private func exportGame(_ game: GameRecord) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(game.white)_vs_\(game.black).pgn"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? game.pgn.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - Game Row

struct GameRowView: View {
    let game: GameRecord
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Players row
                HStack(spacing: 6) {
                    // White player
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

                    // Black player
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

                // Details row
                HStack(spacing: 6) {
                    if !eventSiteLabel.isEmpty {
                        Text(eventSiteLabel)
                            .font(.system(size: 10))
                            .foregroundColor(DS.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Date
                    if !game.date.isEmpty {
                        Text(game.date)
                            .font(.system(size: 10))
                            .foregroundColor(DS.textSecondary)
                    }
                }
            }

            // Right side badges
            VStack(alignment: .trailing, spacing: 4) {
                // Time class badge
                if let timeClass = game.timeClass {
                    Text(timeClass.capitalized)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(timeClassColor(timeClass))
                        .cornerRadius(4)
                }

                // Result badge
                Text(resultText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(resultTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(resultBackgroundColor)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? DS.accent.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private func extractRating(for color: String) -> String? {
        let key = "\(color)Elo"
        let pattern = "\\[\(key) \"(\\d+)\"\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: game.pgn, range: NSRange(game.pgn.startIndex..., in: game.pgn)),
              let range = Range(match.range(at: 1), in: game.pgn) else { return nil }
        return String(game.pgn[range])
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

    private func timeClassColor(_ timeClass: String) -> Color {
        DS.timeControlColor(for: timeClass)
    }

    private var resultText: String {
        switch game.result {
        case "1-0": return "1-0"
        case "0-1": return "0-1"
        case "1/2-1/2": return "½-½"
        default: return "*"
        }
    }

    private var resultBackgroundColor: Color {
        switch game.result {
        case "1-0": return Color.white
        case "0-1": return Color.black.opacity(0.85)
        case "1/2-1/2": return DS.bgTertiary
        default: return DS.textSecondary.opacity(0.2)
        }
    }

    private var resultTextColor: Color {
        switch game.result {
        case "1-0": return .black
        case "0-1": return .white
        case "1/2-1/2": return DS.textPrimary
        default: return DS.textSecondary
        }
    }
}

#Preview {
    GameLibraryView(database: GameDatabase.preview(), onGameSelected: nil, onGameDeleted: nil)
        .frame(width: 500, height: 600)
}
