import SwiftUI

// MARK: - Editable PGN Game

class EditablePGNGame: ObservableObject, Identifiable {
    let id = UUID()
    let originalPGN: PGNGame
    let originalPGNText: String  // Store the original raw PGN text to preserve variations

    @Published var isSelected: Bool = true
    @Published var white: String
    @Published var black: String
    @Published var whiteElo: String
    @Published var blackElo: String
    @Published var event: String
    @Published var site: String
    @Published var date: String
    @Published var round: String
    @Published var result: String
    @Published var eco: String
    @Published var opening: String

    var moveCount: Int {
        originalPGN.moves.count
    }

    /// Check if the PGN contains variations
    var hasVariations: Bool {
        originalPGNText.contains("(") && originalPGNText.contains(")")
    }

    var movesPreview: String {
        let moves = originalPGN.moves.prefix(10)
        var preview = ""
        for (index, move) in moves.enumerated() {
            let moveNumber = index / 2 + 1
            if index % 2 == 0 {
                preview += "\(moveNumber). "
            }
            preview += "\(move) "
        }
        if originalPGN.moves.count > 10 {
            preview += "..."
        }
        if hasVariations {
            preview += " (+ variations)"
        }
        return preview.trimmingCharacters(in: .whitespaces)
    }

    init(from pgnGame: PGNGame, rawPGN: String) {
        self.originalPGN = pgnGame
        self.originalPGNText = rawPGN
        self.white = pgnGame.white == "?" ? "" : pgnGame.white
        self.black = pgnGame.black == "?" ? "" : pgnGame.black
        self.whiteElo = pgnGame.headers["WhiteElo"] ?? ""
        self.blackElo = pgnGame.headers["BlackElo"] ?? ""
        self.event = pgnGame.event == "?" ? "" : pgnGame.event
        self.site = pgnGame.site == "?" ? "" : pgnGame.site
        self.date = pgnGame.date == "????.??.??" ? "" : pgnGame.date
        self.round = pgnGame.round == "?" ? "" : pgnGame.round
        self.result = pgnGame.result
        self.eco = pgnGame.eco ?? ""
        // Use opening from PGN header, or resolve from ECO code
        if let name = pgnGame.opening, !name.isEmpty {
            self.opening = name
        } else if let eco = pgnGame.eco, !eco.isEmpty {
            self.opening = OpeningBook.shared.findByECO(eco) ?? ECODatabase.openingName(for: eco) ?? ""
        } else {
            self.opening = ""
        }
    }

    /// Create a PGNGame with the edited values
    func toEditedPGNGame() -> PGNGame {
        var headers = originalPGN.headers

        headers["White"] = white.isEmpty ? "?" : white
        headers["Black"] = black.isEmpty ? "?" : black
        headers["Event"] = event.isEmpty ? "?" : event
        headers["Site"] = site.isEmpty ? "?" : site
        headers["Date"] = date.isEmpty ? "????.??.??" : date
        headers["Round"] = round.isEmpty ? "?" : round
        headers["Result"] = result

        if !whiteElo.isEmpty {
            headers["WhiteElo"] = whiteElo
        }
        if !blackElo.isEmpty {
            headers["BlackElo"] = blackElo
        }
        if !eco.isEmpty {
            headers["ECO"] = eco
        }
        if !opening.isEmpty {
            headers["Opening"] = opening
        }

        var edited = PGNGame()
        edited.headers = headers
        edited.moves = originalPGN.moves
        edited.moveTree = originalPGN.moveTree   // carry variations/comments so re-export keeps them
        edited.result = result

        return edited
    }

    /// Get the edited PGN string
    func toEditedPGNString() -> String {
        // Use the standard PGNGame export which is known to work
        return toEditedPGNGame().toPGNString()
    }
}

// MARK: - PGN Import View

struct PGNImportView: View {
    @ObservedObject var database: GameDatabase
    let fileURLs: [URL]
    let onImport: (UUID?) -> Void
    let onCancel: () -> Void
    var preselectedFolderId: UUID? = nil

    @State private var editableGames: [EditablePGNGame] = []
    @State private var selectedFolderId: UUID?
    @State private var isLoading = true
    @State private var parseError: String?
    @State private var expandedGameId: UUID?
    @State private var isImporting = false
    @State private var importProgress: Int = 0
    @State private var importTotal: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            if isImporting {
                importProgressView
            } else if isLoading {
                loadingView
            } else if let error = parseError {
                errorView(error)
            } else if editableGames.isEmpty {
                emptyView
            } else {
                // Toolbar
                toolbarView

                // Game list with inline editing
                gamesListView
            }

            // Footer
            footerView
        }
        .frame(width: 560, height: 720)
        .background(DS.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLG)
                .strokeBorder(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 32, x: 0, y: 8)
        .onAppear {
            if let preselected = preselectedFolderId {
                selectedFolderId = preselected
            }
            parseFiles()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Imported Games")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.textPrimary)

                if !editableGames.isEmpty {
                    Text("\(fileURLs.first?.lastPathComponent ?? "PGN") · \(editableGames.count) games found")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textTertiary)
                }
            }

            Spacer()

            Button(action: { onCancel() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack {
            HStack(spacing: 8) {
                Button(action: {
                    let allSelected = editableGames.allSatisfy { $0.isSelected }
                    editableGames.forEach { $0.isSelected = !allSelected }
                }) {
                    let allSelected = editableGames.allSatisfy { $0.isSelected }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(allSelected ? DS.accent : Color.clear)
                        .frame(width: 16, height: 16)
                        .overlay(
                            allSelected ?
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                            : nil
                        )
                        .overlay(
                            !allSelected ?
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(DS.textTertiary, lineWidth: 1)
                            : nil
                        )
                }
                .buttonStyle(.plain)

                Text("Select All (\(editableGames.count))")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()

            let selectedCount = editableGames.filter { $0.isSelected }.count
            Text("\(selectedCount) selected")
                .font(.system(size: 11))
                .foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.glassSeparator).frame(height: 1)
        }
    }

    // MARK: - Loading / Error / Empty States

    private var loadingView: some View {
        LoadingStateView(message: "Parsing PGN files...")
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: DS.spacingMD) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(DS.accentOrange)
            Text("Error parsing PGN")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.textPrimary)
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(DS.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        EmptyStateView(icon: "doc.text", title: "No games found", description: "The selected files don't contain any valid PGN games.")
    }

    private var importProgressView: some View {
        VStack(spacing: DS.spacingLG) {
            Spacer()

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 36))
                .foregroundColor(DS.accent)

            Text("Importing games...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.textPrimary)

            if importTotal > 0 {
                ProgressView(value: Double(importProgress), total: Double(importTotal))
                    .progressViewStyle(.linear)
                    .frame(width: 300)

                Text("\(importProgress) of \(importTotal) games")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Games List (single column with inline expand)

    private var gamesListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(editableGames) { game in
                    if expandedGameId == game.id {
                        // Expanded game with inline edit form
                        expandedGameRow(game)
                    } else {
                        // Collapsed game row
                        collapsedGameRow(game)
                    }
                }
            }
        }
    }

    private func collapsedGameRow(_ game: EditablePGNGame) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: { game.isSelected.toggle() }) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(game.isSelected ? DS.accent : Color.clear)
                    .frame(width: 16, height: 16)
                    .overlay(
                        game.isSelected ?
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                        : nil
                    )
                    .overlay(
                        !game.isSelected ?
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(DS.textTertiary, lineWidth: 1)
                        : nil
                    )
            }
            .buttonStyle(.plain)

            // Game info
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.white.isEmpty ? "Unknown" : game.white) vs \(game.black.isEmpty ? "Unknown" : game.black)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !game.eco.isEmpty {
                        Text(game.eco)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    if !game.opening.isEmpty {
                        Text(game.opening)
                            .font(.system(size: 10))
                    }
                    Text("·")
                    Text(game.result)
                        .font(.system(size: 10, weight: .medium))
                    if !game.event.isEmpty {
                        Text("·")
                        Text(game.event)
                            .font(.system(size: 10))
                    }
                }
                .foregroundColor(DS.textTertiary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Expand chevron
            Image(systemName: "chevron.down")
                .font(.system(size: 11))
                .foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .opacity(game.isSelected ? 1.0 : 0.5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.borderSubtle).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedGameId = game.id
            }
        }
    }

    private func expandedGameRow(_ game: EditablePGNGame) -> some View {
        VStack(spacing: 0) {
            // Header (same as collapsed but with up chevron)
            HStack(spacing: 12) {
                Button(action: { game.isSelected.toggle() }) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(game.isSelected ? DS.accent : Color.clear)
                        .frame(width: 16, height: 16)
                        .overlay(
                            game.isSelected ?
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                            : nil
                        )
                        .overlay(
                            !game.isSelected ?
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(DS.textTertiary, lineWidth: 1)
                            : nil
                        )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(game.white.isEmpty ? "Unknown" : game.white) vs \(game.black.isEmpty ? "Unknown" : game.black)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !game.opening.isEmpty {
                            Text(game.opening)
                                .font(.system(size: 10))
                        }
                        Text("·")
                        Text(game.result)
                            .font(.system(size: 10, weight: .medium))
                        if !game.event.isEmpty {
                            Text("·")
                            Text(game.event)
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(DS.textTertiary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedGameId = nil
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11))
                        .foregroundColor(DS.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            // Inline edit form
            inlineEditForm(game)
        }
        .background(DS.bgSurface)
        .overlay(alignment: .leading) {
            Rectangle().fill(DS.accent).frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.accent).frame(height: 1)
        }
    }

    // MARK: - Inline Edit Form

    private func inlineEditForm(_ game: EditablePGNGame) -> some View {
        VStack(spacing: 10) {
            // Row 1: White + Elo
            HStack(spacing: 10) {
                importField("White", text: Binding(get: { game.white }, set: { game.white = $0 }))
                importField("Elo", text: Binding(get: { game.whiteElo }, set: { game.whiteElo = $0 }), width: 60)
            }

            // Row 2: Black + Elo
            HStack(spacing: 10) {
                importField("Black", text: Binding(get: { game.black }, set: { game.black = $0 }))
                importField("Elo", text: Binding(get: { game.blackElo }, set: { game.blackElo = $0 }), width: 60)
            }

            // Row 3: Event + Result
            HStack(spacing: 10) {
                importField("Event", text: Binding(get: { game.event }, set: { game.event = $0 }))
                importPickerField("Result", selection: Binding(get: { game.result }, set: { game.result = $0 }), width: 80)
            }

            // Row 4: Date + Round
            HStack(spacing: 10) {
                importField("Date", text: Binding(get: { game.date }, set: { game.date = $0 }))
                importField("Round", text: Binding(get: { game.round }, set: { game.round = $0 }))
            }

            // Row 5: Opening + ECO
            HStack(spacing: 10) {
                importField("Opening", text: Binding(get: { game.opening }, set: { game.opening = $0 }), isItalic: true)
                importField("ECO", text: Binding(get: { game.eco }, set: { game.eco = $0 }), width: 60, isItalic: true)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
        .padding(.horizontal, 24)
        .padding(.leading, 28)  // Extra indent to align with text after checkbox
    }

    private func importField(_ label: String, text: Binding<String>, width: CGFloat? = nil, isItalic: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textTertiary)

            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(isItalic ? .system(size: 11).italic() : .system(size: 11))
                .foregroundColor(isItalic ? DS.textSecondary : DS.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(DS.bg)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(DS.border, lineWidth: 1)
                )
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }

    private func importPickerField(_ label: String, selection: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textTertiary)

            Picker("", selection: selection) {
                Text("1-0").tag("1-0")
                Text("0-1").tag("0-1")
                Text("½-½").tag("1/2-1/2")
                Text("*").tag("*")
            }
            .pickerStyle(.menu)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(DS.bg)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(DS.border, lineWidth: 1)
            )
        }
        .frame(width: width)
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 0) {
            // Database picker row (if not preselected)
            if preselectedFolderId == nil && !editableGames.isEmpty {
                HStack(spacing: DS.spacingSM) {
                    Text("Import to:")
                        .font(.system(size: 12))
                        .foregroundColor(DS.textSecondary)

                    Picker("", selection: $selectedFolderId) {
                        Text("Default").tag(nil as UUID?)
                        ForEach(database.folders.sorted(by: { $0.name < $1.name })) { folder in
                            Text(folder.name).tag(folder.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DS.glassSeparator).frame(height: 1)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Spacer()

                Button(action: { onCancel() }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DS.bgTertiary)
                        .cornerRadius(DS.radiusSM)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .disabled(isImporting)

                let selectedCount = editableGames.filter { $0.isSelected }.count
                Button(action: { performImport() }) {
                    Text("Import \(selectedCount) Games")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedCount > 0 && !isImporting ? DS.accent : DS.accent.opacity(0.5))
                        .cornerRadius(DS.radiusSM)
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || isImporting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.glassSeparator).frame(height: 1)
            }
        }
    }

    // MARK: - Actions

    private func parseFiles() {
        isLoading = true
        parseError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var allGames: [EditablePGNGame] = []
            var errors: [String] = []
            let parser = PGNParser()

            for url in fileURLs {
                // Try to access security-scoped resource (may not be needed for all URLs)
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    // Read the raw file content to preserve variations
                    let rawContent = try readFileContent(url: url)
                    let pgnGames = parser.parse(string: rawContent)

                    if pgnGames.isEmpty {
                        errors.append("\(url.lastPathComponent): No games found in file")
                    } else {
                        // Split raw content into individual game strings to preserve variations per game
                        let rawGameStrings = splitIntoGameStrings(rawContent)

                        for (index, pgnGame) in pgnGames.enumerated() {
                            // Use matched raw string if available, otherwise use full content for single game
                            // or empty string as fallback (will use parsed moves)
                            let rawPGN: String
                            if pgnGames.count == 1 {
                                // Single game - use full content
                                rawPGN = rawContent
                            } else if index < rawGameStrings.count {
                                rawPGN = rawGameStrings[index]
                            } else {
                                // Fallback - will use parsed moves
                                rawPGN = ""
                            }
                            let editable = EditablePGNGame(from: pgnGame, rawPGN: rawPGN)
                            allGames.append(editable)
                        }
                    }
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                editableGames = allGames
                if let first = allGames.first {
                    expandedGameId = first.id
                }
                if allGames.isEmpty && !errors.isEmpty {
                    parseError = errors.joined(separator: "\n")
                }
                isLoading = false
            }
        }
    }

    /// Read file content with multiple encoding support
    private func readFileContent(url: URL) throws -> String {
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .ascii, .windowsCP1252]

        for encoding in encodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                return content
            }
        }

        throw NSError(domain: "PGNImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read file with any supported encoding"])
    }

    /// Split a multi-game PGN file into individual game strings
    private func splitIntoGameStrings(_ content: String) -> [String] {
        var games: [String] = []
        var currentGame = ""
        var inMoveText = false

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Header line
                if inMoveText && !currentGame.isEmpty {
                    // New game starting - save previous one
                    games.append(currentGame.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentGame = ""
                    inMoveText = false
                }
                currentGame += line + "\n"
            } else if !trimmed.isEmpty {
                // Move text
                inMoveText = true
                currentGame += line + "\n"

                // Check if this line contains a result (end of game)
                if trimmed.hasSuffix("1-0") || trimmed.hasSuffix("0-1") ||
                   trimmed.hasSuffix("1/2-1/2") || trimmed.hasSuffix("*") {
                    games.append(currentGame.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentGame = ""
                    inMoveText = false
                }
            } else {
                currentGame += "\n"
            }
        }

        // Add last game if present
        if !currentGame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            games.append(currentGame.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return games
    }

    private func performImport() {
        let selectedGames = editableGames.filter { $0.isSelected }
        guard !selectedGames.isEmpty else { return }

        isImporting = true
        importTotal = selectedGames.count
        importProgress = 0

        let folderId = selectedFolderId

        // Build GameRecord objects off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            var records: [GameRecord] = []
            for game in selectedGames {
                let pgnString = game.toEditedPGNString()
                let editedPGN = game.toEditedPGNGame()
                let record = GameRecord.from(pgnGame: editedPGN, pgn: pgnString)
                records.append(record)
            }

            // Insert into database on main thread (SwiftData requirement)
            DispatchQueue.main.async {
                let targetFolder = database.folder(withId: folderId)
                database.addGamesBatched(records, folder: targetFolder, batchSize: 50) { completed in
                    importProgress = completed
                }
                onImport(folderId)
            }
        }
    }
}


#Preview {
    PGNImportView(
        database: GameDatabase.preview(),
        fileURLs: [],
        onImport: { _ in },
        onCancel: { }
    )
}
