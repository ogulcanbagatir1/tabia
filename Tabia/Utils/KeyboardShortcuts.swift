import SwiftUI
import AppKit

// MARK: - Rebindable keyboard-shortcut system

/// One key + a set of modifiers, stored in a token form that round-trips to SwiftUI + AppKit.
struct Chord: Codable, Equatable {
    var key: String            // "n", "1", ",", "left", "right", "up", "down", "home", "end", "delete", "return", "space"
    var mods: [String]         // subset of ["command","shift","option","control"]

    var eventModifiers: EventModifiers {
        var e: EventModifiers = []
        if mods.contains("command") { e.insert(.command) }
        if mods.contains("shift")   { e.insert(.shift) }
        if mods.contains("option")  { e.insert(.option) }
        if mods.contains("control") { e.insert(.control) }
        return e
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "left":   return .leftArrow
        case "right":  return .rightArrow
        case "up":     return .upArrow
        case "down":   return .downArrow
        case "home":   return .home
        case "end":    return .end
        case "delete": return .delete
        case "return": return .return
        case "space":  return .space
        default:       return KeyEquivalent(Character(key.first.map(String.init) ?? "?"))
        }
    }

    /// Human-readable form, e.g. "⇧⌘N", "⌥1", "⌘←".
    var display: String {
        var s = ""
        if mods.contains("control") { s += "⌃" }
        if mods.contains("option")  { s += "⌥" }
        if mods.contains("shift")   { s += "⇧" }
        if mods.contains("command") { s += "⌘" }
        s += Chord.keyGlyph(key)
        return s
    }

    static func keyGlyph(_ key: String) -> String {
        switch key {
        case "left":   return "←"
        case "right":  return "→"
        case "up":     return "↑"
        case "down":   return "↓"
        case "home":   return "Home"
        case "end":    return "End"
        case "delete": return "⌫"
        case "return": return "↩"
        case "space":  return "Space"
        case ",":      return ","
        default:       return key.uppercased()
        }
    }

    /// Build a chord from a captured key event (returns nil for modifier-only presses).
    static func from(event: NSEvent) -> Chord? {
        var mods: [String] = []
        let f = event.modifierFlags
        if f.contains(.control) { mods.append("control") }
        if f.contains(.option)  { mods.append("option") }
        if f.contains(.shift)   { mods.append("shift") }
        if f.contains(.command) { mods.append("command") }

        let key: String
        switch event.keyCode {
        case 123: key = "left"
        case 124: key = "right"
        case 126: key = "up"
        case 125: key = "down"
        case 115: key = "home"
        case 119: key = "end"
        case 51, 117: key = "delete"
        case 36, 76: key = "return"
        case 49: key = "space"
        default:
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            guard let c = chars.first, c.isLetter || c.isNumber || ",./;'[]=-".contains(c) else { return nil }
            key = String(c)
        }
        return Chord(key: key, mods: mods)
    }
}

/// Definition of a single rebindable action.
struct ShortcutDef: Identifiable {
    let id: String
    let category: String
    let name: String
    let detail: String
    let notification: String     // Notification.Name rawValue posted when fired
    let def: Chord

    var notificationName: Notification.Name { Notification.Name(notification) }
}

enum ShortcutRegistry {
    static let all: [ShortcutDef] = [
        // Screens
        ShortcutDef(id: "screen.analysis",   category: "Screens", name: "Analysis",          detail: "Board, engine and move list",              notification: "tabia.screen.analysis",   def: Chord(key: "1", mods: ["command"])),
        ShortcutDef(id: "screen.repertoire", category: "Screens", name: "Repertoire",         detail: "Your opening trees and drills",            notification: "tabia.screen.repertoire", def: Chord(key: "2", mods: ["command"])),
        ShortcutDef(id: "screen.chesscom",   category: "Screens", name: "My Games",           detail: "Synced Chess.com & Lichess games",         notification: "tabia.screen.chesscom",   def: Chord(key: "3", mods: ["command"])),
        ShortcutDef(id: "screen.database",   category: "Screens", name: "Library",            detail: "Imported games and databases",             notification: "tabia.screen.database",   def: Chord(key: "4", mods: ["command"])),

        // Game
        ShortcutDef(id: "game.new",     category: "Game", name: "New Game",           detail: "Reset to the starting position",           notification: "tabia.newGame",        def: Chord(key: "n", mods: ["command"])),
        ShortcutDef(id: "game.open",    category: "Game", name: "Open PGN",           detail: "Load a PGN file onto the board",           notification: "tabia.openPGN",        def: Chord(key: "o", mods: ["command"])),
        ShortcutDef(id: "game.save",    category: "Game", name: "Save Game",          detail: "Save the current game to your library",    notification: "tabia.savePGN",        def: Chord(key: "s", mods: ["command"])),
        ShortcutDef(id: "game.importDb",category: "Game", name: "Import PGN Database",detail: "Bulk-import into the reference database",  notification: "tabia.importDatabase", def: Chord(key: "i", mods: ["command", "shift"])),
        ShortcutDef(id: "game.export",  category: "Game", name: "Export Game",        detail: "Export the current game as PGN",           notification: "tabia.exportGame",     def: Chord(key: "s", mods: ["command", "shift"])),
        ShortcutDef(id: "game.setup",   category: "Game", name: "Set Up Position",    detail: "Open the board editor",                    notification: "tabia.setUpPosition",  def: Chord(key: "n", mods: ["command", "shift"])),

        // Board
        ShortcutDef(id: "board.flip",     category: "Board", name: "Flip Board", detail: "Swap sides on the board",           notification: "tabia.flipBoard", def: Chord(key: "f", mods: ["command", "shift"])),
        ShortcutDef(id: "board.copyFEN",  category: "Board", name: "Copy FEN",   detail: "Copy the position as FEN",          notification: "tabia.copyFEN",   def: Chord(key: "c", mods: ["command", "shift"])),
        ShortcutDef(id: "board.pasteFEN", category: "Board", name: "Paste FEN",  detail: "Load a FEN from the clipboard",     notification: "tabia.pasteFEN",  def: Chord(key: "v", mods: ["command", "shift"])),

        // Analysis
        ShortcutDef(id: "analysis.position",    category: "Analysis", name: "Analyze Position",     detail: "Evaluate the current position",        notification: "tabia.analyzePosition",    def: Chord(key: "a", mods: ["command", "option"])),
        ShortcutDef(id: "analysis.review",      category: "Analysis", name: "Full Game Review",     detail: "Run a full-game engine review",        notification: "tabia.fullReview",         def: Chord(key: "a", mods: ["command", "shift"])),
        ShortcutDef(id: "analysis.best",        category: "Analysis", name: "Show Best Move",       detail: "Draw the engine's best move",          notification: "tabia.showBestMove",       def: Chord(key: "b", mods: ["command"])),
        ShortcutDef(id: "analysis.toggleEngine",category: "Analysis", name: "Toggle Engine",        detail: "Start or stop the engine",             notification: "tabia.toggleEngine",       def: Chord(key: "e", mods: ["control"])),
        ShortcutDef(id: "analysis.autoAnalyze", category: "Analysis", name: "Toggle Auto-analyze",  detail: "Analyze automatically as you move",    notification: "tabia.toggleAutoAnalyze",  def: Chord(key: "a", mods: ["control"])),

        // Navigate
        ShortcutDef(id: "nav.start", category: "Navigate", name: "Go to Start",    detail: "Jump to the first move",  notification: "tabia.goToStart",     def: Chord(key: "left",  mods: ["command", "option"])),
        ShortcutDef(id: "nav.prev",  category: "Navigate", name: "Previous Move",  detail: "Step one move back",      notification: "tabia.previousMove",  def: Chord(key: "left",  mods: ["command"])),
        ShortcutDef(id: "nav.next",  category: "Navigate", name: "Next Move",      detail: "Step one move forward",   notification: "tabia.nextMove",      def: Chord(key: "right", mods: ["command"])),
        ShortcutDef(id: "nav.end",   category: "Navigate", name: "Go to End",      detail: "Jump to the last move",   notification: "tabia.goToEnd",       def: Chord(key: "right", mods: ["command", "option"])),

        // Annotate move
        ShortcutDef(id: "ann.brilliant",   category: "Annotate move", name: "Brilliant \u{203C}",  detail: "Mark the current move \u{203C}", notification: "tabia.ann.brilliant",   def: Chord(key: "1", mods: ["option"])),
        ShortcutDef(id: "ann.good",        category: "Annotate move", name: "Good !",              detail: "Mark the current move !",        notification: "tabia.ann.good",        def: Chord(key: "2", mods: ["option"])),
        ShortcutDef(id: "ann.interesting", category: "Annotate move", name: "Interesting !?",      detail: "Mark the current move !?",       notification: "tabia.ann.interesting", def: Chord(key: "3", mods: ["option"])),
        ShortcutDef(id: "ann.dubious",     category: "Annotate move", name: "Dubious ?!",          detail: "Mark the current move ?!",       notification: "tabia.ann.dubious",     def: Chord(key: "4", mods: ["option"])),
        ShortcutDef(id: "ann.mistake",     category: "Annotate move", name: "Mistake ?",           detail: "Mark the current move ?",        notification: "tabia.ann.mistake",     def: Chord(key: "5", mods: ["option"])),
        ShortcutDef(id: "ann.blunder",     category: "Annotate move", name: "Blunder ??",          detail: "Mark the current move ??",       notification: "tabia.ann.blunder",     def: Chord(key: "6", mods: ["option"])),
        ShortcutDef(id: "ann.delete",      category: "Annotate move", name: "Delete Move",         detail: "Delete from the current move",   notification: "tabia.deleteMove",      def: Chord(key: "delete", mods: ["command"])),

        // Games & Library
        ShortcutDef(id: "lib.sync",    category: "Games & Library", name: "Sync Games",      detail: "Pull new online games",             notification: "tabia.syncGames",             def: Chord(key: "r", mods: ["command"])),
        ShortcutDef(id: "lib.filters", category: "Games & Library", name: "Toggle Filters",  detail: "Show or hide the Library filters",  notification: "tabia.libraryToggleFilters",  def: Chord(key: "f", mods: ["command", "option"])),
        ShortcutDef(id: "lib.search",  category: "Games & Library", name: "Focus Search",    detail: "Jump to the search field",          notification: "tabia.focusSearch",           def: Chord(key: "f", mods: ["command"])),
        ShortcutDef(id: "lib.newDb",   category: "Games & Library", name: "New Database",    detail: "Create a new database",             notification: "tabia.newDatabase",           def: Chord(key: "d", mods: ["command", "shift"])),
        ShortcutDef(id: "rep.new",     category: "Games & Library", name: "New Repertoire",  detail: "Create a new repertoire",           notification: "tabia.newRepertoire",         def: Chord(key: "r", mods: ["command", "shift"])),

        // Windows
        ShortcutDef(id: "win.engineRoom", category: "Windows", name: "Engine Room", detail: "Install, remove and tune engines", notification: "tabia.engineRoom", def: Chord(key: "e", mods: ["command"])),
    ]

    static let byId: [String: ShortcutDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let categories: [String] = {
        var seen = Set<String>(); var order: [String] = []
        for d in all where !seen.contains(d.category) { seen.insert(d.category); order.append(d.category) }
        return order
    }()
}

/// Holds user overrides and resolves the effective chord for each action.
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    private let key = "keyboardShortcutOverrides"

    @Published private(set) var overrides: [String: Chord]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Chord].self, from: data) {
            overrides = decoded
        } else {
            overrides = [:]
        }
    }

    func chord(_ id: String) -> Chord {
        overrides[id] ?? ShortcutRegistry.byId[id]?.def ?? Chord(key: "?", mods: [])
    }

    func keyEquivalent(_ id: String) -> KeyEquivalent { chord(id).keyEquivalent }
    func modifiers(_ id: String) -> EventModifiers { chord(id).eventModifiers }
    func isCustomized(_ id: String) -> Bool { overrides[id] != nil }

    func setChord(_ id: String, _ c: Chord) { overrides[id] = c; persist() }
    func reset(_ id: String) { overrides[id] = nil; persist() }
    func resetAll() { overrides = [:]; persist() }

    /// Any other action currently bound to the same chord (for conflict warnings).
    func conflict(for id: String, chord c: Chord) -> ShortcutDef? {
        for d in ShortcutRegistry.all where d.id != id {
            if chord(d.id) == c { return d }
        }
        return nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
