import SwiftUI
import AppKit

// MARK: - Board Theme

struct BoardTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let lightSquare: Color
    let darkSquare: Color
    let selectedColor: Color
    let lastMoveColor: Color
    let imageName: String?  // Board image filename (e.g. "brown.png"), nil for color-based themes

    init(id: String, name: String, lightSquare: Color, darkSquare: Color,
         selectedColor: Color, lastMoveColor: Color, imageName: String? = nil) {
        self.id = id
        self.name = name
        self.lightSquare = lightSquare
        self.darkSquare = darkSquare
        self.selectedColor = selectedColor
        self.lastMoveColor = lastMoveColor
        self.imageName = imageName
    }

    static let allThemes: [BoardTheme] = {
        // Color-based themes
        let colorThemes: [BoardTheme] = [
            // The Annotator — sepia paper. The board keeps these colors in BOTH app modes.
            BoardTheme(
                id: "annotator",
                name: "Annotator",
                lightSquare: Color(hex: 0xF0E6CF),
                darkSquare: Color(hex: 0xA98F6C),
                selectedColor: Color(hex: 0xC3A566),
                lastMoveColor: Color(hex: 0xE7CF8E)
            ),
            BoardTheme(
                id: "classic",
                name: "Classic",
                lightSquare: Color(red: 0.93, green: 0.93, blue: 0.82),
                darkSquare: Color(red: 0.71, green: 0.59, blue: 0.43),
                selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54),
                lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42)
            ),
            BoardTheme(
                id: "green",
                name: "Green",
                lightSquare: Color(red: 0.93, green: 0.93, blue: 0.82),
                darkSquare: Color(red: 0.46, green: 0.59, blue: 0.34),
                selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54),
                lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42)
            ),
            BoardTheme(
                id: "blue",
                name: "Blue",
                lightSquare: Color(red: 0.87, green: 0.89, blue: 0.90),
                darkSquare: Color(red: 0.45, green: 0.59, blue: 0.70),
                selectedColor: Color(red: 0.30, green: 0.69, blue: 0.31),
                lastMoveColor: Color(red: 0.56, green: 0.73, blue: 0.87)
            ),
            BoardTheme(
                id: "brown",
                name: "Brown",
                lightSquare: Color(red: 0.94, green: 0.85, blue: 0.71),
                darkSquare: Color(red: 0.71, green: 0.53, blue: 0.39),
                selectedColor: Color(red: 0.80, green: 0.60, blue: 0.20),
                lastMoveColor: Color(red: 0.85, green: 0.75, blue: 0.55)
            ),
            BoardTheme(
                id: "purple",
                name: "Purple",
                lightSquare: Color(red: 0.91, green: 0.87, blue: 0.94),
                darkSquare: Color(red: 0.55, green: 0.45, blue: 0.63),
                selectedColor: Color(red: 0.70, green: 0.50, blue: 0.80),
                lastMoveColor: Color(red: 0.75, green: 0.65, blue: 0.85)
            ),
            BoardTheme(
                id: "gray",
                name: "Gray",
                lightSquare: Color(red: 0.90, green: 0.90, blue: 0.90),
                darkSquare: Color(red: 0.55, green: 0.55, blue: 0.55),
                selectedColor: Color(red: 0.40, green: 0.70, blue: 0.40),
                lastMoveColor: Color(red: 0.70, green: 0.70, blue: 0.50)
            ),
            BoardTheme(
                id: "coral",
                name: "Coral",
                lightSquare: Color(red: 0.95, green: 0.90, blue: 0.88),
                darkSquare: Color(red: 0.80, green: 0.52, blue: 0.45),
                selectedColor: Color(red: 0.90, green: 0.60, blue: 0.40),
                lastMoveColor: Color(red: 0.95, green: 0.75, blue: 0.65)
            ),
            BoardTheme(
                id: "ocean",
                name: "Ocean",
                lightSquare: Color(red: 0.85, green: 0.92, blue: 0.95),
                darkSquare: Color(red: 0.30, green: 0.50, blue: 0.60),
                selectedColor: Color(red: 0.20, green: 0.70, blue: 0.70),
                lastMoveColor: Color(red: 0.50, green: 0.75, blue: 0.85)
            ),
            BoardTheme(
                id: "wood",
                name: "Wood",
                lightSquare: Color(red: 0.87, green: 0.76, blue: 0.60),
                darkSquare: Color(red: 0.55, green: 0.38, blue: 0.25),
                selectedColor: Color(red: 0.75, green: 0.55, blue: 0.30),
                lastMoveColor: Color(red: 0.80, green: 0.70, blue: 0.50)
            ),
            BoardTheme(
                id: "midnight",
                name: "Midnight",
                lightSquare: Color(red: 0.75, green: 0.75, blue: 0.82),
                darkSquare: Color(red: 0.25, green: 0.28, blue: 0.38),
                selectedColor: Color(red: 0.40, green: 0.50, blue: 0.70),
                lastMoveColor: Color(red: 0.50, green: 0.55, blue: 0.70)
            ),
        ]

        // Textured full-board images in Resources/Boards — original generated art (no third-party
        // license). The 8x8 pattern is baked in; the squares render .clear over the image.
        let imageThemes: [BoardTheme] = [
            BoardTheme(id: "img_walnut", name: "Walnut", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0xC3A566), lastMoveColor: Color(hex: 0xE7CF8E), imageName: "board_walnut.png"),
            BoardTheme(id: "img_oak", name: "Oak", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0xC3A566), lastMoveColor: Color(hex: 0xE7CF8E), imageName: "board_oak.png"),
            BoardTheme(id: "img_maple", name: "Maple", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0xC3A566), lastMoveColor: Color(hex: 0xE7CF8E), imageName: "board_maple.png"),
            BoardTheme(id: "img_rosewood", name: "Rosewood", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0xD08A50), lastMoveColor: Color(hex: 0xE0A060), imageName: "board_rosewood.png"),
            BoardTheme(id: "img_marble", name: "Marble", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0x9EC1D0), lastMoveColor: Color(hex: 0xBFD9E4), imageName: "board_marble.png"),
            BoardTheme(id: "img_slate", name: "Slate", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0x7FA8C0), lastMoveColor: Color(hex: 0xA8C6D8), imageName: "board_slate.png"),
            BoardTheme(id: "img_graphite", name: "Graphite", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0x8A8F98), lastMoveColor: Color(hex: 0xAEB3BC), imageName: "board_graphite.png"),
            BoardTheme(id: "img_emerald", name: "Emerald", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0x86B47A), lastMoveColor: Color(hex: 0xACCF9E), imageName: "board_emerald.png"),
            BoardTheme(id: "img_sandstone", name: "Sandstone", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(hex: 0xD0A85A), lastMoveColor: Color(hex: 0xE0C080), imageName: "board_sandstone.png"),
        ]

        return colorThemes + imageThemes
    }()

    static func theme(for id: String) -> BoardTheme {
        allThemes.first { $0.id == id } ?? allThemes[0]
    }

    /// Load the board image from the app bundle (cached — the raw decode was re-run every render).
    func loadBoardImage() -> NSImage? {
        guard let imageName = imageName,
              let resourcePath = Bundle.main.resourcePath else { return nil }
        let key = imageName as NSString
        if let cached = boardImageCache.object(forKey: key) { return cached }
        guard let img = NSImage(contentsOfFile: "\(resourcePath)/\(imageName)") else { return nil }
        boardImageCache.setObject(img, forKey: key)
        return img
    }
}

private let boardImageCache = NSCache<NSString, NSImage>()

// MARK: - Piece Style

struct PieceStyle: Identifiable, Equatable {
    let id: String
    let name: String
    let folder: String
    /// CC BY-NC-SA sets — legal to bundle only while the app is distributed free of charge.
    /// If the app ever adds ads / IAP / a paid tier, filter these out (`allStyles.filter { !$0.isNonCommercial }`).
    var isNonCommercial: Bool = false

    func imageFileName(for piece: Piece) -> String {
        let colorLetter = piece.color == .white ? "w" : "b"
        let pieceLetter: String
        switch piece.type {
        case .king:   pieceLetter = "k"
        case .queen:  pieceLetter = "q"
        case .rook:   pieceLetter = "r"
        case .bishop: pieceLetter = "b"
        case .knight: pieceLetter = "n"
        case .pawn:   pieceLetter = "p"
        }
        return "\(folder)_\(colorLetter)\(pieceLetter).png"
    }

    // Freely-licensed piece sets from Lichess (lila/public/piece) — see AcknowledgementsView for the
    // per-set author + license. The previous Chess.com-derived sets were proprietary and removed.
    static let allStyles: [PieceStyle] = [
        PieceStyle(id: "cburnett",   name: "Cburnett",   folder: "cburnett"),
        PieceStyle(id: "merida",     name: "Merida",     folder: "merida"),
        PieceStyle(id: "fantasy",    name: "Fantasy",    folder: "fantasy"),
        PieceStyle(id: "chessnut",   name: "Chessnut",   folder: "chessnut"),
        PieceStyle(id: "celtic",     name: "Celtic",     folder: "celtic"),
        PieceStyle(id: "spatial",    name: "Spatial",    folder: "spatial"),
        PieceStyle(id: "pirouetti",  name: "Pirouetti",  folder: "pirouetti"),
        PieceStyle(id: "kiwen-suwi", name: "Kiwen Suwi", folder: "kiwen-suwi"),
        PieceStyle(id: "totoy",      name: "Totoy",      folder: "totoy"),
        PieceStyle(id: "papercut",   name: "Papercut",   folder: "papercut"),
        PieceStyle(id: "letter",     name: "Letter",     folder: "letter"),
        PieceStyle(id: "shapes",     name: "Shapes",     folder: "shapes"),
        PieceStyle(id: "pixel",      name: "Pixel",      folder: "pixel"),
        PieceStyle(id: "rhosgfx",    name: "RhosGFX",    folder: "rhosgfx"),
        PieceStyle(id: "mpchess",    name: "MPChess",    folder: "mpchess"),
        // Non-Lichess free sets (see AcknowledgementsView for authors + licenses).
        PieceStyle(id: "kaneo",          name: "Kaneo",          folder: "kaneo"),
        PieceStyle(id: "kaneo_midnight", name: "Kaneo Midnight", folder: "kaneo_midnight"),
        PieceStyle(id: "kbyte",          name: "1 Kbyte Gambit", folder: "kbyte"),
        PieceStyle(id: "buch",           name: "Buch",           folder: "buch"),
        PieceStyle(id: "openmoji",       name: "OpenMoji",       folder: "openmoji"),
        PieceStyle(id: "firi",           name: "Firi",           folder: "firi"),
        // CC BY-NC-SA sets from Lichess (lila) — free-app only; see isNonCommercial above.
        PieceStyle(id: "maestro",   name: "Maestro",    folder: "maestro",   isNonCommercial: true),
        PieceStyle(id: "staunty",   name: "Staunty",    folder: "staunty",   isNonCommercial: true),
        PieceStyle(id: "caliente",  name: "Caliente",   folder: "caliente",  isNonCommercial: true),
        PieceStyle(id: "california", name: "California", folder: "california", isNonCommercial: true),
        PieceStyle(id: "cooke",     name: "Cooke",      folder: "cooke",     isNonCommercial: true),
        PieceStyle(id: "gioco",     name: "Gioco",      folder: "gioco",     isNonCommercial: true),
        PieceStyle(id: "horsey",    name: "Horsey",     folder: "horsey",    isNonCommercial: true),
        PieceStyle(id: "dubrovny",  name: "Dubrovny",   folder: "dubrovny",  isNonCommercial: true),
        PieceStyle(id: "fresca",    name: "Fresca",     folder: "fresca",    isNonCommercial: true),
        PieceStyle(id: "tatiana",   name: "Tatiana",    folder: "tatiana",   isNonCommercial: true),
        PieceStyle(id: "cardinal",  name: "Cardinal",   folder: "cardinal",  isNonCommercial: true),
        PieceStyle(id: "icpieces",  name: "IC Pieces",  folder: "icpieces",  isNonCommercial: true),
        PieceStyle(id: "anarcandy", name: "Anarcandy",  folder: "anarcandy", isNonCommercial: true),
        PieceStyle(id: "monarchy",  name: "Monarchy",   folder: "monarchy",  isNonCommercial: true),
        PieceStyle(id: "disguised", name: "Disguised",  folder: "disguised", isNonCommercial: true),
        PieceStyle(id: "xkcd",      name: "xkcd",       folder: "xkcd",      isNonCommercial: true),
        // Classic chess-font style sets (added under Resources/Pieces).
        PieceStyle(id: "classic",    name: "Classic",    folder: "classic"),
        PieceStyle(id: "neo",        name: "Neo",        folder: "neo"),
        PieceStyle(id: "bold",       name: "Bold",       folder: "bold"),
        PieceStyle(id: "fine",       name: "Fine",       folder: "fine"),
        PieceStyle(id: "gothic",     name: "Gothic",     folder: "gothic"),
        PieceStyle(id: "engraving",  name: "Engraving",  folder: "engraving"),
        PieceStyle(id: "regence",    name: "Regence",    folder: "regence"),
        PieceStyle(id: "selenus",    name: "Selenus",    folder: "selenus"),
        PieceStyle(id: "tournament", name: "Tournament", folder: "tournament"),
        PieceStyle(id: "bazinga",    name: "Bazinga",    folder: "bazinga"),
        PieceStyle(id: "bidi",       name: "Bidi",       folder: "bidi"),
        PieceStyle(id: "kram",       name: "Kram",       folder: "kram"),
        PieceStyle(id: "mung",       name: "Mung",       folder: "mung"),
        PieceStyle(id: "pantulsa",   name: "Pantulsa",   folder: "pantulsa"),
        PieceStyle(id: "setto",      name: "Setto",      folder: "setto"),
    ]

    static func style(for id: String) -> PieceStyle {
        allStyles.first { $0.id == id } ?? allStyles[0]
    }
}

// MARK: - App Appearance

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"   // Reading Room
    case dark = "Dark"     // Night Study

    /// Annotator display names for the appearance segmented control.
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Reading Room"
        case .dark:   return "Night Study"
        }
    }
}

// MARK: - App Settings Manager

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("appAppearance") var appAppearanceRaw: String = AppAppearance.system.rawValue {
        didSet { objectWillChange.send() }
    }

    var appAppearance: AppAppearance {
        get { AppAppearance(rawValue: appAppearanceRaw) ?? .system }
        set { appAppearanceRaw = newValue.rawValue }
    }

    @AppStorage("boardThemeId") var boardThemeId: String = "annotator" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("pieceStyleId") var pieceStyleId: String = "cburnett" {
        didSet { objectWillChange.send() }
    }
    
    var engineDepth: Int {
        get { defaultEngine?.settings.depth ?? 30 }
        set {
            guard let id = defaultEngine?.id else { return }
            var s = defaultEngine?.settings ?? .default
            s.depth = min(max(newValue, EngineSettings.depthRange.lowerBound), EngineSettings.depthRange.upperBound)
            updateEngineSettings(id: id, settings: s)
        }
    }

    @AppStorage("autoAnalyze") var autoAnalyze: Bool = true
    @AppStorage("stockfishPath") var stockfishPath: String = ""
    @AppStorage("showCoordinates") var showCoordinates: Bool = true
    @AppStorage("highlightLegalMoves") var highlightLegalMoves: Bool = true
    @AppStorage("showBestMoveArrow") var showBestMoveArrow: Bool = true
    @AppStorage("lichessToken") var lichessToken: String = ""

    // MARK: - Accounts & Import
    @AppStorage("autoSyncEnabled") var autoSyncEnabled: Bool = true
    @AppStorage("syncInterval") var syncIntervalRaw: String = "1h"      // 15m · 1h · 6h · daily
    @AppStorage("skipDuplicatesOnImport") var skipDuplicatesOnImport: Bool = true
    @AppStorage("classifyOpeningsOnImport") var classifyOpeningsOnImport: Bool = true

    // MARK: - Engine preferences (Settings › Engines)
    @AppStorage("reviewDepth") var reviewDepthRaw: String = "balanced"   // fast · balanced · deep
    @AppStorage("cloudFallbackEnabled") var cloudFallbackEnabled: Bool = false
    // Cached account summaries written by My Games so Settings can render them without the DB.
    @AppStorage("chesscom_game_count") var chessComGameCount: Int = 0
    @AppStorage("lichess_game_count") var lichessGameCount: Int = 0
    @AppStorage("chesscom_last_synced") var chessComLastSynced: Double = 0
    @AppStorage("lichess_last_synced") var lichessLastSynced: Double = 0

    // MARK: - Engine Configurations

    @AppStorage("engineConfigs") var engineConfigsJSON: String = "[]"

    var engines: [EngineConfig] {
        get {
            guard let data = engineConfigsJSON.data(using: .utf8),
                  let configs = try? JSONDecoder().decode([EngineConfig].self, from: data) else {
                return []
            }
            return configs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                engineConfigsJSON = json
                objectWillChange.send()
            }
        }
    }

    var defaultEngine: EngineConfig? {
        engines.first(where: { $0.isDefault }) ?? engines.first
    }

    func addEngine(_ config: EngineConfig) {
        var list = engines
        // Never register the same binary twice — keeps startup recovery and dev seeding idempotent.
        // Cloud engines have no path, so only dedupe local binaries by their path.
        if !config.path.isEmpty, list.contains(where: { $0.path == config.path }) { return }
        // If this is the first engine, make it default
        var newConfig = config
        if list.isEmpty {
            newConfig.isDefault = true
        }
        list.append(newConfig)
        engines = list
    }

    func removeEngine(id: UUID) {
        var list = engines
        let wasDefault = list.first(where: { $0.id == id })?.isDefault ?? false
        list.removeAll(where: { $0.id == id })
        // If we removed the default, make the first remaining engine default
        if wasDefault, !list.isEmpty {
            list[0].isDefault = true
        }
        engines = list
    }

    func setDefaultEngine(id: UUID) {
        var list = engines
        for i in list.indices {
            list[i].isDefault = (list[i].id == id)
        }
        engines = list
    }

    func updateEngineSettings(id: UUID, settings: EngineSettings) {
        var list = engines
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].settings = settings
            engines = list
        }
    }

    /// Scan the Engines directory for already-downloaded binaries that are missing from the config.
    /// Called on app startup to recover from preference resets.
    func recoverInstalledEngines() {
        let service = EngineDownloadService()
        let currentPaths = Set(engines.map(\.path))

        for entry in EngineRegistryEntry.available {
            guard service.isEngineDownloaded(entry: entry),
                  let path = service.enginePath(for: entry),
                  !currentPaths.contains(path) else { continue }

            let version = service.installedVersion(for: entry)
            let name = version != nil ? "\(entry.name) \(version!)" : entry.name
            addEngine(EngineConfig(
                id: UUID(),
                name: name,
                path: path,
                isDefault: false,
                source: .downloaded
            ))
        }
    }

    var boardTheme: BoardTheme {
        BoardTheme.theme(for: boardThemeId)
    }
    
    var pieceStyle: PieceStyle {
        PieceStyle.style(for: pieceStyleId)
    }
}
