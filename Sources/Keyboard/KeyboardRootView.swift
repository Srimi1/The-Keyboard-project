import SwiftUI
import UIKit

/// What the keyboard can do to the text field. Implemented by the view controller so the
/// SwiftUI layer never touches `textDocumentProxy` directly.
@MainActor
protocol KeyboardActionHandler: AnyObject {
    func insert(_ text: String)
    func deleteBackward()
    /// Wires a real UIButton to `handleInputModeList(from:with:)`. A SwiftUI Button calling
    /// `advanceToNextInputMode()` handles only tap and silently loses the long-press keyboard
    /// picker, so the globe key has to be a UIKit button (C-21).
    func configureNextKeyboardButton(_ button: UIButton)
    var hasFullAccess: Bool { get }
}

@MainActor
final class KeyboardViewModel: ObservableObject {
    @Published var layer: KeyboardLayer = .base
    @Published var shift: ShiftState = .shifted   // sentence start (auto-capitalization is M1)
    @Published var showDiagnostics = false
    @Published var needsGlobe: Bool = false

    let diagnostics = DiagnosticsRunner()
    weak var handler: KeyboardActionHandler?

    var rows: [KeyRow] {
        KeyboardLayout.rows(layer: layer, shift: shift, needsGlobe: needsGlobe)
    }

    func handle(_ action: KeyAction) {
        guard let handler else { return }

        switch action {
        case .character(let text):
            handler.insert(text)
            if shift == .shifted { shift = .off }

        case .space:
            handler.insert(" ")
            if shift == .shifted { shift = .off }

        case .newline:
            handler.insert("\n")

        case .backspace:
            handler.deleteBackward()

        case .shift:
            switch shift {
            case .off: shift = .shifted
            case .shifted: shift = .capsLock   // M1 replaces this with the double-tap timing rule
            case .capsLock: shift = .off
            }

        case .switchLayer(let target):
            layer = target

        case .nextKeyboard:
            break   // handled by NextKeyboardButton, which needs UIKit target-action

        case .diagnostics:
            showDiagnostics.toggle()
            if showDiagnostics {
                diagnostics.runSafeProbes(hasFullAccess: handler.hasFullAccess)
            }
        }
    }
}

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
// M0 only. The real suggestion strip and toolbar arrive at M4 (UI-SPEC.md §7).

private struct StatusBar: View {
    @ObservedObject var model: KeyboardViewModel
    let theme: KeyboardTheme

    var body: some View {
        HStack(spacing: 8) {
            Text("M0 spike")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.hintGlyph)

            Spacer()

            Text(String(format: "%.1f MB", model.diagnostics.memoryMB))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(memoryColor)

            Button {
                model.handle(.diagnostics)
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

// MARK: - Keys

private struct KeyGrid: View {
    @ObservedObject var model: KeyboardViewModel
    let theme: KeyboardTheme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            VStack(spacing: KeyboardTheme.rowSpacing) {
                ForEach(model.rows) { row in
                    HStack(spacing: KeyboardTheme.keySpacing) {
                        if row.leadingInset > 0 {
                            Spacer().frame(width: width * row.leadingInset)
                        }
                        ForEach(row.keys) { key in
                            Group {
                                if key.action == .nextKeyboard {
                                    NextKeyboardButton(theme: theme) { button in
                                        model.handler?.configureNextKeyboardButton(button)
                                    }
                                } else {
                                    KeyButton(key: key, theme: theme) {
                                        model.handle(key.action)
                                    }
                                }
                            }
                            .frame(width: keyWidth(for: key, totalWidth: width, row: row))
                        }
                        if row.leadingInset > 0 {
                            Spacer().frame(width: width * row.leadingInset)
                        }
                    }
                }
            }
            .padding(.vertical, KeyboardTheme.keyboardVerticalPadding)
            .frame(width: width)
        }
    }

    /// Widths are fractions of keyboard width (AOSP LatinIME, UI-SPEC.md §1). Inter-key
    /// spacing is subtracted proportionally so a row still sums to the full width.
    private func keyWidth(for key: Key, totalWidth: CGFloat, row: KeyRow) -> CGFloat {
        let gapCount = CGFloat(row.keys.count - 1)
        let totalGap = gapCount * KeyboardTheme.keySpacing
        let usableWidth = totalWidth - totalGap - (totalWidth * row.leadingInset * 2)
        let fractionSum = row.keys.reduce(0) { $0 + $1.widthFraction }
        return usableWidth * (key.widthFraction / fractionSum)
    }
}

/// The globe key, as a real UIKit button.
///
/// It must respond to `.allTouchEvents` rather than a tap so that touch-and-hold opens the
/// system keyboard picker; a SwiftUI Button cannot express that (C-21).
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

private struct KeyButton: View {
    let key: Key
    let theme: KeyboardTheme
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KeyboardTheme.keyCornerRadius, style: .continuous)
                .fill(theme.fill(for: key.style))
                .opacity(isPressed ? 0.6 : 1)

            Text(key.label)
                .font(labelFont)
                .foregroundStyle(theme.keyLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Digit hints on the top row. Long-press to insert them is M2 (UI-SPEC.md §5b).
            if let hint = KeyboardLayout.digitHints[key.label.lowercased()], key.style == .letter {
                VStack {
                    HStack {
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
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        // A DragGesture with zero minimum distance gives press-in/release semantics and,
        // unlike Button, lets M1 add slide-off cancellation (UI-SPEC.md §3).
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    isPressed = false
                    onTap()
                }
        )
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
