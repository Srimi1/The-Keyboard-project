// Development-only, with the rest of the development surface (ADR-011). Both call
// sites — RootView's preview row and the `-keyboardPreview` launch argument — are
// Debug-gated, so this whole file compiles out of Release.
#if DEBUG

import SwiftUI
import UIKit

/// Renders the real keyboard inside the host app, typing into a local buffer instead of a
/// text field.
///
/// This exists for the Phase 3 visual gate: compare side by side against the owner's Gboard
/// reference screenshots. Putting the keyboard on screen next to a reference
/// image beats switching keyboards in another app and screenshotting from there — and it
/// works before the extension is even installed.
///
/// It draws the same `KeyboardRootView` the extension does, so what you compare is the real
/// thing, not a mock-up.
struct KeyboardPreviewView: View {
    @StateObject private var model = KeyboardViewModel()
    @StateObject private var handler = PreviewActionHandler()

    var body: some View {
        VStack(spacing: 0) {
            typedTextPane

            Divider()

            KeyboardRootView(model: model)
                .frame(height: previewHeight)
                .background(previewBackground)
        }
        .navigationTitle("Keyboard preview")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.handler = handler
            // Mirror a live extension appearance, but the clipboard remains manual-first.
            model.activate(hasFullAccess: handler.hasFullAccess)
            applyRequestedPreviewOptions()
            model.syncWithTextField()
            // The host app's footprint, not the extension's — the number that counts against
            // the 40 MB budget is the one the keyboard reports when running inside another
            // app. This is here so the bar reads honestly rather than showing 0.0 MB.
            // The preview drives the same clipboard the extension does, so the panel, the
            // paste chip and explicit clipboard save flow can all be exercised here rather than
            // only on a device with the keyboard installed.
            // Lets the clipboard panel be captured without a tap, the same way
            // `-keyboardPreview` scripts the keyboard itself:
            //     xcrun simctl launch <device> com.srijan.keyboardproject -keyboardPreview -clipboardPanel
            if ProcessInfo.processInfo.arguments.contains("-clipboardPanel") {
                model.showPanel(.clipboard)
            }
            #if DEBUG
            model.diagnostics.startMemoryMonitor()
            #endif
        }
        .onDisappear {
            model.deactivate()
            #if DEBUG
            model.diagnostics.stopMemoryMonitor()
            #endif
        }
    }

    private var typedTextPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(handler.text.isEmpty ? "Type on the keyboard below." : handler.text)
                    .font(.body)
                    .foregroundStyle(handler.text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if !handler.text.isEmpty {
                    Button("Clear") { handler.text = "" }
                        .font(.caption)
                }

                Text("Shift: \(shiftDescription)   •   \(handler.text.count) characters")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
    }

    private var shiftDescription: String {
        switch model.shiftState {
        case .off: return "off"
        case .shifted: return "shifted"
        case .capsLock: return "caps lock"
        }
    }

    /// Matches what the extension asks for, so the proportions on screen are the real ones.
    private var previewHeight: CGFloat {
        KeyboardMetrics.preferredKeyboardHeight(
            rowCount: model.rows.count,
            width: UIScreen.main.bounds.width,
            stripHeight: KeyboardTheme.stripHeight
        )
    }

    /// The extension itself must stay transparent for iOS 26's glass container, so the
    /// preview supplies the background iOS would otherwise draw behind it.
    private var previewBackground: some View {
        KeyboardPreviewBackdrop(settings: model.settings)
            .overlay(alignment: .top) { Divider() }
    }

    /// Allows deterministic repository previews without adding a shipping-only control:
    /// `-keyboardPreview -keyboardTheme neon -keyboardGlobe -cleanPreview`.
    private func applyRequestedPreviewOptions() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-keyboardGlobe") {
            // The owner's measured device layout includes the system next-keyboard key. The
            // host preview has no controller to report that value, so clean asset captures opt
            // in explicitly while ordinary UI tests retain their calibrated comma layout.
            model.needsGlobe = true
        }
        guard let flag = arguments.firstIndex(of: "-keyboardTheme"),
              arguments.indices.contains(flag + 1) else { return }
        let requested = arguments[flag + 1]
        let appearance = requested == "black"
            ? KeyboardAppearance.dark
            : KeyboardAppearance(rawValue: requested)
        if let appearance {
            model.setAppearance(appearance)
        }
    }
}

private struct KeyboardPreviewBackdrop: View {
    @ObservedObject var settings: KeyboardSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: KeyboardTheme {
        switch settings.values.appearance {
        case .system: KeyboardTheme.forColorScheme(colorScheme)
        case .light: .light
        case .dark: .black
        case .neon: .neon
        }
    }

    var body: some View {
        theme.canvasGradient
    }
}

/// Stands in for the text field: collects typed characters and answers the trait questions
/// the model asks, so auto-capitalization and the return-key label behave as they would in a
/// real field.
@MainActor
final class PreviewActionHandler: ObservableObject, KeyboardActionHandler {

    @Published var text: String = ""
    @Published var cursorOffset: Int = 0

    func insert(_ text: String) {
        self.text.append(text)
    }

    func deleteBackward() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    /// The preview has no real caret, so a slide is recorded rather than applied.
    func adjustTextPosition(by offset: Int) {
        cursorOffset += offset
    }

    func configureNextKeyboardButton(_ button: UIButton) {
        // The host preview has no keyboard list to switch, but leaving the inert control enabled
        // renders the same tint/contrast used by the live extension.
        button.isEnabled = true
    }

    var hasFullAccess: Bool { true }
    var contextBeforeInput: String? { text }
    var autocapitalizationType: UITextAutocapitalizationType { .sentences }
    var returnKeyType: UIReturnKeyType { .default }
}

#endif
