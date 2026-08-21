import SwiftUI
import UIKit

/// Renders the real keyboard inside the host app, typing into a local buffer instead of a
/// text field.
///
/// This exists for the M1 and M2 exit criteria, which are both "compare side by side against
/// the Gboard reference screenshots". Putting the keyboard on screen next to a reference
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
            model.syncWithTextField()
            // The host app's footprint, not the extension's — the number that counts against
            // the 40 MB budget is the one the keyboard reports when running inside another
            // app. This is here so the bar reads honestly rather than showing 0.0 MB.
            model.diagnostics.startMemoryMonitor()
        }
        .onDisappear {
            model.diagnostics.stopMemoryMonitor()
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
            stripHeight: KeyboardTheme.diagnosticsBarHeight
        )
    }

    /// The extension itself must stay transparent for iOS 26's glass container, so the
    /// preview supplies the background iOS would otherwise draw behind it.
    private var previewBackground: some View {
        KeyboardTheme.forColorScheme(.light).keyboardBackground
            .overlay(alignment: .top) { Divider() }
            .preferredColorScheme(nil)
    }
}

/// Stands in for the text field: collects typed characters and answers the trait questions
/// the model asks, so auto-capitalization and the return-key label behave as they would in a
/// real field.
@MainActor
final class PreviewActionHandler: ObservableObject, KeyboardActionHandler {

    @Published var text: String = ""

    func insert(_ text: String) {
        self.text.append(text)
    }

    func deleteBackward() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    func configureNextKeyboardButton(_ button: UIButton) {
        button.isEnabled = false   // no keyboard to switch to from inside the app
    }

    var hasFullAccess: Bool { true }
    var contextBeforeInput: String? { text }
    var autocapitalizationType: UITextAutocapitalizationType { .sentences }
    var returnKeyType: UIReturnKeyType { .default }
}
