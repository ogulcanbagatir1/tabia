import SwiftUI

/// The shared body of a game table: pinned header, zebra-striped rows, macOS click
/// selection (double-click opens, ⌘ toggles, ⇧ extends from the anchor), infinite-scroll
/// paging and the bottom loading row.
///
/// Columns and context menus stay per-screen — Database shows Event/Site/Opening while
/// Games shows Time/Source/Review — so those come in as builders. Everything else was
/// duplicated verbatim between `DatabaseBrowserView` and `ChessComBrowserView`.
struct GameTableList<Header: View, Row: View, Menu: View>: View {
    let games: [GameRecord]
    @Binding var selectedGameIds: Set<UUID>
    /// Anchor for ⇧-range selection — the last row the user clicked.
    @Binding var selectionAnchor: GameRecord?
    let hasMore: Bool
    let onOpen: (GameRecord) -> Void
    let onLoadMore: () -> Void

    private let header: () -> Header
    private let row: (GameRecord, Bool) -> Row
    private let menu: (GameRecord) -> Menu

    init(games: [GameRecord],
         selectedGameIds: Binding<Set<UUID>>,
         selectionAnchor: Binding<GameRecord?>,
         hasMore: Bool,
         onOpen: @escaping (GameRecord) -> Void,
         onLoadMore: @escaping () -> Void,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder row: @escaping (GameRecord, Bool) -> Row,
         @ViewBuilder menu: @escaping (GameRecord) -> Menu) {
        self.games = games
        self._selectedGameIds = selectedGameIds
        self._selectionAnchor = selectionAnchor
        self.hasMore = hasMore
        self.onOpen = onOpen
        self.onLoadMore = onLoadMore
        self.header = header
        self.row = row
        self.menu = menu
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        row(game, index % 2 == 1)
                            .onTapGesture { handleTap(game) }
                            .contextMenu { menu(game) }
                            .onAppear {
                                // Trigger on the last DISPLAYED row. The list may be sorted
                                // client-side, in which case the store's last row can sit
                                // mid-list and never scroll into view.
                                if game.id == games.last?.id && hasMore { onLoadMore() }
                            }
                    }

                    if hasMore { loadingRow }
                } header: {
                    header()
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(DS.redAccent)
            Text("Loading more games...")
                .font(AnnFont.serif(11))
                .foregroundColor(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onAppear { onLoadMore() }
    }

    private func handleTap(_ game: GameRecord) {
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            onOpen(game)
        }

        if NSEvent.modifierFlags.contains(.command) {
            if selectedGameIds.contains(game.id) {
                selectedGameIds.remove(game.id)
            } else {
                selectedGameIds.insert(game.id)
            }
        } else if NSEvent.modifierFlags.contains(.shift), let anchor = selectionAnchor,
                  let start = games.firstIndex(where: { $0.id == anchor.id }),
                  let end = games.firstIndex(where: { $0.id == game.id }) {
            for i in min(start, end)...max(start, end) {
                selectedGameIds.insert(games[i].id)
            }
        } else {
            selectedGameIds = [game.id]
        }

        selectionAnchor = game
    }
}
