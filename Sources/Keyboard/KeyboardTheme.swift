import SwiftUI

/// Colors and metrics from UI-SPEC.md §9.
///
/// ⚠️ Every value here is a **📐 MEASURE placeholder** derived from Google's Material
/// palette, not measured from Gboard. UI-SPEC.md items V-01 and V-02 replace them once
/// reference screenshots exist. Do not treat these as verified.
struct KeyboardTheme {

    let keyboardBackground: Color
    let letterKeyFill: Color
    let functionKeyFill: Color
    let keyLabel: Color
    let hintGlyph: Color
    let accent: Color
    /// Readable on top of `accent` — white in light mode, near-black in dark, where the
    /// lighter accent would otherwise swallow white text.
    let onAccent: Color
    let popupBackground: Color

    static let light = KeyboardTheme(
        keyboardBackground: Color(red: 0.945, green: 0.953, blue: 0.957), // #F1F3F4
        letterKeyFill: .white,
        functionKeyFill: Color(red: 0.855, green: 0.878, blue: 0.878),    // #DADCE0
        keyLabel: Color(red: 0.122, green: 0.122, blue: 0.122),           // #1F1F1F
        hintGlyph: Color(red: 0.373, green: 0.392, blue: 0.408),          // #5F6368
        accent: Color(red: 0.102, green: 0.451, blue: 0.910),             // #1A73E8
        onAccent: .white,
        popupBackground: .white
    )

    static let dark = KeyboardTheme(
        keyboardBackground: Color(red: 0.125, green: 0.129, blue: 0.141),  // #202124
        letterKeyFill: Color(red: 0.235, green: 0.251, blue: 0.263),       // #3C4043
        functionKeyFill: Color(red: 0.157, green: 0.165, blue: 0.176),     // #282A2D
        keyLabel: Color(red: 0.910, green: 0.918, blue: 0.929),            // #E8EAED
        hintGlyph: Color(red: 0.604, green: 0.628, blue: 0.651),           // #9AA0A6
        accent: Color(red: 0.541, green: 0.706, blue: 0.973),              // #8AB4F8
        onAccent: Color(red: 0.125, green: 0.129, blue: 0.141),            // #202124
        popupBackground: Color(red: 0.235, green: 0.251, blue: 0.263)      // #3C4043
    )

    static func forColorScheme(_ scheme: ColorScheme) -> KeyboardTheme {
        scheme == .dark ? .dark : .light
    }

    func fill(for style: KeyStyle) -> Color {
        style == .letter ? letterKeyFill : functionKeyFill
    }

    // MARK: - Metrics (📐 MEASURE — UI-SPEC.md V-02)

    static let keyCornerRadius: CGFloat = 6
    static let keySpacing: CGFloat = 3
    static let rowSpacing: CGFloat = 6
    static let keyboardVerticalPadding: CGFloat = 6

    /// Total keyboard height. 📐 MEASURE — UI-SPEC.md V-11 measures Gboard's height as a
    /// fraction of screen height; this is a working value until then (C-22).
    static let keyRowHeight: CGFloat = 46

    /// Height of the strip above the keys.
    ///
    /// The v1 strip carries clipboard and settings controls in both Debug and Release
    /// (UI-SPEC.md §7; ADR-015). Keeping one height preserves identical core geometry.
    /// It is 44 pt so its controls meet the minimum touch target, but remains a working value
    /// until the Phase 3 visual comparison closes UI-SPEC.md V-09.
    static let stripHeight: CGFloat = 44
}
