import SwiftUI

/// Line-based drill experience. The user plays their side of a repertoire line to the leaf; the
/// opponent replies automatically. One continuous board — no per-card FEN teleporting.
struct RepertoireDrillView: View {
    @ObservedObject var session: DrillSession
    var onClose: () -> Void

    @StateObject private var board = ChessBoard()
    @StateObject private var gameTree = GameTree()
    @State private var isFlipped = false
    @State private var lastSyncedVersion: Int = -1

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            drillMasthead

            Group {
                switch session.phase {
                case .empty:     emptyView
                case .completed: completedView
                default:         drillStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            drillStatusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.paper)
        .onAppear {
            isFlipped = session.repertoire.side == .black
            syncDisplay(force: true)
            handlePhase()
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: session.boardVersion) { _, _ in syncDisplay(force: false) }
        .onChange(of: session.statePhase) { _, _ in handlePhase() }
        .onChange(of: gameTree.currentNode.id) { _, _ in handleUserMove() }
    }

    // MARK: - Collapsed masthead (R3)

    private var drillMasthead: some View {
        ZStack {
            HStack(spacing: 12) {
                Text("DRILLING — \(session.repertoire.name.uppercased())")
                    .font(AnnFont.label(10)).tracking(10 * 0.12).foregroundColor(DS.redAccent)
                Text("CARD \(min(session.masteredCount + 1, max(session.total, 1))) OF \(session.total)")
                    .font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
            }

            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.ink60).frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                scoreChip
                replyModeMenu
                Button(action: { isFlipped.toggle() }) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 13))
                        .foregroundColor(DS.ink60).frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Flip board")
                Button(action: onClose) {
                    Text("END SESSION").font(AnnFont.label(10)).tracking(10 * 0.1).foregroundColor(DS.ink60)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                            .strokeBorder(DS.borderChip, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 47)
        .background(DS.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private var scoreChip: some View {
        HStack(spacing: 9) {
            Text("✓ \(session.successCount)").font(AnnFont.mono(10.5, bold: true)).foregroundColor(DS.semWin)
            Text("✗ \(session.failCount)").font(AnnFont.mono(10.5, bold: true)).foregroundColor(DS.redAccent)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }

    private var replyModeMenu: some View {
        Menu {
            ForEach(DrillSession.ReplyMode.allCases.filter { $0 != .opponent || session.hasOpponentBook }, id: \.self) { mode in
                Button(action: { session.replyMode = mode }) {
                    if session.replyMode == mode { Label(mode.label, systemImage: "checkmark") }
                    else { Text(mode.label) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(session.replyMode.label.uppercased()).font(AnnFont.label(10)).tracking(10 * 0.1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(DS.ink60)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Opponent reply mix: Realistic (frequency) · Critical (prep) · Breadth (rare lines)")
    }

    private var drillStatusBar: some View {
        HStack {
            Text(modeDescription).font(AnnFont.mono(9.5)).foregroundColor(DS.ink40).lineLimit(1)
            Spacer()
            Text("SESSION \(session.masteredCount)/\(session.total) CORRECT · ✓\(session.successCount) ✗\(session.failCount)")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
        }
        .padding(.horizontal, 18).frame(height: 28).background(DS.chrome)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }

    private var modeDescription: String {
        switch session.replyMode {
        case .realistic: return "REALISTIC MODE — OPPONENT PLAYS WEIGHTED BOOK MOVES"
        case .critical:  return "CRITICAL MODE — OPPONENT PLAYS THE TOUGHEST REPLIES"
        case .breadth:   return "BREADTH MODE — OPPONENT EXPLORES RARE SIDELINES"
        case .opponent:  return "PREP MODE — OPPONENT PLAYS THIS PLAYER'S BOOK"
        }
    }

    // MARK: - Drill stage (asking / thinking / wrong / lineComplete share one layout)

    private var drillStage: some View {
        // The board is pinned to a fixed vertical spot (roughly centered) via a computed top inset, so
        // everything that changes between turns — the ask-card text, the SHOW ANSWER/SKIP row appearing
        // and disappearing, the wrong-move details — flows DOWNWARD below the board and can never
        // re-center the column and jog the board up and down.
        GeometryReader { geo in
            // Board fills the available square area — the width, or the height minus the room the
            // prompt / ask-card / buttons / progress need below it (whichever is smaller).
            let boardSize = max(min(geo.size.width - 48, geo.size.height - 340), 380)
            VStack(spacing: 16) {
                promptLine(boardSize)
                boardArea(boardSize)
                askCard
                if session.phase == .userWrong {
                    referenceStrip
                    annotationBlock
                }
                actionButtons.frame(height: 36)
                progressStrip
                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func promptLine(_ width: CGFloat) -> some View {
        HStack {
            Text(promptTitle).font(AnnFont.serif(15)).foregroundColor(DS.ink)
            Spacer()
            Text("MOVE \(board.fullMoveNumber) · \(session.repertoire.side.displayName.uppercased())")
                .font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
        }
        .frame(width: width)
    }

    private var promptTitle: String {
        switch session.phase {
        case .userToMove:       return "Play your prepared move."
        case .opponentThinking: return "The opponent is replying…"
        case .userWrong:        return "That wasn't your line."
        case .lineComplete:     return "Line complete — well played."
        default:                return ""
        }
    }

    private var askCard: some View {
        let cfg = askConfig
        return HStack(spacing: 12) {
            Circle().fill(cfg.dot).frame(width: 9, height: 9)
                .opacity(session.phase == .userToMove ? (pulse ? 1 : 0.3) : 1)
            Text(cfg.title).font(AnnFont.serif(16, .semibold)).foregroundColor(DS.ink)
            if !cfg.detail.isEmpty {
                Text(cfg.detail).font(AnnFont.voice(15)).foregroundColor(DS.ink60)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    private var askConfig: (dot: Color, title: String, detail: String) {
        switch session.phase {
        case .userToMove:       return (DS.redAccent, "Your move.", "Play your line — alternatives are accepted.")
        case .opponentThinking: return (DS.ink40, "Opponent replies…", "")
        case .userWrong:        return (DS.redAccent, "Not your line.", "Play \(expectedText).")
        case .lineComplete:     return (DS.semWin, "Line complete.", "Next line coming up.")
        default:                return (DS.ink40, "", "")
        }
    }

    @ViewBuilder private var actionButtons: some View {
        switch session.phase {
        case .userToMove:
            HStack(spacing: 12) {
                drillButton("SHOW ANSWER") { session.revealAndFail() }
                drillButton("SKIP", muted: true) { session.skip() }
            }
        case .userWrong:
            drillButton("CONTINUE", primary: true) { session.continueAfterWrong() }
                .keyboardShortcut(.return, modifiers: [])
        case .lineComplete:
            drillButton("NEXT LINE", primary: true) { session.nextLine() }
                .keyboardShortcut(.return, modifiers: [])
        default:
            EmptyView()
        }
    }

    private func drillButton(_ title: String, muted: Bool = false, primary: Bool = false,
                             _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(AnnFont.label(10.5)).tracking(10.5 * 0.1)
                .foregroundColor(primary ? DS.onRed : (muted ? DS.ink60 : DS.ink))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background {
                    if primary { RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(DS.redInk) }
                }
                .overlay {
                    if !primary {
                        RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                            .strokeBorder(muted ? DS.hairline : DS.borderStrong, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progressStrip: some View {
        let total = max(session.total, 1)
        let done = min(session.masteredCount, total)
        let per = 28
        let idxRows = stride(from: 0, to: total, by: per).map { Array($0..<min($0 + per, total)) }
        return VStack(spacing: 6) {
            ForEach(idxRows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(idxRows[r], id: \.self) { i in
                        Circle()
                            .fill(i < done ? DS.semWin : Color.clear)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(
                                i < done ? DS.semWin : (i == done ? DS.redAccent : DS.borderChip),
                                lineWidth: 1.5))
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var referenceStrip: some View {
        Group {
            if let ref = session.expectedReference {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(DS.accent)
                    Text("\(ref.san) — \(Int(ref.userScorePercent.rounded()))% for you over \(ref.games.formatted()) games")
                        .font(AnnFont.serif(11, .medium))
                        .foregroundColor(DS.ink60)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DS.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var annotationBlock: some View {
        Group {
            if let node = session.expectedNodes.first(where: { $0.isPrimary }) ?? session.expectedNodes.first,
               !node.annotation.isEmpty {
                ScrollView {
                    Text(node.annotation)
                        .font(AnnFont.serif(12))
                        .foregroundColor(DS.ink60)
                        .lineSpacing(3)
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxHeight: 120)
                .padding(.horizontal, 28)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.accent)
            Text("All caught up!")
                .font(AnnFont.serif(18, .semibold))
                .foregroundColor(DS.textPrimary)
            Text("No moves are due for drill in this repertoire right now.")
                .font(AnnFont.serif(13))
                .foregroundColor(DS.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: onClose) { Text("Close") }
                .buttonStyle(GlassPrimaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 56))
                .foregroundColor(DS.accent)
            Text("Drill complete")
                .font(AnnFont.serif(18, .semibold))
                .foregroundColor(DS.textPrimary)

            HStack(spacing: 24) {
                statBlock(value: "\(session.successCount)", label: "Correct", color: DS.moveBest)
                statBlock(value: "\(session.failCount)", label: "Wrong", color: DS.moveBlunder)
                statBlock(
                    value: "\(Int(round(Double(session.successCount) / Double(max(1, session.successCount + session.failCount)) * 100)))%",
                    label: "Accuracy",
                    color: DS.accent
                )
                statBlock(value: "\(session.lineCount)", label: "Lines", color: DS.textSecondary)
            }

            Button(action: onClose) { Text("Close") }
                .buttonStyle(GlassPrimaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBlock(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AnnFont.mono(28, bold: true))
                .foregroundColor(color)
            Text(label)
                .font(AnnFont.label(11))
                .tracking(11 * 0.1)
                .foregroundColor(DS.textTertiary)
        }
        .frame(minWidth: 80)
    }

    // MARK: - Reusable bits

    private func boardArea(_ size: CGFloat) -> some View {
        BoardView(board: board, gameTree: gameTree, isFlipped: isFlipped, showLabels: false)
            .frame(width: size, height: size)
            .allowsHitTesting(session.phase == .userToMove)
    }

    // MARK: - Derived text

    private var expectedText: String {
        let sans = session.expectedNodes.compactMap { $0.san ?? $0.uciMove }
        guard let first = sans.first else { return "—" }
        if sans.count > 1 {
            return first + "  (or " + sans.dropFirst().joined(separator: ", ") + ")"
        }
        return first
    }

    private var sideToMoveIsUser: Bool { session.phase == .userToMove }

    // MARK: - Board sync + move detection

    /// Mirror the session's authoritative board onto the interactive display board + tree.
    private func syncDisplay(force: Bool) {
        guard force || session.boardVersion != lastSyncedVersion else { return }
        lastSyncedVersion = session.boardVersion
        resetBoardAndTree(to: session.board)
    }

    /// Trigger phase-dependent side effects (opponent auto-reply, line auto-advance), guarding
    /// against stale timers by re-checking the state token when they fire.
    private func handlePhase() {
        switch session.phase {
        case .opponentThinking:
            let token = session.statePhase
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if session.statePhase == token { session.playOpponentReply() }
            }
        case .lineComplete:
            let token = session.statePhase
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if session.statePhase == token { session.nextLine() }
            }
        default:
            break
        }
    }

    private func handleUserMove() {
        guard session.phase == .userToMove else { return }
        guard let move = gameTree.currentNode.move else { return }
        let uci = UCI.string(from: move)
        session.attemptUserMove(uci)
    }

    private func resetBoardAndTree(to newBoard: ChessBoard) {
        let fresh = GameTree()
        gameTree.root = fresh.root
        gameTree.currentNode = fresh.root
        gameTree.root.boardState = newBoard.copy()
        gameTree.root.children.removeAll()
        gameTree.currentNode = gameTree.root
        gameTree.rebuildMainLine()

        board.restoreState(from: newBoard)
    }
}
