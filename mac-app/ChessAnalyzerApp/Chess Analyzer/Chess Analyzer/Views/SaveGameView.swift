import SwiftUI

struct SaveGameView: View {
    @ObservedObject var gameTree: GameTree
    @ObservedObject var database: GameDatabase
    @Environment(\.dismiss) private var dismiss

    @State private var whiteName = ""
    @State private var blackName = ""
    @State private var eventName = ""
    @State private var siteName = ""
    @State private var gameDate = Date()
    @State private var result = "*"
    @State private var selectedFolderId: UUID?
    @State private var showingSaveSuccess = false
    @State private var showingExportPanel = false

    private let resultOptions = ["*", "1-0", "0-1", "1/2-1/2"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Save Game")
                    .font(AnnFont.serif(16, .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(DS.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(DS.spacingLG)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: DS.spacingLG) {
                    // Players
                    VStack(alignment: .leading, spacing: DS.spacingSM) {
                        Text("Players")
                            .font(DS.titleFont)

                        HStack(spacing: DS.spacingMD) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("White")
                                    .font(DS.captionFont)
                                    .foregroundColor(DS.textSecondary)
                                TextField("White player", text: $whiteName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Black")
                                    .font(DS.captionFont)
                                    .foregroundColor(DS.textSecondary)
                                TextField("Black player", text: $blackName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    Divider()

                    // Event details
                    VStack(alignment: .leading, spacing: DS.spacingSM) {
                        Text("Event Details")
                            .font(DS.titleFont)

                        HStack(spacing: DS.spacingMD) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Event")
                                    .font(DS.captionFont)
                                    .foregroundColor(DS.textSecondary)
                                TextField("Event name", text: $eventName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Site")
                                    .font(DS.captionFont)
                                    .foregroundColor(DS.textSecondary)
                                TextField("Location", text: $siteName)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: DS.spacingMD) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date")
                                    .font(DS.captionFont)
                                    .foregroundColor(DS.textSecondary)
                                DatePicker("", selection: $gameDate, displayedComponents: .date)
                                    .labelsHidden()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Result")
                                    .font(DS.captionFont)
                                    .foregroundColor(DS.textSecondary)
                                Picker("", selection: $result) {
                                    ForEach(resultOptions, id: \.self) { opt in
                                        Text(opt).tag(opt)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }
                        }
                    }

                    Divider()

                    // Folder selection
                    VStack(alignment: .leading, spacing: DS.spacingSM) {
                        Text("Save Location")
                            .font(DS.titleFont)

                        Picker("Database", selection: $selectedFolderId) {
                            Text("Default").tag(nil as UUID?)
                            ForEach(database.folders.sorted(by: { $0.name < $1.name })) { folder in
                                Label(folder.name, systemImage: "cylinder")
                                    .tag(folder.id as UUID?)
                            }
                        }
                        .labelsHidden()
                    }

                    Divider()

                    // PGN Preview
                    VStack(alignment: .leading, spacing: DS.spacingSM) {
                        Text("PGN Preview")
                            .font(DS.titleFont)

                        Text(generatedPGN)
                            .font(DS.monoSmall)
                            .foregroundColor(DS.textSecondary)
                            .padding(DS.spacingMD)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.bgSecondary)
                            .cornerRadius(DS.radiusMD)
                            .lineLimit(8)
                    }
                }
                .padding(DS.spacingLG)
            }

            Divider()

            // Actions
            HStack(spacing: DS.spacingMD) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(GlassButtonStyle())
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export to File...") {
                    exportToFile()
                }
                .buttonStyle(GlassButtonStyle())

                Button("Save to Library") {
                    saveToLibrary()
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(DS.spacingLG)
        }
        .frame(width: 500, height: 550)
        .alert("Game Saved", isPresented: $showingSaveSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("The game has been saved to your library.")
        }
    }

    // MARK: - Helpers

    private var headers: [String: String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return [
            "White": whiteName.isEmpty ? "?" : whiteName,
            "Black": blackName.isEmpty ? "?" : blackName,
            "Event": eventName.isEmpty ? "?" : eventName,
            "Site": siteName.isEmpty ? "?" : siteName,
            "Date": formatter.string(from: gameDate),
            "Result": result
        ]
    }

    private var generatedPGN: String {
        gameTree.toPGN(headers: headers)
    }

    private func saveToLibrary() {
        let pgn = generatedPGN
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"

        let record = GameRecord(
            event: eventName.isEmpty ? "?" : eventName,
            site: siteName.isEmpty ? "?" : siteName,
            date: formatter.string(from: gameDate),
            round: "?",
            white: whiteName.isEmpty ? "?" : whiteName,
            black: blackName.isEmpty ? "?" : blackName,
            result: result,
            pgn: pgn,
            folder: database.folder(withId: selectedFolderId)
        )

        database.addGame(record)
        showingSaveSuccess = true
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "Export PGN"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(whiteName.isEmpty ? "game" : whiteName)_vs_\(blackName.isEmpty ? "game" : blackName).pgn"
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try generatedPGN.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Error saving PGN: \(error)")
                }
            }
        }
    }
}

#Preview {
    SaveGameView(gameTree: GameTree(), database: GameDatabase.preview())
}
