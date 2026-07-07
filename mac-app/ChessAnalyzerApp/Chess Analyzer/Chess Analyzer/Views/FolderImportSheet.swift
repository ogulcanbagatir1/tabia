import SwiftUI

struct FolderImportSheet: View {
    @ObservedObject var database: GameDatabase
    let fileURLs: [URL]
    let onImport: (UUID?) -> Void
    let onCancel: () -> Void

    @State private var createNewFolder = false
    @State private var newFolderName: String = ""
    @State private var selectedFolderId: UUID?

    init(database: GameDatabase, fileURLs: [URL], onImport: @escaping (UUID?) -> Void, onCancel: @escaping () -> Void) {
        self.database = database
        self.fileURLs = fileURLs
        self.onImport = onImport
        self.onCancel = onCancel

        // Set default folder name from first PGN filename
        if let firstURL = fileURLs.first {
            let filename = firstURL.deletingPathExtension().lastPathComponent
            _newFolderName = State(initialValue: filename)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: DS.spacingSM) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(DS.accent)

                Text("Import Games")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.textPrimary)

                Text(fileDescription)
                    .font(DS.captionFont)
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DS.spacingLG)
            .padding(.bottom, DS.spacingMD)

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)
                .padding(.vertical, DS.spacingSM)

            // Folder selection
            VStack(alignment: .leading, spacing: DS.spacingMD) {
                Toggle("Create new database", isOn: $createNewFolder)
                    .toggleStyle(.switch)

                if createNewFolder {
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        Text("Database name")
                            .font(DS.captionFont)
                            .foregroundColor(DS.textSecondary)
                        TextField("Enter database name", text: $newFolderName)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        Text("Select database")
                            .font(DS.captionFont)
                            .foregroundColor(DS.textSecondary)

                        Picker("Database", selection: $selectedFolderId) {
                            Text("Unfiled").tag(nil as UUID?)
                            ForEach(database.folders.sorted(by: { $0.name < $1.name })) { folder in
                                Text(folder.name).tag(folder.id as UUID?)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            .padding(.horizontal, DS.spacingLG)
            .padding(.vertical, DS.spacingMD)

            Spacer()

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Import") {
                    if createNewFolder && !newFolderName.isEmpty {
                        let folder = database.createFolder(name: newFolderName)
                        onImport(folder.id)
                    } else {
                        onImport(selectedFolderId)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(createNewFolder && newFolderName.isEmpty)
            }
            .padding(DS.spacingLG)
        }
        .frame(width: 340, height: 320)
    }

    private var fileDescription: String {
        if fileURLs.count == 1 {
            return fileURLs[0].lastPathComponent
        } else {
            return "\(fileURLs.count) files"
        }
    }
}

#Preview {
    FolderImportSheet(
        database: GameDatabase.preview(),
        fileURLs: [URL(fileURLWithPath: "/test/MyGames.pgn")],
        onImport: { _ in },
        onCancel: {}
    )
}
