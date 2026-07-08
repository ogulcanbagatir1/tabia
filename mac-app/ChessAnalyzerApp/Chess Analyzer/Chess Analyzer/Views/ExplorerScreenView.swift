import SwiftUI

/// Standalone Explorer screen (nav tab). The full E1/E2 layout — master stats, your library,
/// and the reference DB with its indexing state — is built in Phase 3. This is the Phase 2 shell.
struct ExplorerScreenView: View {
    var body: some View {
        VStack {
            Spacer()
            AnnEmptyState(
                title: "Opening Explorer",
                sentence: "Master statistics, your own library, and the reference database — the full explorer screen arrives here in Phase 3.",
                dashed: true
            ) {
                Image(systemName: "book.closed").font(.system(size: 34, weight: .light))
            }
            .frame(maxWidth: 440)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.paper)
    }
}
