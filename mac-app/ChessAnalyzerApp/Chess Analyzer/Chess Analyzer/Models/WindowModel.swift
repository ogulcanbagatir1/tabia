import Foundation
import SwiftUI

// MARK: - Board session (one analysis tab), per TABS-AND-RAIL.md §3.1
// A tab holds an ANALYSIS board only — never a repertoire (those are rail sections). Each session
// stores its own game (as live GameNode tree references, so switching is lossless and instant),
// cursor, orientation, header metadata, dirty flag, and a frozen engine snapshot.

final class BoardSession: ObservableObject, Identifiable {
    let id = UUID()

    // The game — actual node references, swapped in/out of the window's single live GameTree.
    var rootNode: GameNode
    var cursorNode: GameNode

    var isFlipped: Bool = false

    // Header / metadata mirrored from MainWindowView's @State on capture.
    var whiteName = "", blackName = "", whiteRating = "", blackRating = ""
    var event = "", result = ""
    var timeClass: String? = nil
    var openingName: String? = nil
    var openingECO: String? = nil
    var currentGameId: UUID? = nil          // library-match key (§3.7 focus-or-open)

    @Published var title: String = "New board"
    @Published var isDirty: Bool = false
    /// User-set name (double-click rename); overrides the auto-derived title when present.
    var customTitle: String? = nil

    // Frozen engine snapshot so a re-activated tab can show its last eval instantly (§3.2).
    var snapEval: Double? = nil
    var snapDepth: Int = 0
    var snapFEN: String? = nil

    init() {
        let seed = GameTree()
        self.rootNode = seed.root
        self.cursorNode = seed.root
    }

    var isEmpty: Bool { rootNode.children.isEmpty }
}

// MARK: - Persistence payload (§3.5) — open tabs restored across relaunch

struct PersistedTab: Codable {
    var pgn: String = ""
    var cursorPath: [Int] = []      // child-index path root → cursor
    var isFlipped: Bool = false
    var title: String = "New board"
    var customTitle: String? = nil
    var isDirty: Bool = false
    var whiteName = "", blackName = "", whiteRating = "", blackRating = ""
    var event = "", result = ""
    var timeClass: String? = nil
    var openingName: String? = nil
    var openingECO: String? = nil
    var gameId: String? = nil
}

struct PersistedTabSet: Codable {
    var tabs: [PersistedTab] = []
    var activeIndex: Int = 0
}

// MARK: - Window model — the working set of analysis boards (browser-tab style)

final class WindowModel: ObservableObject {
    @Published var sessions: [BoardSession] = [BoardSession()]
    @Published var activeIndex: Int = 0

    /// Session-scoped stack of recently closed tabs (⌘⇧T reopen), ≥5 kept.
    private var closedStack: [BoardSession] = []

    var active: BoardSession {
        sessions[min(max(activeIndex, 0), sessions.count - 1)]
    }

    /// Append a fresh board and make it active. Returns its index.
    @discardableResult
    func newBoard() -> Int {
        let s = BoardSession()
        sessions.append(s)
        activeIndex = sessions.count - 1
        return activeIndex
    }

    /// Close the tab at `index`. Never closes the window — closing the last tab resets it to empty.
    /// Returns true if the tab was removed (caller loads the new active session).
    @discardableResult
    func closeTab(at index: Int) -> Bool {
        guard sessions.indices.contains(index) else { return false }
        let removed = sessions[index]
        if !removed.isEmpty { pushClosed(removed) }

        if sessions.count == 1 {
            // Last tab: reset to a fresh empty board rather than closing the window.
            sessions[0] = BoardSession()
            activeIndex = 0
            return true
        }
        sessions.remove(at: index)
        if activeIndex >= sessions.count { activeIndex = sessions.count - 1 }
        else if index < activeIndex { activeIndex -= 1 }
        return true
    }

    func reopenClosed() -> Bool {
        guard let s = closedStack.popLast() else { return false }
        sessions.append(s)
        activeIndex = sessions.count - 1
        return true
    }

    /// Index of a session already holding the given library game, if any (§3.7 focus-or-open).
    func indexHoldingGame(_ gameId: UUID) -> Int? {
        sessions.firstIndex { $0.currentGameId == gameId }
    }

    private func pushClosed(_ s: BoardSession) {
        closedStack.append(s)
        if closedStack.count > 8 { closedStack.removeFirst(closedStack.count - 8) }
    }
}
