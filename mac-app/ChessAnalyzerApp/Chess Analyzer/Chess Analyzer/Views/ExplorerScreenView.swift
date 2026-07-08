import SwiftUI

/// Standalone Explorer screen (E1/E2). A dedicated opening-explorer: a board + move sequence on
/// the left (448 column), the source picker + moves table on the right. Self-contained board
/// state so you can walk openings here independently of the Analysis board.
struct ExplorerScreenView: View {
    @StateObject private var board = ChessBoard()
    @StateObject private var gameTree = GameTree()
    @StateObject private var lichessExplorer = LichessExplorerService()
    @StateObject private var libraryExplorer = LibraryExplorerService()
    @ObservedObject private var openingBook = OpeningBook.shared

    @State private var source: Source = .lichess
    @State private var searchText = ""
    @State private var openingName: String? = nil
    @State private var openingECO: String? = nil

    enum Source: String, CaseIterable {
        case lichess = "Lichess Masters"
        case library = "My Library"
    }

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(width: 448)
                .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }

            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.paper)
        .onAppear { updateOpening() }
        .onChange(of: gameTree.currentNode.id) { _, _ in
            syncBoard(); updateOpening()
        }
    }

    // MARK: - Left column — position + board

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            // PLATE / ECO label + opening title + move sequence
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let eco = openingECO, !eco.isEmpty {
                        Text("PLATE \(eco)").font(AnnFont.mono(10, bold: true)).tracking(1).foregroundColor(DS.redAccent)
                    } else {
                        AnnLabel("Opening Explorer", size: 10, tracking: 0.14, bold: true, color: DS.ink40)
                    }
                    Spacer()
                }
                Text(openingName ?? "Starting Position")
                    .font(AnnFont.serif(21, .medium)).foregroundColor(DS.ink)
                    .fixedSize(horizontal: false, vertical: true)
                let seq = movesSAN()
                if !seq.isEmpty {
                    Text(numberedSequence(seq)).font(AnnFont.mono(11.5)).foregroundColor(DS.ink60)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Board
            BoardView(board: board, gameTree: gameTree, isFlipped: false)
                .frame(width: 384, height: 384)
                .overlay(Rectangle().strokeBorder(DS.windowBorder, lineWidth: 1))
                .padding(4)
                .background(DS.paperRaised)
                .overlay(Rectangle().strokeBorder(DS.borderStrong, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.28), radius: 20, x: 0, y: 10)

            // Nav row + reset
            HStack(spacing: 8) {
                navButton("chevron.left") { _ = gameTree.goBack() }
                navButton("chevron.right") { _ = gameTree.goForward() }
                navButton("backward.end") { gameTree.goToStart() }
                Spacer()
                navButton("arrow.counterclockwise") { resetBoard() }
            }

            Text("Play a move, or pick a continuation on the right — the explorer walks the position with you.")
                .font(AnnFont.voice(13.5)).foregroundColor(DS.ink60)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(DS.ink60)
                .frame(width: 30, height: 28)
                .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rChip))
                .overlay(RoundedRectangle(cornerRadius: DS.rChip).strokeBorder(DS.hairline, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: - Right column — source picker + explorer table

    private var rightColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AnnSegmented(options: Source.allCases.map { ($0, $0.rawValue) }, selection: $source)
                    Spacer()
                }
                AnnSearchField(text: $searchText, placeholder: "Search openings…")
            }
            .padding(20)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            if source == .lichess {
                LichessExplorerView(
                    explorerService: lichessExplorer, openingBook: openingBook, board: board,
                    currentMoves: movesUCI(), searchText: $searchText,
                    onMovePlayed: { _ = applyUCI($0) },
                    onGameLoaded: { _ in }, onOpeningSelected: { applyOpening($0) }
                )
            } else {
                LibraryExplorerView(
                    explorerService: libraryExplorer, openingBook: openingBook, board: board,
                    currentMoves: movesUCI(), currentSANs: movesSAN(), searchText: $searchText,
                    onMovePlayed: { _ = applyUCI($0) },
                    onGameLoaded: { _ in }, onOpeningSelected: { applyOpening($0) }
                )
            }
        }
    }

    // MARK: - Move logic

    private func pathToCurrent() -> [GameNode] {
        var path: [GameNode] = []; var cur: GameNode? = gameTree.currentNode
        while let n = cur { path.insert(n, at: 0); cur = n.parent }
        return path
    }
    private func movesUCI() -> [String] { pathToCurrent().compactMap { $0.move.map(moveToUCI) } }
    private func movesSAN() -> [String] {
        pathToCurrent().compactMap { $0.cachedNotation?.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "") }
    }

    private func numberedSequence(_ sans: [String]) -> String {
        var out = ""
        for (i, san) in sans.enumerated() {
            if i % 2 == 0 { out += "\(i / 2 + 1). " }
            out += san + " "
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private func moveToUCI(_ move: Move) -> String {
        let files = "abcdefgh"
        let ff = files[files.index(files.startIndex, offsetBy: move.from.file)]
        let tf = files[files.index(files.startIndex, offsetBy: move.to.file)]
        var uci = "\(ff)\(move.from.rank + 1)\(tf)\(move.to.rank + 1)"
        if let p = move.promotionType {
            switch p { case .queen: uci += "q"; case .rook: uci += "r"; case .bishop: uci += "b"; case .knight: uci += "n"; default: break }
        }
        return uci
    }

    @discardableResult
    private func applyUCI(_ uci: String) -> Bool {
        guard uci.count >= 4 else { return false }
        let c = Array(uci)
        guard let ffA = c[0].asciiValue, let tfA = c[2].asciiValue,
              let fr = Int(String(c[1])), let tr = Int(String(c[3])) else { return false }
        let from = Position(Int(ffA) - 97, fr - 1)
        let to = Position(Int(tfA) - 97, tr - 1)
        guard let piece = board.pieceAt(from) else { return false }
        var promo: PieceType? = nil
        if c.count >= 5 { switch c[4] { case "q": promo = .queen; case "r": promo = .rook; case "b": promo = .bishop; case "n": promo = .knight; default: break } }
        let captured = board.pieceAt(to)
        let ep = piece.type == .pawn && from.file != to.file && captured == nil
        let castle = piece.type == .king && abs(from.file - to.file) == 2
        let move = Move(from: from, to: to, piece: piece,
                        capturedPiece: ep ? board.pieceAt(Position(to.file, from.rank)) : captured,
                        isEnPassant: ep, isCastling: castle, promotionType: promo)
        if board.makeMove(move) { _ = gameTree.addMove(move); return true }
        return false
    }

    private func applyOpening(_ uciMoves: [String]) {
        resetBoard()
        for uci in uciMoves { applyUCI(uci) }
        syncBoard(); updateOpening()
    }

    private func resetBoard() {
        let nb = ChessBoard()
        board.squares = nb.squares; board.turn = nb.turn; board.moveHistory = nb.moveHistory
        board.enPassantTarget = nb.enPassantTarget; board.halfMoveClock = nb.halfMoveClock; board.fullMoveNumber = nb.fullMoveNumber
        let nt = GameTree(); gameTree.root = nt.root; gameTree.currentNode = nt.root; gameTree.mainLine = [nt.root]
    }

    private func syncBoard() {
        let cur = gameTree.currentNode.boardState
        board.squares = cur.squares; board.turn = cur.turn; board.moveHistory = cur.moveHistory
        board.enPassantTarget = cur.enPassantTarget; board.halfMoveClock = cur.halfMoveClock; board.fullMoveNumber = cur.fullMoveNumber
    }

    private func updateOpening() {
        if let o = openingBook.findOpening(moves: movesUCI()) {
            openingName = o.name; openingECO = o.eco
        }
    }
}
