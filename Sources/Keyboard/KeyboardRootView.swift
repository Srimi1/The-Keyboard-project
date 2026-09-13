import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel
    @ObservedObject private var settings: KeyboardSettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: KeyboardViewModel) {
        self.model = model
        self._settings = ObservedObject(wrappedValue: model.settings)
    }

    private var theme: KeyboardTheme {
        switch settings.values.appearance {
        case .system: return .forColorScheme(colorScheme)
        case .light: return .light
        case .dark: return .black
        case .neon: return .neon
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            KeyboardStrip(model: model, clipboard: model.clipboard, theme: theme)

            activePanel
        }
        // Transparent, never an opaque fill — iOS 26 wraps keyboards in a system glass
        // container and an opaque background renders as a gray bar (CONSTRAINTS §8).
        .background(Color.clear)
        // Keep identifiers on individual controls. A container identifier propagates
        // through SwiftUI and replaces the clipboard/settings button identifiers.
    }

    @ViewBuilder
    private var activePanel: some View {
        switch model.panel {
        case .keys:
            // Keys never fade in: typing must be instantly hit-testable, and this is where
            // people spend nearly all their time, so a per-switch entrance delay here would
            // read as lag rather than polish (see KeyboardMotion.panelAppear).
            KeyGrid(model: model, theme: theme)
        case .clipboard:
            ClipboardPanel(
                model: model,
                clipboard: model.clipboard,
                settings: settings,
                theme: theme
            )
            .fadeInOnAppear()
        case .settings:
            KeyboardSettingsPanel(
                model: model,
                settings: settings,
                clipboard: model.clipboard,
                theme: theme
            )
            .fadeInOnAppear()
        case .diagnostics:
            #if DEBUG
            DiagnosticsPanel(model: model, theme: theme)
                .fadeInOnAppear()
            #else
            KeyGrid(model: model, theme: theme)
            #endif
        }
    }
}

/// Fades a freshly-mounted panel's own content in, without animating its removal.
///
/// A shared `.animation(value: model.panel)` crossfade would keep the *outgoing* panel
/// mounted — and hit-testable — for the whole transition. For `.clipboard`/`.settings` that
/// is only a stray tap target, but `.keys` hosts `TouchTracker`'s raw multi-touch layer
/// (UI-SPEC.md §3), and that must never coexist with another panel's controls. Animating only
/// the incoming view's own opacity on `onAppear` gets an "eases in, never pops" feel with the
/// outgoing view still removed synchronously, exactly as before this pass.
private struct FadeInOnAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .animation(KeyboardMotion.resolved(KeyboardMotion.panelAppear, reduceMotion: reduceMotion), value: appeared)
            .onAppear { appeared = true }
    }
}

private extension View {
    func fadeInOnAppear() -> some View { modifier(FadeInOnAppear()) }
}

// MARK: - Strip
//
// The v1 band above the keys contains the clipboard/settings controls and paste chip.
//
// It is never collapsed: the keyboard's total height is derived from it
// (`KeyboardMetrics.preferredKeyboardHeight`), and it must stay visible while the clipboard
// panel is open, because the panel replaces the key area only (UI-SPEC.md §8).

private struct KeyboardStrip: View {
    @ObservedObject var model: KeyboardViewModel
    @ObservedObject var clipboard: ClipboardController
    let theme: KeyboardTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            clipboardButton

            // The chip previews the freshest explicit save so pasting it costs one tap and never
            // opens the panel (CLIPBOARD.md §6). Scales in from the clipboard button rather than
            // just fading, so it visibly arrives from the action that created it.
            if let fresh = clipboard.freshItem, model.panel == .keys {
                PasteChip(text: fresh.text, theme: theme) {
                    model.insertClipboardItem(fresh)
                }
                .transition(
                    .scale(scale: 0.85, anchor: .leading).combined(with: .opacity)
                )
            }

            Spacer(minLength: 0)

            settingsButton

        }
        .padding(.horizontal, 8)
        .frame(height: KeyboardTheme.stripHeight)
        // `freshItem` flips outside any explicit withAnimation, so without this the chip's
        // `.transition` never runs and it snaps in and out.
        .animation(KeyboardMotion.resolved(KeyboardMotion.chip, reduceMotion: reduceMotion), value: clipboard.freshItem)
    }

    private var clipboardButton: some View {
        Button {
            model.toggleClipboard()
        } label: {
            Image(systemName: model.panel == .clipboard
                ? KeyboardIconography.keyboard
                : KeyboardIconography.clipboard)
                .font(.system(size: 15))
                .foregroundStyle(model.panel == .clipboard ? theme.accent : theme.keyLabel)
                .frame(width: 44, height: 44)
                .background(
                    theme.keyGradient(for: .function),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            model.panel == .clipboard ? theme.accent : theme.keyBorder,
                            lineWidth: model.panel == .clipboard ? 1.5 : theme.keyBorderWidth
                        )
                }
                .contentShape(Rectangle())
                .animation(KeyboardMotion.resolved(KeyboardMotion.toolbarState, reduceMotion: reduceMotion), value: model.panel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.panel == .clipboard ? "Back to keyboard" : "Clipboard")
        .accessibilityIdentifier("keyboard.toolbar.clipboard")
    }

    private var settingsButton: some View {
        Button { model.toggleSettings() } label: {
            Image(systemName: model.panel == .settings
                ? KeyboardIconography.keyboard
                : KeyboardIconography.settings)
                .font(.system(size: 15))
                .foregroundStyle(model.panel == .settings ? theme.accent : theme.keyLabel)
                .frame(width: 44, height: 44)
                .background(
                    theme.keyGradient(for: .function),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            model.panel == .settings ? theme.accent : theme.keyBorder,
                            lineWidth: model.panel == .settings ? 1.5 : theme.keyBorderWidth
                        )
                }
                .contentShape(Rectangle())
                .animation(KeyboardMotion.resolved(KeyboardMotion.toolbarState, reduceMotion: reduceMotion), value: model.panel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.panel == .settings ? "Back to keyboard" : "Keyboard settings")
        .accessibilityIdentifier("keyboard.toolbar.settings")
    }
}

/// The pill-shaped chip in the strip after a fresh explicit save (UI-SPEC.md §7).
private struct PasteChip: View {
    let text: String
    let theme: KeyboardTheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: KeyboardIconography.clipboardFilled)
                    .font(.system(size: 9))
                Text(text)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(theme.keyLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.keyGradient(for: .function), in: Capsule())
            .overlay {
                Capsule().stroke(theme.keyBorder, lineWidth: theme.keyBorderWidth)
            }
        }
        .buttonStyle(.plain)
        // VoiceOver reads the whole label; a truncated copy keeps it usable when the pasteboard
        // holds pages of text.
        .accessibilityLabel("Paste \(String(text.prefix(80)))")
    }
}

// MARK: - Key grid

/// Keys are drawn at absolute rects computed by ``KeyboardMetrics``, and the same rects are
/// used to hit-test touches — so what is drawn and what is touchable cannot drift apart.
///
/// Touches come from a UIKit overlay rather than SwiftUI gestures, because rollover (pressing
/// the next key before releasing the last) needs per-finger tracking that a `DragGesture`
/// cannot express.
private struct KeyGrid: View {
    @ObservedObject var model: KeyboardViewModel
    let theme: KeyboardTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            // iOS hands a keyboard extension 0×0, then full-screen, then a wrong height before
            // settling; solving against those produces briefly-wrong hit rects (C-45).
            let keys = KeyboardMetrics.isPlausible(geometry.size)
                ? KeyboardMetrics.positionedKeys(rows: model.rows, in: geometry.size)
                : []

            ZStack(alignment: .topLeading) {
                ForEach(keys) { positioned in
                    keyView(for: positioned)
                        .frame(width: positioned.rect.width, height: positioned.rect.height)
                        .position(x: positioned.rect.midX, y: positioned.rect.midY)
                }

                // Previews sit above every key so a top-row popup is not clipped by its
                // neighbours. A keyboard cannot draw above its own top edge, so the preview
                // for row 1 is inset downward rather than floating outside (C-45 territory).
                // Scales in from the key with a light overshoot and fades out plainly on
                // dismiss (UI-SPEC.md §4's appear/dismiss timing); Reduce Motion cuts both.
                ForEach(previewCandidates(in: keys)) { positioned in
                    KeyPreview(label: positioned.key.label, theme: theme)
                        .frame(width: positioned.rect.width * 1.35, height: positioned.rect.height * 1.1)
                        .position(
                            x: positioned.rect.midX,
                            y: max(positioned.rect.height * 0.6, positioned.rect.minY - positioned.rect.height * 0.55)
                        )
                        .transition(popupTransition)
                        .allowsHitTesting(false)
                }

                Group {
                    if let callout = model.callout {
                        CalloutBar(callout: callout, model: model, theme: theme)
                            .transition(popupTransition)
                    }
                }
                .allowsHitTesting(false)

                // The globe key is a real UIButton underneath this layer, so its area must
                // fall through rather than being consumed here (C-47).
                TouchTracker(
                    onTouches: { touches in
                        model.handle(touches: touches, positionedKeys: keys)
                    },
                    accessibilityKeys: accessibilityDescriptors(for: keys),
                    onAccessibilityAction: { action in
                        model.feedback.keyPressed(action: action)
                        model.perform(action)
                    },
                    passthroughRects: keys
                        .filter { $0.key.action == .nextKeyboard }
                        .map(\.hitRect)
                )
            }
            .onChange(of: geometry.size, perform: { _ in
                // Geometry changed under the fingers; anything still tracked is stale.
                model.releaseAllTouches()
            })
        }
    }

    /// Scale-from-the-key-plus-fade on appear, a plain quicker fade on dismiss — the
    /// appear/dismiss timing UI-SPEC.md §4 flags as unmeasured. Baked into the transition
    /// itself (rather than an ambient `.animation(value:)`) so it runs whenever the popup's
    /// membership changes without needing every call site to remember to wrap it.
    private var popupTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.85, anchor: .bottom)
                .combined(with: .opacity)
                .animation(KeyboardMotion.resolved(KeyboardMotion.popupAppear, reduceMotion: reduceMotion)),
            removal: .opacity
                .animation(KeyboardMotion.resolved(KeyboardMotion.popupDismiss, reduceMotion: reduceMotion))
        )
    }

    /// Only character-bearing keys preview. Space, shift, backspace, return and the layer
    /// keys never do — matching Gboard (UI-SPEC.md §4).
    private func previewCandidates(in keys: [PositionedKey]) -> [PositionedKey] {
        keys.filter { positioned in
            guard model.pressedKeyIDs.contains(positioned.id) else { return false }
            guard case .character = positioned.key.action else { return false }
            return true
        }
    }

    private func accessibilityDescriptors(for keys: [PositionedKey]) -> [KeyboardAccessibilityKey] {
        keys.compactMap { positioned in
            guard positioned.key.action != .nextKeyboard else { return nil }
            let semantics = accessibilitySemantics(for: positioned.key)
            return KeyboardAccessibilityKey(
                id: positioned.id,
                frame: positioned.hitRect,
                label: semantics.label,
                value: semantics.value,
                action: positioned.key.action
            )
        }
    }

    private func accessibilitySemantics(for key: Key) -> (label: String, value: String?) {
        switch key.action {
        case .character(let text): return (text, nil)
        case .backspace: return ("Delete", nil)
        case .space: return ("Space", "English US")
        case .newline: return (model.returnLabel.capitalized, nil)
        case .shift:
            let value = model.shiftState == .capsLock ? "Caps lock on" : (model.shiftState == .shifted ? "On" : "Off")
            return ("Shift", value)
        case .switchLayer(let layer):
            return (layer == .base ? "Letters" : "Numbers and symbols", nil)
        case .nextKeyboard: return ("Next keyboard", nil)
        case .diagnostics: return ("Diagnostics", nil)
        }
    }

    @ViewBuilder
    private func keyView(for positioned: PositionedKey) -> some View {
        if positioned.key.action == .nextKeyboard {
            NextKeyboardButton(theme: theme) { button in
                model.handler?.configureNextKeyboardButton(button)
            }
        } else {
            KeyFace(
                key: positioned.key,
                theme: theme,
                isPressed: model.pressedKeyIDs.contains(positioned.id),
                isActive: isActive(positioned.key)
            )
            // Drawing only — the touch layer above owns input. Without this SwiftUI competes
            // for the touch and walks its view tree on every touchesMoved for no benefit.
            .allowsHitTesting(false)
            // TouchTracker publishes one actionable accessibility element per physical key.
            // Hiding the drawing prevents VoiceOver from encountering an inert duplicate.
            .accessibilityHidden(true)
        }
    }

    /// Caps lock gets a distinct look so the state is visible at a glance.
    private func isActive(_ key: Key) -> Bool {
        key.action == .shift && model.shiftState == .capsLock
    }
}

// MARK: - Key rendering

private struct KeyFace: View {
    let key: Key
    let theme: KeyboardTheme
    let isPressed: Bool
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                .fill(theme.keyGradient(for: key.style))
                .overlay {
                    RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                        .stroke(
                            isActive ? theme.accent : theme.keyBorder,
                            lineWidth: isActive ? max(1.5, theme.keyBorderWidth) : theme.keyBorderWidth
                        )
                }
                .shadow(color: theme.shadowColor, radius: theme.shadowRadius, y: theme.shadowY)
                .shadow(color: theme.glowColor, radius: theme.glowRadius)
                .animation(KeyboardMotion.resolved(KeyboardMotion.themeChange, reduceMotion: reduceMotion), value: theme.id)
                .animation(KeyboardMotion.resolved(KeyboardMotion.keyActiveState, reduceMotion: reduceMotion), value: isActive)

            // Pressed keys darken rather than fade. The keyboard background is transparent
            // (iOS 26 glass), so an opacity drop lets the host app bleed through the key —
            // a dim overlay keeps it opaque and legible in both palettes. The overlay itself
            // never leaves the view tree — only its opacity animates — so press and release
            // crossfade instead of the highlight popping in and cutting out.
            RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                .fill(theme.pressedOverlay)
                .opacity(isPressed ? 1 : 0)
                .animation(
                    KeyboardMotion.resolved(
                        isPressed ? KeyboardMotion.keyPress : KeyboardMotion.keyRelease,
                        reduceMotion: reduceMotion
                    ),
                    value: isPressed
                )

            keyLabel

            // Digit hints on the top row. Long-press inserts them (UI-SPEC.md §5b); their
            // exact styling remains a Phase 3 comparison against the owner's Gboard reference.
            if let hint = KeyboardLayout.digitHints[key.label.lowercased()], key.style == .letter {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        Text(hint)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.hintGlyph)
                    }
                    Spacer()
                }
                .padding(.top, 3)
                .padding(.trailing, 4)
            }
        }
    }

    @ViewBuilder
    private var keyLabel: some View {
        if let symbol = KeyboardIconography.symbolName(for: key, isActive: isActive) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? theme.accent : theme.keyLabel)
                .animation(KeyboardMotion.resolved(KeyboardMotion.keyActiveState, reduceMotion: reduceMotion), value: isActive)
        } else {
            Text(key.label)
                .font(labelFont)
                .foregroundStyle(isActive ? theme.accent : theme.keyLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
                .animation(KeyboardMotion.resolved(KeyboardMotion.keyActiveState, reduceMotion: reduceMotion), value: isActive)
        }
    }

    private var labelFont: Font {
        switch key.action {
        case .space:
            return .system(size: 12, weight: .regular)
        case .newline, .switchLayer:
            return .system(size: 14, weight: .medium)
        default:
            return .system(size: 20, weight: .regular)
        }
    }
}

/// The accent / punctuation options shown while a key is held (UI-SPEC §5).
///
/// Laid out from the same numbers the model uses to decide which option the finger is over,
/// so what is highlighted is always what will be inserted. AOSP fills the row nearest the
/// finger first, so resource item 0 sits bottom-left and the grid grows upward.
private struct CalloutBar: View {
    let callout: KeyboardViewModel.CalloutState
    let model: KeyboardViewModel
    let theme: KeyboardTheme

    var body: some View {
        let option = model.calloutOptionSize(for: callout)
        let origin = model.calloutOrigin(for: callout)
        let columns = min(callout.columns, callout.options.count)

        VStack(spacing: 0) {
            ForEach(0..<callout.rows, id: \.self) { rowFromTop in
                let rowFromBottom = callout.rows - 1 - rowFromTop
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = rowFromBottom * callout.columns + column
                        if index < callout.options.count {
                            Text(callout.options[index])
                                .font(.system(size: 19))
                                .foregroundStyle(index == callout.selectedIndex ? theme.onAccent : theme.keyLabel)
                                .frame(width: option.width, height: option.height)
                                .background(
                                    index == callout.selectedIndex ? theme.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                                )
                        } else {
                            Color.clear.frame(width: option.width, height: option.height)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius + 2, style: .continuous)
                .fill(theme.popupBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius + 2, style: .continuous)
                        .stroke(theme.keyBorder, lineWidth: theme.keyBorderWidth)
                }
                .shadow(color: theme.shadowColor, radius: 2, y: 1)
                .shadow(color: theme.glowColor, radius: theme.glowRadius)
        )
        .position(
            x: origin.x + option.width * CGFloat(columns) / 2,
            y: origin.y + option.height * CGFloat(callout.rows) / 2
        )
    }
}

/// The enlarged character shown above a pressed key.
private struct KeyPreview: View {
    let label: String
    let theme: KeyboardTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius + 2, style: .continuous)
                .fill(theme.popupBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius + 2, style: .continuous)
                        .stroke(theme.keyBorder, lineWidth: theme.keyBorderWidth)
                }
                .shadow(color: theme.glowColor, radius: theme.glowRadius)
            Text(label)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(theme.keyLabel)
        }
    }
}

/// The globe key, as a real UIKit button.
///
/// It must respond to `.allTouchEvents` rather than a tap so that touch-and-hold opens the
/// system keyboard picker; a SwiftUI Button cannot express that (C-47).
private struct NextKeyboardButton: UIViewRepresentable {
    let theme: KeyboardTheme
    let configure: (UIButton) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: KeyboardIconography.globe), for: .normal)
        button.tintColor = UIColor(theme.keyLabel)
        button.backgroundColor = UIColor(theme.functionKeyFill)
        button.layer.cornerRadius = KeyboardTheme.keyCornerRadius
        button.layer.cornerCurve = .continuous
        applyTheme(to: button)
        button.accessibilityLabel = "Next keyboard"
        configure(button)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.tintColor = UIColor(theme.keyLabel)
        button.backgroundColor = UIColor(theme.functionKeyFill)
        applyTheme(to: button)
    }

    private func applyTheme(to button: UIButton) {
        button.layer.borderColor = UIColor(theme.keyBorder).cgColor
        button.layer.borderWidth = theme.keyBorderWidth
        button.layer.shadowColor = UIColor(theme.glowColor).cgColor
        button.layer.shadowOpacity = theme.glowRadius > 0 ? 1 : 0
        button.layer.shadowRadius = theme.glowRadius
        button.layer.shadowOffset = .zero
    }
}
