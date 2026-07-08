import SwiftUI

/// Inline PGN-style repertoire view: moves flow as text, variations inline in parentheses with
/// depth-based dimming. Each move is a tappable pill that navigates the GameTree.
struct RepertoireMoveTreeView: View {
    @ObservedObject var gameTree: GameTree
    let nodeMap: [UUID: UUID]
    let repertoire: Repertoire
    let onTap: (GameNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    Group {
                        if gameTree.root.children.isEmpty {
                            emptyState
                                .padding(.top, 24)
                        } else {
                            FlowLayout(horizontalSpacing: 4, verticalSpacing: 3) {
                                ForEach(tokens) { token in
                                    tokenView(token)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: gameTree.currentNode.id) { _, id in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("LINES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.ink25)
                .kerning(0.8)

            Spacer()

            HStack(spacing: 2) {
                navButton(icon: "backward.end.fill") { gameTree.goToStart() }
                    .disabled(gameTree.currentNode.parent == nil)
                navButton(icon: "chevron.left") { _ = gameTree.goBack() }
                    .disabled(gameTree.currentNode.parent == nil)
                navButton(icon: "chevron.right") { _ = gameTree.goForward() }
                    .disabled(gameTree.currentNode.children.isEmpty)
                navButton(icon: "forward.end.fill") { gameTree.goToEnd() }
                    .disabled(gameTree.currentNode.children.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "books.vertical")
                .font(.system(size: 28))
                .foregroundColor(DS.ink25)
            Text("No moves yet")
                .font(.system(size: 11))
                .foregroundColor(DS.ink40)
            Text("Play on the board to build the tree")
                .font(.system(size: 10))
                .foregroundColor(DS.ink25)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tokens

    private struct Token: Identifiable {
        let id = UUID()
        let kind: Kind

        enum Kind {
            case move(node: GameNode, prefix: String, depth: Int)
            case open(depth: Int)
            case close(depth: Int)
        }
    }

    private var tokens: [Token] {
        var tokens: [Token] = []
        var lastWasMove = false

        func emit(_ move: GameNode, depth: Int) {
            guard let parent = move.parent else { return }
            let n = parent.boardState.fullMoveNumber
            let isBlack = parent.boardState.turn == .black
            let prefix: String
            if !isBlack {
                prefix = "\(n)."
            } else if lastWasMove {
                prefix = ""
            } else {
                prefix = "\(n)…"
            }
            tokens.append(Token(kind: .move(node: move, prefix: prefix, depth: depth)))
            lastWasMove = true
        }

        func walk(_ parent: GameNode, depth: Int) {
            guard !parent.children.isEmpty else { return }
            let main = parent.children[0]
            emit(main, depth: depth)
            for variation in parent.children.dropFirst() {
                tokens.append(Token(kind: .open(depth: depth + 1)))
                lastWasMove = false
                emit(variation, depth: depth + 1)
                walk(variation, depth: depth + 1)
                tokens.append(Token(kind: .close(depth: depth + 1)))
                lastWasMove = false
            }
            walk(main, depth: depth)
        }

        walk(gameTree.root, depth: 0)
        return tokens
    }

    // MARK: - Token rendering

    @ViewBuilder
    private func tokenView(_ token: Token) -> some View {
        switch token.kind {
        case .move(let node, let prefix, let depth):
            movePill(node: node, prefix: prefix, depth: depth)
                .id(node.id)
        case .open(let depth):
            Text("(")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(parenColor(depth: depth))
                .padding(.leading, 2)
        case .close(let depth):
            Text(")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(parenColor(depth: depth))
                .padding(.trailing, 2)
        }
    }

    private func movePill(node: GameNode, prefix: String, depth: Int) -> some View {
        let repNode = repertoireNode(for: node)
        let isUser = repNode?.isUserMove
            ?? (node.parent?.boardState.turn == (repertoire.side == .white ? PieceColor.white : .black))
        let ownership = repNode?.ownership
        let glyph = repNode?.evalGlyph ?? ""
        let san = node.cachedNotation ?? "?"
        let isCurrent = node.id == gameTree.currentNode.id

        // Base color from ownership, then dim by depth.
        let baseOpacity: Double = {
            switch ownership {
            case .mineMain:         return 0.95
            case .mineAlternative:  return 0.80
            case .opponentCritical: return 0.75
            case .opponentSideline: return 0.55
            case .opponentUnusual:  return 0.35
            case nil:               return isUser ? 0.90 : 0.60
            }
        }()
        let depthDim = max(0.55, 1.0 - 0.12 * Double(depth))
        let finalOpacity = isCurrent ? 1.0 : baseOpacity * depthDim

        let weight: Font.Weight = {
            if isCurrent { return .semibold }
            if ownership == .mineMain { return .medium }
            return .regular
        }()

        return Button(action: {
            withAnimation(DS.quickFade) { onTap(node) }
        }) {
            HStack(spacing: 1) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DS.ink.opacity(finalOpacity * 0.5))
                }
                Text(san)
                    .font(.system(size: 12, weight: weight))
                    .foregroundColor(DS.ink.opacity(finalOpacity))
                if !glyph.isEmpty {
                    Text(glyph)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(glyphColor(glyph))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                isCurrent
                    ? RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DS.selectedWash)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func parenColor(depth: Int) -> Color {
        let dim = max(0.40, 0.78 - 0.10 * Double(depth - 1))
        return DS.ink.opacity(dim)
    }

    // MARK: - Helpers

    private func repertoireNode(for gn: GameNode) -> RepertoireNode? {
        guard let repId = nodeMap[gn.id] else { return nil }
        return repertoire.nodes.first(where: { $0.id == repId })
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

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.ink60)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

/// Minimal SwiftUI flow layout: arranges subviews left-to-right and wraps to a new line whenever
/// adding the next subview would exceed the proposed width.
private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let (size, _) = arrange(subviews: subviews, maxWidth: maxWidth)
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, positions) = arrange(subviews: subviews, maxWidth: bounds.width)
        for (idx, subview) in subviews.enumerated() {
            let p = positions[idx]
            subview.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (CGSize, [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - horizontalSpacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
