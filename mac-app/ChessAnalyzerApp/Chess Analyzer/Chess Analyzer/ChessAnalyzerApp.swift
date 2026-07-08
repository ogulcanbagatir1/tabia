import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

@main
struct TabiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    let container: ModelContainer
    let database: GameDatabase
    let repertoireDatabase: RepertoireDatabase
    let referenceDatabase: ReferenceDatabase

    init() {
        // The Annotator's three voices — register the bundled OFL fonts before any view renders.
        AnnFont.registerBundledFonts()

        let container = try! ModelContainer(
            for: GameRecord.self, GameFolder.self, ChessComCachedStats.self, CachedName.self,
                 Repertoire.self, RepertoireFolder.self, RepertoireNode.self, PositionSchedule.self
        )
        self.container = container
        self.database = GameDatabase(modelContext: container.mainContext, container: container)
        self.repertoireDatabase = RepertoireDatabase(modelContext: container.mainContext, container: container)
        self.referenceDatabase = ReferenceDatabase()

        // One-time cleanup of old persistence keys
        UserDefaults.standard.removeObject(forKey: "SavedGames")
        UserDefaults.standard.removeObject(forKey: "SavedFolders")
        UserDefaults.standard.removeObject(forKey: "chesscom_cached_games")
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .modelContainer(container)
                .environmentObject(database)
                .environmentObject(repertoireDatabase)
                .environmentObject(referenceDatabase)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    database.startBackgroundBackfills()
                    settings.recoverInstalledEngines()
                }
                .preferredColorScheme(settings.appAppearance == .light ? .light : settings.appAppearance == .dark ? .dark : nil)
                .onOpenURL { url in
                    LichessAuthService.shared.handleCallback(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            EngineRoomCommands()

            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Game") {
                    // TODO: Implement new game
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandMenu("File") {
                Button("Open PGN...") {
                    // TODO: Implement open PGN
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Save PGN...") {
                    // TODO: Implement save PGN
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Divider()
                
                Button("Import PGN Database...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if let pgnType = UTType(filenameExtension: "pgn") {
                        panel.allowedContentTypes = [pgnType, .plainText]
                    }
                    panel.message = "Choose a PGN file to import into the reference database"
                    if panel.runModal() == .OK, let url = panel.url {
                        referenceDatabase.importPGN(url: url)
                    }
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("Export Game...") {
                    // TODO: Implement export
                }
            }
            
            // Edit menu
            CommandMenu("Edit") {
                Button("Copy FEN") {
                    // TODO: Copy FEN to clipboard
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("Paste FEN") {
                    // TODO: Paste FEN from clipboard
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Flip Board") {
                    // TODO: Implement flip board
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            
            // Analysis menu
            CommandMenu("Analysis") {
                Button("Start Engine") {
                    // TODO: Start engine
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Stop Engine") {
                    // TODO: Stop engine
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Analyze Position") {
                    // TODO: Analyze current position
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Show Best Move") {
                    // TODO: Show best move
                }
                .keyboardShortcut("b", modifiers: .command)
            }
            
            // Navigation menu
            CommandMenu("Navigate") {
                Button("Go to Start") {
                    // TODO: Go to start
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                
                Button("Previous Move") {
                    // TODO: Previous move
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                
                Button("Next Move") {
                    // TODO: Next move
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                
                Button("Go to End") {
                    // TODO: Go to end
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
        }
        
        // Preferences window
        Settings {
            PreferencesView()
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))

        // Engine Room — a separate management window (⌘E, the analysis engine-chip menu,
        // Settings → Engines, and engine empty-state buttons all open this).
        Window("Engine Room", id: WindowID.engineRoom) {
            EngineManagerView()
                .modelContainer(container)
                .environmentObject(database)
                .environmentObject(repertoireDatabase)
                .environmentObject(referenceDatabase)
                .frame(minWidth: 760, minHeight: 540)
                .preferredColorScheme(settings.appAppearance == .light ? .light : settings.appAppearance == .dark ? .dark : nil)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Stable identifiers for auxiliary windows.
enum WindowID {
    static let engineRoom = "engineRoom"
}

/// ⌘E → Engine Room (composed into the app's command set).
struct EngineRoomCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Engine Room") { openWindow(id: WindowID.engineRoom) }
                .keyboardShortcut("e", modifiers: .command)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE to prevent crashes when writing to broken pipes
        // (e.g., when Stockfish engine crashes)
        signal(SIGPIPE, SIG_IGN)

        // Register for URL scheme callbacks (onOpenURL is unreliable on macOS)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Maximize window to fill the screen and configure glass appearance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = NSApplication.shared.windows.first,
               let screen = window.screen {
                window.setFrame(screen.visibleFrame, display: true)

                // Glass window styling
                window.titlebarAppearsTransparent = true
                window.backgroundColor = .clear
            }
        }
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        LichessAuthService.shared.handleCallback(url: url)
    }
}
