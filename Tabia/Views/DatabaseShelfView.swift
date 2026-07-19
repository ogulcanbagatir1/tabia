import SwiftUI

// MARK: - Database shelf (D6)
//
// The Database module's root: a full-width page of typographic cards, no sidebar. A 300px panel
// could never be filled by one to three databases, so the space goes to the cards instead.

/// Badge in a shelf card's title row. Absent for ordinary databases.
enum ShelfBadge {
    case synced
    case readOnly

    var text: String {
        switch self {
        case .synced:   return "SYNCED"
        case .readOnly: return "READ-ONLY"
        }
    }

    var foreground: Color { self == .synced ? DS.greenOk : DS.ink40 }
    var border: Color { self == .synced ? DS.greenOkBorder : DS.borderChip }
}

/// One database on the shelf. The whole card is the click target.
struct ShelfCard: View {
    let name: String
    var badge: ShelfBadge? = nil
    /// One user-authored sentence. Rendered only when present — never filler.
    var summary: String? = nil
    /// Nil until the count has been fetched. Navigation never waits for it; the card renders with a
    /// placeholder and fills in when the number arrives.
    let gameCount: Int?
    /// Freshness note in the footer, e.g. "CREATED 3 DAYS AGO".
    var footnote: String? = nil
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(AnnFont.serif(21, .semibold))
                        .foregroundColor(DS.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let badge {
                        Text(badge.text)
                            .font(AnnFont.mono(9.5, bold: true)).tracking(9.5 * 0.08)
                            .foregroundColor(badge.foreground)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(badge.border, lineWidth: 1))
                    }
                }

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(AnnFont.voice(13.5))
                        .foregroundColor(DS.ink60)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                (Text(gameCount.map { $0.formatted() } ?? "—").font(AnnFont.mono(11, bold: true))
                 + Text(" GAMES").font(AnnFont.mono(11)))
                    .foregroundColor(gameCount == nil ? DS.ink25 : DS.inkSoft)

                // Pin the footer to the bottom so every card's rule sits on the same line, whether or
                // not it has a description.
                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline) {
                    Text(footnote ?? "")
                        .font(AnnFont.mono(9.5))
                        .foregroundColor(DS.ink25)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("OPEN →")
                        .font(AnnFont.label(10)).tracking(10 * 0.1)
                        .foregroundColor(DS.redAccent)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(DS.trackBg).frame(height: 1) }
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .background(hover ? DS.hoverWash : DS.paperRaised,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1))
            .shadow(color: hover ? Color.black.opacity(0.12) : .clear, radius: 12, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Database switcher (D7)

/// One row in the switcher popover.
struct SwitcherEntry: Identifiable {
    let id: String
    let name: String
    let count: Int
    var readOnly = false
    let isCurrent: Bool
    let select: () -> Void
}

/// Lets ⌘⇧O open the switcher without the owning screen observing it. The screen holds this with
/// `@State` (kept alive, not subscribed), so bumping it re-renders only the pill.
@MainActor
final class SwitcherTrigger: ObservableObject {
    @Published var pulse = 0
    func fire() { pulse &+= 1 }
}

/// The database name as a dropdown — the ledger's primary navigation, so you jump sideways without
/// going back to the shelf first.
///
/// This is its own view for a performance reason: the open/closed flag used to live on the browser,
/// and toggling it re-rendered the entire module — a fifty-row table inside a GeometryReader — every
/// time the popover animated. Here the state change is contained to the pill.
struct DatabaseSwitcherPill: View {
    let title: String
    let entries: [SwitcherEntry]
    let onNewDatabase: () -> Void
    @ObservedObject var trigger: SwitcherTrigger

    @State private var showing = false

    var body: some View {
        Button(action: { showing.toggle() }) {
            HStack(spacing: 6) {
                Text(title)
                    .font(AnnFont.serif(17.5, .semibold)).foregroundColor(DS.ink)
                    .lineLimit(1)
                Text("▾").font(AnnFont.mono(9)).foregroundColor(DS.ink60)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(DS.hoverWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(DS.borderChip, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch database — ⌘⇧O")
        .onChange(of: trigger.pulse) { _, _ in showing.toggle() }
        .popover(isPresented: $showing, arrowEdge: .bottom) { popoverBody }
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                Button(action: { showing = false; entry.select() }) {
                    HStack(spacing: 6) {
                        Text(entry.isCurrent ? "✓" : " ")
                            .font(AnnFont.mono(10)).foregroundColor(DS.redAccent)
                            .frame(width: 12, alignment: .leading)
                        Text(entry.name)
                            .font(AnnFont.serif(15, entry.isCurrent ? .semibold : .regular))
                            .foregroundColor(entry.isCurrent ? DS.ink : DS.inkSoft)
                            .lineLimit(1)
                        if entry.readOnly {
                            Text("READ-ONLY")
                                .font(AnnFont.mono(8.5)).foregroundColor(DS.ink40)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(DS.borderChip, lineWidth: 1))
                        }
                        Spacer(minLength: 8)
                        Text(entry.count.formatted())
                            .font(AnnFont.mono(10)).foregroundColor(DS.ink40)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Rectangle().fill(DS.trackBg).frame(height: 1).padding(.vertical, 6)

            Button(action: { showing = false; onNewDatabase() }) {
                Text("＋ NEW DATABASE")
                    .font(AnnFont.mono(10)).foregroundColor(DS.ink60)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 320)
        .background(DS.fieldBg)
    }
}

/// A ledger row's chrome — zebra stripe, hover wash, rounded inset.
///
/// The hover flag lives here rather than on the browser. As a `@State` on the parent, every mouse
/// move across the table invalidated the whole module: fifty rows plus the header, rebuilt per
/// pointer event. Contained here, a hover repaints one row.
struct LedgerRowChrome<Content: View>: View {
    let isAlternate: Bool
    @ViewBuilder let content: () -> Content

    @State private var hover = false

    var body: some View {
        content()
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hover ? DS.hoverWash : (isAlternate ? DS.paperRaised.opacity(0.45) : Color.clear))
            )
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

// MARK: - Ledger table geometry (D7)

/// Column widths for the ledger table.
///
/// The spec states them as a CSS grid — `1.05fr 1.05fr 62px 1.5fr 1.05fr 88px 26px 90px`, gap 12.
/// SwiftUI has no `fr`, so the flexible share is divided once here and handed to both the header and
/// the rows; computing it in two places is how header/row alignment drifts.
struct LedgerColumns {
    let white: CGFloat
    let black: CGFloat
    let result: CGFloat
    let opening: CGFloat
    let event: CGFloat
    let date: CGFloat
    let mark: CGFloat
    let action: CGFloat

    static let gap: CGFloat = 12
    static let hPadding: CGFloat = 28

    init(totalWidth: CGFloat) {
        result = 62
        date = 88
        mark = 26
        action = 90

        let fixed = result + date + mark + action
        let gaps = Self.gap * 7
        let flexible = max(160, totalWidth - fixed - gaps - Self.hPadding * 2)
        let unit = flexible / 4.65      // 1.05 + 1.05 + 1.5 + 1.05

        white = unit * 1.05
        black = unit * 1.05
        opening = unit * 1.5
        event = unit * 1.05
    }
}

/// The trailing dashed cell that starts a new database.
struct NewShelfCard: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("+ New database")
                    .font(AnnFont.serif(19, .medium))
                    .foregroundColor(DS.ink60)
                Text("IMPORT A PGN OR START EMPTY")
                    .font(AnnFont.mono(9.5))
                    .foregroundColor(DS.ink25)
            }
            .frame(maxWidth: .infinity, minHeight: 158)
            .background(hover ? DS.paperRaised : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.borderChip, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
