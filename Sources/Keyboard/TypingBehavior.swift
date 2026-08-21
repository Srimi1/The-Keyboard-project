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

    private static func isSentenceStart(_ context: String?) -> Bool {
        // Nothing before the cursor: start of the field.
        guard let context, !context.isEmpty else { return true }

        // Trailing whitespace is what separates "end of sentence" from "mid-word".
        let trimmed = context.reversed().drop { $0 == " " || $0 == "\u{00A0}" }
        guard let lastNonSpace = trimmed.first else {
            // Only whitespace before the cursor — still effectively a start.
            return true
        }

        if lastNonSpace.isNewline { return true }

        // A terminator only starts a new sentence once a space follows it, so "Hello." does
        // not capitalize but "Hello. " does.
        let hadTrailingSpace = context.last == " " || context.last == "\u{00A0}"
        guard hadTrailingSpace else { return false }

        return sentenceTerminators.contains(lastNonSpace)
    }

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "。", "！", "？"]
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
