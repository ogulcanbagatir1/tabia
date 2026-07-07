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

        // Image-based themes from Boards/ resources
        let imageThemes: [BoardTheme] = [
            BoardTheme(id: "img_8_bit", name: "8 Bit", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_8_bit.png"),
            BoardTheme(id: "img_bases", name: "Bases", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_bases.png"),
            BoardTheme(id: "img_blue", name: "Blue Board", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.30, green: 0.69, blue: 0.31), lastMoveColor: Color(red: 0.56, green: 0.73, blue: 0.87), imageName: "board_blue.png"),
            BoardTheme(id: "img_brown", name: "Brown Board", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.80, green: 0.60, blue: 0.20), lastMoveColor: Color(red: 0.85, green: 0.75, blue: 0.55), imageName: "board_brown.png"),
            BoardTheme(id: "img_bubblegum", name: "Bubblegum", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.90, green: 0.50, blue: 0.70), lastMoveColor: Color(red: 0.95, green: 0.70, blue: 0.80), imageName: "board_bubblegum.png"),
            BoardTheme(id: "img_burled_wood", name: "Burled Wood", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.75, green: 0.55, blue: 0.30), lastMoveColor: Color(red: 0.80, green: 0.70, blue: 0.50), imageName: "board_burled_wood.png"),
            BoardTheme(id: "img_dark_wood", name: "Dark Wood", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.75, green: 0.55, blue: 0.30), lastMoveColor: Color(red: 0.80, green: 0.70, blue: 0.50), imageName: "board_dark_wood.png"),
            BoardTheme(id: "img_dash", name: "Dash", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_dash.png"),
            BoardTheme(id: "img_glass", name: "Glass", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.40, green: 0.70, blue: 0.80), lastMoveColor: Color(red: 0.60, green: 0.80, blue: 0.90), imageName: "board_glass.png"),
            BoardTheme(id: "img_graffiti", name: "Graffiti", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_graffiti.png"),
            BoardTheme(id: "img_green", name: "Green Board", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_green.png"),
            BoardTheme(id: "img_icy_sea", name: "Icy Sea", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.20, green: 0.70, blue: 0.70), lastMoveColor: Color(red: 0.50, green: 0.75, blue: 0.85), imageName: "board_icy_sea.png"),
            BoardTheme(id: "img_light", name: "Light", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_light.png"),
            BoardTheme(id: "img_lolz", name: "Lolz", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_lolz.png"),
            BoardTheme(id: "img_marble", name: "Marble", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.40, green: 0.70, blue: 0.40), lastMoveColor: Color(red: 0.70, green: 0.70, blue: 0.50), imageName: "board_marble.png"),
            BoardTheme(id: "img_metal", name: "Metal", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.40, green: 0.70, blue: 0.40), lastMoveColor: Color(red: 0.70, green: 0.70, blue: 0.50), imageName: "board_metal.png"),
            BoardTheme(id: "img_neon", name: "Neon", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.20, green: 0.90, blue: 0.50), lastMoveColor: Color(red: 0.50, green: 0.90, blue: 0.70), imageName: "board_neon.png"),
            BoardTheme(id: "img_newspaper", name: "Newspaper", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.40, green: 0.70, blue: 0.40), lastMoveColor: Color(red: 0.70, green: 0.70, blue: 0.50), imageName: "board_newspaper.png"),
            BoardTheme(id: "img_orange", name: "Orange", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.90, green: 0.60, blue: 0.20), lastMoveColor: Color(red: 0.95, green: 0.75, blue: 0.50), imageName: "board_orange.png"),
            BoardTheme(id: "img_overlay", name: "Overlay", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_overlay.png"),
            BoardTheme(id: "img_parchment", name: "Parchment", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.75, green: 0.55, blue: 0.30), lastMoveColor: Color(red: 0.80, green: 0.70, blue: 0.50), imageName: "board_parchment.png"),
            BoardTheme(id: "img_purple", name: "Purple Board", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.70, green: 0.50, blue: 0.80), lastMoveColor: Color(red: 0.75, green: 0.65, blue: 0.85), imageName: "board_purple.png"),
            BoardTheme(id: "img_red", name: "Red", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.90, green: 0.40, blue: 0.30), lastMoveColor: Color(red: 0.95, green: 0.60, blue: 0.50), imageName: "board_red.png"),
            BoardTheme(id: "img_sand", name: "Sand", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.80, green: 0.60, blue: 0.20), lastMoveColor: Color(red: 0.85, green: 0.75, blue: 0.55), imageName: "board_sand.png"),
            BoardTheme(id: "img_sky", name: "Sky", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.30, green: 0.69, blue: 0.31), lastMoveColor: Color(red: 0.56, green: 0.73, blue: 0.87), imageName: "board_sky.png"),
            BoardTheme(id: "img_stone", name: "Stone", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.40, green: 0.70, blue: 0.40), lastMoveColor: Color(red: 0.70, green: 0.70, blue: 0.50), imageName: "board_stone.png"),
            BoardTheme(id: "img_tan", name: "Tan", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.80, green: 0.60, blue: 0.20), lastMoveColor: Color(red: 0.85, green: 0.75, blue: 0.55), imageName: "board_tan.png"),
            BoardTheme(id: "img_tournament", name: "Tournament", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.49, green: 0.75, blue: 0.54), lastMoveColor: Color(red: 0.80, green: 0.78, blue: 0.42), imageName: "board_tournament.png"),
            BoardTheme(id: "img_translucent", name: "Translucent", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.40, green: 0.70, blue: 0.80), lastMoveColor: Color(red: 0.60, green: 0.80, blue: 0.90), imageName: "board_translucent.png"),
            BoardTheme(id: "img_walnut", name: "Walnut", lightSquare: .clear, darkSquare: .clear,
                       selectedColor: Color(red: 0.75, green: 0.55, blue: 0.30), lastMoveColor: Color(red: 0.80, green: 0.70, blue: 0.50), imageName: "board_walnut.png"),
        ]

        return colorThemes + imageThemes
    }()

    static func theme(for id: String) -> BoardTheme {
        allThemes.first { $0.id == id } ?? allThemes[0]
    }

    /// Load the board image from the app bundle
    func loadBoardImage() -> NSImage? {
        guard let imageName = imageName,
              let resourcePath = Bundle.main.resourcePath else { return nil }
        return NSImage(contentsOfFile: "\(resourcePath)/\(imageName)")
    }
}

// MARK: - Piece Style

struct PieceStyle: Identifiable, Equatable {
    let id: String
    let name: String
    let folder: String

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

    static let allStyles: [PieceStyle] = [
        PieceStyle(id: "classic", name: "Classic", folder: "classic"),
        PieceStyle(id: "neo", name: "Neo", folder: "neo"),
        PieceStyle(id: "modern", name: "Modern", folder: "modern"),
        PieceStyle(id: "alpha", name: "Alpha", folder: "alpha"),
        PieceStyle(id: "8_bit", name: "8 Bit", folder: "8_bit"),
        PieceStyle(id: "bases", name: "Bases", folder: "bases"),
        PieceStyle(id: "book", name: "Book", folder: "book"),
        PieceStyle(id: "bubblegum", name: "Bubblegum", folder: "bubblegum"),
        PieceStyle(id: "cases", name: "Cases", folder: "cases"),
        PieceStyle(id: "club", name: "Club", folder: "club"),
        PieceStyle(id: "condal", name: "Condal", folder: "condal"),
        PieceStyle(id: "dash", name: "Dash", folder: "dash"),
        PieceStyle(id: "game_room", name: "Game Room", folder: "game_room"),
        PieceStyle(id: "glass", name: "Glass", folder: "glass"),
        PieceStyle(id: "gothic", name: "Gothic", folder: "gothic"),
        PieceStyle(id: "graffiti", name: "Graffiti", folder: "graffiti"),
        PieceStyle(id: "icy_sea", name: "Icy Sea", folder: "icy_sea"),
        PieceStyle(id: "light", name: "Light", folder: "light"),
        PieceStyle(id: "lolz", name: "Lolz", folder: "lolz"),
        PieceStyle(id: "marble", name: "Marble", folder: "marble"),
        PieceStyle(id: "maya", name: "Maya", folder: "maya"),
        PieceStyle(id: "metal", name: "Metal", folder: "metal"),
        PieceStyle(id: "nature", name: "Nature", folder: "nature"),
        PieceStyle(id: "neo_wood", name: "Neo Wood", folder: "neo_wood"),
        PieceStyle(id: "neon", name: "Neon", folder: "neon"),
        PieceStyle(id: "newspaper", name: "Newspaper", folder: "newspaper"),
        PieceStyle(id: "ocean", name: "Ocean", folder: "ocean"),
        PieceStyle(id: "sky", name: "Sky", folder: "sky"),
        PieceStyle(id: "space", name: "Space", folder: "space"),
        PieceStyle(id: "tigers", name: "Tigers", folder: "tigers"),
        PieceStyle(id: "tournament", name: "Tournament", folder: "tournament"),
        PieceStyle(id: "vintage", name: "Vintage", folder: "vintage"),
        PieceStyle(id: "wood", name: "Wood", folder: "wood"),
    ]

    static func style(for id: String) -> PieceStyle {
        allStyles.first { $0.id == id } ?? allStyles[0]
    }
}

// MARK: - App Appearance

enum AppAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
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

    @AppStorage("boardThemeId") var boardThemeId: String = "classic" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("pieceStyleId") var pieceStyleId: String = "classic" {
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
