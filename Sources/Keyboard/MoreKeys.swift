import Foundation

/// What a key offers when held — the accent callouts and punctuation grid of
/// [UI-SPEC.md](../../docs/UI-SPEC.md) §5.
///
/// ⏳ **Pending sourcing.** These are a working set. AOSP LatinIME defines the real per-letter
/// sets in `donottranslate-more-keys.xml`, and the order matters as much as the contents —
/// it decides which accent your finger lands on. The M2 research pass replaces this table with
/// the sourced one; until then treat it as unverified (UI-SPEC V-05, V-06).
enum MoreKeys {

    /// Accent alternates per letter, in display order. Letters absent here have none.
    private static let accents: [String: [String]] = [
        "e": ["é", "è", "ê", "ë", "ē", "ė", "ę"],
        "y": ["ÿ", "ý"],
        "u": ["ú", "ù", "û", "ü", "ū"],
        "i": ["í", "ì", "î", "ï", "ī", "į"],
        "o": ["ó", "ò", "ô", "ö", "õ", "ō", "ø", "œ"],
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā", "ą"],
        "s": ["ś", "š", "ß", "ş"],
        "d": ["ð", "ď"],
        "g": ["ğ"],
        "l": ["ł"],
        "z": ["ž", "ź", "ż"],
        "c": ["ç", "ć", "č"],
        "n": ["ñ", "ń"],
    ]

    /// The period's punctuation grid.
    ///
    /// 📐 UI-SPEC V-06 — press coverage lists only a subset of Gboard's grid and never its
    /// ordering, so this is the least trustworthy table here. Verify from a device screenshot
    /// before treating the order as Gboard-faithful.
    private static let periodMoreKeys = ["&", "%", "+", "#", "!", "@", "?", "-", ":", "'", "\"", "(", ")", "/"]

    /// Options shown when `key` is held, in display order, or nil when it has none.
    ///
    /// Top-row letters lead with their digit: the corner hint glyph advertises it, so it has to
    /// be the first thing under the finger.
    static func options(for key: Key, shift: ShiftState) -> [String]? {
        switch key.action {
        case .character(let character):
            let lowercased = character.lowercased()

            if lowercased == "." { return periodMoreKeys }

            var options: [String] = []
            if let digit = KeyboardLayout.digitHints[lowercased] { options.append(digit) }

            if let accented = accents[lowercased] {
                options.append(contentsOf: shift.isUppercase ? accented.map { $0.uppercased() } : accented)
            }

            return options.isEmpty ? nil : options

        default:
            // The comma's settings gear is deferred: reaching the host app needs SwiftUI
            // `Link` (C-48), which a UIKit-driven callout cannot host. Recorded rather than
            // faked with something that would not open.
            return nil
        }
    }

    static func hasOptions(for key: Key, shift: ShiftState) -> Bool {
        options(for: key, shift: shift) != nil
    }
}
