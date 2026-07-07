import SwiftUI

struct ChessComImportView: View {
    @ObservedObject var database: GameDatabase
    @StateObject private var service = ChessComService()
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var selectedGames: Set<String> = []
    @State private var importedCount: Int = 0
    @State private var showingImportSuccess = false

    @AppStorage("chesscom_last_username") private var lastUsername: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 20))
                    .foregroundColor(DS.chessComGreen)

                Text("Import from Chess.com")
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(DS.bgSecondary)

            Divider()

            // Username input
            HStack(spacing: DS.spacingMD) {
                TextField("Chess.com username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        fetchGames()
                    }

                Button(action: fetchGames) {
                    if service.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Fetch")
                    }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(username.isEmpty || service.isLoading)
            }
            .padding()

            // Progress/Status
            if service.isLoading && service.totalArchives > 0 {
                VStack(spacing: 10) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.bgTertiary)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(DS.accent)
                                .frame(width: geometry.size.width * progressPercentage, height: 8)
                        }
                    }
                    .frame(height: 8)

                    // Progress details
                    HStack {
                        Text("\(Int(progressPercentage * 100))%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.accent)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text("Archive \(service.currentArchive) of \(service.totalArchives)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if service.gamesFoundSoFar > 0 {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("\(service.gamesFoundSoFar) games found")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if service.estimatedTimeRemaining > 0 {
                            Text(formatTimeRemaining(service.estimatedTimeRemaining))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, DS.spacingSM)
            } else if !service.progress.isEmpty && !service.isLoading {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DS.chessComGreen)
                        .font(.system(size: 12))
                    Text(service.progress)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, DS.spacingSM)
            } else if service.isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(service.progress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, DS.spacingSM)
            }

            // Error message
            if let error = service.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, DS.spacingSM)
            }

            Divider()

            // Games list
            if service.fetchedGames.isEmpty && !service.isLoading {
                VStack(spacing: DS.spacingMD) {
                    Spacer()
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Enter a username to fetch games")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                // Selection controls
                if !service.fetchedGames.isEmpty {
                    HStack {
                        Text("\(selectedGames.count) of \(service.fetchedGames.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Select All") {
                            selectedGames = Set(service.fetchedGames.map { $0.id })
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)

                        Button("Deselect All") {
                            selectedGames.removeAll()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, DS.spacingSM)

                    Divider()
                }

                // Games list
                List(service.fetchedGames, selection: $selectedGames) { game in
                    ChessComGameRow(game: game, isSelected: selectedGames.contains(game.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedGames.contains(game.id) {
                                selectedGames.remove(game.id)
                            } else {
                                selectedGames.insert(game.id)
                            }
                        }
                }
                .listStyle(.plain)
            }

            Divider()

            // Import button
            HStack {
                if let lastFetch = getLastFetchInfo() {
                    Text("Last import: \(lastFetch)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Clear History") {
                    service.clearHistory(for: username)
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(username.isEmpty)

                Button("Import Selected (\(selectedGames.count))") {
                    importSelectedGames()
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(selectedGames.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .onAppear {
            if !lastUsername.isEmpty {
                username = lastUsername
            }
        }
        .alert("Import Complete", isPresented: $showingImportSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Successfully imported \(importedCount) games to your library.")
        }
    }

    private func fetchGames() {
        guard !username.isEmpty else { return }
        lastUsername = username
        Task {
            await service.fetchNewGames(username: username)
            // Auto-select all new games
            selectedGames = Set(service.fetchedGames.map { $0.id })
        }
    }

    private func importSelectedGames() {
        let gamesToImport = service.fetchedGames.filter { selectedGames.contains($0.id) }
        var records: [GameRecord] = []

        for game in gamesToImport {
            if database.sourceUrlExists(game.url) { continue }
            guard let pgn = game.pgn else { continue }

            // Parse PGN to extract headers
            let parser = PGNParser()
            let parsedGames = parser.parse(string: pgn)
            let parsedGame = parsedGames.first

            // Create game record with timeClass, sourceUsername, and sourceUrl
            let record = GameRecord(
                event: parsedGame?.headers["Event"] ?? "Chess.com \(game.timeClassDisplay)",
                date: game.formattedDate,
                white: game.white.username,
                black: game.black.username,
                result: game.result,
                eco: parsedGame?.headers["ECO"],
                opening: parsedGame?.headers["Opening"],
                pgn: pgn,
                dateAdded: game.endDate ?? Date(),
                timeClass: game.timeClass,
                sourceUsername: username.lowercased(),
                sourceUrl: game.url
            )

            records.append(record)
        }

        database.addGames(records, isChessComImport: true)
        importedCount = records.count
        showingImportSuccess = true
    }

    private func getLastFetchInfo() -> String? {
        guard let archive = service.getLastSyncedArchive(for: username) else { return nil }
        return "Last synced: \(archive)"
    }

    private var progressPercentage: CGFloat {
        guard service.totalArchives > 0 else { return 0 }
        return CGFloat(service.currentArchive) / CGFloat(service.totalArchives)
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "~\(Int(seconds))s remaining"
        } else {
            let minutes = Int(seconds) / 60
            let secs = Int(seconds) % 60
            if secs == 0 {
                return "~\(minutes)m remaining"
            }
            return "~\(minutes)m \(secs)s remaining"
        }
    }
}

// MARK: - Game Row

struct ChessComGameRow: View {
    let game: ChessComGame
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DS.spacingMD) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? DS.accent : DS.textSecondary)
                .font(.system(size: 16))

            // Time class badge
            Text(game.timeClassDisplay)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(timeClassColor)
                .cornerRadius(4)

            // Players
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5))
                    Text(game.white.username)
                        .font(.system(size: 12, weight: game.white.result == "win" ? .bold : .regular))
                    Text("(\(game.white.rating))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 8, height: 8)
                    Text(game.black.username)
                        .font(.system(size: 12, weight: game.black.result == "win" ? .bold : .regular))
                    Text("(\(game.black.rating))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Result
            Text(game.result)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)

            // Date
            Text(game.formattedDate)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DS.spacingSM)
        .background(isSelected ? DS.accentLight : Color.clear)
        .cornerRadius(DS.radiusSM)
    }

    private var timeClassColor: Color {
        switch game.timeClass {
        case "bullet": return .red
        case "blitz": return .orange
        case "rapid": return .green
        case "daily": return .blue
        default: return .gray
        }
    }
}

#Preview {
    ChessComImportView(database: GameDatabase.preview())
}
