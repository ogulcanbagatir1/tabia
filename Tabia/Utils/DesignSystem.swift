import SwiftUI

// MARK: - Design System

enum DS {
    // MARK: - Colors (Light/Dark adaptive)

    /// Apple system blue accent (#0A84FF dark / #007AFF light)
    static let accent: Color = .dsAccent
    static let accentLight: Color = .dsAccentLight

    /// Surfaces
    static let bg: Color = .dsBg
    static let bgSecondary: Color = .dsBgSecondary
    static let bgTertiary: Color = .dsBgTertiary
    static let bgSurface: Color = .dsBgSurface
    static let bgElevated: Color = .dsBgElevated
    static let bgHover: Color = .dsBgHover

    /// Legacy aliases
    static let card: Color = .dsBgElevated
    static let surfacePrimary = bg
    static let surfaceSecondary = bgSecondary
    static let surfaceElevated = bgElevated
    static let surfaceOverlay = Color.black.opacity(0.4)

    /// Text
    static let textPrimary: Color = .dsTextPrimary
    static let textSecondary: Color = .dsTextSecondary
    static let textTertiary: Color = .dsTextTertiary
    static let textMuted: Color = .dsTextMuted

    /// Borders
    static let border: Color = .dsBorder
    static let borderSubtle: Color = .dsBorderSubtle
    static let separator = border

    // MARK: - Static accent fallbacks (non-adaptive, for programmatic use)

    static let accentStatic = Color(hex: 0x9E2B25)
    static let accentLightStatic = Color(hex: 0x9E2B25, opacity: 0.12)

    /// Evaluation colors — eval bar is paper (white adv) → deep ink (black adv), red hairline at boundary.
    static let evalWhiteWinning = Color(hex: 0xF7F1E1)
    static let evalBlackWinning = Color(hex: 0x1C1710)
    static let evalNeutral = Color(hex: 0x8A7E6B)
    static let evalGameOver = DS.redInk
    static let evalPositive = evalWhiteWinning
    static let evalNegative = evalBlackWinning

    // MARK: - Chess Board Colors (sepia paper — never themed; see DS.board* in Theme.swift)

    static let chessBoardLight = DS.boardLight
    static let chessBoardDark = DS.boardDark
    static let chessHighlight = DS.boardLastLight
    static let chessMoveDot = Color.black.opacity(0.22)

    // MARK: - Move Quality Colors

    static let moveBrilliant = DS.qBrilliant
    static let moveGreat = DS.qBrilliant
    static let moveBest = DS.qBest
    static let moveBook = DS.qBook
    static let moveGood = DS.qBest
    static let moveOkay = DS.qBook
    static let moveNeutral = DS.ink40
    static let moveInaccuracy = DS.qInaccuracy
    static let moveMistake = DS.qMistake
    static let moveBlunder = DS.qBlunder

    // MARK: - Time Control Colors

    static let timeControlBullet = Color(hex: 0xE68C33)
    static let timeControlBlitz = Color(hex: 0x4DB3D9)
    static let timeControlRapid = Color(hex: 0x73AD59)
    static let timeControlDaily = Color(hex: 0x9980D9)

    static func timeControlColor(for timeClass: String) -> Color {
        switch timeClass.lowercased() {
        case "bullet": return timeControlBullet
        case "blitz":  return timeControlBlitz
        case "rapid":  return timeControlRapid
        case "daily":  return timeControlDaily
        default:       return textTertiary
        }
    }

    // MARK: - Semantic Colors

    static let accentGreen = DS.semOnline
    static let accentRed = DS.semLoss
    static let accentOrange = DS.semWarning
    static let accentPurple = DS.ink40
    static let accentTeal = DS.ink40
    static let accentYellow = DS.semWarning

    // MARK: - Chess.com Branding (neutralized into the palette; refine per-screen in Phase 3)

    static let chessComGreen = DS.semOnline
    static let lichessWhite = DS.ink
    static let lichessPurple = DS.ink40

    // MARK: - Accuracy Colors

    static let accuracyGreat = DS.semWin
    static let accuracyGood = DS.qBest
    static let accuracyOkay = DS.semWarning
    static let accuracyPoor = DS.semLoss

    static func accuracyColor(for percentage: Double) -> Color {
        if percentage >= 90 { return accuracyGreat }
        if percentage >= 70 { return accuracyGood }
        if percentage >= 50 { return accuracyOkay }
        return accuracyPoor
    }

    // MARK: - Typography

    // Generic tokens remapped to Annotator voices. Data → Courier Prime, prose/titles → Newsreader.
    // (Per-component voices — incl. Instrument Sans labels — are assigned in Phases 2–3.)
    static let microFont = AnnFont.mono(9)
    static let smallFont = AnnFont.serif(10)
    static let labelFont = AnnFont.serif(12)
    static let titleFont = AnnFont.serif(14, .semibold)
    static let headingFont = AnnFont.serif(22, .semibold)
    static let bodyFont = AnnFont.serif(13)
    static let captionFont = AnnFont.serif(11)
    static let monoFont = AnnFont.mono(13)
    static let monoSmall = AnnFont.mono(11)
    static let monoBold = AnnFont.mono(13, bold: true)

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32
    static let spacingXXXL: CGFloat = 48

    // MARK: - Corner Radii

    // Remapped to the Annotator radius scale (4/5/7/8/9/11/12/13).
    static let radiusSM: CGFloat = 7
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 12
    static let radiusXL: CGFloat = 13

    // MARK: - Layout Constants

    static let iconRailWidth: CGFloat = 56
    static let sidebarWidth: CGFloat = 280
    static let rightPanelWidth: CGFloat = 300

    // MARK: - Animations

    static let pieceSlide = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let quickFade = Animation.easeInOut(duration: 0.15)
    static let evalTransition = Animation.easeInOut(duration: 0.5)
}

// MARK: - Adaptive Color Helper

extension DS {
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    init(white: Double) {
        self.init(red: white, green: white, blue: white)
    }
}

// MARK: - Runtime Color Definitions

// Legacy DS color names now resolve to Annotator tokens (see Theme.swift), so every existing
// screen reskins to paper/ink/red in both modes. Phase 3 migrates call sites to the new names.
extension Color {
    static let dsAccent        = DS.redAccent
    static let dsAccentLight    = DS.redAccent.opacity(0.12)
    static let dsBg             = DS.paper
    static let dsBgSecondary    = DS.paperRaised
    static let dsBgTertiary     = DS.fieldBg
    static let dsBgSurface      = DS.paperRaised
    static let dsBgElevated     = DS.paperRaised
    static let dsBgHover        = DS.hoverWash
    static let dsTextPrimary    = DS.ink
    static let dsTextSecondary  = DS.ink60
    static let dsTextTertiary   = DS.ink40
    static let dsTextMuted      = DS.ink25
    static let dsBorder         = DS.hairline
    static let dsBorderSubtle   = DS.hairline
}

// MARK: - Glass Design Constants

extension DS {
    // Legacy "glass" line/shadow tokens, remapped to Annotator hairlines + soft shadow.
    static let glassBorder = DS.hairline
    static let glassBorderOuter = DS.hairline
    /// Every 1px rule.
    static let glassSeparator = DS.hairline
    static let glassHighlight = DS.hairline
    /// Soft shadow (depth = hairlines + soft shadow only).
    static let glassShadowColor = DS.adaptive(light: Color.black.opacity(0.10), dark: Color.black.opacity(0.40))
}

// MARK: - View Extensions

extension View {
    // MARK: Glass Modifiers

    /// Glass panel — frosted material with subtle border and shadow, for floating cards
    func glassPanel(radius: CGFloat = DS.radiusLG) -> some View {
        self
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
            .shadow(color: DS.glassShadowColor, radius: 10, x: 0, y: 4)
    }

    /// Sidebar ground — flat chrome surface.
    func glassSidebar() -> some View {
        self.background(DS.chrome)
    }

    /// Inline card — flat raised paper + 1px hairline.
    func glassCard(radius: CGFloat = DS.radiusMD) -> some View {
        self
            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
    }

    /// Glass separator line — replaces solid border dividers
    func glassDivider(edge: Edge = .bottom) -> some View {
        self.overlay(alignment: edge == .bottom ? .bottom : edge == .top ? .top : edge == .leading ? .leading : .trailing) {
            if edge == .bottom || edge == .top {
                Rectangle().fill(DS.glassSeparator).frame(height: 1)
            } else {
                Rectangle().fill(DS.glassSeparator).frame(width: 1)
            }
        }
    }

    // MARK: Legacy Modifiers (updated with glass styling)

    func panelStyle() -> some View {
        self.glassPanel()
    }

    func sectionHeader() -> some View {
        self
            .font(DS.titleFont)
            .foregroundColor(DS.textPrimary)
    }

    func sectionLabel() -> some View {
        self
            .font(AnnFont.label(10))
            .foregroundColor(DS.ink40)
            .kerning(1.4)
            .textCase(.uppercase)
    }

    func cardStyle(radius: CGFloat = DS.radiusMD) -> some View {
        self.glassCard(radius: radius)
    }

    func pillStyle(isActive: Bool, activeColor: Color = DS.ink) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(isActive ? activeColor : Color.clear)
            .foregroundColor(isActive ? DS.onInk : DS.ink60)
            .font(AnnFont.label(10))
            .textCase(.uppercase)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Color.clear : DS.borderChip, lineWidth: 1)
            )
    }

    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: Glass Button Modifiers

    /// Primary button — the one red pen (flat red fill, no glow).
    func glassButtonPrimary() -> some View {
        self
            .font(AnnFont.label(11)).textCase(.uppercase)
            .foregroundStyle(DS.onRed)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(DS.redInk, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
    }

    /// Secondary button — bordered, ink text.
    func glassButtonSecondary() -> some View {
        self
            .font(AnnFont.label(11)).textCase(.uppercase)
            .foregroundStyle(DS.ink)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
    }

    /// Destructive button — red fill.
    func glassButtonDestructive() -> some View {
        self
            .font(AnnFont.label(11)).textCase(.uppercase)
            .foregroundStyle(DS.onRed)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(DS.redInk, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
    }

    /// Small bordered button.
    func glassButtonSmall() -> some View {
        self
            .font(AnnFont.label(10)).textCase(.uppercase)
            .foregroundStyle(DS.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rChip, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
    }

    /// Small red button.
    func glassButtonSmallPrimary() -> some View {
        self
            .font(AnnFont.label(10)).textCase(.uppercase)
            .foregroundStyle(DS.onRed)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(DS.redInk, in: RoundedRectangle(cornerRadius: DS.rChip, style: .continuous))
    }

    /// Icon button — flat chrome + hairline.
    func glassIconButton(size: CGFloat = 28) -> some View {
        self
            .frame(width: size, height: size)
            .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    /// Toggle — 36×21, red when on, borderStrong when off, 16px knob.
    func glassToggle(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? DS.redInk : DS.borderStrong)
                .frame(width: DS.toggleWidth, height: DS.toggleHeight)

            Circle()
                .fill(DS.onRed)
                .frame(width: DS.toggleKnob, height: DS.toggleKnob)
                .padding(.horizontal, 2.5)
        }
        .animation(.easeOut(duration: 0.17), value: isOn)
    }
}

// MARK: - Glass Button Styles

// MARK: - Glass Background Views

// Annotator grounds — flat paper (Reading Room) / night (Night Study). No blur, no gradients.
// "The paper board never changes; only the lamp does." Columns are separated by 1px hairlines.

/// Window ground.
struct GlassBackground: View {
    var screen: AppScreen = .analysis
    var body: some View { DS.paper.ignoresSafeArea() }
}

/// Full-width content area ground (Database, Games, Settings).

/// Engine content ground.

/// Side panel / column ground.
struct GlassPanelBackground: View {
    var body: some View { DS.paper }
}

/// Board area ground.
struct GlassBoardAreaBackground: View {
    var body: some View { DS.paper }
}

/// Icon rail / chrome ground (legacy rail — superseded by the masthead in Phase 2).
struct GlassRailBackground: View {
    var body: some View { DS.chrome }
}

// MARK: - Lazy View (defers body evaluation)

/// ButtonStyle: bordered secondary (flat Annotator).
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AnnFont.label(11)).textCase(.uppercase)
            .foregroundStyle(DS.ink)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(DS.chrome, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// ButtonStyle: the one red pen — flat red fill.
struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AnnFont.label(11)).textCase(.uppercase)
            .foregroundStyle(DS.onRed)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(DS.redInk, in: RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
