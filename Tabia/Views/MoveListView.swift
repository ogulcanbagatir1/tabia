import SwiftUI
import UniformTypeIdentifiers

struct MoveListView: View {
    @ObservedObject var gameTree: GameTree
    // Optional game metadata — shown as an editorial header above the moves when a game is loaded.
    var whiteName: String = ""
    var blackName: String = ""
    var event: String = ""
    var openingName: String = ""
    var eco: String = ""
    var result: String = ""
    // Game review — rendered at the top of the same scroll (above the moves) once analysis completes,
    // so the whole right column scrolls as one, not just the move list.
    var gameAnalyzer: GameAnalyzer? = nil
    var showReview: Bool = false
    var reviewTimeClass: String? = nil
    // Bring a game in without saving it: the Import button and PGN drag-drop both load the first
    // game from the PGN into the board for viewing only.
    var onImportPGN: (() -> Void)? = nil
    var onSetUpPosition: (() -> Void)? = nil
    var onDropPGNText: ((String) -> Void)? = nil

    private var hasGameInfo: Bool { !whiteName.isEmpty || !blackName.isEmpty }

    private func surname(_ name: String) -> String {
        let s = name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? name
        return s.isEmpty ? name : s
    }

    private var gameInfoHeader: some View {
        let meta = [event, [openingName, eco].filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(surname(whiteName)) – \(surname(blackName))")
                    .font(AnnFont.serif(14, .semibold)).foregroundColor(DS.ink).lineLimit(1)
                if !meta.isEmpty {
                    Text(meta.uppercased())
                        .font(AnnFont.mono(9)).tracking(0.5).foregroundColor(DS.ink40).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !result.isEmpty && result != "*" {
                Text(result)
                    .font(AnnFont.mono(11, bold: true)).foregroundColor(DS.ink60)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Game review on top (once an analysis has completed), then the moves —
                    // all in a single scroll so the whole column moves together.
                    if showReview, let analyzer = gameAnalyzer {
                        GameAnalysisResultsView(
                            gameAnalyzer: analyzer,
                            gameTree: gameTree,
                            timeClass: reviewTimeClass
                        )
                        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
                    }

                    if hasGameInfo { gameInfoHeader }

                    if gameTree.root.children.isEmpty {
                        EmptyMoveListView(onImportPGN: onImportPGN, onSetUpPosition: onSetUpPosition)
                    } else {
                        VerticalMoveTreeView(
                            node: gameTree.root,
                            currentNodeId: gameTree.currentNode.id,
                            structureVersion: gameTree.structureVersion,
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
                        .equatable()
                        .onChange(of: gameTree.currentNode.id) { _, newId in
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipped()
        // Drag-and-drop a PGN anywhere on the moves panel to view its first game (not saved).
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let u = item as? URL { url = u }
                else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                guard let fileURL = url, let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
                DispatchQueue.main.async { onDropPGNText?(text) }
            }
            return true
        }
    }
}

// MARK: - Vertical Move Tree View

struct VerticalMoveTreeView: View, Equatable {
    let node: GameNode
    let currentNodeId: UUID
    // Structural revision of the whole tree — drives the .equatable() skip below (default 0 for the
    // recursive inner instances, which aren't wrapped in .equatable() so their value is unused).
    var structureVersion: Int = 0
    let onTapMove: (GameNode) -> Void
    let onSetAnnotation: (GameNode, String) -> Void
    let onDeleteMove: (GameNode) -> Void
    let onPromoteToMainLine: (GameNode) -> Void
    let onMakeSubline: (GameNode) -> Void
    let isMainLine: Bool
    let startMoveNumber: Int
    let startIsWhite: Bool

    // Skip re-running collectSegments() + every MoveRow/MoveButton body when the parent window
    // re-renders (e.g. on each engine eval tick) but the tree, the selected node, and this view's
    // position are all unchanged. Closures are intentionally excluded — they're pure forwarders
    // keyed on the node, so a fresh closure instance never means a different rendering.
    static func == (lhs: VerticalMoveTreeView, rhs: VerticalMoveTreeView) -> Bool {
        lhs.node.id == rhs.node.id &&
        lhs.currentNodeId == rhs.currentNodeId &&
        lhs.structureVersion == rhs.structureVersion &&
        lhs.isMainLine == rhs.isMainLine &&
        lhs.startMoveNumber == rhs.startMoveNumber &&
        lhs.startIsWhite == rhs.startIsWhite
    }

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
        let moveNumber: Int
        let whiteNode: GameNode?
        let blackNode: GameNode?
        // Stable identity from the (stable) GameNode ids, so SwiftUI diffs rows instead of tearing
        // down and rebuilding every row's views (incl. AppKit overlays) on each move — the stutter fix.
        var id: UUID { whiteNode?.id ?? blackNode?.id ?? Self.empty }
        private static let empty = UUID()
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
        // Variations branching at a WHITE move wait here until Black has replied, so the sideline is
        // drawn below the finished pair. Emitting it immediately used to split the move pair: White
        // was flushed as a half-row, the sideline went in between, and Black's main-line reply was
        // pushed onto its own "3. …" row.
        var pendingVariations: [VariationItem] = []

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

            // Collect variations at this ply; they are emitted once the row they belong to is whole.
            if children.count > 1 {
                for i in 1..<children.count {
                    pendingVariations.append(VariationItem(
                        node: children[i],
                        moveNumber: moveNumber,
                        isWhiteMove: isWhite
                    ))
                }
            }

            // A Black move closes the pair, so anything pending can now be drawn beneath it.
            if !isWhite, !pendingVariations.isEmpty {
                segments.append(Segment(rows: currentRows, variations: pendingVariations))
                currentRows = []
                pendingVariations = []
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

        // The line ended on White, so its variations never got a closing Black move.
        if !pendingVariations.isEmpty {
            segments.append(Segment(rows: currentRows, variations: pendingVariations))
            currentRows = []
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
                    .font(AnnFont.mono(13, bold: true))
                    .foregroundColor(DS.ink25)
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
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("...")
                        .font(AnnFont.mono(13.5))
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
                    .equatable()
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
        .background(row.moveNumber % 2 == 0 ? DS.hoverWash : Color.clear)
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
                        .font(AnnFont.mono(10))
                        .foregroundColor(DS.textTertiary)
                } else {
                    Text("\(moveNumber)...")
                        .font(AnnFont.mono(10))
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
                .equatable()

                if !isExpanded {
                    Text("...")
                        .font(AnnFont.mono(10))
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

struct MoveButton: View, Equatable {
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

    // Skip re-rendering (incl. rebuilding the .popover + right-click NSView) when neither the
    // selection state nor the identity changed. annotation/comment edits still repaint because
    // `node` is observed — @ObservedObject invalidation bypasses this equality skip.
    static func == (lhs: MoveButton, rhs: MoveButton) -> Bool {
        lhs.node.id == rhs.node.id &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.isMainLine == rhs.isMainLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Button(action: onTap) {
                    Text(displayText)
                        .font(AnnFont.mono(isMainLine ? 14 : 12.5, bold: isCurrent))
                        .foregroundColor(isCurrent ? DS.ink : DS.ink)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isCurrent ? DS.selectedWash : Color.clear)
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
                        .font(AnnFont.serif(10, .regular, italic: true))
                        .foregroundColor(DS.accentTeal)
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

// MARK: - Empty State

struct EmptyMoveListView: View {
    var onImportPGN: (() -> Void)? = nil
    var onSetUpPosition: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(DS.ink40)

            Text("No moves yet")
                .font(AnnFont.serif(16, .semibold))
                .foregroundColor(DS.ink)

            Text("Play on the board, or bring a game in.")
                .font(AnnFont.voice(13))
                .foregroundColor(DS.ink40)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                emptyStateButton("IMPORT PGN") { onImportPGN?() }
                emptyStateButton("SET UP A POSITION") { onSetUpPosition?() }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36).padding(.horizontal, 20)
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
        .padding(16)
    }

    private func emptyStateButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AnnFont.label(11)).tracking(11 * 0.1)
                .foregroundColor(DS.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9).padding(.horizontal, 20)
                .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                    .font(AnnFont.serif(11, .medium))
                    .foregroundColor(DS.accentTeal)
            }

            // Text input field
            TextEditor(text: $noteText)
                .font(AnnFont.serif(11))
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
                    .font(AnnFont.mono(10))
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
                    .font(AnnFont.label(10))
                    .foregroundColor(DS.ink40)
                    .kerning(0.6)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)

            Rectangle().fill(DS.hairline).frame(height: 1)

            // Annotation items
            if let setAnnotation = onSetAnnotation {
                ForEach(annotations, id: \.annotation) { item in
                    let isActive = node.annotation == item.annotation
                    ContextMenuItem(isActive: isActive) {
                        setAnnotation(item.annotation)
                        onDismiss()
                    } content: {
                        Text(item.symbol)
                            .font(AnnFont.mono(14, bold: true))
                            .foregroundColor(item.color)
                            .frame(width: 24, alignment: .center)
                        Text(item.label)
                            .font(AnnFont.label(13))
                            .tracking(13 * 0.1)
                            .foregroundColor(DS.ink)
                    }
                }
            }

            Rectangle().fill(DS.hairline).frame(height: 1)

            // Promote / Subline
            if let promote = onPromoteToMainLine, !isMainLine {
                ContextMenuItem {
                    promote()
                    onDismiss()
                } content: {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 14))
                        .foregroundColor(DS.ink60)
                        .frame(width: 24, alignment: .center)
                    Text("Promote to Main Line")
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(DS.ink)
                }
            }

            if let demote = onMakeSubline, isMainLine, node.parent != nil, (node.parent?.children.count ?? 0) > 1 {
                ContextMenuItem {
                    demote()
                    onDismiss()
                } content: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 14))
                        .foregroundColor(DS.ink60)
                        .frame(width: 24, alignment: .center)
                    Text("Make Subline")
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(DS.ink)
                }
            }

            if showsPromoteOrSubline {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            // Add Comment
            ContextMenuItem {
                onAddNote?()
            } content: {
                Image(systemName: "message")
                    .font(.system(size: 14))
                    .foregroundColor(DS.ink60)
                    .frame(width: 24, alignment: .center)
                Text(node.comment.isEmpty ? "Add Comment" : "Edit Comment")
                    .font(AnnFont.label(13))
                    .tracking(13 * 0.1)
                    .foregroundColor(DS.ink)
            }

            Rectangle().fill(DS.hairline).frame(height: 1)

            // Copy PGN
            ContextMenuItem {
                let notation = node.cachedNotation ?? "?"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(notation, forType: .string)
                onDismiss()
            } content: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundColor(DS.ink60)
                    .frame(width: 24, alignment: .center)
                Text("Copy PGN")
                    .font(AnnFont.label(13))
                    .tracking(13 * 0.1)
                    .foregroundColor(DS.ink)
            }

            // Delete
            if let deleteMove = onDeleteMove {
                ContextMenuItem {
                    deleteMove()
                    onDismiss()
                } content: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(DS.redAccent)
                        .frame(width: 24, alignment: .center)
                    Text("Delete from Here")
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(DS.redAccent)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.paperRaised)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
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
                        .fill(DS.hoverWash)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(DS.hairline, lineWidth: 0.5)
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
