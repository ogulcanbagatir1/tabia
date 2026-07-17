import SwiftUI

// R6 board-input mode for RepertoireEditorView — recording moves on the board, the
// board-center pane, the line-so-far list, and the tries/type/engine pane. Split out to
// keep RepertoireEditorView.swift focused on the tree editor.

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
    func refreshR6Tries() {
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
    func r6PromoteToMain() {
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
                .overlay {
                    // Scroll over the board to step through moves (up = back, down = forward), just
                    // like the analysis screen. Clicks still fall through to the board.
                    ScrollNavCatcher { step in
                        if step > 0 { _ = gameTree.goBack() } else { _ = gameTree.goForward() }
                    }
                }

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
