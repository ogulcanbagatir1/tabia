import SwiftUI

// MARK: - Set Up Position (board editor modal)

struct SetUpPositionView: View {
    /// Called with a validated FEN when the user hits "Set Up & Analyze".
    let onSetup: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var board = ChessBoard()
    @State private var tool: EditorTool = .piece(Piece(type: .king, color: .white))
    @State private var flipped = false
    @State private var fenText = ""
    @State private var lastPainted: Int? = nil   // file*8+rank last touched in the current drag stroke
    // Castling mirrors (ChessBoard's flags are not @Published) — kept in sync with the pieces.
    @State private var cwK = true
    @State private var cwQ = true
    @State private var cbK = true
    @State private var cbQ = true

    private enum EditorTool: Equatable { case piece(Piece); case eraser }

    private let whiteOrder: [PieceType] = [.king, .queen, .rook, .bishop, .knight, .pawn]
    private let lightSq = Color(hex: 0xEADFC6)
    private let darkSq  = Color(hex: 0xB39167)
    private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DS.hairline).frame(height: 1)
            HStack(alignment: .top, spacing: 26) {
                leftColumn
                rightColumn
            }
            .padding(24)
            Rectangle().fill(DS.hairline).frame(height: 1)
            footer
        }
        .frame(width: 784, height: 582)
        .background(DS.paper)
        .onAppear {
            syncCastlingMirrors()
            fenText = board.getFEN()
        }
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Set Up Position").font(AnnFont.serif(21, .semibold)).foregroundColor(DS.ink)
                Text("BOARD EDITOR — DRAG, CLICK, OR PASTE A FEN")
                    .font(AnnFont.mono(10)).tracking(0.5).foregroundColor(DS.ink40)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.ink60)
                    .frame(width: 28, height: 28)
                    .background(DS.paperRaised, in: Circle())
                    .overlay(Circle().strokeBorder(DS.borderChip, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Text("EDIT · SET UP POSITION").font(AnnFont.mono(10)).tracking(0.5).foregroundColor(DS.ink25)
            Spacer()
            Button(action: { dismiss() }) {
                Text("CANCEL").font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(DS.ink60)
                    .padding(.vertical, 9).padding(.horizontal, 20)
                    .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: {
                refreshFEN()
                onSetup(board.getFEN())
                dismiss()
            }) {
                Text("SET UP & ANALYZE").font(AnnFont.label(11)).tracking(11 * 0.1)
                    .foregroundColor(DS.onRed)
                    .padding(.vertical, 9).padding(.horizontal, 20)
                    .background(validation.ok ? DS.redAccent : DS.ink25, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!validation.ok)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    // MARK: - Left column (palettes + board)

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            paletteRow(color: .white, includeEraser: true)
            boardGrid
            paletteRow(color: .black, includeEraser: false)
            Text(placingText).font(AnnFont.mono(10)).tracking(0.5).foregroundColor(DS.ink40)
                .padding(.top, 2)
        }
    }

    private func paletteRow(color: PieceColor, includeEraser: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(whiteOrder, id: \.self) { type in
                paletteTile(Piece(type: type, color: color))
            }
            if includeEraser {
                Button(action: { tool = .eraser }) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundColor(DS.ink40)
                        .frame(width: 44, height: 44)
                        .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(tool == .eraser ? DS.redAccent : DS.borderChip, lineWidth: tool == .eraser ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func paletteTile(_ piece: Piece) -> some View {
        let sel = tool == .piece(piece)
        return Button(action: { tool = .piece(piece) }) {
            pieceGlyph(piece, size: 28)
                .frame(width: 44, height: 44)
                .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(sel ? DS.redAccent : DS.borderChip, lineWidth: sel ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private var boardGrid: some View {
        let size: CGFloat = 396
        let sq = size / 8
        return VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        let file = flipped ? 7 - col : col
                        let rank = flipped ? row : 7 - row
                        let isLight = (file + rank) % 2 == 1
                        ZStack {
                            Rectangle().fill(isLight ? lightSq : darkSq)
                            if let p = board.squares[file][rank] {
                                pieceGlyph(p, size: sq * 0.82)
                            }
                        }
                        .frame(width: sq, height: sq)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        // Press-and-drag paints/erases every square the pointer passes over in one stroke.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in paint(at: value.location, sq: sq) }
                .onEnded { _ in lastPainted = nil }
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1.5))
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            // FEN
            VStack(alignment: .leading, spacing: 8) {
                Text("FEN").font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
                HStack(spacing: 8) {
                    TextField("FEN", text: $fenText)
                        .textFieldStyle(.plain).font(AnnFont.mono(11)).foregroundColor(DS.ink)
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(DS.fieldBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                        .onSubmit { applyFEN(fenText) }
                    Button(action: {
                        if let s = NSPasteboard.general.string(forType: .string) { fenText = s; applyFEN(s) }
                    }) {
                        Text("PASTE \u{2318}V").font(AnnFont.label(10)).tracking(0.5).foregroundColor(DS.ink60)
                            .padding(.vertical, 9).padding(.horizontal, 12)
                            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Text(validation.ok ? "\u{2713} \(validation.message)" : "\u{2715} \(validation.message)")
                    .font(AnnFont.mono(10)).tracking(0.3)
                    .foregroundColor(validation.ok ? DS.semOnline : DS.redAccent)
            }

            // Side to move
            VStack(alignment: .leading, spacing: 8) {
                Text("SIDE TO MOVE").font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
                HStack(spacing: 2) {
                    sideButton(.white, "WHITE")
                    sideButton(.black, "BLACK")
                }
                .padding(3)
                .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
            }

            // Castling rights
            VStack(alignment: .leading, spacing: 8) {
                Text("CASTLING RIGHTS").font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
                HStack(spacing: 28) {
                    checkbox("WHITE O-O", $cwK)
                    checkbox("WHITE O-O-O", $cwQ)
                }
                HStack(spacing: 28) {
                    checkbox("BLACK O-O", $cbK)
                    checkbox("BLACK O-O-O", $cbQ)
                }
                Text("Detected from the pieces — kings and rooks must sit on their home squares.")
                    .font(AnnFont.voice(12)).foregroundColor(DS.ink40)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Quick set
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK SET").font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
                HStack(spacing: 8) {
                    quickButton("START POSITION") { applyFEN(startFEN) }
                    quickButton("EMPTY BOARD") { clearBoard() }
                    quickButton("FLIP BOARD") { flipped.toggle() }
                }
            }

            Spacer(minLength: 0)

            Text("Place the pieces or paste a FEN, then let the engine take it from here.")
                .font(AnnFont.voice(13)).foregroundColor(DS.ink40)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sideButton(_ color: PieceColor, _ label: String) -> some View {
        let sel = board.turn == color
        return Button(action: { board.turn = color; refreshFEN() }) {
            HStack(spacing: 7) {
                Circle().fill(color == .white ? Color(hex: 0xF2ECDD) : Color(hex: 0x2B2B2B))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(DS.borderStrong, lineWidth: 0.5))
                Text(label).font(AnnFont.label(11)).tracking(11 * 0.1).foregroundColor(sel ? DS.ink : DS.ink40)
            }
            .padding(.vertical, 7).padding(.horizontal, 16)
            .background(sel ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.selectedWash) : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func checkbox(_ label: String, _ on: Binding<Bool>) -> some View {
        Button(action: { on.wrappedValue.toggle(); refreshFEN() }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(on.wrappedValue ? DS.redAccent : Color.clear)
                    .frame(width: 15, height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(on.wrappedValue ? DS.redAccent : DS.borderStrong, lineWidth: 1))
                    .overlay(on.wrappedValue ? Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(DS.onRed) : nil)
                Text(label).font(AnnFont.label(10)).tracking(0.5).foregroundColor(DS.ink60)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 120, alignment: .leading)
    }

    private func quickButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(AnnFont.label(10)).tracking(0.4).foregroundColor(DS.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8).padding(.horizontal, 8)
                .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Piece rendering

    private var pieceStyle: PieceStyle {
        PieceStyle.allStyles.first(where: { $0.id == AppSettings.shared.pieceStyleId }) ?? PieceStyle.allStyles[0]
    }

    @ViewBuilder
    private func pieceGlyph(_ piece: Piece, size: CGFloat) -> some View {
        if let img = loadPieceImage(pieceStyle.imageFileName(for: piece)) {
            Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(piece.symbol).font(.system(size: size * 0.94))
                .foregroundColor(piece.color == .white ? Color(hex: 0xF7F1E1) : Color(hex: 0x1A1A1A))
        }
    }

    // MARK: - Editing

    private var placingText: String {
        switch tool {
        case .eraser: return "ERASING — CLICK SQUARES TO CLEAR"
        case .piece(let p): return "PLACING \(p.symbol) — CLICK SQUARES"
        }
    }

    private func paint(at location: CGPoint, sq: CGFloat) {
        let col = Int(location.x / sq)
        let row = Int(location.y / sq)
        guard (0..<8).contains(col), (0..<8).contains(row) else { return }
        let file = flipped ? 7 - col : col
        let rank = flipped ? row : 7 - row
        let key = file * 8 + rank
        if lastPainted == key { return }   // don't re-apply while still inside the same square
        lastPainted = key
        place(file: file, rank: rank)
    }

    private func place(file: Int, rank: Int) {
        switch tool {
        case .eraser: board.squares[file][rank] = nil
        case .piece(let p): board.squares[file][rank] = p
        }
        autoDetectCastling()
        refreshFEN()
    }

    private func clearBoard() {
        board.squares = Array(repeating: Array(repeating: Piece?.none, count: 8), count: 8)
        board.enPassantTarget = nil
        cwK = false; cwQ = false; cbK = false; cbQ = false
        refreshFEN()
    }

    private func applyFEN(_ fen: String) {
        guard board.loadFEN(fen.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        syncCastlingMirrors()
        fenText = board.getFEN()
    }

    /// Turn availability on when the king and the relevant rook sit on their home squares.
    private func autoDetectCastling() {
        func isRook(_ file: Int, _ rank: Int, _ color: PieceColor) -> Bool {
            let p = board.squares[file][rank]; return p?.type == .rook && p?.color == color
        }
        let wk = board.squares[4][0]?.type == .king && board.squares[4][0]?.color == .white
        cwK = wk && isRook(7, 0, .white)
        cwQ = wk && isRook(0, 0, .white)
        let bk = board.squares[4][7]?.type == .king && board.squares[4][7]?.color == .black
        cbK = bk && isRook(7, 7, .black)
        cbQ = bk && isRook(0, 7, .black)
    }

    private func syncCastlingMirrors() {
        cwK = board.whiteCanCastleKingside
        cwQ = board.whiteCanCastleQueenside
        cbK = board.blackCanCastleKingside
        cbQ = board.blackCanCastleQueenside
    }

    private func refreshFEN() {
        board.whiteCanCastleKingside = cwK
        board.whiteCanCastleQueenside = cwQ
        board.blackCanCastleKingside = cbK
        board.blackCanCastleQueenside = cbQ
        board.enPassantTarget = nil
        fenText = board.getFEN()
    }

    // MARK: - Validation

    private var validation: (ok: Bool, message: String) {
        var pieces: [Piece] = []
        for f in 0..<8 { for r in 0..<8 { if let p = board.squares[f][r] { pieces.append(p) } } }
        let whiteKings = pieces.filter { $0.type == .king && $0.color == .white }.count
        let blackKings = pieces.filter { $0.type == .king && $0.color == .black }.count
        if whiteKings != 1 { return (false, "NEEDS EXACTLY ONE WHITE KING") }
        if blackKings != 1 { return (false, "NEEDS EXACTLY ONE BLACK KING") }
        let pawnOnBackRank = (0..<8).contains { f in
            board.squares[f][0]?.type == .pawn || board.squares[f][7]?.type == .pawn
        }
        if pawnOnBackRank { return (false, "PAWNS CAN\u{2019}T SIT ON THE BACK RANK") }
        return (true, "LEGAL POSITION — \(pieces.count) PIECE\(pieces.count == 1 ? "" : "S")")
    }
}
