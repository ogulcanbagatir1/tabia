import SwiftUI
import CoreText
import AppKit

// MARK: - The Annotator — theme layer (from tokens.json)
//
// Two modes share one palette split: readingRoom (light) and nightStudy (dark).
// Every token below is adaptive (light value / dark value) via DS.adaptive, EXCEPT the
// board — it is sepia paper in both modes and must never be recolored by the theme.
//
// This is the canonical color/type/metric API. Legacy `DS`/`dsXxx` names in
// DesignSystem.swift are remapped onto these during the migration and will be swept away.

extension DS {

    // MARK: Ground & surfaces
    /// Window ground — paper #F4EFE3 / night #1C1811
    static let paper        = adaptive(light: 0xF4EFE3, dark: 0x1C1811)
    /// Cards, review panels, notable-game cards — #EFE8D6 / #241E14
    static let paperRaised  = adaptive(light: 0xEFE8D6, dark: 0x241E14)
    /// Titlebar, status bar, sheet headers — #EDE6D2 / #211C13
    static let chrome       = adaptive(light: 0xEDE6D2, dark: 0x211C13)
    /// Inputs, eval chips, graph background — #F7F1E1 / #241E14
    static let fieldBg      = adaptive(light: 0xF7F1E1, dark: 0x241E14)
    /// Row/list hover — #ECE4CD / #241E14
    static let hoverWash    = adaptive(light: 0xECE4CD, dark: 0x241E14)
    /// Selected row / active card — #ECE4CD / #2A2317
    static let selectedWash = adaptive(light: 0xECE4CD, dark: 0x2A2317)
    /// Current move highlight in move lists — #E7DDC0 / #3F3624
    static let selectedMove = adaptive(light: 0xE7DDC0, dark: 0x3F3624)
    /// Empty bar/track fills — #E2D8BE / #2A2418
    static let trackBg      = adaptive(light: 0xE2D8BE, dark: 0x2A2418)
    /// Black side of W/D/L + eval-bar well — #2E271C / #0F0C08
    static let deepWell     = adaptive(light: 0x2E271C, dark: 0x0F0C08)

    // MARK: Lines & borders
    /// Every 1px rule — #D9CFB8 / #3A3222
    static let hairline     = adaptive(light: 0xD9CFB8, dark: 0x3A3222)
    /// Input borders, secondary-button borders, W/D/L bar frame — #B5A98D / #4A4130
    static let borderStrong = adaptive(light: 0xB5A98D, dark: 0x4A4130)
    /// Chip/badge/segmented borders — #C9BB9C / #4A4130
    static let borderChip   = adaptive(light: 0xC9BB9C, dark: 0x4A4130)
    /// 1px window outline — #2A2117 / #0A0805
    static let windowBorder = adaptive(light: 0x2A2117, dark: 0x0A0805)

    // MARK: Text / ink
    /// Primary text, filled controls, active segment bg — ink #1C1710 / paperText #EDE6DA
    static let ink    = adaptive(light: 0x1C1710, dark: 0xEDE6DA)
    /// Secondary text — #6B6050 / #A99C82
    static let ink60  = adaptive(light: 0x6B6050, dark: 0xA99C82)
    /// Captions, section labels — #8A7E6B / #857A63
    static let ink40  = adaptive(light: 0x8A7E6B, dark: 0x857A63)
    /// Placeholders, faintest text, disabled — #A79A80 / #6B6050
    static let ink25  = adaptive(light: 0xA79A80, dark: 0x6B6050)
    /// Bright data text (result chips) — #1C1710 / #D8CFBA
    static let inkData = adaptive(light: 0x1C1710, dark: 0xD8CFBA)
    /// Engine PV lines, checkbox labels — #6B6050 / #C4B99F
    static let inkPV  = adaptive(light: 0x6B6050, dark: 0xC4B99F)
    /// Legible text ON an ink-filled control / active segment — paper / night
    static let onInk  = adaptive(light: 0xF4EFE3, dark: 0x1C1811)

    // MARK: The one red pen
    /// Primary button fills (same in both modes) — #9E2B25
    static let redInk   = Color(hex: 0x9E2B25)
    /// Accent on surfaces: active tab underline, due counts, marks, logo dot — #9E2B25 / #C25048 (lifted)
    static let redAccent = adaptive(light: 0x9E2B25, dark: 0xC25048)
    /// Text/glyph on a red fill.
    static let onRed = Color(hex: 0xF7F1E1)

    // MARK: Board — sepia paper, NEVER themed by mode
    static let boardLight    = Color(hex: 0xF0E6CF)
    static let boardDark     = Color(hex: 0xA98F6C)
    static let boardLastLight = Color(hex: 0xE7CF8E)
    static let boardLastDark  = Color(hex: 0xC3A566)
    static let boardWhitePiece = Color(hex: 0xFAF5E8)
    static let boardBlackPiece = Color(hex: 0x241C12)

    // MARK: Move quality (light / dark pairs) — marks are typographic (!! ! □ ?! ? ??)
    static let qBrilliant  = adaptive(light: 0x1E7A5A, dark: 0x3FA97C)
    static let qBest       = adaptive(light: 0x4E7A34, dark: 0x8FB35B)
    static let qBook       = adaptive(light: 0x8A6F4D, dark: 0xB29A73)
    static let qInaccuracy = adaptive(light: 0xC08A1E, dark: 0xD9A43C)
    static let qMistake    = adaptive(light: 0xBC5A22, dark: 0xD07A3E)
    static let qBlunder    = adaptive(light: 0x9E2B25, dark: 0xC4534A)

    // MARK: Semantic
    static let semWin     = adaptive(light: 0x4E7A34, dark: 0x8FB35B)
    static let semLoss    = adaptive(light: 0x9E2B25, dark: 0xC4534A)
    static let semDraw    = adaptive(light: 0x8A7E6B, dark: 0xA99C82)
    /// Gap badges, indexing, sync-in-progress, deviations.
    static let semWarning = adaptive(light: 0xC08A1E, dark: 0xD9A43C)
    /// Engine-running dot (pulses), connected dot.
    static let semOnline  = adaptive(light: 0x1E7A5A, dark: 0x3FA97C)

    // MARK: W/D/L monochrome bars (paper → ink stack, never traffic-light)
    static let wdlWin   = adaptive(light: 0xF7F1E1, dark: 0xEDE6DA)
    static let wdlDraw  = adaptive(light: 0xC9BB9C, dark: 0x6B6050)
    static let wdlLoss  = adaptive(light: 0x3A3226, dark: 0x0F0C08)
    static let wdlFrame = adaptive(light: 0xB5A98D, dark: 0x4A4130)

    // MARK: Traffic lights
    static let trafficClose = Color(hex: 0xD3766A)
    static let trafficMin   = Color(hex: 0xD9B36A)
    static let trafficZoom  = Color(hex: 0x8FAE7F)

    // MARK: Metrics — radii (4/5/7/8/9/11/12/13)
    static let rBar: CGFloat = 4
    static let rChip: CGFloat = 5
    static let rControl: CGFloat = 7
    static let rInput: CGFloat = 8
    static let rCardSmall: CGFloat = 9
    static let rPanel: CGFloat = 11
    static let rCard: CGFloat = 12
    static let rWindow: CGFloat = 13

    // MARK: Metrics — chrome + controls
    static let titlebarHeight: CGFloat = 47
    static let statusBarHeight: CGFloat = 28
    static let toggleWidth: CGFloat = 36
    static let toggleHeight: CGFloat = 21
    static let toggleKnob: CGFloat = 16

    // MARK: adaptive convenience over hex
    static func adaptive(light: UInt, dark: UInt) -> Color {
        adaptive(light: Color(hex: light), dark: Color(hex: dark))
    }
}

// MARK: - Typography — three voices (bundled OFL fonts)

enum AnnFont {

    // Bundled PostScript face names (see Resources/Fonts, instanced from the variable masters).
    private static let faces = [
        "Newsreader-Regular", "Newsreader-Medium", "Newsreader-SemiBold",
        "Newsreader-Italic", "Newsreader-MediumItalic", "Newsreader-SemiBoldItalic",
        "InstrumentSans-SemiBold", "InstrumentSans-Bold",
        "CourierPrime-Regular", "CourierPrime-Bold", "CourierPrime-Italic",
    ]

    /// Register the bundled fonts with CoreText, then verify each PostScript name actually
    /// resolves (Font.custom silently falls back to system on a bad name). Call once at launch.
    static func registerBundledFonts() {
        var registerFailed: [String] = []
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf") else {
                registerFailed.append("\(face) (not in bundle)"); continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                if let e = error?.takeUnretainedValue(),
                   CFErrorGetCode(e) != CTFontManagerError.alreadyRegistered.rawValue {
                    registerFailed.append("\(face): \(CFErrorCopyDescription(e) as String? ?? "?")")
                }
            }
        }
        // Verify the PostScript names resolve to the real faces (not a system fallback).
        let unresolved = faces.filter { NSFont(name: $0, size: 12) == nil }
        NSLog("Annotator fonts — registered \(faces.count - registerFailed.count)/\(faces.count), "
              + "resolved \(faces.count - unresolved.count)/\(faces.count)"
              + (registerFailed.isEmpty ? "" : "; registerFailed=\(registerFailed)")
              + (unresolved.isEmpty ? "" : "; UNRESOLVED=\(unresolved)"))
    }

    // MARK: Serif — Newsreader (display + prose; italic = the commentary voice)
    enum SerifWeight { case regular, medium, semibold }

    static func serif(_ size: CGFloat, _ weight: SerifWeight = .regular, italic: Bool = false) -> Font {
        let name: String
        switch (weight, italic) {
        case (.regular, false):  name = "Newsreader-Regular"
        case (.medium, false):   name = "Newsreader-Medium"
        case (.semibold, false): name = "Newsreader-SemiBold"
        case (.regular, true):   name = "Newsreader-Italic"
        case (.medium, true):    name = "Newsreader-MediumItalic"
        case (.semibold, true):  name = "Newsreader-SemiBoldItalic"
        }
        return .custom(name, fixedSize: size)
    }

    /// The product's speaking voice — italic Newsreader.
    static func voice(_ size: CGFloat, _ weight: SerifWeight = .regular) -> Font {
        serif(size, weight, italic: true)
    }

    // MARK: Label — Instrument Sans (ALWAYS uppercase + letter-spaced; use .annLabel())
    static func label(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "InstrumentSans-Bold" : "InstrumentSans-SemiBold", fixedSize: size)
    }

    // MARK: Mono — Courier Prime (ALL data: SAN, evals, FEN, counts, dates, ECO, status bars)
    static func mono(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        let name = italic ? "CourierPrime-Italic" : (bold ? "CourierPrime-Bold" : "CourierPrime-Regular")
        return .custom(name, fixedSize: size)
    }
}

// MARK: - Label helpers (uppercase + letter-spacing is mandatory for Instrument Sans)

extension Text {
    /// Instrument Sans label: uppercased + letter-spaced. Size 9–11 typical.
    func annLabel(_ size: CGFloat = 10, bold: Bool = true, tracking: CGFloat = 0.12) -> some View {
        self.font(AnnFont.label(size, bold: bold))
            .textCase(.uppercase)
            .tracking(size * tracking)
    }
}
