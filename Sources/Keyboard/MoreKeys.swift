import Foundation

/// What a key offers when held — the accent callouts and punctuation grid of
/// [UI-SPEC.md](../../docs/UI-SPEC.md) §5.
///
/// **Sourced from AOSP LatinIME.** The resource files moved out of `java/res/values/` into the
/// code-generation tool; the live definitions are
/// `tools/make-keyboard-text/res/values/donottranslate-more-keys.xml` (base) and
/// `values-en/` (English overrides), resolved into the checked-in
/// `KeyboardTextsTable.java` (`TEXTS_en`). There is no `values-en-rUS`, so en_US and en_GB
/// share one set.
///
/// **Order is ground truth, not decoration** — it decides which alternate the finger lands on.
enum MoreKeys {

    /// Accent alternates per letter, in resource order.
    ///
    /// English overrides exactly **eight** letters. Everything else has none — notably y, d,
    /// g, l and z, which a plausible-looking guess would have given ÿ, ď, ğ, ł and ž.
    private static let accents: [String: [String]] = [
        "e": ["é", "è", "ê", "ë", "ē"],
        "u": ["ú", "û", "ü", "ù", "ū"],
        "i": ["í", "î", "ï", "ī", "ì"],
        "o": ["ó", "ô", "ö", "ò", "œ", "ø", "ō", "õ"],
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "s": ["ß"],
        "c": ["ç"],
        "n": ["ñ"],
    ]

    /// The period's punctuation grid — `morekeys_punctuation`, 16 entries in resource order.
    /// Note it leads with the comma, and that the set is nothing like the subset press
    /// coverage lists.
    private static let periodMoreKeys = [
        ",", "?", "!", "#", ")", "(", "/", ";",
        "'", "@", ":", "-", "\"", "+", "%", "&",
    ]

    /// `!autoColumnOrder!8` on the punctuation set. Despite the name this means *fixed* column
    /// count with automatic placement order, so the grid is 8 wide and wraps to a second row.
    /// Letter callouts stay a single row.
    private static let punctuationColumns = 8

    /// Options shown when `key` is held, in display order, or nil when it has none.
    ///
    /// Top-row letters lead with their digit: AOSP declares those via `additionalMoreKeys`,
    /// and because no English more-key string contains the `%` placeholder marker,
    /// `MoreKeySpec.insertAdditionalMoreKeys` prepends rather than substitutes.
    static func options(for key: Key, shift: ShiftState) -> [String]? {
        switch key.action {
        case .character(let character):
            let lowercased = character.lowercased()

            if lowercased == "." { return periodMoreKeys }

            var options: [String] = []
            if let digit = KeyboardLayout.digitHints[lowercased] { options.append(digit) }

            if let accented = accents[lowercased] {
                // Shifted callouts are upper-cased per key. ß upper-cases to the two-character
                // "SS" rather than a single glyph, which AOSP handles as an output-text key —
                // Swift's uppercased() produces the same string, so it falls out for free.
                options.append(contentsOf: shift.isUppercase ? accented.map { $0.uppercased() } : accented)
            }

            return options.isEmpty ? nil : options

        default:
            // v1 exposes preferences in the keyboard's dedicated settings panel. It does not
            // give comma a host-app launch action; keyboard extensions may not launch other
            // apps for this workflow.
            return nil
        }
    }

    /// Columns the callout lays out in before wrapping to another row.
    ///
    /// The 8 is specific to `morekeys_punctuation`'s `!autoColumnOrder!8`, not a general
    /// maximum — conflating the two wrapped nine-option letter callouts like `o` for no
    /// reason. AOSP does have a general cap in `config_max_more_keys_column`, but that value
    /// is **not yet sourced**, so letters stay on one row until it is (⏳ pending).
    static func columns(for key: Key, options: [String]) -> Int {
        if case .character(let character) = key.action, character == "." {
            return min(options.count, punctuationColumns)
        }
        return options.count
    }

    static func hasOptions(for key: Key, shift: ShiftState) -> Bool {
        options(for: key, shift: shift) != nil
    }
}
