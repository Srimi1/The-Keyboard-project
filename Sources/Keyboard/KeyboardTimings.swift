import CoreGraphics
import Foundation

/// Every timing and distance that governs how the keyboard feels, in one place.
///
/// ⏳ **Pending verification.** These are working values matching AOSP LatinIME's documented
/// defaults from memory; the M1 research pass replaces each with the exact constant and its
/// source file. Until a value carries a `Source:` note it is not verified — do not treat
/// these as measured (CLAUDE.md §2).
enum KeyboardTimings {

    // MARK: - Key repeat (backspace)

    /// How long backspace must be held before it starts repeating.
    static let keyRepeatStartTimeout: TimeInterval = 0.40

    /// Interval between repeats once started.
    static let keyRepeatInterval: TimeInterval = 0.05

    /// After this many repeats, deletion switches from characters to whole words — Gboard
    /// accelerates rather than deleting one character at a time forever.
    static let repeatsBeforeWordDeletion: Int = 12

    // MARK: - Shift

    /// Two shift taps within this window latch caps lock.
    static let doubleTapShiftTimeout: TimeInterval = 0.30

    // MARK: - Punctuation

    /// Two spaces within this window become ". " — outside it, they stay two spaces.
    static let doubleSpacePeriodTimeout: TimeInterval = 1.10

    // MARK: - Long press (M2)

    /// Hold duration before the accent callout / punctuation grid opens.
    static let longPressTimeout: TimeInterval = 0.50

    // MARK: - Key preview

    /// How long the enlarged preview lingers after release.
    static let keyPreviewLinger: TimeInterval = 0.07

    // MARK: - Touch

    /// Slack around a key's visual bounds before a drifting finger is treated as having left
    /// it. Without hysteresis, fast typing drops characters at key edges.
    static let keyHysteresis: CGFloat = 8
}
