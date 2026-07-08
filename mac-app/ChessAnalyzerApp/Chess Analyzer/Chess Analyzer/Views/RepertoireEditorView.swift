import SwiftUI

/// First-cut repertoire editor. Reuses BoardView + MoveListView with an in-memory GameTree, and
/// mirrors every change back to SwiftData RepertoireNodes so the tree persists across sessions.
struct RepertoireEditorView: View {
    @EnvironmentObject var repertoireDB: RepertoireDatabase
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    let repertoire: Repertoire
    var onClose: () -> Void

    @StateObject private var board = ChessBoard()
    @StateObject private var gameTree = GameTree()
    @StateObject private var multiEngine = MultiEngineManager()
    @StateObject private var gameAnalyzer = GameAnalyzer()
    @ObservedObject private var settings = AppSettings.shared
    @State private var autoAnalyze = true

    /// In-memory GameNode.id → persisted RepertoireNode.id
    @State private var nodeMap: [UUID: UUID] = [:]
    @State private var isHydrating = false
    @State private var isFlipped = false

    // Inspector draft state (synced from the current RepertoireNode on every navigation)
    @State private var draftOwnership: NodeOwnership = .mineMain
    @State private var draftGlyph: String = ""
    @State private var draftAnnotation: String = ""
    @State private var draftIsPrimary: Bool = true
    @State private var draftIsImportant: Bool = false
    @State private var draftIdeaTags: String = ""
    @State private var draftLinkedECO: String = ""
    @State private var isLoadingDraft = false

    @State private var showingImportPicker = false
    @State private var importMessage: String?

    @State private var drillSession: DrillSession?
    @State private var showingCoverageAudit = false
    @State private var showingStats = false
    @State private var showingOpponentPicker = false
    @State private var opponentBook: OpponentBook?
    @State private var opponentLoading = false

    var body: some View {
        Group {
            if let session = drillSession {
                RepertoireDrillView(session: session, onClose: { drillSession = nil })
            } else {
                editorBody
            }
        }
        .sheet(isPresented: $showingCoverageAudit) {
            CoverageGapView(repertoire: repertoire, referenceDB: referenceDatabase,
                            onClose: { showingCoverageAudit = false })
        }
        .sheet(isPresented: $showingStats) {
            RepertoireStatsView(repertoire: repertoire, repertoireDB: repertoireDB,
                                onClose: { showingStats = false })
        }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                // Left: inspector (mirrors main screen's left sidebar)
                inspector
                    .frame(width: 300)
                    .background(DS.paperRaised)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(
                            DS.hairline
                        ).frame(width: 1)
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(
                            DS.hairline
                        ).frame(height: 1)
                    }
                    .shadow(color: Color.black.opacity(0.31), radius: 25, x: 6, y: 0)

                // Center: board
                BoardView(board: board, gameTree: gameTree, isFlipped: isFlipped)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)

                // Right: engine + move tree (mirrors main screen's right sidebar)
                VStack(spacing: 0) {
                    AnalysisPanelView(
                        multiEngine: multiEngine,
                        gameTree: gameTree,
                        autoAnalyze: $autoAnalyze,
                        gameAnalyzer: gameAnalyzer,
                        onStartAnalysis: {},
                        onCancelAnalysis: {},
                        onNavigateToEngines: {},
                        showAnalyzeButton: false
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DS.hairline).frame(height: 1)
                    }

                    RepertoireMoveTreeView(
                        gameTree: gameTree,
                        nodeMap: nodeMap,
                        repertoire: repertoire,
                        onTap: { node in gameTree.goToNode(node) }
                    )
                }
                .frame(width: 300)
                .background(DS.paperRaised)
                .overlay(alignment: .leading) {
                    Rectangle().fill(
                        DS.hairline
                    ).frame(width: 1)
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(
                        DS.hairline
                    ).frame(height: 1)
                }
                .shadow(color: Color.black.opacity(0.31), radius: 25, x: -6, y: 0)
            }
        }
        .onAppear {
            isFlipped = repertoire.side == .black
            hydrateTree()
            loadDraft()
            startEngineIfConfigured()
        }
        .onChange(of: gameTree.currentNode.id) { _, _ in
            syncBoardToCurrent()
            if !isHydrating {
                persistFromRoot()
            }
            loadDraft()
            if autoAnalyze {
                evaluateCurrentPosition()
            }
        }
        .onChange(of: settings.engineConfigsJSON) { _, _ in
            multiEngine.reconfigure()
        }
        .onChange(of: multiEngine.slots.count) { _, count in
            // Engine just became ready — evaluate the current position
            if count > 0 && autoAnalyze {
                evaluateCurrentPosition()
            }
        }
        .background(
            KeyboardNavigationHandler(
                onLeftArrow: {
                    DispatchQueue.main.async {
                        _ = gameTree.goBack()
                    }
                },
                onRightArrow: {
                    DispatchQueue.main.async {
                        _ = gameTree.goForward()
                    }
                }
            )
        )
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImportPGN(result)
        }
        .fileImporter(
            isPresented: $showingOpponentPicker,
            allowedContentTypes: [.plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            handleOpponentPGN(result)
        }
        .alert("Import", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    // MARK: - Engine

    private func startEngineIfConfigured() {
        guard settings.defaultEngine != nil else {
            multiEngine.stopAllProcesses()
            return
        }
        if multiEngine.slots.isEmpty {
            multiEngine.setup()
        } else {
            multiEngine.reconfigure()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if autoAnalyze {
                evaluateCurrentPosition()
            }
        }
    }

    private func evaluateCurrentPosition() {
        // No anyEngineAvailable guard — evaluateAll is a no-op when slots are empty, and we want
        // the position to be queued so the engine analyzes it as soon as it's ready.
        let boardCopy = gameTree.currentNode.boardState.copy()
        multiEngine.evaluateAll(board: boardCopy, depth: settings.engineDepth)
    }

    private func startDrill() {
        let session = DrillSession(repertoire: repertoire, repertoireDB: repertoireDB, referenceDB: referenceDatabase)
        if let book = opponentBook, !book.isEmpty {
            session.opponentBook = book
            session.replyMode = .opponent   // prep against this opponent by default
        }
        drillSession = session
    }

    /// Load an opponent's games (PGN) into an in-memory book used for prep-mode drilling. Parsed on a
    /// background queue since a tournament export can be thousands of games.
    private func handleOpponentPGN(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        opponentLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            // Use the opponent = the side we're NOT playing, by convention no name filter here
            // (the position's side-to-move already isolates the opponent's replies).
            let book = OpponentBook.build(fileURL: url, opponentName: nil)
            DispatchQueue.main.async {
                opponentLoading = false
                opponentBook = book.isEmpty ? nil : book
                importMessage = book.isEmpty
                    ? "No games could be read from that PGN."
                    : "Loaded \(book.gameCount) opponent games (\(book.plyCount) positions). Start a drill to prep in Opponent mode."
            }
        }
    }

    private func handleImportPGN(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        do {
            let added = try repertoireDB.importPGN(from: url, into: repertoire)
            // Rebuild the in-memory tree from scratch so newly-imported nodes appear.
            resetAndHydrate()
            importMessage = "Imported \(added) new nodes."
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Reset the in-memory GameTree and rebuild it from RepertoireNodes. Used after PGN import.
    private func resetAndHydrate() {
        // Replace GameTree with a fresh one
        let freshTree = GameTree()
        gameTree.root = freshTree.root
        gameTree.currentNode = freshTree.root
        gameTree.rebuildMainLine()
        nodeMap.removeAll()
        hydrateTree()
        loadDraft()
    }

    // MARK: - Current RepertoireNode lookup

    private var currentRepNode: RepertoireNode? {
        guard let repId = nodeMap[gameTree.currentNode.id] else { return nil }
        return repertoire.nodes.first(where: { $0.id == repId })
    }

    private var availableOwnerships: [NodeOwnership] {
        guard let node = currentRepNode else { return [] }
        return node.isUserMove
            ? [.mineMain, .mineAlternative]
            : [.opponentCritical, .opponentSideline, .opponentUnusual]
    }

    private func loadDraft() {
        isLoadingDraft = true
        defer { isLoadingDraft = false }

        guard let node = currentRepNode else {
            draftOwnership = .mineMain
            draftGlyph = ""
            draftAnnotation = ""
            draftIsPrimary = true
            draftIsImportant = false
            draftIdeaTags = ""
            draftLinkedECO = ""
            return
        }
        draftOwnership = node.ownership
        draftGlyph = node.evalGlyph ?? ""
        draftAnnotation = node.annotation
        draftIsPrimary = node.isPrimary
        draftIsImportant = node.isImportant
        draftIdeaTags = node.ideaTags.joined(separator: ", ")
        draftLinkedECO = node.linkedECO ?? ""
    }

    private func saveDraftIdeaTags() {
        guard !isLoadingDraft, let node = currentRepNode else { return }
        let tags = draftIdeaTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        node.ideaTags = tags
        repertoireDB.updateNode(node)
    }

    private func saveDraftLinkedECO() {
        guard !isLoadingDraft, let node = currentRepNode else { return }
        let trimmed = draftLinkedECO.trimmingCharacters(in: .whitespaces)
        node.linkedECO = trimmed.isEmpty ? nil : trimmed.uppercased()
        repertoireDB.updateNode(node)
    }

    private func saveDraftOwnership() {
        guard !isLoadingDraft, let node = currentRepNode else { return }
        node.ownership = draftOwnership
        node.isPrimary = node.isUserMove ? draftIsPrimary : false
        repertoireDB.updateNode(node)
    }

    private func saveDraftGlyph() {
        guard !isLoadingDraft, let node = currentRepNode else { return }
        node.evalGlyph = draftGlyph.isEmpty ? nil : draftGlyph
        repertoireDB.updateNode(node)
    }

    private func saveDraftAnnotation() {
        guard !isLoadingDraft, let node = currentRepNode else { return }
        node.annotation = draftAnnotation
        repertoireDB.updateNode(node)
    }

    private func saveDraftPrimary() {
        guard !isLoadingDraft, let node = currentRepNode, node.isUserMove else { return }
        node.isPrimary = draftIsPrimary
        repertoireDB.updateNode(node)
    }

    private func saveDraftImportant() {
        guard !isLoadingDraft, let node = currentRepNode else { return }
        node.isImportant = draftIsImportant
        repertoireDB.updateNode(node)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.ink60)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Circle()
                .fill(repertoire.side == .white ? Color.white : Color.black)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(DS.borderChip, lineWidth: 1))

            Text(repertoire.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DS.ink)

            Spacer()

            Button(action: startDrill) {
                Image(systemName: "graduationcap")
                    .font(.system(size: 13))
                    .foregroundColor(DS.ink60)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Start drill session")

            Button(action: { showingOpponentPicker = true }) {
                Image(systemName: opponentLoading ? "hourglass" : (opponentBook != nil ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus"))
                    .font(.system(size: 13))
                    .foregroundColor(opponentBook != nil ? DS.accent : DS.ink60)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(opponentLoading)
            .help(opponentBook != nil
                  ? "Opponent games loaded (\(opponentBook!.gameCount)) — drill in Opponent mode"
                  : "Load an opponent's games (PGN) for prep")

            Button(action: { showingStats = true }) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 13))
                    .foregroundColor(DS.ink60)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Knowledge & weak spots")

            Button(action: { showingCoverageAudit = true }) {
                Image(systemName: "exclamationmark.magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(DS.ink60)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Audit coverage against the reference database")

            Button(action: { showingImportPicker = true }) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(DS.ink60)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Import PGN into this repertoire")

            Button(action: { isFlipped.toggle() }) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13))
                    .foregroundColor(DS.ink60)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Flip board")
        }
        .padding(.horizontal, 28)
        .frame(height: 56)
        .background(DS.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                moveTitleSection

                if currentRepNode != nil {
                    Rectangle().fill(DS.hairline).frame(height: 1)
                    ownershipSection

                    Rectangle().fill(DS.hairline).frame(height: 1)
                    glyphSection

                    Rectangle().fill(DS.hairline).frame(height: 1)
                    annotationSection

                    Rectangle().fill(DS.hairline).frame(height: 1)
                    tagsAndECOSection
                } else {
                    Rectangle().fill(DS.hairline).frame(height: 1)
                    rootPrompt
                }
            }
        }
    }

    private var moveTitleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let node = currentRepNode {
                HStack(spacing: 8) {
                    Text(moveTitleText(for: node))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DS.ink)
                    if !draftGlyph.isEmpty {
                        Text(draftGlyph)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(glyphColor(draftGlyph))
                    }
                    Spacer()
                    sideBadge(isUserMove: node.isUserMove)
                }
            } else {
                HStack {
                    Text("Starting position")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.ink)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func moveTitleText(for node: RepertoireNode) -> String {
        let san = node.san ?? node.uciMove ?? "?"
        let parentTurn = gameTree.currentNode.parent?.boardState.turn ?? .white
        let fullMove = gameTree.currentNode.parent?.boardState.fullMoveNumber ?? 1
        let prefix = parentTurn == .white ? "\(fullMove)." : "\(fullMove)..."
        return "\(prefix) \(san)"
    }

    private func sideBadge(isUserMove: Bool) -> some View {
        Text(isUserMove ? "Your move" : "Opponent")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isUserMove ? DS.accent : DS.ink40)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isUserMove ? DS.accent.opacity(0.15) : DS.hoverWash,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }

    private var rootPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Play a move on the board to start building this repertoire. The tree saves automatically as you go.")
                .font(.system(size: 11))
                .foregroundColor(DS.ink40)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: Ownership

    private var ownershipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ownership")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.ink60)
                .kerning(0.4)

            VStack(spacing: 6) {
                ForEach(availableOwnerships, id: \.self) { ownership in
                    ownershipRow(ownership)
                }
            }

            if currentRepNode?.isUserMove == true {
                primaryToggleRow
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func ownershipRow(_ ownership: NodeOwnership) -> some View {
        let isSelected = draftOwnership == ownership
        return Button(action: {
            draftOwnership = ownership
            saveDraftOwnership()
        }) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(isSelected ? DS.accent : DS.borderChip, lineWidth: 1.5)
                    .background(
                        Circle().fill(isSelected ? DS.accent : Color.clear)
                            .padding(3)
                    )
                    .frame(width: 14, height: 14)

                Text(ownership.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DS.textPrimary : DS.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isSelected ? DS.accentLight : Color.clear)
            .cornerRadius(DS.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSM)
                    .strokeBorder(isSelected ? DS.accent.opacity(0.5) : DS.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var primaryToggleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { draftIsPrimary },
                set: { newValue in
                    draftIsPrimary = newValue
                    saveDraftPrimary()
                }
            )) {
                Text("Drill as primary answer")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { draftIsImportant },
                set: { newValue in
                    draftIsImportant = newValue
                    saveDraftImportant()
                }
            )) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(DS.accent)
                    Text("Important for me")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textSecondary)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: Glyph

    private var glyphSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Evaluation")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.ink60)
                .kerning(0.4)

            let glyphs = ["", "!", "!!", "?", "??", "!?", "?!"]
            HStack(spacing: 6) {
                ForEach(glyphs, id: \.self) { g in
                    glyphButton(g)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func glyphButton(_ glyph: String) -> some View {
        let isSelected = draftGlyph == glyph
        let label = glyph.isEmpty ? "—" : glyph
        return Button(action: {
            draftGlyph = glyph
            saveDraftGlyph()
        }) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isSelected ? .white : (glyph.isEmpty ? DS.textTertiary : glyphColor(glyph)))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(isSelected ? glyphColor(glyph) : DS.fieldBg)
                .cornerRadius(DS.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSM)
                        .strokeBorder(DS.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func glyphColor(_ glyph: String) -> Color {
        switch glyph {
        case "!":   return DS.moveBest
        case "!!":  return DS.moveBrilliant
        case "?":   return DS.moveInaccuracy
        case "??":  return DS.moveBlunder
        case "!?":  return DS.moveGreat
        case "?!":  return DS.moveMistake
        default:    return DS.textTertiary
        }
    }

    // MARK: Tags + ECO

    private var tagsAndECOSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Idea tags")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.ink60)
                    .kerning(0.4)

                TextField("e.g. space, prepares e5", text: Binding(
                    get: { draftIdeaTags },
                    set: { newValue in
                        draftIdeaTags = newValue
                        saveDraftIdeaTags()
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.fieldBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DS.borderStrong, lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ECO code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.ink60)
                    .kerning(0.4)

                TextField("e.g. B90", text: Binding(
                    get: { draftLinkedECO },
                    set: { newValue in
                        draftLinkedECO = newValue
                        saveDraftLinkedECO()
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.fieldBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DS.borderStrong, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: Annotation

    private var annotationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.ink60)
                .kerning(0.4)

            TextEditor(text: Binding(
                get: { draftAnnotation },
                set: { newValue in
                    draftAnnotation = newValue
                    saveDraftAnnotation()
                }
            ))
            .scrollContentBackground(.hidden)
            .font(.system(size: 12))
            .frame(minHeight: 120, idealHeight: 140)
            .padding(8)
            .background(DS.bg)
            .cornerRadius(DS.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSM)
                    .strokeBorder(DS.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Hydration

    /// Replay every persisted RepertoireNode into the in-memory GameTree so the user sees
    /// what was previously stored.
    private func hydrateTree() {
        guard let rootRepId = repertoire.rootNodeId,
              let rootRepNode = repertoire.nodes.first(where: { $0.id == rootRepId })
        else {
            // No persisted root — leave fresh GameTree as-is.
            syncBoardToCurrent()
            return
        }

        isHydrating = true
        nodeMap[gameTree.root.id] = rootRepNode.id
        hydrateChildren(of: rootRepNode, gameNode: gameTree.root)
        gameTree.goToStart()
        isHydrating = false
        syncBoardToCurrent()
    }

    private func hydrateChildren(of repNode: RepertoireNode, gameNode: GameNode) {
        for childRep in repNode.children {
            guard let uci = childRep.uciMove,
                  let move = Self.parseUCI(uci, board: gameNode.boardState) else { continue }

            gameTree.currentNode = gameNode
            guard gameTree.addMove(move, notation: childRep.san) else { continue }
            let newGameNode = gameTree.currentNode
            nodeMap[newGameNode.id] = childRep.id
            hydrateChildren(of: childRep, gameNode: newGameNode)
        }
    }

    // MARK: - Board sync

    private func syncBoardToCurrent() {
        let cur = gameTree.currentNode.boardState
        guard board.turn != cur.turn ||
              board.fullMoveNumber != cur.fullMoveNumber ||
              board.squares != cur.squares else { return }
        board.squares = cur.squares
        board.turn = cur.turn
        board.moveHistory = cur.moveHistory
        board.enPassantTarget = cur.enPassantTarget
        board.halfMoveClock = cur.halfMoveClock
        board.fullMoveNumber = cur.fullMoveNumber
    }

    // MARK: - Persistence

    /// Walk root → current; create a RepertoireNode for any GameNode that lacks a mapping.
    /// Idempotent — already-mapped nodes are skipped.
    private func persistFromRoot() {
        // Build path from current node up to root, then reverse it.
        var path: [GameNode] = []
        var cur: GameNode? = gameTree.currentNode
        while let n = cur {
            path.append(n)
            cur = n.parent
        }
        path.reverse()

        for i in 1..<path.count {
            let gn = path[i]
            if nodeMap[gn.id] != nil { continue }

            guard let parentRepId = nodeMap[path[i - 1].id],
                  let parentRep = repertoire.nodes.first(where: { $0.id == parentRepId }),
                  let move = gn.move
            else { continue }

            let uci = Self.uci(from: move)
            let san = gn.cachedNotation

            // Owner = parent side to move (the side that played this move)
            let parentTurn = path[i - 1].boardState.turn
            let isUserMove = parentTurn == (repertoire.side == .white ? .white : .black)

            let ownership: NodeOwnership = isUserMove ? .mineMain : .opponentCritical

            let newRepNode = RepertoireNode(
                repertoire: repertoire,
                parent: parentRep,
                uciMove: uci,
                san: san,
                fen: gn.boardState.getFEN(),
                isUserMove: isUserMove,
                ownership: ownership,
                isPrimary: isUserMove
            )
            nodeMap[gn.id] = newRepNode.id
            repertoireDB.insertNode(newRepNode, into: repertoire, parent: parentRep)
        }
    }

    // MARK: - UCI helpers

    private static func parseUCI(_ uci: String, board: ChessBoard) -> Move? {
        guard uci.count >= 4 else { return nil }
        let chars = Array(uci)
        guard let fromFileAscii = chars[0].asciiValue,
              let toFileAscii = chars[2].asciiValue else { return nil }

        let fromFile = Int(fromFileAscii) - Int(Character("a").asciiValue!)
        guard let fromRank = Int(String(chars[1])) else { return nil }
        let toFile = Int(toFileAscii) - Int(Character("a").asciiValue!)
        guard let toRank = Int(String(chars[3])) else { return nil }

        let from = Position(fromFile, fromRank - 1)
        let to = Position(toFile, toRank - 1)
        guard let piece = board.pieceAt(from) else { return nil }

        var promotionType: PieceType? = nil
        if chars.count >= 5 {
            switch chars[4] {
            case "q": promotionType = .queen
            case "r": promotionType = .rook
            case "b": promotionType = .bishop
            case "n": promotionType = .knight
            default: break
            }
        }

        let capturedPiece = board.pieceAt(to)
        let isEnPassant = piece.type == .pawn && from.file != to.file && capturedPiece == nil
        let isCastling = piece.type == .king && abs(from.file - to.file) == 2

        return Move(
            from: from, to: to, piece: piece,
            capturedPiece: isEnPassant ? board.pieceAt(Position(to.file, from.rank)) : capturedPiece,
            isEnPassant: isEnPassant,
            isCastling: isCastling,
            promotionType: promotionType
        )
    }

    private static func uci(from move: Move) -> String {
        func sq(_ p: Position) -> String {
            let file = Character(UnicodeScalar(Int(Character("a").asciiValue!) + p.file)!)
            return "\(file)\(p.rank + 1)"
        }
        var s = sq(move.from) + sq(move.to)
        if let promo = move.promotionType {
            switch promo {
            case .queen:  s += "q"
            case .rook:   s += "r"
            case .bishop: s += "b"
            case .knight: s += "n"
            default: break
            }
        }
        return s
    }
}
