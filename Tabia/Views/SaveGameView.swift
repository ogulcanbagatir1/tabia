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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text("Save ").font(AnnFont.serif(18, .semibold))
                     + Text("Game").font(AnnFont.voice(18)))
                        .foregroundColor(DS.ink)
                    Text("File the game to your library, or export it as PGN.")
                        .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.ink40)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
            .overlay(alignment: .bottom) { hairline }

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Players") {
                        HStack(spacing: 12) {
                            field("White") { annTextField("White player", $whiteName) }
                            field("Black") { annTextField("Black player", $blackName) }
                        }
                    }

                    section("Event") {
                        HStack(spacing: 12) {
                            field("Event") { annTextField("Event name", $eventName) }
                            field("Site") { annTextField("Location", $siteName) }
                        }
                        HStack(spacing: 12) {
                            field("Date") {
                                DatePicker("", selection: $gameDate, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            field("Result") {
                                Picker("", selection: $result) {
                                    ForEach(resultOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden().pickerStyle(.segmented)
                            }
                        }
                    }

                    section("Save Location") {
                        Picker("Database", selection: $selectedFolderId) {
                            Text("Default").tag(nil as UUID?)
                            ForEach(database.folders.sorted(by: { $0.name < $1.name })) { folder in
                                Label(folder.name, systemImage: "cylinder").tag(folder.id as UUID?)
                            }
                        }
                        .labelsHidden()
                    }

                    section("PGN Preview") {
                        Text(generatedPGN)
                            .font(AnnFont.mono(11))
                            .foregroundColor(DS.ink60)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.fieldBg)
                            .cornerRadius(DS.rControl)
                            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                                .strokeBorder(DS.hairline, lineWidth: 1))
                            .lineLimit(8)
                    }
                }
                .padding(24)
            }

            // Actions
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export to File…") { exportToFile() }
                    .buttonStyle(GlassButtonStyle())

                Button("Save to Library") { saveToLibrary() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .overlay(alignment: .top) { hairline }
        }
        .frame(width: 500, height: 560)
        .background(DS.paper)
        .alert("Game Saved", isPresented: $showingSaveSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("The game has been saved to your library.")
        }
    }

    // MARK: - Annotator form pieces

    private var hairline: some View { Rectangle().fill(DS.hairline).frame(height: 1) }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(AnnFont.label(10)).tracking(10 * 0.14).foregroundColor(DS.ink40)
            content()
        }
    }

    private func field<Content: View>(_ caption: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption.uppercased())
                .font(AnnFont.label(9)).tracking(9 * 0.12).foregroundColor(DS.ink40)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func annTextField(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(AnnFont.serif(13.5)).foregroundColor(DS.ink)
            .padding(.horizontal, 12).frame(height: 36)
            .background(DS.fieldBg)
            .cornerRadius(DS.rControl)
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1))
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
