import SwiftUI

// MARK: - Masthead (47px) — wordmark · centered nav tabs (red underline) · right actions

struct MastheadView<Right: View>: View {
    @Binding var active: AppScreen
    let onSelectTab: (AppScreen) -> Void
    let onSettings: () -> Void
    var onEngines: (() -> Void)? = nil
    @ViewBuilder var rightActions: () -> Right

    var body: some View {
        ZStack {
            // Nav tabs — centered in the FULL window width, so they never shift when the
            // per-screen right-actions change width (the side groups are overlaid, not in flow).
            HStack(spacing: 26) {
                ForEach(AppScreen.navTabs, id: \.self) { tab in
                    NavTab(tab: tab, active: active == tab) { onSelectTab(tab) }
                }
            }

            HStack(spacing: 14) {
                // Reserve room for the native traffic lights so the wordmark sits just to their right.
                Color.clear.frame(width: 60, height: 1)

                HStack(spacing: 7) {
                    Image("TabiaMark")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 21, height: 21)
                    (Text("Tabia").foregroundColor(DS.ink) + Text(".").foregroundColor(DS.redAccent))
                        .font(AnnFont.serif(20, .semibold))
                }
                .fixedSize()

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    rightActions()
                    if let onEngines {
                        Button(action: onEngines) {
                            Image(systemName: "cpu")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(DS.ink60)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Engines (⌘E)")
                    }
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(DS.ink60)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings (⌘,)")
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: DS.titlebarHeight)
        .background(DS.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }
}

private struct NavTab: View {
    let tab: AppScreen
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(tab.navLabel.uppercased())
                .font(AnnFont.label(11))
                .tracking(11 * 0.12)
                .foregroundColor(active || hover ? DS.ink : DS.ink40)
                .frame(height: DS.titlebarHeight)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(active ? DS.redAccent : Color.clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Status bar (28px) — mono, left = context truth, right = system truth

struct AnnStatusBar: View {
    var left: String = ""
    var right: String = ""
    /// Optional custom leading/trailing content (overrides the string when provided).
    var leading: AnyView? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let leading { leading } else {
                Text(left).font(AnnFont.mono(9.5)).foregroundColor(DS.ink40).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing { trailing } else {
                Text(right).font(AnnFont.mono(9.5)).foregroundColor(DS.ink40).lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: DS.statusBarHeight)
        .background(DS.chrome)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
    }
}
