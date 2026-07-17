import SwiftUI

// MARK: - Board tab (titlebar) — anatomy per TABS-AND-RAIL.md §2.3
// One tab = one board session. Active tab fuses with the content below (content bg + red top edge);
// inactive tabs are quiet with a right hairline. Leading indicator: green pulse (engine live) /
// `‖` (frozen background eval) / amber dot (unsaved).

enum TabLeadingIndicator {
    case none, engineLive, frozen, dirty
}

struct BoardTabView: View {
    let title: String
    let active: Bool
    var indicator: TabLeadingIndicator = .none
    var showClose: Bool = true
    var width: CGFloat = 232
    let onSelect: () -> Void
    var onClose: () -> Void = {}
    var onRename: (String) -> Void = { _ in }

    @State private var hover = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool

    private var activeBg: Color { DS.adaptive(light: 0xF4EFE3, dark: 0x1C1811) }
    private var hoverBg: Color { DS.adaptive(light: 0xE4DBC6, dark: 0x241E14) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                leading
                if editing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(AnnFont.mono(11, bold: true))
                        .foregroundColor(DS.ink)
                        .focused($editFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { editing = false }
                        // Commit on blur (click away) too, so the draft is never silently lost.
                        .onChange(of: editFocused) { _, focused in if !focused && editing { commitRename() } }
                } else {
                    Text(title)
                        .font(AnnFont.mono(11, bold: active))
                        .foregroundColor(active ? DS.ink : DS.ink40)
                        .lineLimit(1)
                        // Focus on the NEXT runloop — the TextField owning $editFocused isn't mounted
                        // in this same tick, so setting focus synchronously here no-ops.
                        .onTapGesture(count: 2) { draft = title; editing = true; DispatchQueue.main.async { editFocused = true } }
                }
                Spacer(minLength: 4)
                if showClose && (active || hover) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DS.ink40)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close tab — ⌘W")
                }
            }
            .padding(.leading, 14).padding(.trailing, 10)
            .frame(width: width, height: DS.titlebarHeight)
            .background(active ? activeBg : (hover ? hoverBg : Color.clear))
            .overlay(alignment: .top) {
                // Inset 2px red top edge marks the active tab.
                if active { Rectangle().fill(DS.redAccent).frame(height: 2) }
            }
            .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: 1) }
            .overlay(alignment: .leading) { if active { Rectangle().fill(DS.hairline).frame(width: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private func commitRename() {
        editing = false
        let name = draft.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { onRename(name) }
    }

    @ViewBuilder private var leading: some View {
        switch indicator {
        case .engineLive: PulsingDot(color: DS.adaptive(light: 0x1E7A5A, dark: 0x1E7A5A), size: 7)
        case .frozen:     Text("‖").font(AnnFont.mono(10, bold: true)).foregroundColor(DS.ink40)
        case .dirty:      Circle().fill(DS.adaptive(light: 0xC08A1E, dark: 0xD9A43C)).frame(width: 6, height: 6)
        case .none:       EmptyView()
        }
    }
}

// MARK: - New-tab button (§2.3)

struct NewTabButton: View {
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.ink60)
                .frame(width: 30, height: 26)
                .background(hover ? DS.adaptive(light: 0xE4DBC6, dark: 0x241E14) : Color.clear,
                           in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.leading, 6)
        .help("New board — ⌘T")
    }
}
