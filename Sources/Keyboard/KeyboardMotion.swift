import SwiftUI

/// Motion tokens for the keyboard's interactive surfaces: press feedback, popups, panel
/// switches and theme changes.
///
/// These are engineering choices, not AOSP-sourced — contrast `KeyboardTimings`, which times
/// *behavior* (repeat rate, long-press, double-space) against Gboard's own numbers. Nothing
/// here changes what a gesture does or when it fires, only how the already-implemented state
/// change is drawn, so a wrong value here is a feel regression, never a functional one.
///
/// Every curve below animates opacity, scale or color. None adds blur or widens per-key glow —
/// UI-SPEC.md §9 reserves larger blur for after signed-device GPU/memory profiling, and this
/// pass does not touch that budget.
enum KeyboardMotion {

    /// A key darkening under a finger must read as instantaneous — any easing here reads as
    /// input lag, not polish. Kept shorter than the release curve on purpose.
    static let keyPress: Animation = .easeOut(duration: 0.05)

    /// The pressed highlight lifting on release can be a touch slower than the press without
    /// feeling laggy, and reads as considered rather than a hard cut.
    static let keyRelease: Animation = .easeOut(duration: 0.09)

    /// Caps lock's accent border/label switching state.
    static let keyActiveState: Animation = .easeOut(duration: 0.12)

    /// Key-preview popup and long-press callout (UI-SPEC.md §4/§5): a light overshoot on
    /// appear signals "this opened for you"; dismiss stays a plain, quicker fade so lifting a
    /// finger never feels sticky.
    static let popupAppear: Animation = .spring(response: 0.22, dampingFraction: 0.7)
    static let popupDismiss: Animation = .easeIn(duration: 0.08)

    /// A freshly-mounted panel (clipboard/settings/diagnostics) fading its own content in.
    /// Deliberately an *insertion-only* fade — see `KeyboardRootView.fadeInOnAppear()` — so the
    /// outgoing panel is never kept mounted (and hit-testable) during an animated crossfade.
    static let panelAppear: Animation = .easeOut(duration: 0.16)

    /// The toolbar's clipboard/settings buttons swapping their active accent/icon.
    static let toolbarState: Animation = .easeOut(duration: 0.15)

    /// The strip's post-save paste chip (UI-SPEC.md §7).
    static let chip: Animation = .easeOut(duration: 0.2)

    /// Clipboard grid cells appearing, reordering (pin moves a card between sections) or
    /// being removed.
    static let listChange: Animation = .easeInOut(duration: 0.2)

    /// Recoloring every key when the user switches Light/Black/Neon/System in settings.
    static let themeChange: Animation = .easeInOut(duration: 0.22)

    /// Reduce Motion collapses every curve above to an instant cut. Returns `nil` rather than
    /// a zero-duration animation so the state change bypasses SwiftUI's animation pipeline
    /// entirely instead of running a degenerate one-frame animation.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
