import SwiftUI

/// First-cut repertoire editor. Reuses BoardView + MoveListView with an in-memory GameTree, and
/// mirrors every change back to SwiftData RepertoireNodes so the tree persists across sessions.
struct RepertoireEditorView: View {
    @EnvironmentObject var repertoireDB: RepertoireDatabase
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    let repertoire: Repertoire
    var onClose: () -> Void
    /// When true, jump straight into a drill session on appear (used by the shelf's BEGIN DRILL).
    var autoStartDrill: Bool = false

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

    // MARK: - R6 Board Input mode (per R6-BOARD-INPUT.md)
    enum CenterMode { case tree, board }
    @State private var centerMode: CenterMode = .tree
    @State private var sanInput: String = ""
    @State private var sanError: Bool = false
    @State private var mergeToast: String? = nil
    @State private var dueCount: Int = 0
    /// Masters "tries" for the cursor position — recomputed off the render path on cursor change.
    @State private var r6Tries: ReferenceExplorerResult = ReferenceExplorerResult()
    @State private var showingOpponentPicker = false
    @State private var opponentBook: OpponentBook?
    @State private var opponentLoading = false

    // MARK: - R2 spec (standalone manuscript, per R2-REPERTOIRE-EDITOR.md)
    private struct SpecRow: Identifiable {
        let id: Int
        let depth: Int
        let mine: Bool          // filled dot = your move; hollow = theirs
        let san: String
        let note: String?
        let chip: String?       // "MAIN" | "ALT"
        let gap: Bool
    }
    private static let specRows: [SpecRow] = [
        .init(id: 0,  depth: 0, mine: false, san: "1.e4",   note: nil, chip: nil, gap: false),
        .init(id: 1,  depth: 0, mine: true,  san: "1…c6",   note: "the Caro-Kann — your defence", chip: "MAIN", gap: false),
        .init(id: 2,  depth: 0, mine: false, san: "2.d4",   note: nil, chip: nil, gap: false),
        .init(id: 3,  depth: 0, mine: true,  san: "2…d5",   note: nil, chip: "MAIN", gap: false),
        .init(id: 4,  depth: 1, mine: false, san: "3.e5",   note: "Advance Variation", chip: nil, gap: false),
        .init(id: 5,  depth: 1, mine: true,  san: "3…Bf5",  note: "bishop out before …e6", chip: "MAIN", gap: false),
        .init(id: 6,  depth: 2, mine: false, san: "4.Nf3",  note: nil, chip: nil, gap: false),
        .init(id: 7,  depth: 2, mine: true,  san: "4…e6",   note: nil, chip: "MAIN", gap: false),
        .init(id: 8,  depth: 2, mine: false, san: "4.h4",   note: "the aggressive try", chip: nil, gap: false),
        .init(id: 9,  depth: 2, mine: true,  san: "4…h5",   note: "fix the pawn", chip: "ALT", gap: false),
        .init(id: 10, depth: 1, mine: false, san: "3.exd5", note: "Exchange Variation", chip: nil, gap: false),
        .init(id: 11, depth: 1, mine: true,  san: "3…cxd5", note: nil, chip: "MAIN", gap: false),
        .init(id: 12, depth: 1, mine: false, san: "3.Nc3",  note: "Classical", chip: nil, gap: false),
        .init(id: 13, depth: 1, mine: true,  san: "3…dxe4", note: nil, chip: "MAIN", gap: false),
        .init(id: 14, depth: 1, mine: false, san: "3.f3",   note: "Fantasy Variation", chip: nil, gap: true),
    ]
    @State private var specSel: Int = 5
    @State private var specOwnershipMain = true
    @State private var specDrillPrimary = true
    @State private var specImportant = false
    @State private var specEval = "—"
    @State private var specNote = "The point of the whole line: the bad bishop leaves home before …e6 locks it in."

    var body: some View {
        Group {
            if let session = drillSession {
                // If the editor was opened purely to drill (BEGIN DRILL on the shelf), closing the
                // drill should return to the shelf, not drop into the editor the user never asked for.
                RepertoireDrillView(session: session, onClose: {
                    if autoStartDrill { onClose() } else { drillSession = nil }
                })
            } else {
                editorBody
            }
        }
        .onAppear {
            if autoStartDrill && drillSession == nil { startDrill() }
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
            editorHeader
            HStack(spacing: 0) {
                if centerMode == .tree {
                    specInspector
                        .frame(width: 300)
                        .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }
                    // Tree and board+engine SHARE the remaining width equally (both flexible), so the
                    // board fills roughly half — big, not a tiny square lost in one giant column.
                    specCenter
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                    specRight
                        .frame(minWidth: 440, maxWidth: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(DS.hairline).frame(width: 1) }
                } else {
                    // BOARD INPUT: same move inspector as TREE on the left · board fills the center ·
                    // full engine view + the move tree beneath it on the right.
                    specInspector
                        .frame(width: 300)
                        .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }
                    r6BoardCenter
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    r6EngineMovesPane
                        .frame(width: 400)
                        .overlay(alignment: .leading) { Rectangle().fill(DS.hairline).frame(width: 1) }
                }
            }
            .frame(maxHeight: .infinity)
            centerMode == .board ? AnyView(r6StatusBar) : AnyView(specStatusBar)
        }
        .background(DS.paper)
        .onAppear {
            isFlipped = repertoire.side == .black
            hydrateTree()
            loadDraft()
            startEngineIfConfigured()
            // An empty repertoire never shows an empty tree — it shows a board to record into (R6 §1).
            if repertoire.nodeCount <= 1 { centerMode = .board }
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
            refreshR6Tries()
            refreshDueCount()
        }
        .onAppear { refreshR6Tries(); refreshDueCount() }
        .onChange(of: centerMode) { _, m in if m == .board { refreshR6Tries() } }
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

    // MARK: - R2 spec screen

    private var selectedSpecRow: SpecRow { Self.specRows.first { $0.id == specSel } ?? Self.specRows[5] }

    // Real repertoire tree (from the hydrated gameTree + nodeMap), flattened for the spec-styled rows.
    private struct EditorRow: Identifiable {
        let id: UUID
        let node: GameNode
        let repNode: RepertoireNode?
        let depth: Int
        let ply: Int
    }

    /// [RepertoireNode.id : node] built once — avoids an O(nodes) linear scan per lookup.
    private var repIndex: [UUID: RepertoireNode] {
        Dictionary(repertoire.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var realTreeRows: [EditorRow] {
        var rows: [EditorRow] = []
        let index = repIndex
        func rep(for node: GameNode) -> RepertoireNode? {
            nodeMap[node.id].flatMap { index[$0] }
        }
        func walk(_ parent: GameNode, depth: Int, ply: Int) {
            guard let main = parent.children.first else { return }
            // The main move stays on this line…
            rows.append(EditorRow(id: main.id, node: main, repNode: rep(for: main), depth: depth, ply: ply + 1))
            // …then any alternatives to it are shown INDENTED right below the branch point (not
            // dumped at the very bottom of the tree), so a freshly created line's first move sits
            // directly under the move it deviates from.
            for variation in parent.children.dropFirst() {
                rows.append(EditorRow(id: variation.id, node: variation, repNode: rep(for: variation), depth: depth + 1, ply: ply + 1))
                walk(variation, depth: depth + 1, ply: ply + 1)
            }
            // Continue the main line after its variations.
            walk(main, depth: depth, ply: ply + 1)
        }
        walk(gameTree.root, depth: 0, ply: 0)
        return rows
    }

    private func realMoveLabel(_ row: EditorRow) -> String {
        let san = row.node.cachedNotation ?? "?"
        let isWhite = row.ply % 2 == 1
        let num = (row.ply + 1) / 2
        return isWhite ? "\(num). \(san)" : "\(num)… \(san)"
    }

    private var realEditorMeta: String {
        "\(repertoire.side.displayName.uppercased()) · \(repertoire.nodeCount) MOVES"
    }

    private func figurineSAN(_ san: String) -> String {
        let black = san.contains("…")
        let map: [Character: String] = black
            ? ["K": "♚", "Q": "♛", "R": "♜", "B": "♝", "N": "♞"]
            : ["K": "♔", "Q": "♕", "R": "♖", "B": "♗", "N": "♘"]
        var out = ""; var done = false
        for ch in san {
            if !done, let g = map[ch] { out += g; done = true } else { out.append(ch) }
        }
        return out
    }

    // MARK: LEFT — Move Inspector (292)

    private var specInspector: some View {
        let node = currentRepNode
        let mine = node?.isUserMove ?? false
        let title = node.map { figurineSAN(moveTitleText(for: $0)) } ?? "Starting position"
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("MOVE INSPECTOR").font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
                    HStack(spacing: 10) {
                        Text(title)
                            .font(node == nil ? AnnFont.serif(16, .semibold) : AnnFont.mono(22, bold: true))
                            .foregroundColor(DS.ink)
                        if node != nil {
                            Text(mine ? "YOUR MOVE" : "THEIR MOVE")
                                .font(AnnFont.label(8.5, bold: true)).tracking(8.5 * 0.1).foregroundColor(DS.redAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(DS.redAccent, lineWidth: 1))
                        }
                        Spacer(minLength: 0)
                    }
                }

                // These controls are bound to the persisted draft* state (→ repertoireDB.updateNode),
                // so every edit is saved to the RepertoireNode — not to throwaway mock state.
                if node != nil {
                    if mine {
                        specSection("OWNERSHIP") {
                            VStack(spacing: 6) {
                                specOwnershipRow(main: true)
                                specOwnershipRow(main: false)
                            }
                        }
                    }

                    specSection("FLAGS") {
                        VStack(alignment: .leading, spacing: 10) {
                            if mine {
                                specCheckbox("DRILL AS PRIMARY ANSWER", Binding(
                                    get: { draftIsPrimary },
                                    set: { draftIsPrimary = $0; saveDraftPrimary() }))
                            }
                            specCheckbox("IMPORTANT FOR ME ✦", Binding(
                                get: { draftIsImportant },
                                set: { draftIsImportant = $0; saveDraftImportant() }))
                        }
                    }

                    specSection("EVALUATION") {
                        HStack(spacing: 6) {
                            specEvalChip("—", nil)
                            specEvalChip("!", DS.qBrilliant)
                            specEvalChip("!!", DS.qBrilliant)
                            specEvalChip("?!", DS.qInaccuracy)
                            specEvalChip("?", DS.qMistake)
                            specEvalChip("??", DS.qBlunder)
                        }
                    }

                    specSection("NOTE") {
                        TextEditor(text: Binding(
                            get: { draftAnnotation },
                            set: { draftAnnotation = $0; saveDraftAnnotation() }))
                            .font(AnnFont.serif(13.5, .regular, italic: true))
                            .foregroundColor(DS.ink).lineSpacing(4)
                            .scrollContentBackground(.hidden)
                            .padding(10).frame(minHeight: 72)
                            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                    }

                    specSection("IDEA TAGS") {
                        TextField("comma, separated, ideas", text: Binding(
                            get: { draftIdeaTags },
                            set: { draftIdeaTags = $0; saveDraftIdeaTags() }))
                            .textFieldStyle(.plain).font(AnnFont.mono(11))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                    }

                    Spacer(minLength: 20)

                    specSection("ECO") {
                        TextField("e.g. B12", text: Binding(
                            get: { draftLinkedECO },
                            set: { draftLinkedECO = $0; saveDraftLinkedECO() }))
                            .textFieldStyle(.plain).font(AnnFont.mono(11, bold: true)).foregroundColor(DS.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
                    }
                } else {
                    Text("Play a move on the board to start building this repertoire. The tree saves automatically as you go.")
                        .font(AnnFont.serif(12)).foregroundColor(DS.ink40).lineSpacing(3)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .frame(minHeight: 700, alignment: .top)
        }
        .background(DS.paper)
    }

    private func specSection<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
            content()
        }
    }

    private func specOwnershipRow(main: Bool) -> some View {
        let selected = (draftOwnership == .mineMain) == main
        return Button(action: { draftOwnership = main ? .mineMain : .mineAlternative; saveDraftOwnership() }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(selected && main ? DS.redAccent : Color.clear)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(selected ? DS.redAccent : DS.ink25, lineWidth: 1.5))
                Text(main ? "MAIN — drilled as the answer" : "ALTERNATIVE — accepted in drills")
                    .font(AnnFont.mono(11.5)).foregroundColor(selected ? DS.ink : DS.ink60)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background((selected ? DS.selectedWash : Color.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(selected ? DS.borderStrong : DS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func specCheckbox(_ label: String, _ on: Binding<Bool>) -> some View {
        Button(action: { on.wrappedValue.toggle() }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(on.wrappedValue ? DS.redInk : Color.clear)
                    .frame(width: 15, height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(on.wrappedValue ? DS.redInk : DS.borderStrong, lineWidth: 1))
                    .overlay(on.wrappedValue ? Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(DS.onRed) : nil)
                Text(label).font(AnnFont.mono(11)).foregroundColor(on.wrappedValue ? DS.inkPV : DS.ink40)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func specEvalChip(_ glyph: String, _ color: Color?) -> some View {
        // "—" means "no glyph", which the model stores as an empty string.
        let value = glyph == "—" ? "" : glyph
        let selected = draftGlyph == value
        let fg: Color = glyph == "—" ? (selected ? DS.onInk : DS.ink60) : (selected ? DS.onRed : (color ?? DS.ink60))
        let bg: Color = selected ? (glyph == "—" ? DS.ink : (color ?? DS.ink)) : Color.clear
        return Button(action: { draftGlyph = value; saveDraftGlyph() }) {
            Text(glyph).font(AnnFont.mono(12, bold: true)).foregroundColor(fg)
                .padding(.vertical, 5).padding(.horizontal, 10)
                .background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(selected ? Color.clear : DS.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func specTag(_ text: String, dashed: Bool) -> some View {
        Text(text).font(AnnFont.mono(10)).foregroundColor(dashed ? DS.ink40 : DS.inkPV)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(DS.borderStrong, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : []))
            )
    }

    // MARK: CENTER — Variation tree

    // Shared editor header (below the standard masthead): title · TREE|BOARD segmented (⌥T) ·
    // recording indicator (BOARD only) · DUE badge. Spans the full editor width above both layouts.
    private var editorHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onClose) {
                HStack(spacing: 7) {
                    Text(repertoire.name.isEmpty ? "Caro-Kann" : repertoire.name)
                        .font(AnnFont.serif(20, .semibold)).foregroundColor(DS.ink)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundColor(DS.ink40)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to the shelf")

            HStack(spacing: 8) {
                AnnSegmented(options: [(CenterMode.tree, "Tree"), (CenterMode.board, "Board")],
                             selection: $centerMode, size: 9.5)
                Text("⌥T").font(AnnFont.mono(10)).foregroundColor(DS.ink40)
            }

            if centerMode == .board {
                HStack(spacing: 7) {
                    PulsingDot(color: DS.redAccent, size: 8)
                    Text("RECORDING INTO \(repertoire.name.isEmpty ? "REPERTOIRE" : repertoire.name.uppercased())")
                        .font(AnnFont.label(9.5, bold: true)).tracking(9.5 * 0.1).foregroundColor(DS.redAccent)
                }
            }

            Spacer(minLength: 8)
            Text(realEditorMeta).font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
            if dueCount > 0 {
                Text("\(dueCount) DUE").font(AnnFont.mono(10, bold: true)).foregroundColor(DS.redAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(DS.redAccent, lineWidth: 1))
            }
        }
        .padding(.leading, 26).padding(.trailing, 26).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
        .background(
            Group {
                Button("") { centerMode = centerMode == .tree ? .board : .tree }
                    .keyboardShortcut("t", modifiers: .option)
                Button("") { r6PromoteToMain() }
                    .keyboardShortcut(.return, modifiers: .option)
            }
            .opacity(0)
        )
    }

    private var specCenter: some View {
        VStack(spacing: 0) {
            let rows = realTreeRows
            if rows.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No lines yet").font(AnnFont.serif(17, .medium)).foregroundColor(DS.ink)
                    Text("Play moves on the board to build this repertoire. It autosaves as you go.")
                        .font(AnnFont.voice(13)).foregroundColor(DS.ink40).multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(rows) { row in specTreeRow(row) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Solid dots are your moves; hollow dots are theirs. Autosaved as you write.")
                        .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 18)
                }
            }
        }
        .background(DS.paper)
    }

    private func specTreeRow(_ row: EditorRow) -> some View {
        let selected = gameTree.currentNode.id == row.id
        let mine = row.repNode?.isUserMove ?? false
        let chip: String? = mine ? ((row.repNode?.isPrimary ?? true) ? "MAIN" : "ALT") : nil
        let note = row.repNode?.annotation ?? ""
        return Button(action: { gameTree.goToNode(row.node) }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(mine ? DS.redAccent : Color.clear)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(mine ? DS.redAccent : DS.ink25, lineWidth: 1.5))
                Text(realMoveLabel(row)).font(AnnFont.mono(13.5, bold: true)).foregroundColor(DS.ink).fixedSize()
                if !note.isEmpty {
                    Text(note).font(AnnFont.serif(13, .regular, italic: true)).foregroundColor(DS.ink60).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let chip {
                    Text(chip).font(AnnFont.label(8.5, bold: true)).tracking(8.5 * 0.1).foregroundColor(DS.ink60)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
                }
            }
            .padding(.vertical, 7).padding(.trailing, 10)
            .padding(.leading, CGFloat(18 + row.depth * 26))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((selected ? DS.selectedWash : Color.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: RIGHT — Board & context (396)

    private var specRight: some View {
        GeometryReader { geo in
        // Board scales to fill the column (width- or height-bound), so it's never a tiny square lost
        // in a wide near-empty band. Reserve vertical room for the engine + deviations below.
        let boardSize = max(min(geo.size.width - 40, geo.size.height - 250, 620), 260)
        VStack(alignment: .leading, spacing: 16) {
            BoardView(board: board, gameTree: gameTree, isFlipped: isFlipped)
                .frame(width: boardSize, height: boardSize)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(specBoardCaption)
                .font(AnnFont.mono(10)).foregroundColor(DS.ink40)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Text("ENGINE CHECK").font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
                HStack(spacing: 12) {
                    Text(specEvalText).font(AnnFont.mono(11.5, bold: true)).foregroundColor(DS.ink)
                        .frame(width: 52).padding(.vertical, 4)
                        .background(DS.trackBg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
                    Text(specPVText)
                        .font(AnnFont.mono(11.5)).foregroundColor(DS.inkPV).lineLimit(1)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
            }

            // (RECENT DEVIATIONS is not wired yet — hidden rather than shown as a permanent
            // "nothing here ever" placeholder that reads as broken. Re-add when populated.)

            Spacer(minLength: 0)

            Text("Every edit is a card — the drill queue updates as you write.")
                .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(DS.paper)
    }

    private var specBoardCaption: String {
        guard let node = currentRepNode else { return "STARTING POSITION" }
        let title = moveTitleText(for: node)
        let line = node.isUserMove ? (node.isPrimary ? "YOUR MAIN LINE" : "YOUR LINE") : "THEIR REPLY"
        return "AFTER \(figurineSAN(title).uppercased()) — \(line)"
    }

    private var specEvalText: String {
        guard let e = multiEngine.primaryEngine.evaluation else { return "—" }
        if abs(e) >= 10000 { return e > 0 ? "M" : "-M" }
        return String(format: "%+.2f", e / 100.0)
    }

    private var specPVText: String {
        let pv = multiEngine.primaryEngine.analysisLines.first?.pvNotation.prefix(10).joined(separator: " ") ?? ""
        return pv.isEmpty ? "engine idle" : pv
    }

    private func specDeviation(_ title: String, _ meta: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(AnnFont.serif(13.5, .regular, italic: true)).foregroundColor(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(meta).font(AnnFont.mono(9)).foregroundColor(DS.ink40)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(DS.semWarning).frame(width: 2) }
    }

    private var specBoard: some View {
        let size: CGFloat = 320
        let sq = size / 8
        let b = ChessBoard(fen: "rn1qkbnr/pp2pppp/2p5/3pPb2/3P4/8/PPP2PPP/RNBQKBNR w KQkq - 1 4")
        let last: Set<Int> = [2 * 8 + 7, 5 * 8 + 4]   // c8, f5 as file*8+rank
        return VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { rowIdx in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { colIdx in
                        let file = colIdx
                        let rank = 7 - rowIdx
                        let isLight = (file + rank) % 2 == 1
                        let isLast = last.contains(file * 8 + rank)
                        ZStack {
                            Rectangle().fill(isLast ? (isLight ? DS.boardLastLight : DS.boardLastDark)
                                                    : (isLight ? DS.boardLight : DS.boardDark))
                            if let p = b?.squares[file][rank] {
                                Text(p.symbol).font(.system(size: sq * 0.72))
                                    .foregroundColor(p.color == .white ? DS.boardWhitePiece : DS.boardBlackPiece)
                            }
                        }
                        .frame(width: sq, height: sq)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().strokeBorder(DS.windowBorder, lineWidth: 1))
        .padding(3).background(DS.paperRaised)
        .padding(1).background(DS.borderStrong)
    }

    private var specStatusBar: some View {
        let node = currentRepNode
        let mine = node?.isUserMove ?? false
        let own = mine ? ((node?.isPrimary ?? true) ? "MAIN" : "ALT") : "LINE"
        let selName = node.map { moveTitleText(for: $0) } ?? "—"
        let eco = repertoire.ecoRangeDisplay.map { " · \($0)" } ?? ""
        return HStack {
            Text("\(repertoire.name.uppercased()) · \(repertoire.nodeCount) MOVES · AUTOSAVED")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
            Spacer()
            Text("SELECTED \(selName) · \(own)\(eco)").font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
        }
        .padding(.horizontal, 18)
        .frame(height: 28)
        .background(DS.chrome)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    // MARK: - Center column (repertoire header + move tree)

    private var centerColumn: some View {
        VStack(spacing: 0) {
            repHeader
            RepertoireMoveTreeView(
                gameTree: gameTree,
                nodeMap: nodeMap,
                repertoire: repertoire,
                onTap: { node in gameTree.goToNode(node) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text("Solid dots are your moves; hollow dots are theirs. Autosaved as you write.")
                .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 14)
        }
        .background(DS.paper)
    }

    private var repHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button(action: onClose) {
                HStack(spacing: 7) {
                    Text(repertoire.name).font(AnnFont.serif(21, .semibold)).foregroundColor(DS.ink)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundColor(DS.ink40)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to the shelf")

            Text(editorMeta).font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
            Spacer(minLength: 8)
            if dueCount > 0 {
                Text("\(dueCount) DUE")
                    .font(AnnFont.mono(10, bold: true)).foregroundColor(DS.redAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous).strokeBorder(DS.redAccent, lineWidth: 1))
            }
            editorToolsMenu
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private var editorMeta: String {
        "\(repertoire.side.displayName.uppercased()) · \(repertoire.nodeCount) MOVES"
    }

    private var editorToolsMenu: some View {
        Menu {
            Button("Begin Drill") { startDrill() }
            Button("Flip Board") { isFlipped.toggle() }
            Divider()
            Button("Import PGN…") { showingImportPicker = true }
            Button("Knowledge & Stats") { showingStats = true }
            Button("Coverage Audit") { showingCoverageAudit = true }
            Button("Load Opponent Games…") { showingOpponentPicker = true }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundColor(DS.ink60)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Cached — the editor header re-renders on every engine tick, and the SwiftData fetch behind
    /// this must NOT run each time. Refreshed on appear / cursor change / after drills+imports.
    private func refreshDueCount() {
        let scheds = repertoireDB.positionSchedules(for: repertoire.id)
        let now = Date()
        dueCount = scheds.values.filter { ($0.stats.nextDue ?? .distantFuture) <= now }.count
    }

    // MARK: - Right column (board + engine check + recent deviations)

    private var rightBoardColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            BoardView(board: board, gameTree: gameTree, isFlipped: isFlipped)
                .aspectRatio(1, contentMode: .fit)
            Text(boardCaption)
                .font(AnnFont.mono(10)).tracking(0.4).foregroundColor(DS.ink40)
                .frame(maxWidth: .infinity, alignment: .center)
            engineCheckPanel
            recentDeviationsPanel
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.paper)
    }

    private var boardCaption: String {
        guard let node = currentRepNode else { return "STARTING POSITION" }
        let line = node.isUserMove ? (node.isPrimary ? "YOUR MAIN LINE" : "YOUR LINE") : "THEIR REPLY"
        return "AFTER \(moveTitleText(for: node).uppercased()) — \(line)"
    }

    private var engineCheckPanel: some View {
        let engine = multiEngine.primaryEngine
        let evalText: String = {
            guard let e = engine.evaluation else { return "—" }
            if abs(e) >= 10000 { return e > 0 ? "M" : "-M" }
            let p = e / 100.0
            return String(format: "%+.2f", p)
        }()
        let pv = engine.analysisLines.first?.pvNotation.prefix(8).joined(separator: " ") ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text("ENGINE CHECK").font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
            HStack(spacing: 10) {
                Text(evalText)
                    .font(AnnFont.mono(11, bold: true)).foregroundColor(DS.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(DS.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                Text(pv.isEmpty ? "engine idle" : pv)
                    .font(AnnFont.mono(10.5)).foregroundColor(DS.ink60).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
        }
    }

    private var recentDeviationsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT DEVIATIONS").font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
            Text("Deviations show up here as your synced games leave the book.")
                .font(AnnFont.voice(12)).foregroundColor(DS.ink40)
                .fixedSize(horizontal: false, vertical: true)
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
                .font(AnnFont.serif(16, .semibold))
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
                        .font(AnnFont.mono(18, bold: true))
                        .foregroundColor(DS.ink)
                    if !draftGlyph.isEmpty {
                        Text(draftGlyph)
                            .font(AnnFont.mono(16, bold: true))
                            .foregroundColor(glyphColor(draftGlyph))
                    }
                    Spacer()
                    sideBadge(isUserMove: node.isUserMove)
                }
            } else {
                HStack {
                    Text("Starting position")
                        .font(AnnFont.serif(16, .semibold))
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
            .font(AnnFont.label(10, bold: false))
            .tracking(10 * 0.1)
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
                .font(AnnFont.serif(11))
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
                .font(AnnFont.label(11, bold: false))
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
                    .font(AnnFont.serif(12, isSelected ? .semibold : .regular))
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
                    .font(AnnFont.serif(12))
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
                        .font(AnnFont.serif(12))
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
                .font(AnnFont.label(11, bold: false))
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
                .font(AnnFont.mono(13, bold: true))
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
                    .font(AnnFont.label(11, bold: false))
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
                .font(AnnFont.serif(11))
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
                    .font(AnnFont.label(11, bold: false))
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
                .font(AnnFont.mono(11))
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
                .font(AnnFont.label(11, bold: false))
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
            .font(AnnFont.serif(12))
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
        // Full snapshot restore incl. castling rights — otherwise re-castling breaks after a takeback.
        board.restoreState(from: cur)
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

// MARK: - R6 Board Input mode (per R6-BOARD-INPUT.md)

extension RepertoireEditorView {

    fileprivate var r6AuthorColor: PieceColor { repertoire.side == .white ? .white : .black }
    fileprivate var r6IsOpponentTurn: Bool { gameTree.currentNode.boardState.turn != r6AuthorColor }

    /// The path root → current (excluding root), as GameNodes.
    fileprivate var r6LinePath: [GameNode] {
        var path: [GameNode] = []
        var cur: GameNode? = gameTree.currentNode
        while let n = cur, n.parent != nil { path.append(n); cur = n.parent }
        return path.reversed()
    }

    /// A recorded child that is a leaf ending on the opponent's move = a gap (no reply yet).
    fileprivate func r6IsGap(_ node: GameNode) -> Bool {
        guard node.children.isEmpty else { return false }
        if let repId = nodeMap[node.id], let rep = repertoire.nodes.first(where: { $0.id == repId }) {
            return !rep.isUserMove
        }
        return node.boardState.turn == r6AuthorColor
    }

    /// Recompute the masters "tries" for the cursor position. Runs off the main thread (the SQL
    /// GROUP BY + per-row SAN would otherwise block every arrow-key step) and only in board mode,
    /// where the panel is actually shown; a cursor-id guard drops stale results.
    fileprivate func refreshR6Tries() {
        guard centerMode == .board else { return }
        let boardCopy = gameTree.currentNode.boardState.copy()
        let cursorId = gameTree.currentNode.id
        DispatchQueue.global(qos: .userInitiated).async {
            let result = referenceDatabase.explorer(board: boardCopy)
            DispatchQueue.main.async {
                if gameTree.currentNode.id == cursorId { r6Tries = result }
            }
        }
    }

    // MARK: Recording

    fileprivate func r6RecordUCI(_ uci: String) {
        guard let move = Self.parseUCI(uci, board: gameTree.currentNode.boardState) else { return }
        _ = gameTree.addMove(move)   // advances cursor; onChange persists + syncs + refreshes tries
    }

    @discardableResult
    fileprivate func r6PlaySAN(_ san: String) -> Bool {
        let clean = san.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return false }
        guard let move = NotationEngine(board: gameTree.currentNode.boardState).fromAlgebraic(clean) else { return false }
        _ = gameTree.addMove(move)
        return true
    }

    /// ⌥↵ — promote the cursor's move to the main line (demote the previous main to alternative).
    fileprivate func r6PromoteToMain() {
        let node = gameTree.currentNode
        guard let parent = node.parent, parent.children.count > 1, parent.children.first !== node else { return }
        gameTree.promoteNodeToMainLine(node)
        if let repId = nodeMap[node.id], let rep = repertoire.nodes.first(where: { $0.id == repId }), rep.isUserMove,
           let parentRepId = nodeMap[parent.id], let parentRep = repertoire.nodes.first(where: { $0.id == parentRepId }) {
            for child in parentRep.children where child.isUserMove {
                child.isPrimary = (child.id == rep.id)
                repertoireDB.updateNode(child)
            }
        }
        gameTree.objectWillChange.send()
        loadDraft()
    }

    /// Merge a bare SAN sequence (e.g. "4.h4 h6 5.g4 Bd7") from the cursor, folding duplicates.
    fileprivate func r6MergeSAN() {
        let raw = sanInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        // Tokenize: drop move numbers and result markers, normalize zero-castling to SAN.
        let results: Set<String> = ["*", "1-0", "0-1", "1/2-1/2", "½-½"]
        var tokens: [String] = []
        for rawTok in raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init) {
            var t = rawTok
            if let dot = t.lastIndex(of: ".") { t = String(t[t.index(after: dot)...]) }   // "4.h4"→"h4", "4."→""
            if t.isEmpty || results.contains(t) { continue }
            if t.allSatisfy({ $0.isNumber }) { continue }                                  // bare move number
            if t == "0-0" { t = "O-O" } else if t == "0-0-0" { t = "O-O-O" }               // zero-castling
            tokens.append(t)
        }
        guard !tokens.isEmpty else { return }

        // All-or-nothing: validate the WHOLE sequence on a scratch board copy before touching the
        // real tree, so an illegal token late in the line doesn't leave phantom moves behind.
        let scratch = gameTree.currentNode.boardState.copy()
        var moves: [Move] = []
        for tok in tokens {
            guard let mv = NotationEngine(board: scratch).fromAlgebraic(tok), scratch.makeMove(mv) else {
                withAnimation(.default) { sanError = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { sanError = false }
                return
            }
            moves.append(mv)
        }

        // Commit: fold moves that already exist as children, count the rest as new.
        var newCount = 0, folded = 0
        for mv in moves {
            let exists = gameTree.currentNode.children.contains {
                $0.move?.from == mv.from && $0.move?.to == mv.to && $0.move?.promotionType == mv.promotionType
            }
            if exists { folded += 1 } else { newCount += 1 }
            _ = gameTree.addMove(mv)
        }
        mergeToast = "MERGED — \(newCount) NEW · \(folded) FOLDED"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { mergeToast = nil }
        sanInput = ""
    }

    // MARK: Board-center pane

    var r6BoardCenter: some View {
        GeometryReader { geo in
        // Board fills the center column — bound by width, or by height minus the prompt/legend/plate.
        // Board fills the center as a large square — bound by the smaller of the column's width or
        // its height (minus the prompt + plate strip), with a little breathing padding. No hard cap.
        let s = max(min(geo.size.width - 48, geo.size.height - 118), 300)
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                r6TurnPrompt
                Spacer(minLength: 8)
                Text(r6MoveLabel).font(AnnFont.mono(10.5, bold: true)).foregroundColor(DS.ink40)
            }
            .frame(width: s)

            BoardView(board: board, gameTree: gameTree, extraArrows: r6BoardArrows, isFlipped: isFlipped, showLabels: false)
                .frame(width: s, height: s)

            if r6IsOpponentTurn && !r6BoardArrows.isEmpty {
                HStack(spacing: 18) {
                    r6Legend(DS.qBrilliant, "IN THE TREE — ANSWERED")
                    r6Legend(DS.qInaccuracy, "GAP — PLAY IT, THEN YOUR REPLY")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("PLATE \(Self.r6Roman(max(gameTree.currentNode.boardState.fullMoveNumber, 1)))")
                    .font(AnnFont.mono(10, bold: true)).tracking(1.0).foregroundColor(DS.redAccent)
                Text(r6PlateCaption).font(AnnFont.voice(14)).foregroundColor(DS.ink60).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: s)
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        }
        .background(DS.paper)
    }

    private var r6TurnPrompt: some View {
        Group {
            if r6IsOpponentTurn {
                (Text("Their move ").font(AnnFont.serif(15, .medium)).foregroundColor(DS.ink)
                 + Text("— pick their try to answer").font(AnnFont.voice(15)).foregroundColor(DS.ink40))
            } else {
                (Text("Your move ").font(AnnFont.serif(15, .medium)).foregroundColor(DS.ink)
                 + Text("— write your reply").font(AnnFont.voice(15)).foregroundColor(DS.ink40))
            }
        }
    }

    private var r6MoveLabel: String {
        let n = gameTree.currentNode.boardState.fullMoveNumber
        let side = gameTree.currentNode.boardState.turn == .white ? "WHITE" : "BLACK"
        return "MOVE \(n) · \(side)"
    }

    private var r6PlateCaption: String {
        guard let last = r6LinePath.last, let san = last.cachedNotation else {
            return "The starting position — drag a piece, and the move is written."
        }
        return "After \(san) — drag a piece, and the move is written."
    }

    private func r6Legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 14, height: 3)
            Text(text).font(AnnFont.mono(9)).foregroundColor(DS.ink40)
        }
    }

    /// Overlay arrows for the cursor's existing children — only on the opponent's turn (§2.3).
    private var r6BoardArrows: [BoardArrow] {
        guard r6IsOpponentTurn else { return [] }
        var arrows: [BoardArrow] = []
        for child in gameTree.currentNode.children.prefix(4) {
            guard let m = child.move else { continue }
            let color = r6IsGap(child) ? DS.qInaccuracy : DS.qBrilliant
            arrows.append(BoardArrow(from: m.from, to: m.to, color: color))
        }
        return arrows
    }

    private static func r6Roman(_ n: Int) -> String {
        guard n > 0 else { return "I" }
        let table: [(Int, String)] = [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),
                                       (90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        var num = n, out = ""
        for (v, s) in table { while num >= v { out += s; num -= v } }
        return out
    }

    // MARK: THE LINE SO FAR (left 292)

    var r6LineSoFar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE LINE SO FAR").font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(r6LinePath.enumerated()), id: \.element.id) { _, node in
                        r6LineRow(node)
                    }
                    if r6LinePath.isEmpty {
                        Text("Nothing yet — play a move.").font(AnnFont.voice(12)).foregroundColor(DS.ink40)
                            .padding(.horizontal, 20).padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 12)
            }

            VStack(alignment: .leading, spacing: 4) {
                (Text("▸ CURSOR ").font(AnnFont.mono(10, bold: true)).foregroundColor(DS.redAccent)
                 + Text("NEW MOVES BRANCH HERE").font(AnnFont.mono(10)).foregroundColor(DS.ink40))
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }

            // ALREADY IN THE TREE HERE — the cursor node's existing children.
            if !gameTree.currentNode.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ALREADY IN THE TREE HERE").font(AnnFont.label(9.5, bold: true)).tracking(9.5 * 0.14).foregroundColor(DS.ink40)
                    ForEach(gameTree.currentNode.children, id: \.id) { child in
                        r6ChildRow(child)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("Step back with ←, play a different move — that is a branch. Nothing to manage; the tree grows under your hands.")
                    .font(AnnFont.voice(13)).foregroundColor(DS.ink40).fixedSize(horizontal: false, vertical: true)
                Text("← → STEP · ⌫ TAKE BACK · ⌥↵ PROMOTE TO MAIN")
                    .font(AnnFont.mono(9)).foregroundColor(DS.ink40)
            }
            .padding(20)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.paper)
    }

    private func r6LineRow(_ node: GameNode) -> some View {
        let mine = (nodeMap[node.id].flatMap { rid in repertoire.nodes.first { $0.id == rid } })?.isUserMove ?? false
        let selected = node.id == gameTree.currentNode.id
        let num = node.boardState.fullMoveNumber
        let isWhiteMove = node.boardState.turn == .black   // after a white move it's black to move
        return Button(action: { gameTree.goToNode(node) }) {
            HStack(spacing: 8) {
                Text(isWhiteMove ? "\(num)." : "\(num)…").font(AnnFont.mono(11)).foregroundColor(DS.ink40)
                    .frame(width: 26, alignment: .trailing)
                Circle().fill(mine ? DS.redAccent : Color.clear).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(mine ? DS.redAccent : DS.ink40, lineWidth: 1.4))
                Text(node.cachedNotation ?? "?").font(AnnFont.mono(13, bold: true)).foregroundColor(DS.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background((selected ? DS.selectedWash : Color.clear), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func r6ChildRow(_ child: GameNode) -> some View {
        let mine = (nodeMap[child.id].flatMap { rid in repertoire.nodes.first { $0.id == rid } })?.isUserMove ?? false
        let gap = r6IsGap(child)
        let isMain = gameTree.currentNode.children.first?.id == child.id
        let status = gap ? "— gap, no reply" : (isMain ? "— main, answered" : "— answered")
        return Button(action: { gameTree.goToNode(child) }) {
            HStack(spacing: 8) {
                Circle().fill(gap ? DS.qInaccuracy : (mine ? DS.redAccent : Color.clear)).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(gap ? DS.qInaccuracy : (mine ? DS.redAccent : DS.ink40), lineWidth: 1.4))
                Text(child.cachedNotation ?? "?").font(AnnFont.mono(12.5, bold: true)).foregroundColor(DS.ink)
                Text(status).font(AnnFont.serif(11.5, .regular, italic: true)).foregroundColor(gap ? DS.qInaccuracy : DS.ink40).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: RIGHT — tries · type · engine (396)

    // Right column of BOARD mode: the full engine view (same as the analysis screen) with the
    // repertoire move tree beneath it.
    var r6EngineMovesPane: some View {
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
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            ScrollView {
                let rows = realTreeRows
                if rows.isEmpty {
                    Text("Play a move to start the line.")
                        .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 16)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(rows) { row in specTreeRow(row) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.paper)
    }

    var r6RightPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            r6TriesSection
            r6TypeItSection
            Spacer(minLength: 0)
            r6EngineCard
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.paper)
    }

    private var r6TriesSection: some View {
        let side = r6IsOpponentTurn ? (gameTree.currentNode.boardState.turn == .white ? "WHITE'S TRIES HERE" : "BLACK'S TRIES HERE") : "MOVES HERE"
        let entries = r6Tries.moves   // already sorted by frequency (total desc) by explorer(board:)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(side).font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
                Spacer()
                Text("MASTERS · \(r6ShortCount(r6Tries.total)) GAMES").font(AnnFont.mono(9)).foregroundColor(DS.ink40)
            }
            if entries.count < 1 || r6Tries.total < 50 {
                Text("Out of book — you're on your own here. The engine still checks your work.")
                    .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(entries.prefix(6)) { entry in r6TryRow(entry) }
                Text("Click a move to play it on the board.").font(AnnFont.voice(11.5)).foregroundColor(DS.ink40)
            }
        }
    }

    private func r6TryRow(_ entry: ReferenceExplorerEntry) -> some View {
        // Match against the cursor's recorded children.
        let childMatch = gameTree.currentNode.children.first { child in
            child.move.map { Self.uci(from: $0) } == entry.uci
        }
        let inTree = childMatch != nil
        let gap = childMatch.map { r6IsGap($0) } ?? false
        let scorePct = repertoire.side == .white ? entry.scorePercent : (100 - entry.scorePercent)
        return Button(action: { r6RecordUCI(entry.uci) }) {
            HStack(spacing: 10) {
                Text(entry.san).font(AnnFont.mono(13.5, bold: true)).foregroundColor(DS.ink).frame(width: 62, alignment: .leading)
                Text("\(Int(scorePct))% · \(r6ShortCount(entry.total))").font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
                Spacer(minLength: 6)
                r6TryChip(inTree: inTree, gap: gap, reply: childMatch.flatMap { $0.children.first?.cachedNotation })
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(gap ? DS.qInaccuracy.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(gap ? RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(DS.qInaccuracy, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func r6TryChip(inTree: Bool, gap: Bool, reply: String?) -> some View {
        if gap {
            r6Chip("GAP — ADD REPLY", color: DS.qInaccuracy, dashed: true)
        } else if inTree {
            r6Chip("✓ COVERED\(reply.map { " — \($0)" } ?? "")", color: DS.qBrilliant, dashed: false)
        } else {
            r6Chip("+ ADD", color: DS.ink40, dashed: false)
        }
    }

    private func r6Chip(_ text: String, color: Color, dashed: Bool) -> some View {
        Text(text).font(AnnFont.label(8.5, bold: true)).tracking(8.5 * 0.08).foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
    }

    private var r6TypeItSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OR TYPE IT").font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
            HStack(spacing: 8) {
                TextField("e.g. 4.h4 h6 5.g4", text: $sanInput)
                    .textFieldStyle(.plain)
                    .font(AnnFont.mono(12))
                    .foregroundColor(sanError ? DS.redAccent : DS.ink)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(sanError ? DS.redAccent : DS.hairline, lineWidth: 1))
                    .onSubmit { r6MergeSAN() }
                    .offset(x: sanError ? 4 : 0)
            }
            if let toast = mergeToast {
                Text(toast).font(AnnFont.mono(9)).foregroundColor(DS.ink40)
            } else {
                Text("A move, a sequence, or a pasted PGN — all merge into the tree at the cursor.")
                    .font(AnnFont.voice(11.5)).foregroundColor(DS.ink40).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var r6EngineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ENGINE CHECK").font(AnnFont.label(10, bold: true)).tracking(10 * 0.14).foregroundColor(DS.ink40)
            HStack(spacing: 12) {
                Text(specEvalText).font(AnnFont.mono(11.5, bold: true)).foregroundColor(DS.ink)
                    .frame(width: 54).padding(.vertical, 4)
                    .background(DS.trackBg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
                Text(specPVText).font(AnnFont.mono(11.5)).foregroundColor(DS.inkPV).lineLimit(1)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
        }
    }

    var r6StatusBar: some View {
        HStack {
            Text("PLAY ON THE BOARD · TYPE SAN · PASTE PGN — ALL ROADS INTO THE TREE")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
            Spacer(minLength: 8)
            Text("\(r6IsOpponentTurn ? "THEIR MOVE" : "YOUR MOVE") · AUTOSAVED")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
        }
        .padding(.horizontal, 16)
        .frame(height: DS.statusBarHeight)
        .background(DS.chrome)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private func r6ShortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
