import Foundation

// Layout model for the Gboard-style keyboard.
//
// Key widths are fractions of keyboard width, matching AOSP LatinIME — Gboard's
// open-source visual ancestor and the closest primary source to its closed-source
// metrics. See UI-SPEC.md §1. Letter keys 10%, shift/backspace 15%, bottom row
// [?123 15%][, 10%][space 50%][. 10%][return 15%].
//
// M0 SCOPE: structure and widths only. Heights, gaps, corner radii and exact colors
// are 📐 MEASURE items in UI-SPEC.md §12, blocked on reference screenshots, and the
// placeholder values in KeyboardTheme are explicitly not verified.

enum KeyboardLayer: Equatable {
    case base
    case symbols
    case extendedSymbols
}

enum ShiftState: Equatable {
    case off
    case shifted
    case capsLock

    var isUppercase: Bool { self != .off }
}

enum KeyAction: Equatable {
    case character(String)
    case backspace
    case space
    case newline
    case shift
    case switchLayer(KeyboardLayer)
    case nextKeyboard
    case diagnostics
}

enum KeyStyle {
    case letter
    case function
}

struct Key: Identifiable, Equatable {
    let id: String
    let label: String
    let action: KeyAction
    let widthFraction: Double
    let style: KeyStyle

    init(id: String, label: String, action: KeyAction, widthFraction: Double = 0.10, style: KeyStyle = .letter) {
        self.id = id
        self.label = label
        self.action = action
        self.widthFraction = widthFraction
        self.style = style
    }

    static func letter(_ character: String) -> Key {
        Key(id: "key-\(character)", label: character, action: .character(character))
    }
}

struct KeyRow: Identifiable, Equatable {
    let id: String
    /// Leading inset as a fraction of keyboard width. The home row is centered with a
    /// half-key (5%) inset on both sides.
    let leadingInset: Double
    let keys: [Key]

    init(id: String, leadingInset: Double = 0, keys: [Key]) {
        self.id = id
        self.leadingInset = leadingInset
        self.keys = keys
    }
}

enum KeyboardLayout {

    /// - Parameter needsGlobe: pass `UIInputViewController.needsInputModeSwitchKey`. It is
    ///   false on Face ID iPhones, where iOS draws globe and dictation below the keyboard,
    ///   so the key must not be drawn at all there (C-21).
    static func rows(layer: KeyboardLayer, shift: ShiftState, needsGlobe: Bool) -> [KeyRow] {
        switch layer {
        case .base:
            return letterRows(shift: shift) + [bottomRow(layerKeyLabel: "?123", target: .symbols, needsGlobe: needsGlobe)]
        case .symbols:
            return symbolRows() + [bottomRow(layerKeyLabel: "ABC", target: .base, needsGlobe: needsGlobe)]
        case .extendedSymbols:
            return extendedSymbolRows() + [bottomRow(layerKeyLabel: "ABC", target: .base, needsGlobe: needsGlobe)]
        }
    }

    // MARK: - Letters

    private static let topLetters = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private static let homeLetters = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    private static let bottomLetters = ["z", "x", "c", "v", "b", "n", "m"]

    /// Digit hints shown on the top row. Long-press to insert them is M2 work
    /// (UI-SPEC.md §5b); M0 renders the glyphs only.
    static let digitHints: [String: String] = [
        "q": "1", "w": "2", "e": "3", "r": "4", "t": "5",
        "y": "6", "u": "7", "i": "8", "o": "9", "p": "0",
    ]

    private static func letterRows(shift: ShiftState) -> [KeyRow] {
        let transform: (String) -> String = shift.isUppercase ? { $0.uppercased() } : { $0 }

        return [
            KeyRow(id: "row-1", keys: topLetters.map { Key.letter(transform($0)) }),
            KeyRow(id: "row-2", leadingInset: 0.05, keys: homeLetters.map { Key.letter(transform($0)) }),
            KeyRow(id: "row-3", keys:
                [Key(id: "key-shift", label: shift == .capsLock ? "⇪" : "⇧", action: .shift, widthFraction: 0.15, style: .function)]
                + bottomLetters.map { Key.letter(transform($0)) }
                + [Key(id: "key-backspace", label: "⌫", action: .backspace, widthFraction: 0.15, style: .function)]
            ),
        ]
    }

    // MARK: - Symbols
    //
    // 📐 MEASURE: the exact contents and arrangement of Gboard's ?123 and =\< layers are
    // UI-SPEC.md item V-03, blocked on reference screenshots. These are a working set for
    // M0 typing, not a verified match.

    private static func symbolRows() -> [KeyRow] {
        [
            KeyRow(id: "sym-1", keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map { Key.letter($0) }),
            KeyRow(id: "sym-2", keys: ["@", "#", "$", "_", "&", "-", "+", "(", ")", "/"].map { Key.letter($0) }),
            KeyRow(id: "sym-3", keys:
                [Key(id: "key-extended", label: "=\\<", action: .switchLayer(.extendedSymbols), widthFraction: 0.15, style: .function)]
                + ["*", "\"", "'", ":", ";", "!", "?"].map { Key.letter($0) }
                + [Key(id: "key-backspace", label: "⌫", action: .backspace, widthFraction: 0.15, style: .function)]
            ),
        ]
    }

    private static func extendedSymbolRows() -> [KeyRow] {
        [
            KeyRow(id: "ext-1", keys: ["~", "`", "|", "•", "√", "π", "÷", "×", "¶", "∆"].map { Key.letter($0) }),
            KeyRow(id: "ext-2", keys: ["£", "¢", "€", "¥", "^", "°", "=", "{", "}", "\\"].map { Key.letter($0) }),
            KeyRow(id: "ext-3", keys:
                [Key(id: "key-symbols", label: "?123", action: .switchLayer(.symbols), widthFraction: 0.15, style: .function)]
                + ["%", "©", "®", "™", "✓", "[", "]"].map { Key.letter($0) }
                + [Key(id: "key-backspace", label: "⌫", action: .backspace, widthFraction: 0.15, style: .function)]
            ),
        ]
    }

    // MARK: - Bottom row
    //
    // The row iPhone users notice is wrong. Gboard: [?123][,][space][.][return].

    private static func bottomRow(layerKeyLabel: String, target: KeyboardLayer, needsGlobe: Bool) -> KeyRow {
        var keys: [Key] = [
            Key(id: "key-layer", label: layerKeyLabel, action: .switchLayer(target), widthFraction: 0.15, style: .function)
        ]

        // When iOS requires a globe key it takes the comma's slot, and the comma moves into
        // the period's long-press set — which does not exist until M2 (UI-SPEC.md §1, §5c).
        if needsGlobe {
            keys.append(Key(id: "key-globe", label: "🌐", action: .nextKeyboard, style: .function))
        } else {
            keys.append(Key(id: "key-comma", label: ",", action: .character(",")))
        }

        keys.append(Key(id: "key-space", label: "English (US)", action: .space, widthFraction: 0.50))
        keys.append(Key(id: "key-period", label: ".", action: .character(".")))
        keys.append(Key(id: "key-return", label: "return", action: .newline, widthFraction: 0.15, style: .function))

        return KeyRow(id: "row-bottom", keys: keys)
    }
}
