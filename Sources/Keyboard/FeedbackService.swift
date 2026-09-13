import UIKit

/// Haptics and key clicks (UI-SPEC §10).
///
/// Both are gated on Full Access and **degrade silently** — the underlying APIs already no-op
/// without it (C-07), so the gate exists to avoid pointless work rather than to prevent an
/// error. The keyboard must type identically either way (C-09).
///
/// Feedback adapts to the key's purpose and typing cadence. No typed content is retained.
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
    private var lastPressTime: TimeInterval?

    private var isActive: Bool { hasFullAccess }

    func apply(_ settings: KeyboardSettings) {
        hapticsEnabled = settings.hapticsEnabled
        soundEnabled = settings.soundEnabled
    }

    /// Call when the keyboard appears — asking the engine to warm up makes the first tap feel
    /// the same as the rest.
    func prepare() {
        lastPressTime = nil
        guard isActive, hapticsEnabled else { return }
        impact.prepare()
        selection.prepare()
    }

    func keyPressed(action: KeyAction = .character(""), at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isActive else { return }
        let interval = lastPressTime.map { max(0, time - $0) }
        lastPressTime = time
        if hapticsEnabled {
            impact.impactOccurred(intensity: Self.intensity(for: action, interval: interval))
            impact.prepare()
        }
        if soundEnabled { UIDevice.current.playInputClick() }
    }

    /// Product-tuned values, not claimed as Gboard measurements. Rapid taps soften to
    /// avoid a continuous buzz; structural keys still feel distinct from letters.
    static func intensity(for action: KeyAction, interval: TimeInterval?) -> CGFloat {
        let base: CGFloat
        switch action {
        case .newline: base = 0.85
        case .space: base = 0.65
        case .backspace: base = 0.55
        case .shift, .switchLayer, .nextKeyboard, .diagnostics: base = 0.6
        case .character: base = 0.4
        }
        guard let interval, interval < 0.12 else { return base }
        return base * 0.65
    }

    /// Sliding across a callout's options, or the caret stepping during a spacebar slide.
    func selectionChanged() {
        guard isActive, hapticsEnabled else { return }
        selection.selectionChanged()
    }
}
