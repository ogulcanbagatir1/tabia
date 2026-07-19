import SwiftUI

// MARK: - Screen state that outlives the screen
//
// Rail sections are mounted with a `switch activeScreen`, so leaving one tears its view down and
// takes every `@State` with it — filters, sort, scroll position and the loaded page all reset.
//
// The fix is to move that state out of the view rather than keeping every screen mounted and hidden.
// Hidden-but-mounted views still evaluate their bodies on every `objectWillChange` from the shared
// databases, which is exactly the cost we do not want to pay.
//
// Ownership rule: MainWindowView holds these with `@State`, NOT `@StateObject`. `@State` keeps the
// object alive for the window's lifetime without subscribing to it, so a filter change never
// invalidates the window — only the screen that actually observes it re-renders, and only while it
// is on screen.
//
// What belongs here: where you were and what you asked for (navigation, filters, sort, selection,
// the loaded page). What does not: transient UI (open sheets, alerts, hovered row, in-flight tasks)
// — that *should* reset when you come back.

// MARK: - Why the screens are Equatable
//
// The rail screens are built inside MainWindowView.body with fresh closures every time
// (`onGameSelected: { game in openGameInTab(game) }`). A new closure is never equal to the old one,
// so SwiftUI cannot tell the view is unchanged and re-runs its body on EVERY window render — and the
// window renders whenever anything it observes publishes, engine ticks included. Measured idle, that
// was rebuilding the whole ledger 2–10× a second, ~46 rows each time, with nobody touching the app.
//
// All of a screen's mutable data lives in its state object, which the screen observes directly. So a
// screen is "unchanged" exactly when its state object is the same instance: declaring that and
// wrapping the screen in `.equatable()` lets SwiftUI skip the parent-driven rebuilds while still
// re-rendering on real state changes.
//
// The captured closures stay correct: @State/@StateObject/@ObservedObject read through their storage
// box, not through the captured struct copy, so an older closure still sees current values.

@MainActor
final class DatabaseBrowserState: ObservableObject {
    /// The module opens on the shelf, not inside a database.
    @Published var navigation: DatabaseBrowserView.Navigation = .root

    /// On-disk store size, e.g. "84 MB". Stat'ed once on first appear — reading it per render would
    /// put file IO in the view body.
    @Published var storeSizeText: String?

    /// Per-folder game counts. `gamesInFolderCount` is an unindexed fetchCount over a relationship,
    /// and the shelf and the switcher both want one per database — called from a body it ran on every
    /// evaluation, which is what made the switcher popover crawl open.
    @Published var folderCounts: [UUID: Int] = [:]

    /// Newest `dateAdded` per database — the shelf card's "last changed" note. GameFolder has no
    /// dateModified, so the most recent game standing in for it is the honest signal, and it is what
    /// actually changes when you import.
    @Published var folderLastChanged: [UUID: Date] = [:]

    /// Same idea for the All Games card — newest game anywhere in the library.
    @Published var libraryLastChanged: Date?

    /// The library revision the counts above were computed at. Recounting costs 40–90 ms (unindexed
    /// relationship predicates over every database), so it must happen when the library actually
    /// changes — not on every appear, which put that stall on the screen-switch path.
    var countsRevision: Int?
    @Published var selectedGameIds: Set<UUID> = []
    @Published var selectedGame: GameRecord?
    @Published var rootSearchText = ""
    @Published var sidebarCollapsed = false

    // Filter panel — the pending values the user is editing.
    @Published var filterWhite: String = ""
    @Published var filterBlack: String = ""
    @Published var filterResult: String? = nil
    @Published var filterWhiteEloRange: ClosedRange<Double> = 0...3000
    @Published var filterBlackEloRange: ClosedRange<Double> = 0...3000
    @Published var filterDateFrom: String = ""
    @Published var filterDateTo: String = ""
    @Published var filterEvent: String = ""
    @Published var filterOpening: String = ""

    /// What the current query actually uses.
    @Published var appliedFilter = GameFilter()

    @Published var sortColumn: DatabaseBrowserView.SortColumn = .date
    @Published var sortAscending = false

    // The loaded page. Retaining these is what makes coming back instant: `onAppear` only refetches
    // when `cachedGames` is empty. They are the same SwiftData objects the context already holds, so
    // keeping references costs a pointer each, not a copy.
    @Published var cachedGames: [GameRecord] = []
    @Published var totalCount: Int = 0
    @Published var dbOffset: Int = 0
    @Published var allExhausted = false
}

@MainActor
final class ChessComBrowserState: ObservableObject {
    @Published var selectedGameIds: Set<UUID> = []
    @Published var lastSelectedGame: GameRecord?
    @Published var cachedRatings: [String: Int] = [:]

    @Published var sortColumn: ChessComBrowserView.SortColumn = .date
    @Published var sortAscending = false
    @Published var sortedGames: [GameRecord] = []

    @Published var filterTimeControl: String = "All"
    @Published var filterResult: String = "All"
    @Published var filterColor: String = "All"
    @Published var filterOpening: String = ""
    @Published var filterDateFrom: Date? = nil
    @Published var filterDateTo: Date? = nil
    @Published var filterSource: String = "All"

    @Published var cachedGames: [GameRecord] = []
    @Published var totalGameCount: Int = 0
    @Published var dbOffset: Int = 0
    @Published var allDbGamesExhausted = false
}

@MainActor
final class RepertoireBrowserState: ObservableObject {
    @Published var shelfFilter: RepertoireBrowserView.ShelfFilter = .all
    @Published var searchText = ""
    @Published var selectedRepertoire: Repertoire?
    @Published var knowledge: [UUID: RepertoireKnowledge] = [:]
    @Published var forecastBuckets: [Int] = Array(repeating: 0, count: 7)
}

// MARK: - Equatable conformances (see the note above)

extension DatabaseBrowserView: Equatable {
    nonisolated public static func == (lhs: DatabaseBrowserView, rhs: DatabaseBrowserView) -> Bool {
        lhs.state === rhs.state
    }
}

extension ChessComBrowserView: Equatable {
    nonisolated public static func == (lhs: ChessComBrowserView, rhs: ChessComBrowserView) -> Bool {
        lhs.state === rhs.state
    }
}

extension RepertoireBrowserView: Equatable {
    /// The pending-new-repertoire flag is compared too: it arrives as a Binding from the window and
    /// is consumed by an onChange, which only fires if the view actually re-renders.
    nonisolated public static func == (lhs: RepertoireBrowserView, rhs: RepertoireBrowserView) -> Bool {
        lhs.browserState === rhs.browserState && lhs.pendingNewRepertoire == rhs.pendingNewRepertoire
    }
}
