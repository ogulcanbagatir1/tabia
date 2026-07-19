import SwiftUI

struct RepertoireBrowserView: View {
    @EnvironmentObject var repertoireDB: RepertoireDatabase
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    @EnvironmentObject var database: GameDatabase

    /// Open this repertoire as an analysis tab (recording mode). Wired by MainWindowView.
    var onOpen: (Repertoire) -> Void = { _ in }
    /// Open one of your own games — from the game-link badge on a line. Wired by MainWindowView.
    var onOpenGame: (GameRecord) -> Void = { _ in }

    /// Survives leaving the screen. See BrowserStates.swift for the ownership rule.
    @ObservedObject var browserState: RepertoireBrowserState

    // Forwarding accessors — the body is unchanged; these fields just live in `browserState`.
    private var shelfFilter: ShelfFilter {
        get { browserState.shelfFilter } nonmutating set { browserState.shelfFilter = newValue }
    }
    private var searchText: String {
        get { browserState.searchText } nonmutating set { browserState.searchText = newValue }
    }
    private var selectedRepertoire: Repertoire? {
        get { browserState.selectedRepertoire } nonmutating set { browserState.selectedRepertoire = newValue }
    }
    private var knowledge: [UUID: RepertoireKnowledge] {
        get { browserState.knowledge } nonmutating set { browserState.knowledge = newValue }
    }
    private var forecastBuckets: [Int] {
        get { browserState.forecastBuckets } nonmutating set { browserState.forecastBuckets = newValue }
    }

    @State private var renamingRepertoire: Repertoire?
    @State private var newName = ""
    @State private var repertoireToDelete: Repertoire?
    @State private var showingDeleteAlert = false
    // Active drill session (BEGIN DRILL) — presented full-screen over the library.
    @State private var drillSession: DrillSession?
    // The repertoire selected in the left shelf — its lines show in the center panel.
    @State private var showingKnowledge = false

    // Shelves (RepertoireFolder). The chip row above the grid narrows it to one shelf.
    @State private var renamingFolder: RepertoireFolder?
    @State private var folderToDelete: RepertoireFolder?
    @State private var showingDeleteFolderAlert = false
    @State private var showingNewShelfAlert = false
    @State private var newShelfName = ""
    /// Set when "New Shelf…" is picked from a book's move menu — the book lands on the new shelf.
    @State private var pendingMoveRepertoire: Repertoire?

    // Game linking — replays your games to mark which repertoire lines you actually reached.
    @State private var isLinkingGames = false
    /// The per-repertoire detail sheet (lines tree + Knowledge / Audit / Link Games). Its content is
    /// `centerPanel`, which the shelf layout has no column for.
    @State private var showingLines = false
    @State private var showingCoverageAudit = false
    /// The line whose game-link popover is open (only one at a time).
    @State private var linkedPopoverNodeId: UUID?

    // New repertoire (⇧⌘R / the shelf-row button). Bound from MainWindowView so the menu command
    // can request the sheet even when this screen wasn't mounted at the time.
    @Binding var pendingNewRepertoire: Bool
    @State private var showingNewRepertoireAlert = false
    @State private var newRepertoireName = ""

    enum ShelfFilter: Hashable {
        case all
        /// Built-in shelf: every repertoire for one colour, regardless of folder.
        case side(RepertoireSide)
        case unfiled
        case folder(UUID)
    }

    // Per-repertoire SM-2 knowledge (due/coverage/drilled…) + the 7-day due forecast, computed
    // from the position schedules and cached so cards and the training rail don't re-fetch on render.

    var body: some View {
        Group {
            if let session = drillSession {
                RepertoireDrillView(session: session, onClose: { drillSession = nil })
            } else {
                libraryBody
            }
        }
    }

    private var libraryBody: some View {
        VStack(spacing: 0) {
            if repertoireDB.repertoireCount == 0 {
                emptyState
            } else {
                HStack(spacing: 0) {
                    shelfMain
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    rightRail
                        .frame(width: 400)
                        .overlay(alignment: .leading) { Rectangle().fill(DS.hairline).frame(width: 1) }
                }
                .frame(maxHeight: .infinity)
            }

            statusBar
        }
        .onAppear {
            refreshKnowledge()
            if selectedRepertoire == nil { selectedRepertoire = repertoireDB.repertoires.first }
            consumePendingNewRepertoire()
        }
        // ⇧⌘R arrives while another screen is mounted, so the request is carried in as a flag and
        // picked up here once this screen actually exists.
        .onChange(of: pendingNewRepertoire) { _, _ in consumePendingNewRepertoire() }
        .onChange(of: repertoireDB.repertoires.count) { _, _ in
            refreshKnowledge()
            if selectedRepertoire == nil { selectedRepertoire = repertoireDB.repertoires.first }
        }
        .alert("Rename Repertoire", isPresented: Binding(
            get: { renamingRepertoire != nil },
            set: { if !$0 { renamingRepertoire = nil } }
        )) {
            TextField("Repertoire name", text: $newName)
            Button("Cancel", role: .cancel) { renamingRepertoire = nil }
            Button("Rename") {
                if let rep = renamingRepertoire {
                    repertoireDB.renameRepertoire(rep, to: newName)
                }
                renamingRepertoire = nil
            }
        }
        .alert("Delete Repertoire", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let rep = repertoireToDelete {
                    repertoireDB.deleteRepertoire(rep)
                }
                repertoireToDelete = nil
            }
            Button("Cancel", role: .cancel) { repertoireToDelete = nil }
        } message: {
            Text("This will permanently delete this repertoire and all its lines.")
        }
        .alert("New Repertoire", isPresented: $showingNewRepertoireAlert) {
            TextField("Name", text: $newRepertoireName)
            Button("Cancel", role: .cancel) { newRepertoireName = "" }
            Button("For White") { createRepertoire(side: .white) }
            Button("For Black") { createRepertoire(side: .black) }
        } message: {
            Text("It opens on the Analysis board in recording mode — every move you play is saved into it.")
        }
        .alert("New Shelf", isPresented: $showingNewShelfAlert) {
            TextField("Shelf name", text: $newShelfName)
            Button("Cancel", role: .cancel) { pendingMoveRepertoire = nil; newShelfName = "" }
            Button("Create") {
                let name = newShelfName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let folder = repertoireDB.createFolder(name: name)
                    // Created from a book's move menu — file that book onto the new shelf.
                    if let rep = pendingMoveRepertoire {
                        repertoireDB.moveRepertoire(rep, toFolder: folder.id)
                    }
                }
                pendingMoveRepertoire = nil
                newShelfName = ""
            }
        }
        .alert("Rename Shelf", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Shelf name", text: $newShelfName)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Rename") {
                let name = newShelfName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let folder = renamingFolder, !name.isEmpty {
                    repertoireDB.renameFolder(folder, to: name)
                }
                renamingFolder = nil
            }
        }
        .alert("Delete Shelf", isPresented: $showingDeleteFolderAlert) {
            Button("Delete", role: .destructive) {
                if let folder = folderToDelete {
                    if shelfFilter == .folder(folder.id) { shelfFilter = .all }
                    repertoireDB.deleteFolder(folder, deleteRepertoires: false)
                }
                folderToDelete = nil
            }
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: {
            Text("The shelf is removed. Its repertoires are kept and become Unfiled.")
        }
        .sheet(isPresented: $showingLines) { repertoireDetailSheet }
    }

    // MARK: - Shelf (R1) — "Your Books" grid + training rail

    private var shelfMain: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                (Text("Your Books ").font(AnnFont.serif(26, .semibold)).foregroundColor(DS.ink)
                 + Text("— \(repertoireWord)").font(AnnFont.voice(22)).foregroundColor(DS.ink40))
                Text(aggregateStatLine).font(AnnFont.mono(10)).tracking(0.3).foregroundColor(DS.ink40)
            }
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 14)

            shelfChips
                .padding(.bottom, 18)

            ScrollView {
                // Explicit leading VStack: a ScrollView with multiple children wraps them in an
                // implicit CENTER-aligned stack, which is what pushed the capped grid to the middle.
                VStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                        ForEach(filtered) { rep in
                            bookCard(rep)
                                .contextMenu {
                                    Button("Open") { onOpen(rep) }
                                    Button("Drill") { startDrill(for: rep) }
                                    Divider()
                                    // Knowledge / Audit / Link Games all live inside this sheet.
                                    Button("Lines & Stats…") { selectedRepertoire = rep; showingLines = true }
                                    Divider()
                                    Button("Rename…") { newName = rep.name; renamingRepertoire = rep }
                                    moveToShelfMenu(rep)
                                    Divider()
                                    Button("Delete…", role: .destructive) { repertoireToDelete = rep; showingDeleteAlert = true }
                                }
                        }
                    }
                    // Cap the grid so cards stay a readable size on wide screens instead of stretching
                    // to half the window each; anchored to the start (left) of the shelf.
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 32)

                    Text("Coverage is measured against your own online games — not against theory you'll never meet.")
                        .font(AnnFont.voice(13)).foregroundColor(DS.ink40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DS.paper)
    }

    private var repertoireWord: String {
        let n = repertoireDB.repertoireCount
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let numStr = n < words.count ? words[n] : "\(n)"
        return "\(numStr) repertoire\(n == 1 ? "" : "s"), one habit"
    }

    // MARK: - Left column — "Your Books" (R1)

    // MARK: - Center — selected repertoire's lines (read-only preview; "Open" loads it into Analysis)

    /// The detail sheet. Knowledge and Audit hang off THIS view rather than the shelf, so presenting
    /// them from inside stacks cleanly instead of racing the sheet that is already up.
    private var repertoireDetailSheet: some View {
        VStack(spacing: 0) {
            centerPanel

            HStack {
                Spacer()
                Button(action: { showingLines = false }) { Text("Done") }
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
        .frame(width: 780, height: 660)
        .background(DS.paper)
        .sheet(isPresented: $showingKnowledge) {
            if let rep = selectedRepertoire {
                RepertoireStatsView(repertoire: rep, repertoireDB: repertoireDB,
                                    onClose: { showingKnowledge = false },
                                    preloaded: knowledge[rep.id])
            }
        }
        .sheet(isPresented: $showingCoverageAudit) {
            if let rep = selectedRepertoire {
                CoverageGapView(repertoire: rep, referenceDB: referenceDatabase,
                                onClose: { showingCoverageAudit = false })
            }
        }
    }

    private var centerPanel: some View {
        VStack(spacing: 0) {
            if let rep = selectedRepertoire {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rep.name).font(AnnFont.serif(22, .semibold)).foregroundColor(DS.ink)
                        Text(centerMeta(rep)).font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
                    }
                    Spacer()
                    if let k = knowledge[rep.id], k.dueNow > 0 { dueChip(k.dueNow) }
                    Button(action: { linkGames(for: rep) }) {
                        if isLinkingGames {
                            ProgressView().controlSize(.small).tint(DS.redAccent)
                        } else {
                            Text("Link Games")
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(isLinkingGames)
                    .help("Replay your games and mark the lines you actually reached")
                    Button(action: { showingKnowledge = true }) { Text("Knowledge") }
                        .buttonStyle(GlassButtonStyle())
                    Button(action: { showingCoverageAudit = true }) { Text("Audit") }
                        .buttonStyle(GlassButtonStyle())
                        .help("Check this repertoire against the reference database for unanswered popular replies")
                    Button(action: { showingLines = false; onOpen(rep) }) { Text("Open") }
                        .buttonStyle(GlassButtonStyle())
                }
                .padding(.horizontal, 26).padding(.vertical, 18)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

                linesTree(rep)
            } else {
                centerEmpty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.paper)
    }

    private func centerMeta(_ rep: Repertoire) -> String {
        let cov = Int((knowledge[rep.id]?.coveragePercent ?? 0).rounded())
        return "\(rep.side.displayName.uppercased()) · \(rep.userMoveCount) YOUR MOVES · \(cov)% COVERAGE"
    }

    private var centerEmpty: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 40, weight: .light)).foregroundColor(DS.ink25)
            Text("Select a repertoire").font(AnnFont.serif(18, .semibold)).foregroundColor(DS.ink)
            Text("Pick a book on the left to see its lines here.")
                .font(AnnFont.voice(14)).foregroundColor(DS.ink40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func linesTree(_ rep: Repertoire) -> some View {
        let rows = flattenedLines(rep)
        if rows.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Text("No lines yet").font(AnnFont.serif(17, .medium)).foregroundColor(DS.ink)
                Text("Open it in Analysis to build this repertoire, move by move.")
                    .font(AnnFont.voice(13.5)).foregroundColor(DS.ink40).multilineTextAlignment(.center)
                Button(action: { onOpen(rep) }) { Text("Open") }
                    .buttonStyle(GlassButtonStyle())
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in lineRow(row) }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lineRow(_ row: LineRow) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(row.node.isUserMove ? DS.redAccent : Color.clear)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(row.node.isUserMove ? DS.redAccent : DS.ink40, lineWidth: 1.5))
            Text(moveLabel(row))
                .font(AnnFont.mono(13.5, bold: true)).foregroundColor(DS.ink).fixedSize()
            if !row.node.annotation.isEmpty {
                Text(row.node.annotation).font(AnnFont.voice(13)).foregroundColor(DS.ink40).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !row.node.gameLinkIdStrings.isEmpty {
                let n = row.node.gameLinkIdStrings.count
                Button(action: {
                    linkedPopoverNodeId = linkedPopoverNodeId == row.node.id ? nil : row.node.id
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "flag.checkered").font(.system(size: 8, weight: .semibold))
                        Text("\(n)").font(AnnFont.mono(9.5, bold: true))
                    }
                    .foregroundColor(DS.ink60)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(n) of your games reached this position — click to list them")
                .popover(isPresented: Binding(
                    get: { linkedPopoverNodeId == row.node.id },
                    set: { if !$0 && linkedPopoverNodeId == row.node.id { linkedPopoverNodeId = nil } }
                ), arrowEdge: .bottom) {
                    linkedGamesPopover(row.node)
                }
            }
            if row.node.isUserMove {
                Text(row.node.isPrimary ? "MAIN" : "ALT")
                    .font(AnnFont.label(8.5)).tracking(8.5 * 0.12).foregroundColor(DS.ink40)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, CGFloat(row.depth) * 22 + 4)
        .padding(.trailing, 8)
    }

    private func moveLabel(_ row: LineRow) -> String {
        let san = row.node.san ?? row.node.uciMove ?? "—"
        let isWhite = row.ply % 2 == 1
        let num = (row.ply + 1) / 2
        return isWhite ? "\(num). \(san)" : "\(num)… \(san)"
    }

    private struct LineRow: Identifiable {
        let id: UUID
        let node: RepertoireNode
        let depth: Int
        let ply: Int
    }

    private func flattenedLines(_ rep: Repertoire) -> [LineRow] {
        guard let root = rep.nodes.first(where: { $0.id == rep.rootNodeId })
                ?? rep.nodes.first(where: { $0.parent == nil }) else { return [] }
        var rows: [LineRow] = []
        func walk(_ node: RepertoireNode, depth: Int, ply: Int) {
            let kids = node.children.sorted { a, b in
                if a.isPrimary != b.isPrimary { return a.isPrimary }
                return (a.san ?? "") < (b.san ?? "")
            }
            for (i, child) in kids.enumerated() {
                let d = i == 0 ? depth : depth + 1
                rows.append(LineRow(id: child.id, node: child, depth: d, ply: ply + 1))
                walk(child, depth: d, ply: ply + 1)
            }
        }
        walk(root, depth: 0, ply: 0)
        return rows
    }

    private func dueChip(_ n: Int) -> some View {
        Text("\(n) DUE")
            .font(AnnFont.mono(10, bold: true)).foregroundColor(DS.redAccent)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous).strokeBorder(DS.redAccent, lineWidth: 1))
    }

    // MARK: - Grid (reuses rootDatabaseCard styling)

    private var filtered: [Repertoire] {
        let onShelf: [Repertoire]
        switch shelfFilter {
        case .all:
            onShelf = repertoireDB.repertoires
        case .side(let side):
            onShelf = repertoireDB.repertoires(side: side)
        case .unfiled:
            onShelf = repertoireDB.repertoires(in: nil)
        case .folder(let id):
            // A shelf deleted out from under the selection falls back to everything.
            onShelf = repertoireDB.folders.contains { $0.id == id }
                ? repertoireDB.repertoires(in: id)
                : repertoireDB.repertoires
        }
        guard !searchText.isEmpty else { return onShelf }
        return onShelf.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - New Repertoire

    /// The shelf the new repertoire should land on — whichever one is currently filtered to.
    private var activeShelfFolder: RepertoireFolder? {
        guard case .folder(let id) = shelfFilter else { return nil }
        return repertoireDB.folders.first { $0.id == id }
    }

    private func consumePendingNewRepertoire() {
        guard pendingNewRepertoire else { return }
        pendingNewRepertoire = false
        newRepertoireName = ""
        showingNewRepertoireAlert = true
    }

    private func createRepertoire(side: RepertoireSide) {
        let trimmed = newRepertoireName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rep = repertoireDB.createRepertoire(
            name: trimmed.isEmpty ? "New Repertoire" : trimmed,
            side: side,
            folder: activeShelfFolder
        )
        newRepertoireName = ""
        selectedRepertoire = rep
        onOpen(rep)   // straight into recording mode — moves you play are saved into it
    }

    // MARK: - Game Linking

    /// The games recorded on a line. Links can outlive the games themselves (deleted from the
    /// library after linking), so resolve rather than trusting the stored count.
    private func linkedGamesPopover(_ node: RepertoireNode) -> some View {
        let games = node.gameLinkIds.compactMap { database.game(withId: $0) }

        return VStack(alignment: .leading, spacing: 0) {
            Text("YOUR GAMES HERE")
                .font(AnnFont.label(9)).tracking(9 * 0.14).foregroundColor(DS.ink40)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            if games.isEmpty {
                Text("These games are no longer in your library. Re-run Link Games to refresh.")
                    .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(games, id: \.id) { game in
                            Button(action: {
                                linkedPopoverNodeId = nil
                                onOpenGame(game)
                            }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(game.white) — \(game.black)")
                                        .font(AnnFont.serif(13)).foregroundColor(DS.ink).lineLimit(1)
                                    Text("\(game.result)  ·  \(game.date)")
                                        .font(AnnFont.mono(10)).foregroundColor(DS.ink40)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 290)
        .background(DS.paper)
    }

    /// Replay every game in the store against this repertoire and mark the nodes reached.
    private func linkGames(for rep: Repertoire) {
        guard !isLinkingGames else { return }
        isLinkingGames = true
        repertoireDB.rebuildGameLinks(for: rep, games: database.allGames()) { _ in
            isLinkingGames = false
        }
    }

    // MARK: - Shelves (RepertoireFolder)

    private var unfiledCount: Int { repertoireDB.repertoires(in: nil).count }

    private var shelfChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                shelfChip(title: "All", count: repertoireDB.repertoireCount, filter: .all)

                // Colour is the one split every repertoire has, so it ships as a built-in shelf.
                shelfChip(title: "White",
                          count: repertoireDB.repertoires(side: .white).count,
                          filter: .side(.white))
                shelfChip(title: "Black",
                          count: repertoireDB.repertoires(side: .black).count,
                          filter: .side(.black))

                ForEach(repertoireDB.folders, id: \.id) { folder in
                    shelfChip(title: folder.name,
                              count: repertoireDB.repertoiresInFolderCount(folder.id),
                              filter: .folder(folder.id))
                        .contextMenu {
                            Button("Rename…") { newShelfName = folder.name; renamingFolder = folder }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                folderToDelete = folder
                                showingDeleteFolderAlert = true
                            }
                        }
                }

                // Keep the chip while it's the active filter, even once it empties out.
                if unfiledCount > 0 || shelfFilter == .unfiled {
                    shelfChip(title: "Unfiled", count: unfiledCount, filter: .unfiled)
                }

                addButton(title: "Shelf", help: "New shelf") {
                    newShelfName = ""; pendingMoveRepertoire = nil; showingNewShelfAlert = true
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func addButton(title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                Text(title).font(AnnFont.label(10)).tracking(0.9)
            }
            .foregroundColor(DS.ink60)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(DS.paperRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.borderChip, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func shelfChip(title: String, count: Int, filter: ShelfFilter) -> some View {
        let isSelected = shelfFilter == filter

        return Button(action: { withAnimation(DS.quickFade) { shelfFilter = filter } }) {
            HStack(spacing: 6) {
                Text(title).font(AnnFont.serif(13, .regular))
                Text("\(count)").font(AnnFont.mono(10))
                    .foregroundColor(isSelected ? DS.ink60 : DS.ink25)
            }
            .foregroundColor(isSelected ? DS.ink : DS.ink60)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? DS.selectedWash : DS.paperRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? DS.ink40 : DS.borderChip, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func moveToShelfMenu(_ rep: Repertoire) -> some View {
        Menu("Move to Shelf") {
            ForEach(repertoireDB.folders, id: \.id) { folder in
                Button(folder.name) { repertoireDB.moveRepertoire(rep, toFolder: folder.id) }
                    .disabled(rep.folder?.id == folder.id)
            }
            if !repertoireDB.folders.isEmpty { Divider() }
            Button("Unfiled") { repertoireDB.moveRepertoire(rep, toFolder: nil) }
                .disabled(rep.folder == nil)
            Divider()
            Button("New Shelf…") {
                pendingMoveRepertoire = rep
                newShelfName = ""
                showingNewShelfAlert = true
            }
        }
    }

    // MARK: - Right rail — Training Queue + 7-day forecast (R1)

    private var rightRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            trainingQueueCard
            forecastCard
            Text("Twenty cards a day keeps the whole shelf warm. Miss a day and the queue forgives — the intervals just tighten.")
                .font(AnnFont.voice(13)).foregroundColor(DS.ink40).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 26)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.paper)
    }

    private var trainingQueueCard: some View {
        let totalDue = knowledge.values.reduce(0) { $0 + $1.dueNow }
        let drilled = knowledge.values.reduce(0) { $0 + $1.drilledDecisions }
        let mature = knowledge.values.reduce(0) { $0 + $1.matureDecisions }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TRAINING QUEUE").font(AnnFont.label(10)).tracking(10 * 0.14).foregroundColor(DS.ink40)
                Spacer()
                Text("SM-2").font(AnnFont.mono(10)).foregroundColor(DS.ink40)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(totalDue)").font(AnnFont.serif(44, .semibold)).foregroundColor(DS.ink)
                Text("CARDS DUE TODAY").font(AnnFont.mono(10.5)).foregroundColor(DS.ink60)
            }
            HStack(spacing: 20) {
                queueStat("\(drilled)", "DRILLED")
                queueStat("\(mature)", "MATURE")
                queueStat("\(averageRetention)%", "RETENTION")
            }
            Text("Drill a book from its card on the left.")
                .font(AnnFont.voice(11.5)).foregroundColor(DS.ink40)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    private func queueStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(AnnFont.mono(13, bold: true)).foregroundColor(DS.ink)
            Text(label).font(AnnFont.mono(9)).foregroundColor(DS.ink40)
        }
    }

    private var forecastCard: some View {
        let maxCount = max(forecastBuckets.max() ?? 1, 1)
        let labels = forecastDayLabels
        return VStack(alignment: .leading, spacing: 10) {
            Text("NEXT 7 DAYS").font(AnnFont.label(10)).tracking(10 * 0.14).foregroundColor(DS.ink40)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Text("\(forecastBuckets[i])").font(AnnFont.mono(8.5)).foregroundColor(DS.ink60)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DS.borderChip)
                            .frame(height: max(CGFloat(forecastBuckets[i]) / CGFloat(maxCount) * 46, 3))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    Text(labels[i]).font(AnnFont.mono(8)).foregroundColor(DS.ink25)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    // MARK: - Book card (R1)

    private func bookCard(_ rep: Repertoire, selected: Bool = false) -> some View {
        let k = knowledge[rep.id] ?? .empty
        let cov = Int(k.coveragePercent.rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(rep.name).font(AnnFont.serif(21, .semibold)).foregroundColor(DS.ink).lineLimit(1)
                Spacer(minLength: 6)
                if k.dueNow > 0 { dueChip(k.dueNow) }
            }
            Text(sideLabel(rep))
                .font(AnnFont.label(9)).tracking(9 * 0.12).foregroundColor(DS.ink40).lineLimit(1)
            HStack(spacing: 22) {
                statSpan("\(rep.nodeCount)", "POSITIONS")
                statSpan("\(rep.userMoveCount)", "YOUR MOVES")
            }
            HStack(spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.trackBg)
                        Capsule().fill(DS.semWin)
                            .frame(width: g.size.width * CGFloat(min(max(cov, 0), 100)) / 100)
                    }
                }
                .frame(height: 5)
                Text("\(cov)% COVERED").font(AnnFont.mono(10.5)).foregroundColor(DS.ink60).fixedSize()
            }
            Text(revisedLine(rep.dateModified)).font(AnnFont.mono(9.5)).foregroundColor(DS.ink25)

            HStack(spacing: 8) {
                cardButton("Edit", filled: false) { onOpen(rep) }
                cardButton("Drill", filled: true) { startDrill(for: rep) }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? DS.selectedMove : DS.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? DS.redAccent : DS.hairline, lineWidth: selected ? 1.5 : 1))
    }

    private func cardButton(_ title: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AnnFont.label(10.5)).tracking(10.5 * 0.1)
                .foregroundColor(filled ? DS.onRed : DS.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(filled ? DS.redAccent : DS.fieldBg,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(filled ? Color.clear : DS.hairline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statSpan(_ value: String, _ label: String) -> some View {
        (Text(value + " ").font(AnnFont.mono(11, bold: true))
         + Text(label).font(AnnFont.mono(11))).foregroundColor(DS.ink)
    }

    // MARK: - Derived data

    private func sideLabel(_ rep: Repertoire) -> String {
        var s = rep.side.displayName.uppercased()
        if let eco = rep.ecoRangeDisplay, !eco.isEmpty { s += " · \(eco)" }
        return s
    }

    private func revisedLine(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        let day = 86_400.0
        if secs < day { return "REVISED TODAY" }
        let days = Int(secs / day)
        if days < 7 { return "REVISED \(days)D AGO" }
        let weeks = days / 7
        if weeks < 5 { return "REVISED \(weeks)W AGO" }
        return "REVISED \(days / 30)MO AGO"
    }

    private var aggregateStatLine: String {
        let moves = repertoireDB.repertoires.reduce(0) { $0 + $1.nodeCount }
        let yours = repertoireDB.repertoires.reduce(0) { $0 + $1.userMoveCount }
        let covs = repertoireDB.repertoires.compactMap { knowledge[$0.id]?.coveragePercent }
        let avg = covs.isEmpty ? 0 : Int((covs.reduce(0, +) / Double(covs.count)).rounded())
        return "\(moves) MOVES · \(yours) YOURS · AVG COVERAGE \(avg)%"
    }

    private var averageRetention: Int {
        let vals = knowledge.values.map { $0.knowledgePercent }
        guard !vals.isEmpty else { return 0 }
        return Int((vals.reduce(0, +) / Double(vals.count)).rounded())
    }

    private var forecastDayLabels: [String] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        let today = cal.startOfDay(for: Date())
        return (0..<7).map { i in
            fmt.string(from: cal.date(byAdding: .day, value: i, to: today) ?? today).uppercased()
        }
    }

    private func startDrill(for rep: Repertoire) {
        drillSession = DrillSession(repertoire: rep, repertoireDB: repertoireDB, referenceDB: referenceDatabase)
    }

    private func refreshKnowledge() {
        var map: [UUID: RepertoireKnowledge] = [:]
        var buckets = [Int](repeating: 0, count: 7)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for rep in repertoireDB.repertoires {
            let schedMap = repertoireDB.positionSchedules(for: rep.id)
            map[rep.id] = RepertoireStatsBuilder.build(repertoire: rep, schedules: schedMap.mapValues { $0.stats })
            for sched in schedMap.values {
                guard let due = sched.stats.nextDue else { continue }
                let d = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 0
                buckets[max(0, min(6, d))] += 1
            }
        }
        knowledge = map
        forecastBuckets = buckets
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.textTertiary)

            VStack(spacing: 8) {
                Text("No Repertoires Yet")
                    .font(AnnFont.serif(20, .semibold))
                    .foregroundColor(DS.textPrimary)

                Text("Start one here, or build a line on the Analysis board and Save it as a repertoire. Either way it lands here, ready to drill.")
                    .font(AnnFont.serif(13))
                    .foregroundColor(DS.textTertiary)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(action: { newRepertoireName = ""; showingNewRepertoireAlert = true }) {
                Text("New Repertoire")
            }
            .buttonStyle(GlassButtonStyle())

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        let moves = repertoireDB.repertoires.reduce(0) { $0 + $1.nodeCount }
        let due = knowledge.values.reduce(0) { $0 + $1.dueNow }
        return HStack {
            Text("\(repertoireDB.repertoireCount) REPERTOIRES · \(moves) MOVES · \(due) DUE")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
            Spacer()
            Text("SPACED REPETITION · SM-2")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
        }
        .padding(.horizontal, 18)
        .frame(height: 28)
        .background(DS.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
