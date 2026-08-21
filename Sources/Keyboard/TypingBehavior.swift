import Foundation
import UIKit

// The rules that decide what a keypress actually does. Kept free of UI so each can be
// reasoned about — and later tested — on its own.

// MARK: - Shift

/// Gboard's shift semantics: a tap shifts the next character only, a second tap inside the
/// double-tap window latches caps lock, and auto-capitalization can raise shift on its own
/// without that counting as a tap.
struct ShiftController {

    private(set) var state: ShiftState = .off
    private var lastTapAt: Date?

    mutating func handleTap(now: Date = Date()) {
        defer { lastTapAt = now }

        if let last = lastTapAt,
           now.timeIntervalSince(last) <= KeyboardTimings.doubleTapShiftTimeout,
           state != .capsLock {
            state = .capsLock
            return
        }

        switch state {
        case .off: state = .shifted
        case .shifted, .capsLock: state = .off
        }
    }

    /// Shift falls back to lowercase after one character; caps lock does not.
    mutating func didInsertCharacter() {
        if state == .shifted { state = .off }
    }

    /// Auto-capitalization result. Never overrides caps lock, and never counts as a tap —
    /// otherwise typing a sentence would latch caps lock by accident.
    mutating func applyAutoCapitalization(_ shouldCapitalize: Bool) {
        guard state != .capsLock else { return }
        state = shouldCapitalize ? .shifted : .off
    }
}

// MARK: - Auto-capitalization

enum AutoCapitalization {

    /// Whether the next character should be capitalized.
    ///
    /// Honors the field's own `autocapitalizationType` rather than always capitalizing —
    /// a username or URL field asks for `.none` and overriding it is a real annoyance.
    /// The sentence rule works off `documentContextBeforeInput`, which returns only the last
    /// sentences or so (C-18), and correctly treats an empty context as the start of the field.
    static func shouldCapitalize(
        before context: String?,
        type: UITextAutocapitalizationType
    ) -> Bool {
        switch type {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let context, let last = context.last else { return true }
            return last.isWhitespace
        case .sentences:
            return isSentenceStart(context)
        @unknown default:
            return isSentenceStart(context)
        }
    }

    /// Follows AOSP LatinIME's `CapsModeUtils.getCapsMode` — the algorithm behind Gboard's
    /// shift behavior, so this is imitation rather than invention (ADR-001).
    ///
    /// The steps that are easy to miss: opening punctuation the user just typed is skipped
    /// (`Hello. "` still starts a sentence), American typography puts the period inside the
    /// closing quote (`he said "hi." ` starts a sentence), and a period that ends an
    /// abbreviation does not (`e.g. ` must not capitalize).
    private static func isSentenceStart(_ context: String?) -> Bool {
        // The proxy returns nil rather than "" when there is nothing before the cursor.
        guard let context, !context.isEmpty else { return true }
        var characters = Array(context)

        // 1. Skip trailing opening punctuation — the quote or bracket just typed is not
        //    itself a reason to stop capitalizing.
        while let last = characters.last, openingPunctuation.contains(last) {
            characters.removeLast()
        }

        // 2. Walk back over spaces and tabs, remembering whether there were any.
        var sawWhitespace = false
        while let last = characters.last, last == " " || last == "\t" || last == "\u{00A0}" {
            characters.removeLast()
            sawWhitespace = true
        }

        // 3. Start of text or a newline begins a sentence.
        guard let lastCharacter = characters.last else { return true }
        if lastCharacter.isNewline { return true }

        // No whitespace between the cursor and the previous word means we are inside it.
        guard sawWhitespace else { return false }

        // 4. Skip closing quotes: American typography puts the terminator inside them.
        while let last = characters.last, closingQuotes.contains(last) {
            characters.removeLast()
        }
        guard let terminator = characters.last else { return true }

        // 5. Question and exclamation marks always end a sentence.
        if exclamationTerminators.contains(terminator) { return true }

        // 6. A period ends a sentence unless it ends an abbreviation.
        guard periodTerminators.contains(terminator) else { return false }
        return !endsWithAbbreviation(characters)
    }

    /// "e.g." and "U.S." end in a period but do not end a sentence. The tell is a single
    /// letter sitting between two periods.
    private static func endsWithAbbreviation(_ characters: [Character]) -> Bool {
        var scan = characters
        scan.removeLast()                                   // the terminating period
        guard let letter = scan.last, letter.isLetter else { return false }
        scan.removeLast()
        guard let preceding = scan.last else { return false }
        return periodTerminators.contains(preceding)
    }

    private static let periodTerminators: Set<Character> = [".", "。"]
    private static let exclamationTerminators: Set<Character> = ["!", "?", "！", "？"]
    private static let openingPunctuation: Set<Character> = ["\"", "'", "(", "[", "{", "«", "¿", "¡", "“", "‘"]
    private static let closingQuotes: Set<Character> = ["\"", "'", ")", "]", "}", "»", "”", "’"]
}

// MARK: - Return key

enum ReturnKeyLabel {

    /// What Apple's keyboard shows for each return-key type. Getting this wrong is a small
    /// thing that makes a keyboard feel obviously third-party.
    static func label(for type: UIReturnKeyType) -> String {
        switch type {
        case .go: return "go"
        case .google: return "search"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .search: return "search"
        case .send: return "send"
        case .yahoo: return "search"
        case .done: return "done"
        case .emergencyCall: return "call"
        case .continue: return "continue"
        case .default: return "return"
        @unknown default: return "return"
        }
    }
}

// MARK: - Key repeat

/// Hold-to-repeat for backspace, accelerating into whole-word deletion the way Gboard does.
///
/// Driven by a cancellable `Task` rather than a `Timer`: it stays on the MainActor with no
/// isolation gymnastics, and unlike a run-loop timer it cannot stall while something scrolls.
@MainActor
final class KeyRepeater {

    private var task: Task<Void, Never>?

    /// - Parameter fire: called immediately for the initial press, then on each repeat, with
    ///   `deletesWord` true once repeats have accelerated past the per-character stage.
    func start(fire: @escaping (_ deletesWord: Bool) -> Void) {
        stop()
        fire(false)

        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(KeyboardTimings.keyRepeatStartTimeout))
            guard self != nil, !Task.isCancelled else { return }

            var repeatCount = 0
            while !Task.isCancelled {
                repeatCount += 1
                fire(repeatCount >= KeyboardTimings.repeatsBeforeWordDeletion)
                try? await Task.sleep(nanoseconds: Self.nanoseconds(KeyboardTimings.keyRepeatInterval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(seconds * 1_000_000_000)
    }

    deinit {
        task?.cancel()
    }
}
