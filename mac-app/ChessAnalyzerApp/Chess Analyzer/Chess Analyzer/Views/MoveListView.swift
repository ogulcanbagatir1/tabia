import SwiftUI

struct MoveListView: View {
    @ObservedObject var gameTree: GameTree

    var body: some View {
        VStack(spacing: 0) {
            // Header with section label and navigation
            HStack {
                Text("MOVES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.2))
                    .kerning(0.8)

                Spacer()

                HStack(spacing: 2) {
                    navButton(icon: "backward.end.fill", action: { gameTree.goToStart() })
                        .disabled(gameTree.currentNode.parent == nil)

                    navButton(icon: "chevron.left", action: { _ = gameTree.goBack() })
                        .disabled(gameTree.currentNode.parent == nil)

                    navButton(icon: "chevron.right", action: { _ = gameTree.goForward() })
                        .disabled(gameTree.currentNode.children.isEmpty)

                    navButton(icon: "forward.end.fill", action: { gameTree.goToEnd() })
                        .disabled(gameTree.currentNode.children.isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.19)).frame(height: 1)
            }

            // Move list with vertical layout
            ScrollViewReader { proxy in
                ScrollView {
                    if gameTree.root.children.isEmpty {
                        EmptyMoveListView()
                    } else {
                        VerticalMoveTreeView(
                            node: gameTree.root,
                            currentNodeId: gameTree.currentNode.id,
                            onTapMove: { node in
                                withAnimation(DS.quickFade) {
                                    gameTree.goToNode(node)
                                }
                            },
                            onSetAnnotation: { node, annotation in
                                node.setAnnotation(annotation)
                                gameTree.objectWillChange.send()
                            },
                            onDeleteMove: { node in
                                gameTree.deleteFromNode(node)
                            },
                            onPromoteToMainLine: { node in
                                gameTree.promoteNodeToMainLine(node)
                                gameTree.objectWillChange.send()
                            },
                            onMakeSubline: { node in
                                gameTree.demoteToSubline(node)
                                gameTree.objectWillChange.send()
                            },
                            isMainLine: true,
                            startMoveNumber: 1,
                            startIsWhite: true
                        )
                        .onChange(of: gameTree.currentNode.id) { _, newId in
                            withAnimation {
                                proxy.scrollTo(newId, anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipped()
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vertical Move Tree View

struct VerticalMoveTreeView: View {
    let node: GameNode
    let currentNodeId: UUID
    let onTapMove: (GameNode) -> Void
    let onSetAnnotation: (GameNode, String) -> Void
    let onDeleteMove: (GameNode) -> Void
    let onPromoteToMainLine: (GameNode) -> Void
    let onMakeSubline: (GameNode) -> Void
    let isMainLine: Bool
    let startMoveNumber: Int
    let startIsWhite: Bool

    var body: some View {
        let segments = collectSegments()

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                // Render move rows for this segment
                ForEach(segment.rows, id: \.id) { row in
                    MoveRow(
                        row: row,
                        currentNodeId: currentNodeId,
                        isMainLine: isMainLine,
                        onTapMove: onTapMove,
                        onSetAnnotation: onSetAnnotation,
                        onDeleteMove: onDeleteMove,
                        onPromoteToMainLine: onPromoteToMainLine,
                        onMakeSubline: onMakeSubline
                    )
                }

                // Render variations that branch off after this segment
                ForEach(segment.variations, id: \.node.id) { variation in
                    VariationView(
                        child: variation.node,
                        currentNodeId: currentNodeId,
                        onTapMove: onTapMove,
                        onSetAnnotation: onSetAnnotation,
                        onDeleteMove: onDeleteMove,
                        onPromoteToMainLine: onPromoteToMainLine,
                        onMakeSubline: onMakeSubline,
                        moveNumber: variation.moveNumber,
                        isWhiteMove: variation.isWhiteMove
                    )
                    .padding(.leading, 0)
                }
            }
        }
    }

    // MARK: - Data structures

    struct MoveRowData: Identifiable {
        let id = UUID()
        let moveNumber: Int
        let whiteNode: GameNode?
        let blackNode: GameNode?
    }

    private struct VariationItem {
        let node: GameNode
        let moveNumber: Int
        let isWhiteMove: Bool
    }

    private struct Segment {
        var rows: [MoveRowData]
        var variations: [VariationItem]
    }

    // MARK: - Collect segments

    private func collectSegments() -> [Segment] {
        var segments: [Segment] = []
        var currentRows: [MoveRowData] = []
        var currentNode: GameNode? = node
        var moveNumber = startMoveNumber
        var isWhite = startIsWhite

        // Accumulate pairs of white/black moves into rows
        var pendingWhiteNode: GameNode? = nil

        while let nd = currentNode {
            let children = nd.children
            guard !children.isEmpty else { break }

            let mainChild = children[0]

            if isWhite {
                pendingWhiteNode = mainChild
            } else {
                // Black move — pair it with the pending white move
                if let whiteNode = pendingWhiteNode {
                    currentRows.append(MoveRowData(
                        moveNumber: moveNumber,
                        whiteNode: whiteNode,
                        blackNode: mainChild
                    ))
                    pendingWhiteNode = nil
                } else {
                    // Black move without a white move (e.g., start from black's turn)
                    currentRows.append(MoveRowData(
                        moveNumber: moveNumber,
                        whiteNode: nil,
                        blackNode: mainChild
                    ))
                }
            }

            // Check for variations
            if children.count > 1 {
                // Flush pending white-only row before variations
                if let whiteNode = pendingWhiteNode, !isWhite {
                    // Already handled above
                    _ = whiteNode
                } else if let whiteNode = pendingWhiteNode, isWhite {
                    // White move has variations — flush it as a half-row
                    currentRows.append(MoveRowData(
                        moveNumber: moveNumber,
                        whiteNode: whiteNode,
                        blackNode: nil
                    ))
                    pendingWhiteNode = nil
                }

                var variationItems: [VariationItem] = []
                for i in 1..<children.count {
                    variationItems.append(VariationItem(
                        node: children[i],
                        moveNumber: moveNumber,
                        isWhiteMove: isWhite
                    ))
                }

                segments.append(Segment(rows: currentRows, variations: variationItems))
                currentRows = []
            }

            // Advance
            if !isWhite {
                moveNumber += 1
            }
            isWhite.toggle()
            currentNode = mainChild
        }

        // Flush remaining pending white move
        if let whiteNode = pendingWhiteNode {
            currentRows.append(MoveRowData(
                moveNumber: moveNumber,
                whiteNode: whiteNode,
                blackNode: nil
            ))
        }

        // Final segment
        if !currentRows.isEmpty {
            segments.append(Segment(rows: currentRows, variations: []))
        }

        return segments
    }
}

// MARK: - Move Row

struct MoveRow: View {
    let row: VerticalMoveTreeView.MoveRowData
    let currentNodeId: UUID
    let isMainLine: Bool
    let onTapMove: (GameNode) -> Void
    let onSetAnnotation: (GameNode, String) -> Void
    let onDeleteMove: (GameNode) -> Void
    let onPromoteToMainLine: (GameNode) -> Void
    let onMakeSubline: (GameNode) -> Void

    @State private var editingNoteNode: GameNode? = nil
    @State private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Move number column
                Text("\(row.moveNumber).")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.2))
                    .frame(width: 24, alignment: .trailing)

                // White move column
                if let whiteNode = row.whiteNode {
                    MoveButton(
                        node: whiteNode,
                        isCurrent: whiteNode.id == currentNodeId,
                        isMainLine: isMainLine,
                        onTap: { onTapMove(whiteNode) },
                        onSetAnnotation: { annotation in onSetAnnotation(whiteNode, annotation) },
                        onDeleteMove: { onDeleteMove(whiteNode) },
                        onPromoteToMainLine: { onPromoteToMainLine(whiteNode) },
                        onMakeSubline: { onMakeSubline(whiteNode) },
                        onEditNote: { beginEditingNote(for: whiteNode) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Black move column
                if let blackNode = row.blackNode {
                    MoveButton(
                        node: blackNode,
                        isCurrent: blackNode.id == currentNodeId,
                        isMainLine: isMainLine,
                        onTap: { onTapMove(blackNode) },
                        onSetAnnotation: { annotation in onSetAnnotation(blackNode, annotation) },
                        onDeleteMove: { onDeleteMove(blackNode) },
                        onPromoteToMainLine: { onPromoteToMainLine(blackNode) },
                        onMakeSubline: { onMakeSubline(blackNode) },
                        onEditNote: { beginEditingNote(for: blackNode) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 10)

            // Inline note editor (appears below the row)
            if let editNode = editingNoteNode {
                InlineNoteEditorView(
                    moveLabel: "\(row.moveNumber). \(editNode.cachedNotation ?? "?")",
                    noteText: $noteText,
                    onSave: {
                        editNode.objectWillChange.send()
                        editNode.comment = noteText
                        withAnimation(DS.quickFade) { editingNoteNode = nil }
                    },
                    onCancel: {
                        withAnimation(DS.quickFade) { editingNoteNode = nil }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(row.moveNumber % 2 == 0 ? Color.white.opacity(0.06) : Color.clear)
    }

    private func beginEditingNote(for node: GameNode) {
        noteText = node.comment
        withAnimation(DS.quickFade) {
            editingNoteNode = node
        }
    }
}

// MARK: - Variation View

struct VariationView: View {
    let child: GameNode
    let currentNodeId: UUID
    let onTapMove: (GameNode) -> Void
    let onSetAnnotation: (GameNode, String) -> Void
    let onDeleteMove: (GameNode) -> Void
    let onPromoteToMainLine: (GameNode) -> Void
    let onMakeSubline: (GameNode) -> Void
    let moveNumber: Int
    let isWhiteMove: Bool

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Variation header
            HStack(spacing: 4) {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textTertiary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                if isWhiteMove {
                    Text("\(moveNumber).")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textTertiary)
                } else {
                    Text("\(moveNumber)...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textTertiary)
                }

                MoveButton(
                    node: child,
                    isCurrent: child.id == currentNodeId,
                    isMainLine: false,
                    onTap: { onTapMove(child) },
                    onSetAnnotation: { annotation in onSetAnnotation(child, annotation) },
                    onDeleteMove: { onDeleteMove(child) },
                    onPromoteToMainLine: { onPromoteToMainLine(child) },
                    onMakeSubline: { onMakeSubline(child) }
                )

                if !isExpanded {
                    Text("...")
                        .font(.system(size: 10))
                        .foregroundColor(DS.textTertiary)
                }
            }

            // Expanded variation content
            if isExpanded {
                VerticalMoveTreeView(
                    node: child,
                    currentNodeId: currentNodeId,
                    onTapMove: onTapMove,
                    onSetAnnotation: onSetAnnotation,
                    onDeleteMove: onDeleteMove,
                    onPromoteToMainLine: onPromoteToMainLine,
                    onMakeSubline: onMakeSubline,
                    isMainLine: false,
                    startMoveNumber: isWhiteMove ? moveNumber : moveNumber + 1,
                    startIsWhite: !isWhiteMove
                )
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 10)
    }
}

// MARK: - Move Button

struct MoveButton: View {
    @ObservedObject var node: GameNode
    let isCurrent: Bool
    let isMainLine: Bool
    let onTap: () -> Void
    var onSetAnnotation: ((String) -> Void)? = nil
    var onDeleteMove: (() -> Void)? = nil
    var onPromoteToMainLine: (() -> Void)? = nil
    var onMakeSubline: (() -> Void)? = nil
    var onEditNote: (() -> Void)? = nil

    @State private var showingComment = false
    @State private var showingContextMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Button(action: onTap) {
                    Text(displayText)
                        .font(.system(
                            size: isMainLine ? 12 : 11,
                            weight: isCurrent ? .semibold : .medium
                        ))
                        .foregroundColor(isCurrent ? .white : Color(hex: 0xFFFFFF, opacity: 0.93))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isCurrent ? Color(hex: 0x0A84FF, opacity: 0.35) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .id(node.id)
                .onRightClick { showingContextMenu = true }
                .popover(isPresented: $showingContextMenu, arrowEdge: .trailing) {
                    MoveContextMenuView(
                        node: node,
                        isMainLine: isMainLine,
                        onSetAnnotation: onSetAnnotation,
                        onDeleteMove: onDeleteMove,
                        onPromoteToMainLine: onPromoteToMainLine,
                        onMakeSubline: onMakeSubline,
                        onAddNote: {
                            showingContextMenu = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onEditNote?()
                            }
                        },
                        onDismiss: { showingContextMenu = false }
                    )
                }

                // Note icon — tap to toggle inline editor or comment
                if !node.comment.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingComment.toggle()
                        }
                    } label: {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 9))
                            .foregroundColor(showingComment ? DS.accent : DS.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Expanded comment text (teal styled like Pencil moveNote)
            if showingComment && !node.comment.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DS.accentTeal)
                    Text(node.comment)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(DS.accentTeal)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
                .transition(.opacity)
            }
        }
    }

    private var displayText: String {
        let base = notation
        let ann = node.annotation
        // Only show traditional annotations in move list: !!, !, ?!, ?, ??
        // Hide book (*), best (B), good (+), okay (o)
        let hiddenAnnotations = ["*", "B", "+", "o"]
        if ann.isEmpty || hiddenAnnotations.contains(ann) {
            return base
        }
        return base + ann
    }

    private var notation: String {
        // Use cached notation (computed once when move was added)
        if let cached = node.cachedNotation, !cached.isEmpty {
            // Filter out invalid notations that are just dots
            let trimmed = cached.trimmingCharacters(in: CharacterSet(charactersIn: ".…· "))
            if !trimmed.isEmpty && trimmed != "?" {
                return cached
            }
        }

        // Fallback: compute notation from move data
        guard let move = node.move, let parent = node.parent else { return "?" }

        // Safely compute notation from parent board state
        let parentBoard = parent.boardState
        let computed = NotationEngine(board: parentBoard).toAlgebraic(move)

        // Cache it for future use
        node.cachedNotation = computed

        return computed
    }

    private var annotationColor: Color? {
        switch node.annotation {
        case "!!": return DS.moveBrilliant
        case "!":  return DS.moveGreat
        case "!?": return DS.moveOkay
        case "?!": return DS.moveInaccuracy
        case "?":  return DS.moveMistake
        case "??": return DS.moveBlunder
        default:   return nil
        }
    }

    private var foregroundColor: Color {
        if isCurrent {
            return .white
        }
        if let color = annotationColor {
            return color
        }
        return isMainLine ? DS.textPrimary : DS.accentPurple
    }
}

// MARK: - Navigation Button

struct NavigationButton: View {
    let icon: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isEnabled ? DS.textSecondary : DS.textMuted)
                .glassIconButton(size: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

struct EmptyMoveListView: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "list.bullet")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DS.textTertiary)

            VStack(spacing: 6) {
                Text("No Moves Yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textSecondary)

                Text("Play moves on the board or import a PGN to get started")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textTertiary)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inline Note Editor (matches Pencil design)

struct InlineNoteEditorView: View {
    let moveLabel: String
    @Binding var noteText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: icon + "Add note after 12. Nxe4"
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.accentTeal)

                Text(noteText.isEmpty ? "Add note after \(moveLabel)" : "Edit note for \(moveLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.accentTeal)
            }

            // Text input field
            TextEditor(text: $noteText)
                .font(.system(size: 11))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DS.border, lineWidth: 1)
                )
                .focused($isFocused)

            // Actions row
            HStack(spacing: 8) {
                Text("Esc to cancel")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textTertiary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(GlassButtonStyle())

                Button("Save") {
                    onSave()
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(DS.bgSurface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.accentTeal)
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.accentTeal)
                .frame(height: 1)
        }
        .onAppear { isFocused = true }
        .onExitCommand { onCancel() }
    }
}

// MARK: - Legacy Note Editor (popover fallback)

struct NoteEditorView: View {
    @Binding var noteText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DS.spacingMD) {
            HStack {
                Text("Move Note")
                    .font(DS.titleFont)
                Spacer()
            }

            TextEditor(text: $noteText)
                .font(.system(size: 13))
                .frame(minHeight: 80, maxHeight: 150)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSM)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSM)
                        .strokeBorder(DS.border, lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(GlassButtonStyle())

                Spacer()

                Button("Save") {
                    onSave()
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && noteText.isEmpty)
            }
        }
        .padding(DS.spacingLG)
        .frame(width: 280)
    }
}

// MARK: - Custom Context Menu (matches Pencil design)

struct MoveContextMenuView: View {
    @ObservedObject var node: GameNode
    let isMainLine: Bool
    var onSetAnnotation: ((String) -> Void)?
    var onDeleteMove: (() -> Void)?
    var onPromoteToMainLine: (() -> Void)?
    var onMakeSubline: (() -> Void)?
    var onAddNote: (() -> Void)?
    let onDismiss: () -> Void

    private struct AnnotationItem {
        let symbol: String
        let label: String
        let color: Color
        let annotation: String
    }

    private let annotations: [AnnotationItem] = [
        AnnotationItem(symbol: "!!", label: "Brilliant", color: DS.moveBrilliant, annotation: "!!"),
        AnnotationItem(symbol: "!", label: "Good Move", color: DS.moveGreat, annotation: "!"),
        AnnotationItem(symbol: "!?", label: "Interesting", color: DS.moveBest, annotation: "!?"),
        AnnotationItem(symbol: "?!", label: "Dubious", color: DS.moveInaccuracy, annotation: "?!"),
        AnnotationItem(symbol: "?", label: "Mistake", color: DS.moveMistake, annotation: "?"),
        AnnotationItem(symbol: "??", label: "Blunder", color: DS.moveBlunder, annotation: "??"),
    ]

    private var showsPromoteOrSubline: Bool {
        let canPromote = onPromoteToMainLine != nil && !isMainLine
        let canDemote = onMakeSubline != nil && isMainLine && node.parent != nil && (node.parent?.children.count ?? 0) > 1
        return canPromote || canDemote
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section label
            HStack {
                Text("ANNOTATE MOVE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.33))
                    .kerning(0.6)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            // Annotation items
            if let setAnnotation = onSetAnnotation {
                ForEach(annotations, id: \.annotation) { item in
                    let isActive = node.annotation == item.annotation
                    ContextMenuItem(isActive: isActive) {
                        setAnnotation(item.annotation)
                        onDismiss()
                    } content: {
                        Text(item.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(item.color)
                            .frame(width: 24, alignment: .center)
                        Text(item.label)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
                    }
                }
            }

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            // Promote / Subline
            if let promote = onPromoteToMainLine, !isMainLine {
                ContextMenuItem {
                    promote()
                    onDismiss()
                } content: {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                        .frame(width: 24, alignment: .center)
                    Text("Promote to Main Line")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
                }
            }

            if let demote = onMakeSubline, isMainLine, node.parent != nil, (node.parent?.children.count ?? 0) > 1 {
                ContextMenuItem {
                    demote()
                    onDismiss()
                } content: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                        .frame(width: 24, alignment: .center)
                    Text("Make Subline")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
                }
            }

            if showsPromoteOrSubline {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            // Add Comment
            ContextMenuItem {
                onAddNote?()
            } content: {
                Image(systemName: "message")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                    .frame(width: 24, alignment: .center)
                Text(node.comment.isEmpty ? "Add Comment" : "Edit Comment")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
            }

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            // Copy PGN
            ContextMenuItem {
                let notation = node.cachedNotation ?? "?"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(notation, forType: .string)
                onDismiss()
            } content: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.67))
                    .frame(width: 24, alignment: .center)
                Text("Copy PGN")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xFFFFFF, opacity: 0.93))
            }

            // Delete
            if let deleteMove = onDeleteMove {
                ContextMenuItem {
                    deleteMove()
                    onDismiss()
                } content: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xFF453A))
                        .frame(width: 24, alignment: .center)
                    Text("Delete from Here")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xFF453A))
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 4)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0x161620, opacity: 0.7))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.094))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.157), Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.3)
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.31), Color.white.opacity(0.06), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.37), radius: 10, x: 0, y: 8)
    }
}

// MARK: - Context Menu Item

private struct ContextMenuItem<Content: View>: View {
    var isActive: Bool = false
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            .padding(.horizontal, 12)
            .background {
                if isHovered || isActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - Right-Click Helper

private struct RightClickModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(
            RightClickOverlay(action: action)
        )
    }
}

private struct RightClickOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickNSView {
        let view = RightClickNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickNSView, context: Context) {
        nsView.action = action
    }

    class RightClickNSView: NSView {
        var action: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only intercept right-click events; let left clicks fall through to
            // the SwiftUI Button beneath (otherwise tapping a move did nothing).
            guard bounds.contains(point) else { return nil }
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return self
            default:
                return nil
            }
        }
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        modifier(RightClickModifier(action: action))
    }
}

#Preview {
    let gameTree = GameTree()
    let board = gameTree.root.boardState

    if let e4 = MoveGenerator(board: board).legalMoves(for: Position(4, 1)).first(where: { $0.to == Position(4, 3) }) {
        _ = gameTree.addMove(e4)

        if let e5 = MoveGenerator(board: gameTree.currentNode.boardState).legalMoves(for: Position(4, 6)).first(where: { $0.to == Position(4, 4) }) {
            _ = gameTree.addMove(e5)
        }
    }

    return MoveListView(gameTree: gameTree)
        .frame(width: 260, height: 500)
}
