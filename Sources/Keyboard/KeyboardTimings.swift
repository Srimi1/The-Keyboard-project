import CoreGraphics
import Foundation

/// Every timing and distance that governs how the keyboard feels, in one place.
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

    /// Two shift taps within this window latch caps lock, measured from the first tap's release
    /// to the second tap's press. Not a LatinIME resource — it is the Android platform's
    /// `ViewConfiguration.DOUBLE_TAP_TIMEOUT`, used via `getDoubleTapTimeout()` in
    /// java/src/.../keyboard/internal/TimerHandler.java:174.
    static let doubleTapShiftTimeout: TimeInterval = 0.300

    /// Holding shift also latches caps lock, on a much longer window than a normal long press.
    /// `config_longpress_shift_lock_timeout` — java/res/values/config-common.xml:57
    static let longPressShiftLockTimeout: TimeInterval = 1.200

    // MARK: - Punctuation

    /// Two spaces within this window become ". " — outside it, they stay two spaces.
    /// `config_double_space_period_timeout` — java/res/values/config-common.xml:28
    static let doubleSpacePeriodTimeout: TimeInterval = 1.100

    // MARK: - Long press (M2)

    /// Hold duration before the accent callout / punctuation grid opens.
    /// `config_default_longpress_key_timeout` — java/res/values/config-common.xml:47.
    /// User-adjustable in Gboard between 100 and 700 ms in 10 ms steps; this is the default.
    static let longPressTimeout: TimeInterval = 0.300

    /// When the finger is already sliding, the long-press timeout is tripled.
    /// `MULTIPLIER_FOR_LONG_PRESS_TIMEOUT_IN_SLIDING_INPUT` —
    /// java/src/.../keyboard/PointerTracker.java:140
    static let longPressSlidingMultiplier: Double = 3

    // MARK: - Key preview

    /// How long the enlarged preview lingers after release.
    /// `config_key_preview_linger_timeout` — java/res/values/config-common.xml:40
    static let keyPreviewLinger: TimeInterval = 0.070

    /// `config_key_preview_show_up_duration` — java/res/values/config-common.xml:35
    static let keyPreviewShowUpDuration: TimeInterval = 0.017

    /// `config_key_preview_dismiss_duration` — java/res/values/config-common.xml:36
    static let keyPreviewDismissDuration: TimeInterval = 0.053

    // MARK: - Touch

    /// Slack around a key's visual bounds before a drifting finger is treated as having left
    /// it. Without hysteresis, fast typing drops characters at key edges.
    /// `config_key_hysteresis_distance` — java/res/values/config.xml:25 (phone bucket; the
    /// sw600dp tablet bucket raises it to 40dp, which does not apply here).
    ///
    /// dp and iOS points are both 1/160 inch at 1×, so the number carries over directly.
    static let keyHysteresis: CGFloat = 8.0

    /// A press landing within this time *and* distance of the previous release is discarded as
    /// digitizer noise. Note it is an up-to-down filter, not a during-touch one.
    /// `config_touch_noise_threshold_time` — java/res/values/config-common.xml:97
    static let touchNoiseThresholdTime: TimeInterval = 0.040

    /// `config_touch_noise_threshold_distance` — java/res/values/config-common.xml:96
    static let touchNoiseThresholdDistance: CGFloat = 12.6

    // MARK: - Defaults Gboard ships with (java/res/xml/prefs_*.xml, config-per-form-factor.xml)

    /// Auto-capitalization is on by default.
    static let autoCapitalizationDefault = true

    /// Double-space → period is on by default.
    static let doubleSpacePeriodDefault = true

    /// The key-preview popup is on by default on phones (off on tablets).
    static let keyPreviewDefault = true

    /// Haptics on, keypress sound off — the phone defaults. Both land at M2.
    static let hapticFeedbackDefault = true
    static let keypressSoundDefault = false
}
