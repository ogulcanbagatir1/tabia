import SwiftUI

// Extracted from the (removed) ChessComTabView; still used by ChessComBrowserView's connect flow.

struct ChessComConnectSheet: View {
    @ObservedObject var service: ChessComService
    @Binding var savedUsername: String
    @Binding var lastSyncTimestamp: Double
    var onImport: ([ChessComGame], String) -> Void
    var onDismiss: () -> Void

    @State private var username: String = ""

    private let chessComGreen = DS.chessComGreen

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 20))
                    .foregroundColor(chessComGreen)

                Text(savedUsername.isEmpty ? "Connect Chess.com" : "Account Settings")
                    .font(.headline)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DS.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(DS.bgSecondary)

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chess.com Username")
                        .font(AnnFont.label(12))
                        .tracking(12 * 0.1)
                        .foregroundColor(DS.textSecondary)

                    TextField("Enter username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            username = savedUsername
                        }
                }

                // Progress
                if service.isLoading && service.totalArchives > 0 {
                    VStack(spacing: 10) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DS.bgSecondary)
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(chessComGreen)
                                    .frame(width: geometry.size.width * progressPercentage, height: 8)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("\(Int(progressPercentage * 100))%")
                                .font(AnnFont.mono(12, bold: true))
                                .foregroundColor(chessComGreen)

                            Text("\u{2022}")
                                .foregroundColor(DS.textSecondary)

                            Text("Archive \(service.currentArchive) of \(service.totalArchives)")
                                .font(AnnFont.mono(11))
                                .foregroundColor(DS.textSecondary)

                            if service.gamesFoundSoFar > 0 {
                                Text("\u{2022}")
                                    .foregroundColor(DS.textSecondary)
                                Text("\(service.gamesFoundSoFar) games")
                                    .font(AnnFont.mono(11))
                                    .foregroundColor(DS.textSecondary)
                            }

                            Spacer()
                        }
                    }
                }

                // Error
                if let error = service.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(DS.textSecondary)
                        Spacer()
                    }
                }

                Spacer()
            }
            .padding()

            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            // Footer
            HStack {
                if !savedUsername.isEmpty {
                    Button(role: .destructive, action: {
                        savedUsername = ""
                        lastSyncTimestamp = 0
                        onDismiss()
                    }) {
                        Text("Disconnect")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(GlassButtonStyle())

                Button(action: connectAccount) {
                    if service.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(savedUsername.isEmpty ? "Connect" : "Save")
                    }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .tint(chessComGreen)
                .disabled(username.isEmpty || service.isLoading)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }

    private var progressPercentage: CGFloat {
        guard service.totalArchives > 0 else { return 0 }
        return CGFloat(service.currentArchive) / CGFloat(service.totalArchives)
    }

    private func connectAccount() {
        Task {
            service.clearHistory(for: username)

            await service.fetchAllGames(username: username)
            await MainActor.run {
                if service.error == nil {
                    savedUsername = username
                    lastSyncTimestamp = Date().timeIntervalSince1970
                    onImport(service.fetchedGames, username)
                    onDismiss()
                }
            }
        }
    }
}
