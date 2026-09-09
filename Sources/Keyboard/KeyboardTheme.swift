import SwiftUI

/// One coherent set of visual tokens for the keyboard and its compact panels.
///
/// Keys stay code-native vectors: gradients, borders and pressed states remain sharp at every
/// iPhone size and do not add bitmap decoding cost to the extension. The matching design
/// handoff lives in `assets/themes/`.
struct KeyboardTheme {
    let id: String
    let displayName: String
    let canvasTop: Color
    let canvasBottom: Color
    let letterKeyFill: Color
    let letterKeyHighlight: Color
    let functionKeyFill: Color
    let functionKeyHighlight: Color
    let keyLabel: Color
    let hintGlyph: Color
    let accent: Color
    /// Readable on top of `accent`.
    let onAccent: Color
    let popupBackground: Color
    let keyBorder: Color
    let keyBorderWidth: CGFloat
    let pressedOverlay: Color
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let glowColor: Color
    let glowRadius: CGFloat

    static let light = KeyboardTheme(
        id: "light",
        displayName: "Light",
        canvasTop: Color(hex: 0xF6F8FB),
        canvasBottom: Color(hex: 0xE8EDF3),
        letterKeyFill: Color(hex: 0xF8FAFC),
        letterKeyHighlight: .white,
        functionKeyFill: Color(hex: 0xD5DCE4),
        functionKeyHighlight: Color(hex: 0xE8EDF2),
        keyLabel: Color(hex: 0x111827),
        hintGlyph: Color(hex: 0x64748B),
        accent: Color(hex: 0x2563EB),
        onAccent: .white,
        popupBackground: .white,
        keyBorder: Color(hex: 0xC9D2DC),
        keyBorderWidth: 0.75,
        pressedOverlay: Color.black.opacity(0.14),
        shadowColor: Color.black.opacity(0.18),
        shadowRadius: 1.25,
        shadowY: 1,
        glowColor: .clear,
        glowRadius: 0
    )

    /// Near-black rather than gray: this is the user's explicit Black theme and also the
    /// dark half of System appearance. The persisted raw value remains `dark` so existing
    /// installations migrate without losing their selection.
    static let black = KeyboardTheme(
        id: "black",
        displayName: "Black",
        canvasTop: Color(hex: 0x050506),
        canvasBottom: Color(hex: 0x111318),
        letterKeyFill: Color(hex: 0x15171C),
        letterKeyHighlight: Color(hex: 0x252830),
        functionKeyFill: Color(hex: 0x090A0D),
        functionKeyHighlight: Color(hex: 0x181A20),
        keyLabel: Color(hex: 0xF8FAFC),
        hintGlyph: Color(hex: 0xA3ACBA),
        accent: Color(hex: 0x55D6FF),
        onAccent: Color(hex: 0x00141B),
        popupBackground: Color(hex: 0x20232A),
        keyBorder: Color(hex: 0x373B45),
        keyBorderWidth: 0.8,
        pressedOverlay: Color.white.opacity(0.10),
        shadowColor: Color.black.opacity(0.58),
        shadowRadius: 1.5,
        shadowY: 1,
        glowColor: .clear,
        glowRadius: 0
    )

    /// Electric cyan and ultraviolet accents on a restrained dark base. Glow is deliberately
    /// shallow: a keyboard renders roughly thirty keys at once, so large blur radii would spend
    /// extension memory and GPU time for little visual gain.
    static let neon = KeyboardTheme(
        id: "neon",
        displayName: "Neon",
        canvasTop: Color(hex: 0x050611),
        canvasBottom: Color(hex: 0x0B1020),
        letterKeyFill: Color(hex: 0x091222),
        letterKeyHighlight: Color(hex: 0x172A40),
        functionKeyFill: Color(hex: 0x10091F),
        functionKeyHighlight: Color(hex: 0x2A1450),
        keyLabel: Color(hex: 0xF4FBFF),
        hintGlyph: Color(hex: 0x7ADFFF),
        accent: Color(hex: 0x00F0FF),
        onAccent: Color(hex: 0x001316),
        popupBackground: Color(hex: 0x0E1930),
        keyBorder: Color(hex: 0x7C4DFF),
        keyBorderWidth: 1,
        pressedOverlay: Color(hex: 0x00F0FF).opacity(0.20),
        shadowColor: Color.black.opacity(0.62),
        shadowRadius: 1,
        shadowY: 1,
        glowColor: Color(hex: 0x00F0FF).opacity(0.42),
        glowRadius: 1.6
    )

    /// Compatibility spelling for callers and old documentation.
    static let dark = black

    static func forColorScheme(_ scheme: ColorScheme) -> KeyboardTheme {
        scheme == .dark ? .black : .light
    }

    var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [canvasTop, canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    func fill(for style: KeyStyle) -> Color {
        style == .letter ? letterKeyFill : functionKeyFill
    }

    func keyGradient(for style: KeyStyle) -> LinearGradient {
        let colors = style == .letter
            ? [letterKeyHighlight, letterKeyFill]
            : [functionKeyHighlight, functionKeyFill]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Metrics (📐 MEASURE — UI-SPEC.md V-02)

    static let keyCornerRadius: CGFloat = 7
    static let keySpacing: CGFloat = 3
    static let rowSpacing: CGFloat = 6
    static let keyboardVerticalPadding: CGFloat = 6
    static let keyRowHeight: CGFloat = 46

    /// The strip remains 44 pt so every control meets Apple's minimum touch target.
    static let stripHeight: CGFloat = 44
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
