import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var theme: KeyboardTheme { .forColorScheme(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(model: model, theme: theme)

            if model.showDiagnostics {
                DiagnosticsPanel(model: model, theme: theme)
            } else {
                KeyGrid(model: model, theme: theme)
            }
        }
        // Transparent, never an opaque fill — iOS 26 wraps keyboards in a system glass
        // container and an opaque background renders as a gray bar (CONSTRAINTS §8).
        .background(Color.clear)
    }
}

// MARK: - Status bar
//
// M0/M1 scaffolding. The real suggestion strip and toolbar arrive at M4 (UI-SPEC.md §7).

private struct StatusBar: View {
    @ObservedObject var model: KeyboardViewModel
    let theme: KeyboardTheme

    var body: some View {
        HStack(spacing: 8) {
            Text("M1")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.hintGlyph)

            Spacer()

            Text(String(format: "%.1f MB", model.diagnostics.memoryMB))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(memoryColor)

            Button {
                model.perform(.diagnostics)
            } label: {
                Text(model.showDiagnostics ? "Close" : "Diagnostics")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: KeyboardTheme.diagnosticsBarHeight)
    }

    private var memoryColor: Color {
        switch model.diagnostics.memoryVerdict {
        case .withinBudget: return theme.hintGlyph
        case .overBudget: return .orange
        case .critical: return .red
        }
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
                ForEach(previewCandidates(in: keys)) { positioned in
                    KeyPreview(label: positioned.key.label, theme: theme)
                        .frame(width: positioned.rect.width * 1.35, height: positioned.rect.height * 1.1)
                        .position(
                            x: positioned.rect.midX,
                            y: max(positioned.rect.height * 0.6, positioned.rect.minY - positioned.rect.height * 0.55)
                        )
                        .allowsHitTesting(false)
                }

                if let callout = model.callout {
                    CalloutBar(callout: callout, model: model, theme: theme)
                        .allowsHitTesting(false)
                }

                // The globe key is a real UIButton underneath this layer, so its area must
                // fall through rather than being consumed here (C-47).
                TouchTracker(
                    onTouches: { touches in
                        model.handle(touches: touches, positionedKeys: keys)
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

    /// Only character-bearing keys preview. Space, shift, backspace, return and the layer
    /// keys never do — matching Gboard (UI-SPEC.md §4).
    private func previewCandidates(in keys: [PositionedKey]) -> [PositionedKey] {
        keys.filter { positioned in
            guard model.pressedKeyIDs.contains(positioned.id) else { return false }
            guard case .character = positioned.key.action else { return false }
            return true
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                .fill(fill)

            Text(key.label)
                .font(labelFont)
                .foregroundStyle(isActive ? theme.accent : theme.keyLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)

            // Digit hints on the top row. Long-pressing to insert them is M2 (UI-SPEC.md §5b);
            // M1 renders the glyphs so the layout already reads like Gboard.
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

    private var fill: Color {
        let base = theme.fill(for: key.style)
        return isPressed ? base.opacity(0.55) : base
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
/// Positioned from the same numbers the model uses to decide which option the finger is over,
/// so what is highlighted is always what will be inserted.
private struct CalloutBar: View {
    let callout: KeyboardViewModel.CalloutState
    let model: KeyboardViewModel
    let theme: KeyboardTheme

    var body: some View {
        let optionWidth = model.calloutOptionWidth(for: callout)
        let originX = model.calloutOrigin(for: callout, optionWidth: optionWidth)
        let height = callout.anchor.height

        HStack(spacing: 0) {
            ForEach(Array(callout.options.enumerated()), id: \.offset) { index, option in
                Text(option)
                    .font(.system(size: 20))
                    .foregroundStyle(index == callout.selectedIndex ? Color.white : theme.keyLabel)
                    .frame(width: optionWidth, height: height)
                    .background(
                        index == callout.selectedIndex ? theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                    )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius + 2, style: .continuous)
                .fill(theme.popupBackground)
                .shadow(radius: 2, y: 1)
        )
        .position(
            x: originX + optionWidth * CGFloat(callout.options.count) / 2,
            // A keyboard cannot draw above its own top edge, so a callout on the top row sits
            // just below it rather than floating outside (C-45).
            y: max(height * 0.6, callout.anchor.minY - height * 0.65)
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
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = UIColor(theme.keyLabel)
        button.backgroundColor = UIColor(theme.functionKeyFill)
        button.layer.cornerRadius = KeyboardTheme.keyCornerRadius
        button.layer.cornerCurve = .continuous
        configure(button)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.tintColor = UIColor(theme.keyLabel)
        button.backgroundColor = UIColor(theme.functionKeyFill)
    }
}
