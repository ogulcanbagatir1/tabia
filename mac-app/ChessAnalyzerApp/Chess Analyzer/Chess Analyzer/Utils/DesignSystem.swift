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

    static let accentStatic = Color(hex: 0x0A84FF)
    static let accentLightStatic = Color(hex: 0x007AFF)

    /// Evaluation colors
    static let evalWhiteWinning = Color(hex: 0xECECEC)
    static let evalBlackWinning = Color(hex: 0x262626)
    static let evalNeutral = Color(white: 0.50)
    static let evalGameOver = accentStatic
    static let evalPositive = evalWhiteWinning
    static let evalNegative = evalBlackWinning

    // MARK: - Chess Board Colors

    static let chessBoardLight = Color(hex: 0xEBECD0)
    static let chessBoardDark = Color(hex: 0x739552)
    static let chessHighlight = Color(hex: 0xF6F669)
    static let chessMoveDot = Color.black.opacity(0.25)

    // MARK: - Move Quality Colors

    static let moveBrilliant = Color(hex: 0x1ABF66)
    static let moveGreat = Color(hex: 0x3387DE)
    static let moveBest = Color(hex: 0x8CCC59)
    static let moveBook = Color(hex: 0xA68C66)
    static let moveGood = Color(red: 0.40, green: 0.70, blue: 0.85)
    static let moveOkay = Color(red: 0.56, green: 0.36, blue: 0.82)
    static let moveNeutral = Color(red: 0.56, green: 0.56, blue: 0.58)
    static let moveInaccuracy = Color(hex: 0xEDA619)
    static let moveMistake = Color(hex: 0xE87623)
    static let moveBlunder = Color(hex: 0xD62E2E)

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

    static let accentGreen = Color(hex: 0x30D158)
    static let accentRed = DS.adaptive(
        light: Color(hex: 0xFF3B30),
        dark: Color(hex: 0xFF453A)
    )
    static let accentOrange = Color(hex: 0xFF9F0A)
    static let accentPurple = Color(hex: 0xBF5AF2)
    static let accentTeal = Color(hex: 0x64D2FF)
    static let accentYellow = Color(hex: 0xFFD60A)

    // MARK: - Chess.com Branding

    static let chessComGreen = Color(hex: 0x73AD59)
    static let lichessWhite = Color(hex: 0xFAFAFA)
    static let lichessPurple = Color(hex: 0x629924)

    // MARK: - Accuracy Colors

    static let accuracyGreat = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let accuracyGood = Color(red: 0.95, green: 0.75, blue: 0.15)
    static let accuracyOkay = Color(red: 0.95, green: 0.55, blue: 0.15)
    static let accuracyPoor = Color(red: 0.90, green: 0.25, blue: 0.20)

    static func accuracyColor(for percentage: Double) -> Color {
        if percentage >= 90 { return accuracyGreat }
        if percentage >= 70 { return accuracyGood }
        if percentage >= 50 { return accuracyOkay }
        return accuracyPoor
    }

    // MARK: - Typography

    static let microFont = Font.system(size: 9)
    static let smallFont = Font.system(size: 10)
    static let labelFont = Font.system(size: 12)
    static let titleFont = Font.system(size: 14, weight: .semibold)
    static let headingFont = Font.system(size: 22, weight: .bold)
    static let bodyFont = Font.system(size: 13)
    static let captionFont = Font.system(size: 11)
    static let monoFont = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoBold = Font.system(size: 13, weight: .semibold, design: .monospaced)

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32
    static let spacingXXXL: CGFloat = 48

    // MARK: - Corner Radii

    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 12
    static let radiusXL: CGFloat = 20

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

extension Color {
    static let dsAccent = DS.adaptive(
        light: Color(hex: 0x007AFF),
        dark: Color(hex: 0x0A84FF)
    )
    static let dsAccentLight = DS.adaptive(
        light: Color(hex: 0x007AFF).opacity(0.12),
        dark: Color(hex: 0x0A84FF).opacity(0.12)
    )
    static let dsBg = DS.adaptive(
        light: Color.white.opacity(0.65),
        dark: Color(hex: 0x1C1C1E, opacity: 0.55)
    )
    static let dsBgSecondary = DS.adaptive(
        light: Color(hex: 0xF5F5F7, opacity: 0.55),
        dark: Color(hex: 0x2C2C2E, opacity: 0.45)
    )
    static let dsBgTertiary = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.06),
        dark: Color(hex: 0xFFFFFF, opacity: 0.08)
    )
    static let dsBgSurface = DS.adaptive(
        light: Color(hex: 0xF0F0F2, opacity: 0.50),
        dark: Color(hex: 0x242426, opacity: 0.45)
    )
    static let dsBgElevated = DS.adaptive(
        light: Color.white.opacity(0.70),
        dark: Color(hex: 0x323234, opacity: 0.55)
    )
    static let dsBgHover = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.05),
        dark: Color(hex: 0xFFFFFF, opacity: 0.07)
    )
    static let dsTextPrimary = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.85),
        dark: Color(hex: 0xFFFFFF, opacity: 0.92)
    )
    static let dsTextSecondary = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.55),
        dark: Color(hex: 0xFFFFFF, opacity: 0.65)
    )
    static let dsTextTertiary = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.38),
        dark: Color(hex: 0xFFFFFF, opacity: 0.42)
    )
    static let dsTextMuted = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.22),
        dark: Color(hex: 0xFFFFFF, opacity: 0.25)
    )
    static let dsBorder = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.12),
        dark: Color(hex: 0xFFFFFF, opacity: 0.10)
    )
    static let dsBorderSubtle = DS.adaptive(
        light: Color(hex: 0x000000, opacity: 0.06),
        dark: Color(hex: 0xFFFFFF, opacity: 0.06)
    )
}

// MARK: - Glass Design Constants

extension DS {
    /// Glass border — a subtle white/black stroke that catches light
    static let glassBorder = DS.adaptive(
        light: Color.white.opacity(0.7),
        dark: Color.white.opacity(0.12)
    )
    static let glassBorderOuter = DS.adaptive(
        light: Color.black.opacity(0.08),
        dark: Color.black.opacity(0.35)
    )
    /// Glass separator — subtle dividers between sections
    static let glassSeparator = DS.adaptive(
        light: Color.black.opacity(0.12),
        dark: Color.white.opacity(0.10)
    )
    /// Inner glow for glass panels
    static let glassHighlight = DS.adaptive(
        light: Color.white.opacity(0.7),
        dark: Color.white.opacity(0.04)
    )
    /// Glass shadow
    static let glassShadowColor = Color.black.opacity(0.12)
}

// MARK: - View Extensions

extension View {
    // MARK: Glass Modifiers

    /// Glass panel — frosted material with subtle border and shadow, for floating cards
    func glassPanel(radius: CGFloat = DS.radiusLG) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.glassBorderOuter, lineWidth: 0.5)
                    .padding(-0.5)
            )
            .shadow(color: DS.glassShadowColor, radius: 8, x: 0, y: 2)
    }

    /// Glass sidebar — translucent material background for sidebar regions
    func glassSidebar() -> some View {
        self
            .background(.ultraThinMaterial)
    }

    /// Glass card — lighter material for inline cards within a glass sidebar
    func glassCard(radius: CGFloat = DS.radiusMD) -> some View {
        self
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
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
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DS.textTertiary)
            .kerning(0.8)
            .textCase(.uppercase)
    }

    func cardStyle(radius: CGFloat = DS.radiusMD) -> some View {
        self.glassCard(radius: radius)
    }

    func pillStyle(isActive: Bool, activeColor: Color = DS.accentStatic) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(isActive ? activeColor : Color.clear)
            .foregroundColor(isActive ? .white : DS.textSecondary)
            .font(.system(size: 12, weight: .medium))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Color.clear : DS.glassBorder, lineWidth: 0.5)
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

    /// Primary glass button — accent-tinted glass with glow
    func glassButtonPrimary() -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(DS.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: DS.accent.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    /// Secondary glass button — translucent material with border
    func glassButtonSecondary() -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: DS.glassShadowColor, radius: 2, x: 0, y: 1)
    }

    /// Destructive glass button — red-tinted glass
    func glassButtonDestructive() -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(DS.accentRed, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: DS.accentRed.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    /// Small glass button — compact variant for inline use
    func glassButtonSmall() -> some View {
        self
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: DS.glassShadowColor, radius: 1, x: 0, y: 0.5)
    }

    /// Small primary glass button — compact accent variant
    func glassButtonSmallPrimary() -> some View {
        self
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(DS.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: DS.accent.opacity(0.3), radius: 2, x: 0, y: 1)
    }

    /// Glass icon button — for toolbar/icon-only buttons
    func glassIconButton(size: CGFloat = 28) -> some View {
        self
            .frame(width: size, height: size)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .shadow(color: DS.glassShadowColor, radius: 1.5, x: 0, y: 0.5)
    }

    /// Glass toggle — frosted capsule switch
    func glassToggle(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? DS.accent : DS.bgTertiary)
                .background {
                    if !isOn {
                        Capsule().fill(.thinMaterial)
                    }
                }
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? Color.white.opacity(0.2) : DS.glassBorder, lineWidth: 0.5)
                )
                .shadow(color: isOn ? DS.accent.opacity(0.3) : DS.glassShadowColor, radius: 2, x: 0, y: 1)
                .frame(width: 36, height: 20)

            Circle()
                .fill(.white)
                .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 0.5)
                .frame(width: 16, height: 16)
                .padding(.horizontal, 2)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
    }
}

// MARK: - Glass Button Styles

// MARK: - Glass Background Views

/// Window background — dark base with subtle muted gradients (same for all screens)
struct GlassBackground: View {
    var screen: AppScreen = .analysis

    var body: some View {
        ZStack {
            Color(hex: 0x0E0E14)

            // Subtle blue-gray glow top-left
            RadialGradient(
                colors: [Color(hex: 0x1A2030), Color(hex: 0x0E0E14, opacity: 0)],
                center: UnitPoint(x: 0, y: 0),
                startRadius: 0,
                endRadius: 600
            )

            // Subtle purple tint bottom-right
            RadialGradient(
                colors: [Color(hex: 0x221828), Color(hex: 0x0E0E14, opacity: 0)],
                center: UnitPoint(x: 1, y: 1),
                startRadius: 0,
                endRadius: 500
            )

            // Subtle dark blue wash across top
            RadialGradient(
                colors: [Color(hex: 0x161820), Color(hex: 0x0E0E14, opacity: 0)],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 350
            )
        }
        .ignoresSafeArea()
    }
}

/// Full-width content area background (Database, ChessCom, Settings)
struct GlassContentBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.white.opacity(0.047)
            LinearGradient(
                colors: [Color.white.opacity(0.082), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.2)
            )
        }
    }
}

/// Engine content area — slightly dimmer than other screens
struct GlassEngineContentBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.white.opacity(0.031)
            LinearGradient(
                colors: [Color.white.opacity(0.07), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.15)
            )
        }
    }
}

/// Side panel background — blur + #FFFFFF18 + top gradient overlay
struct GlassPanelBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)

            Color.white.opacity(0.094)

            LinearGradient(
                colors: [Color.white.opacity(0.157), Color.white.opacity(0.012)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.35)
            )
        }
    }
}

/// Board area background — blur + #FFFFFF0C + subtle top gradient
struct GlassBoardAreaBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)

            Color.white.opacity(0.047)

            LinearGradient(
                colors: [Color.white.opacity(0.082), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.2)
            )
        }
    }
}

/// Icon rail background — blur + #FFFFFF20 + top gradient
struct GlassRailBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)

            Color.white.opacity(0.08)

            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.01)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.3)
            )
        }
    }
}

// MARK: - Lazy View (defers body evaluation)

struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content { build() }
}

/// ButtonStyle: glass secondary — use with .buttonStyle(GlassButtonStyle())
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: DS.glassShadowColor, radius: 2, x: 0, y: 1)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// ButtonStyle: glass primary — accent-filled glass
struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(DS.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: DS.accent.opacity(0.3), radius: 4, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
