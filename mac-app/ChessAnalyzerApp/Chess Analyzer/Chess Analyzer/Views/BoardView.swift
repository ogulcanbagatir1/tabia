import SwiftUI
import AppKit

// Arrow for annotation
struct BoardArrow: Identifiable, Equatable {
    let id = UUID()
    let from: Position
    let to: Position
    let color: Color

    static func == (lhs: BoardArrow, rhs: BoardArrow) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to
    }
}

struct BoardView: View {
    @ObservedObject var board: ChessBoard
    @ObservedObject var gameTree: GameTree
    var explorerArrow: BoardArrow? = nil  // Optional explorer arrow to show
    var isFlipped: Bool = false  // Board orientation (false = White at bottom)
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedSquare: Position?
    @State private var legalMoves: [Move] = []
    @State private var moveGenerator: MoveGenerator?
    @State private var lastMove: Move?

    // Drag & Drop state
    @State private var draggedPiece: Piece?
    @State private var draggedFrom: Position?
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    // Arrow drawing state
    @State private var arrows: [BoardArrow] = []
    @State private var arrowStart: Position?
    @State private var highlightedSquares: Set<Position> = []

    // Colors from settings
    private var lightSquare: Color { settings.boardTheme.lightSquare }
    private var darkSquare: Color { settings.boardTheme.darkSquare }
    private var selectedColor: Color { settings.boardTheme.selectedColor }
    private var lastMoveColor: Color { settings.boardTheme.lastMoveColor }
    let legalMoveColor = Color.black.opacity(0.12)
    let captureColor = Color(red: 0.80, green: 0.26, blue: 0.26)

    // Coordinate label size
    let labelWidth: CGFloat = 20
    let labelHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - labelWidth
            let availableHeight = geometry.size.height - labelHeight
            let squareSize = min(availableWidth, availableHeight) / 8
            let boardSize = squareSize * 8

            VStack(spacing: 0) {
                Spacer()

                HStack(spacing: 0) {
                    Spacer()

                    // Board with coordinates
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            // Left rank numbers
                            VStack(spacing: 0) {
                                ForEach(displayRanks, id: \.self) { rank in
                                    Text("\(rank + 1)")
                                        .font(.system(size: max(10, squareSize * 0.15), weight: .medium, design: .monospaced))
                                        .foregroundColor(DS.textSecondary)
                                        .frame(width: labelWidth, height: squareSize)
                                }
                            }

                            // Board
                            ZStack {
                                // Layer 0: Board image (if image-based theme)
                                if let boardImage = settings.boardTheme.loadBoardImage() {
                                    Image(nsImage: boardImage)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: boardSize, height: boardSize)
                                        .cornerRadius(DS.radiusSM)
                                }

                                // Layer 1: Board squares + static pieces
                                VStack(spacing: 0) {
                                    ForEach(displayRanks, id: \.self) { rank in
                                        HStack(spacing: 0) {
                                            ForEach(displayFiles, id: \.self) { file in
                                                let position = Position(file, rank)

                                                ModernSquareView(
                                                    position: position,
                                                    piece: squarePiece(at: position),
                                                    isLight: (file + rank) % 2 != 0,
                                                    isSelected: selectedSquare == position,
                                                    isLegalMove: legalMoves.contains(where: { $0.to == position }),
                                                    isLastMove: isLastMoveSquare(position),
                                                    isHighlighted: highlightedSquares.contains(position),
                                                    isDragging: isDragging && draggedFrom == position,
                                                    squareSize: squareSize,
                                                    hasBoardImage: settings.boardTheme.imageName != nil,
                                                    lightSquare: lightSquare,
                                                    darkSquare: darkSquare,
                                                    selectedColor: selectedColor,
                                                    lastMoveColor: lastMoveColor,
                                                    legalMoveColor: legalMoveColor,
                                                    captureColor: captureColor
                                                )
                                                .contentShape(Rectangle())
                                                .gesture(
                                                    TapGesture()
                                                        .onEnded {
                                                            if !isDragging {
                                                                handleTap(position: position, squareSize: squareSize)
                                                            }
                                                        }
                                                )
                                                .simultaneousGesture(
                                                    DragGesture(minimumDistance: 5)
                                                        .onChanged { value in
                                                            handleDragChanged(position: position, value: value, squareSize: squareSize)
                                                        }
                                                        .onEnded { value in
                                                            handleDragEnded(position: position, value: value, squareSize: squareSize)
                                                        }
                                                )
                                            }
                                        }
                                    }
                                }
                                .cornerRadius(DS.radiusSM)

                                // Layer 2: Dragged piece overlay
                                if isDragging, let piece = draggedPiece, let fromPos = draggedFrom {
                                    let visualFile = isFlipped ? (7 - fromPos.file) : fromPos.file
                                    let visualRank = isFlipped ? fromPos.rank : (7 - fromPos.rank)
                                    let squareCenterX = CGFloat(visualFile) * squareSize + squareSize / 2
                                    let squareCenterY = CGFloat(visualRank) * squareSize + squareSize / 2

                                    PieceView(piece: piece, size: squareSize)
                                        .position(
                                            x: squareCenterX + dragOffset.width,
                                            y: squareCenterY + dragOffset.height
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 8, x: 2, y: 4)
                                        .allowsHitTesting(false)
                                        .zIndex(9999)
                                }

                                // Layer 4: Explorer arrow (light colored, drawn first so user arrows are on top)
                                if let explorerArrow = explorerArrow {
                                    ArrowShape(
                                        from: squareCenter(explorerArrow.from, squareSize: squareSize),
                                        to: squareCenter(explorerArrow.to, squareSize: squareSize),
                                        headSize: squareSize * 0.35
                                    )
                                    .fill(explorerArrow.color.opacity(0.6))
                                    .allowsHitTesting(false)
                                }

                                // Layer 5: User arrows
                                ForEach(arrows) { arrow in
                                    ArrowShape(
                                        from: squareCenter(arrow.from, squareSize: squareSize),
                                        to: squareCenter(arrow.to, squareSize: squareSize),
                                        headSize: squareSize * 0.35
                                    )
                                    .fill(arrow.color.opacity(0.8))
                                    .allowsHitTesting(false)
                                }

                                // Layer 6: Move annotation badge
                                if let move = gameTree.currentNode.move,
                                   !gameTree.currentNode.annotation.isEmpty {
                                    let ann = gameTree.currentNode.annotation
                                    let badgeSize = squareSize * 0.38
                                    AnnotationBadge(annotation: ann, size: badgeSize)
                                        .position(
                                            x: CGFloat(move.to.file + 1) * squareSize,
                                            y: CGFloat(7 - move.to.rank) * squareSize
                                        )
                                        .allowsHitTesting(false)
                                        .zIndex(10000)
                                        .id("annotation-\(move.to.file)-\(move.to.rank)")
                                }
                            }
                            .frame(width: boardSize, height: boardSize)
                            .background(
                                RightClickMonitor(
                                    squareSize: squareSize,
                                    boardSize: boardSize,
                                    onRightClick: { startPos, endPos in
                                        if startPos == endPos {
                                            // Same square - toggle highlight
                                            if highlightedSquares.contains(startPos) {
                                                highlightedSquares.remove(startPos)
                                            } else {
                                                highlightedSquares.insert(startPos)
                                            }
                                        } else {
                                            // Different square - toggle arrow
                                            if let index = arrows.firstIndex(where: { $0.from == startPos && $0.to == endPos }) {
                                                arrows.remove(at: index)
                                            } else {
                                                arrows.append(BoardArrow(from: startPos, to: endPos, color: .orange))
                                            }
                                        }
                                    },
                                    onLeftClick: {
                                        arrows.removeAll()
                                        highlightedSquares.removeAll()
                                    }
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.radiusSM)
                                    .strokeBorder(DS.border, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                        }

                        // Bottom file letters
                        HStack(spacing: 0) {
                            Spacer().frame(width: labelWidth)
                            ForEach(displayFiles, id: \.self) { file in
                                Text(String("abcdefgh"[String.Index(utf16Offset: file, in: "abcdefgh")]))
                                    .font(.system(size: max(10, squareSize * 0.15), weight: .medium, design: .monospaced))
                                    .foregroundColor(DS.textSecondary)
                                    .frame(width: squareSize, height: labelHeight)
                            }
                        }
                    }

                    Spacer()
                }

                Spacer()
            }
        }
        .onAppear {
            moveGenerator = MoveGenerator(board: board)
        }
        .onChange(of: board.turn) { _, _ in
            // Board synced by MainWindowView - just update moveGenerator
            moveGenerator = MoveGenerator(board: board)
            selectedSquare = nil
            legalMoves = []
        }
        .background(
            ScrollWheelHandler { delta in
                if delta > 0 {
                    _ = gameTree.goBack()
                } else if delta < 0 {
                    _ = gameTree.goForward()
                }
            }
        )
    }

    private func squarePiece(at position: Position) -> Piece? {
        return board.pieceAt(position)
    }

    // Display order for ranks and files based on board orientation
    private var displayRanks: [Int] {
        isFlipped ? Array(0..<8) : Array((0..<8).reversed())
    }

    private var displayFiles: [Int] {
        isFlipped ? Array((0..<8).reversed()) : Array(0..<8)
    }

    // Returns the center point of a square in board coordinates
    private func squareCenter(_ position: Position, squareSize: CGFloat) -> CGPoint {
        let visualFile = isFlipped ? (7 - position.file) : position.file
        let visualRank = isFlipped ? position.rank : (7 - position.rank)
        return CGPoint(
            x: CGFloat(visualFile) * squareSize + squareSize / 2,
            y: CGFloat(visualRank) * squareSize + squareSize / 2
        )
    }

    private func isLastMoveSquare(_ position: Position) -> Bool {
        guard let move = gameTree.currentNode.move else { return false }
        return move.from == position || move.to == position
    }


    // MARK: - Tap Handling

    private func handleTap(position: Position, squareSize: CGFloat) {
        if let _ = selectedSquare,
           let move = legalMoves.first(where: { $0.to == position }) {
            executeMove(move)
            return
        }

        if let piece = board.pieceAt(position), piece.color == board.turn {
            selectedSquare = position
            if let gen = moveGenerator {
                legalMoves = gen.legalMoves(for: position)
            }
        } else {
            selectedSquare = nil
            legalMoves = []
        }
    }

    // MARK: - Drag Handling

    private func handleDragChanged(position: Position, value: DragGesture.Value, squareSize: CGFloat) {
        if !isDragging {
            guard let piece = board.pieceAt(position),
                  piece.color == board.turn else { return }

            isDragging = true
            draggedPiece = piece
            draggedFrom = position
            selectedSquare = position

            if let gen = moveGenerator {
                legalMoves = gen.legalMoves(for: position)
            }
        }

        dragOffset = value.translation
    }

    private func handleDragEnded(position: Position, value: DragGesture.Value, squareSize: CGFloat) {
        guard let fromPos = draggedFrom else {
            clearDragState()
            return
        }

        // When flipped, drag directions are inverted
        let fileOffset = isFlipped
            ? -Int(round(value.translation.width / squareSize))
            : Int(round(value.translation.width / squareSize))
        let rankOffset = isFlipped
            ? Int(round(value.translation.height / squareSize))
            : -Int(round(value.translation.height / squareSize))

        let targetFile = fromPos.file + fileOffset
        let targetRank = fromPos.rank + rankOffset

        let targetPos = Position(targetFile, targetRank)

        let moveToExecute = legalMoves.first(where: { $0.to == targetPos })

        clearDragState()

        guard targetPos.isValid() else { return }

        if let move = moveToExecute {
            executeMove(move)
        }
    }

    private func clearDragState() {
        isDragging = false
        draggedPiece = nil
        draggedFrom = nil
        dragOffset = .zero
        selectedSquare = nil
        legalMoves = []
    }

    // MARK: - Move Execution

    private func executeMove(_ move: Move) {
        guard board.makeMove(move) else { return }

        _ = gameTree.addMove(move)
        lastMove = move

        moveGenerator = MoveGenerator(board: board)
        selectedSquare = nil
        legalMoves = []
    }

}

// MARK: - Modern Square View

struct ModernSquareView: View {
    let position: Position
    let piece: Piece?
    let isLight: Bool
    let isSelected: Bool
    let isLegalMove: Bool
    let isLastMove: Bool
    let isHighlighted: Bool
    let isDragging: Bool
    let squareSize: CGFloat
    var hasBoardImage: Bool = false

    let lightSquare: Color
    let darkSquare: Color
    let selectedColor: Color
    let lastMoveColor: Color
    let legalMoveColor: Color
    let captureColor: Color

    var body: some View {
        ZStack {
            // Base square color
            Rectangle()
                .fill(squareColor)

            // Last-move accent overlay (separate layer for better blending)
            if isLastMove && !isSelected {
                Rectangle()
                    .fill(lastMoveColor.opacity(hasBoardImage ? 0.35 : 0.45))
            }

            // Red highlight overlay (right-click annotation)
            if isHighlighted {
                Rectangle()
                    .fill(Color.red.opacity(0.5))
            }

            // Legal move indicator
            if isLegalMove {
                if piece != nil {
                    // Capture indicator - corner triangles
                    CaptureIndicator()
                        .fill(captureColor.opacity(0.8))
                } else {
                    // Move indicator - subtle dot with shadow
                    Circle()
                        .fill(legalMoveColor)
                        .frame(width: squareSize * 0.3, height: squareSize * 0.3)
                        .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                }
            }

            // Piece
            if let piece = piece, !isDragging {
                PieceView(piece: piece, size: squareSize)
                    .transition(.scale)
            }
        }
        .frame(width: squareSize, height: squareSize)
    }

    private var squareColor: Color {
        if isSelected {
            return selectedColor.opacity(hasBoardImage ? 0.6 : 1.0)
        }
        return hasBoardImage ? .clear : (isLight ? lightSquare : darkSquare)
    }

}

// MARK: - Annotation Badge

struct AnnotationBadge: View {
    let annotation: String
    let size: CGFloat

    var body: some View {
        Group {
            if let iconName = iconName {
                Image(systemName: iconName)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text(annotation)
                    .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .background(
            Circle()
                .fill(badgeColor)
                .shadow(color: badgeColor.opacity(0.55), radius: 4, x: 0, y: 2)
        )
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
        )
    }

    private var iconName: String? {
        switch annotation {
        case "*": return "star.fill"      // Best
        case "B": return "book.fill"      // Book
        case "+": return "hand.thumbsup.fill"  // Good
        case "o": return "checkmark"      // Okay
        default: return nil
        }
    }

    private var badgeColor: Color {
        switch annotation {
        case "!!": return DS.moveBrilliant
        case "!":  return DS.moveGreat
        case "*":  return DS.moveBest
        case "B":  return DS.moveBook
        case "+":  return DS.moveGood
        case "o":  return DS.moveOkay
        case "!?": return DS.moveOkay       // Interesting — same as Okay
        case "?!": return DS.moveInaccuracy
        case "?":  return DS.moveMistake
        case "??": return DS.moveBlunder
        default:   return Color.gray
        }
    }
}

// MARK: - Capture Indicator Shape

struct CaptureIndicator: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = rect.width * 0.25

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: size, y: 0))
        path.addLine(to: CGPoint(x: 0, y: size))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width - size, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: size))
        path.closeSubpath()

        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: size, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height - size))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - size, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - size))
        path.closeSubpath()

        return path
    }
}

// MARK: - Piece View

struct PieceView: View {
    let piece: Piece
    let size: CGFloat
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        let style = settings.pieceStyle

        if let nsImage = loadPieceImage(style.imageFileName(for: piece)) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(piece.symbol)
                .font(.system(size: size * 0.75))
        }
    }
}

// MARK: - Scroll Wheel Handler

struct ScrollWheelHandler: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY
        if abs(delta) > 0.5 {
            onScroll?(delta)
        }
    }
}

// MARK: - Keyboard Navigation Handler

struct KeyboardNavigationHandler: NSViewRepresentable {
    let onLeftArrow: () -> Void
    let onRightArrow: () -> Void

    func makeNSView(context: Context) -> KeyboardMonitorView {
        let view = KeyboardMonitorView()
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        return view
    }

    func updateNSView(_ nsView: KeyboardMonitorView, context: Context) {
        nsView.onLeftArrow = onLeftArrow
        nsView.onRightArrow = onRightArrow
    }
}

class KeyboardMonitorView: NSView {
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    private var keyMonitor: Any?

    // Throttling to prevent crashes from rapid key presses
    private var lastKeyTime: Date = Date.distantPast
    private let minKeyInterval: TimeInterval = 0.05 // 50ms between key presses

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupMonitor()
        } else {
            removeMonitor()
        }
    }

    private func setupMonitor() {
        removeMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Throttle key presses to prevent crashes
            let now = Date()
            guard now.timeIntervalSince(self.lastKeyTime) >= self.minKeyInterval else {
                return nil // Ignore key press if too soon
            }
            self.lastKeyTime = now

            switch event.keyCode {
            case 123: // Left arrow
                self.onLeftArrow?()
                return nil
            case 124: // Right arrow
                self.onRightArrow?()
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    deinit {
        removeMonitor()
    }
}

// MARK: - Board With Evaluation Bar

struct BoardWithEvalBar: View {
    @ObservedObject var board: ChessBoard
    @ObservedObject var gameTree: GameTree
    @ObservedObject var engine: StockfishEngine
    var fixedBoardSize: CGFloat? = nil // If provided, use this size; otherwise calculate from geometry
    var explorerArrow: BoardArrow? = nil // Optional explorer arrow to show
    var isFlipped: Bool = false // Board orientation

    // Coordinate label size (must match BoardView)
    let labelWidth: CGFloat = 20
    let labelHeight: CGFloat = 18
    let evalBarWidth: CGFloat = 24
    let spacing: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            // Use fixed size if provided, otherwise calculate from available height
            let boardSize: CGFloat = fixedBoardSize ?? max(geometry.size.height - labelHeight - 20, 300)

            HStack(alignment: .center, spacing: spacing) {
                // Evaluation bar - matches board height exactly
                EvaluationBar(engine: engine, barHeight: boardSize)
                    .frame(width: evalBarWidth, height: boardSize)

                // Chess board with fixed size
                BoardView(board: board, gameTree: gameTree, explorerArrow: explorerArrow, isFlipped: isFlipped)
                    .frame(width: boardSize + labelWidth, height: boardSize + labelHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Arrow Shape

struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let headSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)

        guard length > 0 else { return path }

        // Unit vector in arrow direction
        let ux = dx / length
        let uy = dy / length

        // Perpendicular vector
        let px = -uy
        let py = ux

        // Arrow shaft width
        let shaftWidth = headSize * 0.35

        // Arrow head starts before the tip
        let headLength = headSize * 0.8
        let headBaseX = to.x - ux * headLength
        let headBaseY = to.y - uy * headLength

        // Shaft points
        let shaftStart1 = CGPoint(x: from.x + px * shaftWidth / 2, y: from.y + py * shaftWidth / 2)
        let shaftStart2 = CGPoint(x: from.x - px * shaftWidth / 2, y: from.y - py * shaftWidth / 2)
        let shaftEnd1 = CGPoint(x: headBaseX + px * shaftWidth / 2, y: headBaseY + py * shaftWidth / 2)
        let shaftEnd2 = CGPoint(x: headBaseX - px * shaftWidth / 2, y: headBaseY - py * shaftWidth / 2)

        // Arrow head points
        let headWidth = headSize * 0.5
        let headLeft = CGPoint(x: headBaseX + px * headWidth, y: headBaseY + py * headWidth)
        let headRight = CGPoint(x: headBaseX - px * headWidth, y: headBaseY - py * headWidth)

        // Draw arrow
        path.move(to: shaftStart1)
        path.addLine(to: shaftEnd1)
        path.addLine(to: headLeft)
        path.addLine(to: to)
        path.addLine(to: headRight)
        path.addLine(to: shaftEnd2)
        path.addLine(to: shaftStart2)
        path.closeSubpath()

        return path
    }
}

// MARK: - Right Click Monitor

struct RightClickMonitor: NSViewRepresentable {
    let squareSize: CGFloat
    let boardSize: CGFloat
    let onRightClick: (Position, Position) -> Void
    let onLeftClick: () -> Void

    func makeNSView(context: Context) -> RightClickMonitorView {
        let view = RightClickMonitorView()
        view.squareSize = squareSize
        view.boardSize = boardSize
        view.onRightClick = onRightClick
        view.onLeftClick = onLeftClick
        return view
    }

    func updateNSView(_ nsView: RightClickMonitorView, context: Context) {
        nsView.squareSize = squareSize
        nsView.boardSize = boardSize
        nsView.onRightClick = onRightClick
        nsView.onLeftClick = onLeftClick
    }
}

class RightClickMonitorView: NSView {
    var squareSize: CGFloat = 0
    var boardSize: CGFloat = 0
    var onRightClick: ((Position, Position) -> Void)?
    var onLeftClick: (() -> Void)?

    private var rightMouseMonitor: Any?
    private var leftMouseMonitor: Any?
    private var startPosition: Position?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            setupMonitors()
        } else {
            removeMonitors()
        }
    }

    private func setupMonitors() {
        removeMonitors()

        rightMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self] event in
            self?.handleRightMouseEvent(event)
            return event
        }

        leftMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleLeftMouseEvent(event)
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = rightMouseMonitor {
            NSEvent.removeMonitor(monitor)
            rightMouseMonitor = nil
        }
        if let monitor = leftMouseMonitor {
            NSEvent.removeMonitor(monitor)
            leftMouseMonitor = nil
        }
    }

    private func handleRightMouseEvent(_ event: NSEvent) {
        guard let window = self.window else { return }

        // Convert to view coordinates
        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)

        // Check if click is within board bounds
        guard viewPoint.x >= 0 && viewPoint.x < boardSize &&
              viewPoint.y >= 0 && viewPoint.y < boardSize else {
            startPosition = nil
            return
        }

        let position = positionFromPoint(viewPoint)
        guard position.isValid() else {
            startPosition = nil
            return
        }

        if event.type == .rightMouseDown {
            startPosition = position
        } else if event.type == .rightMouseUp {
            if let start = startPosition {
                onRightClick?(start, position)
            }
            startPosition = nil
        }
    }

    private func handleLeftMouseEvent(_ event: NSEvent) {
        guard let window = self.window else { return }

        let windowPoint = event.locationInWindow
        let viewPoint = convert(windowPoint, from: nil)

        // Only clear if click is within board bounds
        guard viewPoint.x >= 0 && viewPoint.x < boardSize &&
              viewPoint.y >= 0 && viewPoint.y < boardSize else {
            return
        }

        onLeftClick?()
    }

    private func positionFromPoint(_ point: CGPoint) -> Position {
        let file = Int(point.x / squareSize)
        let rank = Int(point.y / squareSize)
        return Position(file, rank)
    }

    deinit {
        removeMonitors()
    }
}

// MARK: - Helper Functions

func loadPieceImage(_ filename: String) -> NSImage? {
    guard let resourcePath = Bundle.main.resourcePath else { return nil }
    let imagePath = "\(resourcePath)/\(filename)"
    return NSImage(contentsOfFile: imagePath)
}

#Preview {
    let board = ChessBoard()
    let gameTree = GameTree()
    return BoardView(board: board, gameTree: gameTree)
        .frame(width: 700, height: 700)
        .background(DS.bg)
}
