import SwiftUI
import Combine
import Sparkle

// MARK: - Sparkle auto-update
// Tabia ships outside the Mac App Store, so updates are delivered with Sparkle: it checks the
// appcast feed (SUFeedURL in Info.plist), verifies each update against SUPublicEDKey, and installs
// it. The private signing key lives in the developer's keychain (see scripts/NOTARIZE.md +
// UPDATES.md); releases are signed with `sign_update`.

/// Owns the single Sparkle updater for the app's lifetime and exposes whether a check is allowed
/// (so the menu item can disable itself while an update is already in flight).
final class UpdaterViewModel: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true begins the scheduled background checks immediately.
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

/// Adds "Check for Updates…" under the app menu (right after the About item).
struct CheckForUpdatesCommand: Commands {
    @ObservedObject var updater: UpdaterViewModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
