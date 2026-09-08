import CoreGraphics
import Foundation

/// Implemented timings and distances that govern how the keyboard feels, in one place.
///
/// Values come from **AOSP LatinIME** — Gboard's open-source ancestor and the closest primary
/// source to its closed-source behavior (ADR-001). Source paths are relative to
/// `android.googlesource.com/platform/packages/inputmethods/LatinIME`, read at
/// `refs/heads/main` (HEAD `127336e9`, 2025-02-26).
///
/// Note that almost all of these live in `config-common.xml`, which has **no screen-size
/// bucket overrides** — so they are device-independent. Hysteresis is the exception.
enum KeyboardTimings {

    // MARK: - Key repeat (backspace)

    /// How long backspace must be held before it starts repeating.
    /// `config_key_repeat_start_timeout` — java/res/values/config-common.xml:30
    static let keyRepeatStartTimeout: TimeInterval = 0.400

    /// Interval between repeats once started.
    /// `config_key_repeat_interval` — java/res/values/config-common.xml:31
    static let keyRepeatInterval: TimeInterval = 0.050

    /// After this many deletes, each tick removes **two** characters instead of one.
    /// `Constants.DELETE_ACCELERATE_AT` — common/src/.../common/Constants.java:182
    ///
    /// This is the whole escalation: AOSP never switches to deleting whole words on hold.
    /// Gboard's word-level delete is the *slide-left-from-backspace gesture*, which is
    /// deferred with the rest of the gesture engine (ADR-007) — not this path.
    static let deletesBeforeAcceleration: Int = 20

    /// Characters removed per tick once accelerated.
    static let acceleratedDeleteCount: Int = 2

    // MARK: - Shift

    /// Two completed shift taps within this window latch caps lock. Not a LatinIME resource —
    /// it is based on the Android platform's
    /// `ViewConfiguration.DOUBLE_TAP_TIMEOUT`, used via `getDoubleTapTimeout()` in
    /// java/src/.../keyboard/internal/TimerHandler.java:174.
    static let doubleTapShiftTimeout: TimeInterval = 0.300

    // MARK: - Punctuation

    /// Two spaces within this window become ". " — outside it, they stay two spaces.
    /// `config_double_space_period_timeout` — java/res/values/config-common.xml:28
    static let doubleSpacePeriodTimeout: TimeInterval = 1.100

    // MARK: - Long press (M2)

    /// Hold duration before the accent callout / punctuation grid opens.
    /// `config_default_longpress_key_timeout` — java/res/values/config-common.xml:47.
    /// User-adjustable in Gboard between 100 and 700 ms in 10 ms steps; this is the default.
    static let longPressTimeout: TimeInterval = 0.300

    // MARK: - Touch

    /// Slack around a key's visual bounds before a drifting finger is treated as having left
    /// it. Without hysteresis, fast typing drops characters at key edges.
    /// `config_key_hysteresis_distance` — java/res/values/config.xml:25 (phone bucket; the
    /// sw600dp tablet bucket raises it to 40dp, which does not apply here).
    ///
    /// dp and iOS points are both 1/160 inch at 1×, so the number carries over directly.
    static let keyHysteresis: CGFloat = 8.0

    // MARK: - Defaults Gboard ships with (java/res/xml/prefs_*.xml, config-per-form-factor.xml)

    /// Auto-capitalization is on by default.
    static let autoCapitalizationDefault = true

    /// Double-space → period is on by default.
    static let doubleSpacePeriodDefault = true

    /// Haptics on, keypress sound off — the phone defaults.
    static let hapticFeedbackDefault = true
    static let keypressSoundDefault = false
}
