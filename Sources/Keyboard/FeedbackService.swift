import UIKit

/// Haptics and key clicks (UI-SPEC §10).
///
/// Both are gated on Full Access and **degrade silently** — the underlying APIs already no-op
/// without it (C-07), so the gate exists to avoid pointless work rather than to prevent an
/// error. The keyboard must type identically either way (C-09).
///
/// Defaults follow Gboard's own phone settings: haptics on, keypress sound off.
@MainActor
final class FeedbackService {

    /// Mirrors `UIInputViewController.hasFullAccess`, re-read on every appearance since there
    /// is no notification for it changing (C-41).
    var hasFullAccess = false

    private(set) var hapticsEnabled = KeyboardTimings.hapticFeedbackDefault
    private(set) var soundEnabled = KeyboardTimings.keypressSoundDefault

    /// Generators are kept alive rather than created per keystroke: constructing one warms up
    /// the Taptic Engine, and doing that at 5 keys per second is wasteful.
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()

    private var isActive: Bool { hasFullAccess }

    func apply(_ settings: KeyboardSettings) {
        hapticsEnabled = settings.hapticsEnabled
        soundEnabled = settings.soundEnabled
    }

    /// Call when the keyboard appears — asking the engine to warm up makes the first tap feel
    /// the same as the rest.
    func prepare() {
        guard isActive, hapticsEnabled else { return }
        impact.prepare()
        selection.prepare()
    }

    func keyPressed() {
        guard isActive else { return }
        if hapticsEnabled { impact.impactOccurred() }
        if soundEnabled { UIDevice.current.playInputClick() }
    }

    /// Sliding across a callout's options, or the caret stepping during a spacebar slide.
    func selectionChanged() {
        guard isActive, hapticsEnabled else { return }
        selection.selectionChanged()
    }
}
