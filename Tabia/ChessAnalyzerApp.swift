import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

@main
struct TabiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @StateObject private var updater = UpdaterViewModel()

    let container: ModelContainer
    let database: GameDatabase
    let repertoireDatabase: RepertoireDatabase
    let referenceDatabase: ReferenceDatabase

    init() {
        // The Annotator's three voices — register the bundled OFL fonts before any view renders.
        AnnFont.registerBundledFonts()

        // Seed runs (TABIA_SEED) use an in-memory store so sample data never touches the real DB.
        let ephemeral = ProcessInfo.processInfo.environment["TABIA_SEED"] != nil

        // Pin the on-disk store to an ABSOLUTE path. SwiftData's default store URL is derived from
        // sandbox-relative APIs (NSHomeDirectory / applicationSupportDirectory), so the resolved
        // location silently shifts between the sandbox container and ~/Library/Application Support
        // across launches — a sync would write to one and the next launch would read the other, so
        // freshly imported games appeared to vanish. Resolve the real home from the password db
        // (sandbox-independent) and always use the app's container path, which is writable whether or
        // not the process is sandboxed and already holds the existing library.
        let config: ModelConfiguration
        if ephemeral {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            let realHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
            let storeDir = URL(fileURLWithPath: realHome, isDirectory: true)
                .appendingPathComponent("Library/Containers/com.ogulcan.Tabia/Data/Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            config = ModelConfiguration(url: storeDir.appendingPathComponent("default.store"))
        }

        let schema = Schema([
            GameRecord.self, GameFolder.self, ChessComCachedStats.self, CachedName.self,
            Repertoire.self, RepertoireFolder.self, RepertoireNode.self, PositionSchedule.self,
        ])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // The on-disk store failed to open — a store corrupted by an interrupted write, or an
            // incompatible schema from a downgrade. Rather than a hard launch crash (try!), move the
            // store aside so the app opens fresh; fall back to in-memory as a last resort so it always
            // launches. (A proper SchemaMigrationPlan is still needed before the first model change.)
            NSLog("Tabia: ModelContainer open failed (\(error)); attempting recovery.")
            if !ephemeral {
                let fm = FileManager.default
                for suffix in ["", "-wal", "-shm"] {
                    let live = URL(fileURLWithPath: config.url.path + suffix)
                    let quarantine = URL(fileURLWithPath: config.url.path + suffix + ".corrupt")
                    try? fm.removeItem(at: quarantine)
                    try? fm.moveItem(at: live, to: quarantine)
                }
            }
            container = (try? ModelContainer(for: schema, configurations: config))
                ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        }
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
                .tint(DS.redAccent)   // our one red pen — never the system blue
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    database.startBackgroundBackfills()
                    settings.recoverInstalledEngines()
                    DevSeed.seedIfRequested(database: database, repertoire: repertoireDatabase, settings: settings)
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
            CheckForUpdatesCommand(updater: updater)

            CommandGroup(replacing: .newItem) {
                menuItem("game.new")
            }

            CommandMenu("File") {
                menuItem("game.open")
                menuItem("game.save")
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
                .keyboardShortcut(shortcuts.keyEquivalent("game.importDb"), modifiers: shortcuts.modifiers("game.importDb"))
                menuItem("game.export")
            }

            CommandMenu("Board") {
                menuItem("game.setup")
                Divider()
                menuItem("board.flip")
                menuItem("board.copyFEN")
                menuItem("board.pasteFEN")
            }

            CommandMenu("Analysis") {
                menuItem("analysis.position")
                menuItem("analysis.review")
                menuItem("analysis.best")
                Divider()
                menuItem("analysis.toggleEngine")
                menuItem("analysis.autoAnalyze")
            }

            CommandMenu("Navigate") {
                menuItem("nav.start")
                menuItem("nav.prev")
                menuItem("nav.next")
                menuItem("nav.end")
                Divider()
                menuItem("screen.analysis")
                menuItem("screen.explorer")
                menuItem("screen.repertoire")
                menuItem("screen.chesscom")
                menuItem("screen.database")
            }

            CommandMenu("Move") {
                menuItem("ann.brilliant")
                menuItem("ann.good")
                menuItem("ann.interesting")
                menuItem("ann.dubious")
                menuItem("ann.mistake")
                menuItem("ann.blunder")
                Divider()
                menuItem("ann.delete")
            }

            CommandMenu("Library") {
                menuItem("lib.sync")
                menuItem("lib.filters")
                menuItem("lib.search")
                Divider()
                menuItem("lib.newDb")
                menuItem("rep.new")
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
                .tint(DS.redAccent)
                .frame(minWidth: 760, minHeight: 540)
                .preferredColorScheme(settings.appAppearance == .light ? .light : settings.appAppearance == .dark ? .dark : nil)
        }
        .windowResizability(.contentMinSize)
    }

    /// A menu command whose key equivalent is read live from the (rebindable) shortcut store.
    @ViewBuilder
    private func menuItem(_ id: String) -> some View {
        if let def = ShortcutRegistry.byId[id] {
            Button(def.name) { NotificationCenter.default.post(name: def.notificationName, object: nil) }
                .keyboardShortcut(shortcuts.keyEquivalent(id), modifiers: shortcuts.modifiers(id))
        }
    }
}

/// Stable identifiers for auxiliary windows.
enum WindowID {
    static let engineRoom = "engineRoom"
}

/// ⌘E → Engine Room (composed into the app's command set).
struct EngineRoomCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var shortcuts = ShortcutStore.shared
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Engine Room") { openWindow(id: WindowID.engineRoom) }
                .keyboardShortcut(shortcuts.keyEquivalent("win.engineRoom"), modifiers: shortcuts.modifiers("win.engineRoom"))
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

                // Vertically center the native traffic lights within the 47pt masthead band
                // (the masthead rises into the title-bar area, so the OS-default high position
                // would sit above the wordmark's centerline).
                self.centerTrafficLights(in: window)
                NotificationCenter.default.addObserver(
                    self, selector: #selector(self.windowDidResize(_:)),
                    name: NSWindow.didResizeNotification, object: window)
            }
        }
    }

    @objc func windowDidResize(_ note: Notification) {
        if let window = note.object as? NSWindow { centerTrafficLights(in: window) }
    }

    /// Move the close/minimize/zoom buttons so their vertical centers sit at the middle of
    /// the 47pt masthead band, on the same line as the wordmark and nav tabs.
    func centerTrafficLights(in window: NSWindow) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let container = buttons.first?.superview else { return }
        let bar = DS.titlebarHeight
        for button in buttons {
            var origin = button.frame.origin
            origin.y = container.bounds.height - bar / 2 - button.frame.height / 2
            button.setFrameOrigin(origin)
        }
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        LichessAuthService.shared.handleCallback(url: url)
    }
}
