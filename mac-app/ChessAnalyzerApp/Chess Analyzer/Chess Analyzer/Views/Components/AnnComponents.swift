import SwiftUI

// MARK: - The Annotator — component primitives (matches HTML §00 component gallery)
//
// Every control here is built from Theme.swift tokens, so it renders correctly in both
// Reading Room (light) and Night Study (dark). Data is mono (Courier Prime), labels are
// uppercase letter-spaced Instrument Sans, prose/titles are Newsreader.

// MARK: Label text helper

/// Uppercase, letter-spaced Instrument Sans label.
struct AnnLabel: View {
    let text: String
    var size: CGFloat = 10
    var tracking: CGFloat = 0.12
    var bold: Bool = false
    var color: Color = DS.ink40
    init(_ text: String, size: CGFloat = 10, tracking: CGFloat = 0.12, bold: Bool = false, color: Color = DS.ink40) {
        self.text = text; self.size = size; self.tracking = tracking; self.bold = bold; self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(AnnFont.label(size, bold: bold))
            .tracking(size * tracking)
            .foregroundColor(color)
    }
}

// MARK: Live indicator — pulsing dot (scale 1→0.75, opacity 1→0.3, ~1.6s)

struct PulsingDot: View {
    var color: Color = DS.semOnline
    var size: CGFloat = 7
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(on ? 0.75 : 1.0)
            .opacity(on ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: Buttons — one red per screen, max

enum AnnButtonKind { case primary, secondary, disabled }

struct AnnButtonStyle: ButtonStyle {
    var kind: AnnButtonKind = .primary
    var size: CGFloat = 10.5
    var hPad: CGFloat = 13
    var vPad: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        let base = configuration.label
            .font(AnnFont.label(size)).textCase(.uppercase).tracking(size * 0.10)
            .padding(.horizontal, hPad).padding(.vertical, vPad)
        return Group {
            switch kind {
            case .primary:
                base.foregroundStyle(DS.onRed)
                    .background(DS.redInk, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(Color.black.opacity(0.22), lineWidth: 1))
            case .secondary:
                base.foregroundStyle(DS.ink)
                    .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
            case .disabled:
                base.foregroundStyle(DS.ink25)
                    .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
            }
        }
        .brightness(configuration.isPressed && kind != .disabled ? (kind == .primary ? 0.12 : -0.03) : 0)
        .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        .contentShape(Rectangle())
    }
}

/// Red text link — "OPEN IN DATABASE →"
struct AnnLink: View {
    let text: String
    var size: CGFloat = 11
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            AnnLabel(text, size: size, tracking: 0.08, color: DS.redAccent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Segmented control

struct AnnSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let active = opt.value == selection
                Button(action: { selection = opt.value }) {
                    Text(opt.label.uppercased())
                        .font(AnnFont.label(size)).tracking(size * 0.10)
                        .foregroundColor(active ? DS.onInk : DS.ink40)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(active ? DS.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }
}

/// Source chip — active is ink-filled (with optional live dot), others bordered.
struct AnnSourceChip: View {
    let label: String
    var active: Bool = false
    var dot: Color? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let dot { PulsingDot(color: dot, size: 6) }
                Text(label.uppercased()).font(AnnFont.label(10, bold: active)).tracking(1.0)
            }
            .foregroundColor(active ? DS.onInk : DS.ink40)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? DS.ink : Color.clear, in: RoundedRectangle(cornerRadius: DS.rChip + 1, style: .continuous))
            .overlay(active ? nil : RoundedRectangle(cornerRadius: DS.rChip + 1, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Chips & badges

/// Bordered label chip (e.g. MAIN).
struct AnnChip: View {
    let text: String
    var color: Color = DS.ink60
    var border: Color = DS.borderChip
    var dashed: Bool = false
    var mono: Bool = false
    var size: CGFloat = 8.5
    var body: some View {
        Group {
            if mono { Text(text).font(AnnFont.mono(size, bold: true)) }
            else { Text(text.uppercased()).font(AnnFont.label(size, bold: true)).tracking(size * 0.12) }
        }
        .foregroundColor(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: DS.rBar, style: .continuous)
                .strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : []))
        )
    }
}

/// Amber dashed "GAP — NO REPLY YET".
struct AnnGapBadge: View {
    var text: String = "Gap — no reply yet"
    var body: some View { AnnChip(text: text, color: DS.semWarning, border: DS.semWarning, dashed: true) }
}

/// Red due count "8 DUE".
struct AnnDueBadge: View {
    let count: Int
    var body: some View { AnnChip(text: "\(count) DUE", color: DS.redAccent, border: DS.redAccent, mono: true, size: 9.5) }
}

/// ECO code chip "B90".
struct AnnECOChip: View {
    let eco: String
    var body: some View { AnnChip(text: eco, color: DS.ink60, mono: true, size: 10) }
}

/// Result chip "1–0".
struct AnnResultChip: View {
    let text: String
    var body: some View {
        Text(text).font(AnnFont.mono(11, bold: true)).foregroundColor(DS.inkData)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }
}

/// Red "TO MOVE" chip.
struct AnnToMoveChip: View {
    var text: String = "To move"
    var body: some View {
        AnnLabel(text, size: 9.5, tracking: 0.14, bold: true, color: DS.redAccent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.redAccent, lineWidth: 1))
    }
}

// MARK: Move quality

enum AnnMoveQuality: CaseIterable {
    case brilliant, best, book, inaccuracy, mistake, blunder
    var mark: String {
        switch self {
        case .brilliant: return "!!"; case .best: return "!"; case .book: return "□"
        case .inaccuracy: return "?!"; case .mistake: return "?"; case .blunder: return "??"
        }
    }
    var color: Color {
        switch self {
        case .brilliant: return DS.qBrilliant; case .best: return DS.qBest; case .book: return DS.qBook
        case .inaccuracy: return DS.qInaccuracy; case .mistake: return DS.qMistake; case .blunder: return DS.qBlunder
        }
    }
}

/// Typographic quality mark, mono bold + quality color.
struct QualityMark: View {
    let quality: AnnMoveQuality
    var size: CGFloat = 12
    var body: some View {
        Text(quality.mark).font(AnnFont.mono(size, bold: true)).foregroundColor(quality.color)
    }
}

// MARK: Toggle — 36×21, red on / borderStrong off, 16px knob

struct AnnToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? DS.redInk : DS.borderStrong)
                    .frame(width: DS.toggleWidth, height: DS.toggleHeight)
                Circle().fill(DS.onRed)
                    .frame(width: DS.toggleKnob, height: DS.toggleKnob)
                    .padding(.horizontal, 2.5)
            }
            .animation(.easeOut(duration: 0.17), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Checkbox / radio

struct AnnCheckbox: View {
    @Binding var checked: Bool
    let label: String
    var body: some View {
        Button(action: { checked.toggle() }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(checked ? DS.redInk : Color.clear)
                        .frame(width: 15, height: 15)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(checked ? DS.redInk : DS.borderStrong, lineWidth: 1))
                    if checked { Text("✓").font(.system(size: 10, weight: .bold)).foregroundColor(DS.onRed) }
                }
                Text(label.uppercased()).font(AnnFont.mono(11)).foregroundColor(DS.inkPV)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct AnnRadioDot: View {
    var filled: Bool
    var body: some View {
        Circle()
            .fill(filled ? DS.redAccent : Color.clear)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(filled ? DS.redAccent : DS.ink40, lineWidth: 1.5))
    }
}

// MARK: Stepper — bordered − value +

struct AnnStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let onChange: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            stepButton("−") { onChange(max(range.lowerBound, value - step)) }
            Text("\(value)").font(AnnFont.mono(12, bold: true)).foregroundColor(DS.inkData)
                .frame(minWidth: 40).padding(.vertical, 5)
            stepButton("+") { onChange(min(range.upperBound, value + step)) }
        }
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
    }
    private func stepButton(_ s: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(s).font(AnnFont.mono(13, bold: true)).foregroundColor(DS.ink60)
                .frame(width: 30, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: Input

struct AnnSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search…"
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text("⌕").font(AnnFont.mono(12)).foregroundColor(DS.ink25)
            TextField("", text: $text, prompt: Text(placeholder).font(AnnFont.mono(11)).foregroundColor(DS.ink25))
                .textFieldStyle(.plain).font(AnnFont.mono(11)).foregroundColor(DS.ink)
                .focused($focused)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(DS.fieldBg, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
        .onReceive(NotificationCenter.default.publisher(for: .tabiaFocusSearch)) { _ in focused = true }
    }
}

// MARK: W/D/L monochrome bar

struct AnnWDLBar: View {
    let white: Int
    let draw: Int
    let black: Int
    var height: CGFloat = 20
    var labeled: Bool = true

    private var total: Int { max(white + draw + black, 1) }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                seg(Double(white) / Double(total) * w, DS.wdlWin, DS.inkData, white)
                seg(Double(draw) / Double(total) * w, DS.wdlDraw, DS.onInk, draw)
                seg(Double(black) / Double(total) * w, DS.wdlLoss, DS.wdlWin, black)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous).strokeBorder(DS.wdlFrame, lineWidth: 1))
    }
    @ViewBuilder private func seg(_ width: CGFloat, _ bg: Color, _ fg: Color, _ n: Int) -> some View {
        let pct = Int((Double(n) / Double(total) * 100).rounded())
        ZStack {
            bg
            if labeled && width > 26 {
                Text("\(pct)%").font(AnnFont.mono(10, bold: true)).foregroundColor(fg)
            }
        }.frame(width: max(width, 0))
    }
}

// MARK: Eval chip + PV row

struct AnnEvalChip: View {
    let text: String
    var body: some View {
        Text(text).font(AnnFont.mono(11.5, bold: true)).foregroundColor(DS.inkData)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(DS.fieldBg, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }
}

struct AnnPVRow: View {
    let eval: String
    let line: String
    var body: some View {
        HStack(spacing: 10) {
            AnnEvalChip(text: eval)
            Text(line).font(AnnFont.mono(11.5)).foregroundColor(DS.inkPV).lineLimit(1)
        }
    }
}

// MARK: Empty-state pattern — icon → title → one italic sentence → one action

struct AnnEmptyState<Icon: View>: View {
    let icon: Icon
    let title: String
    let sentence: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var dashed: Bool = true

    init(title: String, sentence: String, actionTitle: String? = nil, action: (() -> Void)? = nil,
         dashed: Bool = true, @ViewBuilder icon: () -> Icon) {
        self.icon = icon(); self.title = title; self.sentence = sentence
        self.actionTitle = actionTitle; self.action = action; self.dashed = dashed
    }

    var body: some View {
        VStack(spacing: 8) {
            icon.foregroundColor(DS.ink40)
            Text(title).font(AnnFont.serif(15, .semibold)).foregroundColor(DS.ink)
            Text(sentence).font(AnnFont.voice(12)).foregroundColor(DS.ink60)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AnnButtonStyle(kind: .primary, size: 9.5))
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.rCardSmall, style: .continuous)
                .strokeBorder(DS.borderChip, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : []))
        )
    }
}

// MARK: Sheet scaffold — chrome header + hairline body + right-aligned CANCEL + one red confirm

struct AnnSheet<Body: View>: View {
    let title: String
    var confirmTitle: String = "Confirm"
    var confirmEnabled: Bool = true
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder let content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title).font(AnnFont.serif(15, .semibold)).foregroundColor(DS.ink)
                Spacer()
                Button(action: onCancel) { Text("✕").font(.system(size: 13)).foregroundColor(DS.ink40) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(DS.chrome)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            // Body
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            // Footer
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(AnnButtonStyle(kind: .secondary, size: 9.5))
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(AnnButtonStyle(kind: confirmEnabled ? .primary : .disabled, size: 9.5))
                    .disabled(!confirmEnabled)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(DS.chrome)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
        .background(DS.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 26, x: 0, y: 12)
    }
}
