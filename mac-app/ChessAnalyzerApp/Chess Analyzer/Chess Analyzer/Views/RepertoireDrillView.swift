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

    var body: some View {
        VStack(spacing: 0) {
            header

            switch session.phase {
            case .empty:
                emptyView
            case .userToMove:
                askingBody
            case .opponentThinking:
                thinkingBody
            case .userWrong:
                wrongBody
            case .lineComplete:
                lineCompleteBody
            case .completed:
                completedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassContentBackground())
        .onAppear {
            isFlipped = session.repertoire.side == .black
            syncDisplay(force: true)
            handlePhase()
        }
        .onChange(of: session.boardVersion) { _, _ in
            syncDisplay(force: false)
        }
        .onChange(of: session.statePhase) { _, _ in
            handlePhase()
        }
        .onChange(of: gameTree.currentNode.id) { _, _ in
            handleUserMove()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "graduationcap")
                .font(.system(size: 14))
                .foregroundColor(DS.accent)

            Text("Drilling")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.55))
            Text(session.repertoire.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))

            Spacer()

            replyModeMenu

            progressBadge

            Button(action: { isFlipped.toggle() }) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Flip board")
        }
        .padding(.horizontal, 28)
        .frame(height: 56)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .bottom) {
            Rectangle().fill(
                LinearGradient(colors: [Color.white.opacity(0.19), Color.white.opacity(0.03)], startPoint: .leading, endPoint: .trailing)
            ).frame(height: 1)
        }
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
                Image(systemName: "dial.medium")
                    .font(.system(size: 11))
                Text(session.replyMode.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Opponent reply mix: Realistic (frequency) · Critical (prep) · Breadth (rare lines)")
    }

    private var progressBadge: some View {
        HStack(spacing: 8) {
            Label("\(session.successCount)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.moveBest)

            Label("\(session.failCount)", systemImage: "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.moveBlunder)

            Text("\(session.masteredCount) / \(session.total)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Body states

    private var askingBody: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            boardArea

            statusBar(
                icon: "play.circle",
                tint: DS.accent,
                title: sideToMoveIsUser ? "Your move" : "Your move",
                detail: "Play your line. Alternatives are accepted."
            )

            HStack(spacing: 12) {
                Button(action: { session.revealAndFail() }) {
                    Text("Show answer")
                }
                .buttonStyle(GlassButtonStyle())

                Button(action: { session.skip() }) {
                    Text("Skip")
                }
                .buttonStyle(GlassButtonStyle())
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thinkingBody: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            boardArea
            statusBar(
                icon: "ellipsis.circle",
                tint: Color(hex: 0xFFFFFF, opacity: 0.55),
                title: "Opponent replies",
                detail: "…"
            )
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var wrongBody: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            boardArea

            statusBar(
                icon: "xmark.circle.fill",
                tint: DS.moveBlunder,
                title: "Not your line",
                detail: "Play: \(expectedText)"
            )

            referenceStrip

            annotationBlock

            Button(action: { session.continueAfterWrong() }) {
                Text("Continue")
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lineCompleteBody: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            boardArea
            statusBar(
                icon: "checkmark.seal.fill",
                tint: DS.moveBest,
                title: "Line complete",
                detail: "Next line…"
            )
            Button(action: { session.nextLine() }) {
                Text("Next line")
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var referenceStrip: some View {
        Group {
            if let ref = session.expectedReference {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(DS.accent)
                    Text("\(ref.san) — \(Int(ref.userScorePercent.rounded()))% for you over \(ref.games.formatted()) games")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.72))
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
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.72))
                        .lineSpacing(3)
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.textPrimary)
            Text("No moves are due for drill in this repertoire right now.")
                .font(.system(size: 13))
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
                .font(.system(size: 18, weight: .semibold))
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
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(DS.textTertiary)
        }
        .frame(minWidth: 80)
    }

    // MARK: - Reusable bits

    private var boardArea: some View {
        HStack {
            Spacer(minLength: 0)
            BoardView(board: board, gameTree: gameTree, isFlipped: isFlipped)
                .frame(maxWidth: 560, maxHeight: 560)
                .padding(.horizontal, 20)
                .allowsHitTesting(session.phase == .userToMove)
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }

    private func statusBar(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        )
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
        let uci = DrillSession.uci(from: move)
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

        board.squares = newBoard.squares
        board.turn = newBoard.turn
        board.moveHistory = newBoard.moveHistory
        board.enPassantTarget = newBoard.enPassantTarget
        board.halfMoveClock = newBoard.halfMoveClock
        board.fullMoveNumber = newBoard.fullMoveNumber
    }
}
