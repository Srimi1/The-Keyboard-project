import SwiftUI

/// Preferences that must be reachable without launching the containing app.
struct KeyboardSettingsPanel: View {
    @ObservedObject var model: KeyboardViewModel
    @ObservedObject var settings: KeyboardSettingsStore
    @ObservedObject var clipboard: ClipboardController
    let theme: KeyboardTheme

    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    feedbackCard
                    appearanceCard
                    clipboardCard
                    if let error = settings.persistenceError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .confirmationDialog(
            "Delete all clipboard history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) { clipboard.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clipboard.lastError == nil
                ? "Pinned items are deleted too. This cannot be undone."
                : "This discards the unreadable clipboard file and every recoverable copy. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.showPanel(.keys) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .accessibilityLabel("Back to keyboard")

            Text("Keyboard settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.keyLabel)
            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(height: 44)
    }

    private var feedbackCard: some View {
        settingsCard("Feedback") {
            Toggle("Haptic feedback", isOn: Binding(
                get: { settings.values.hapticsEnabled },
                set: { model.setHapticsEnabled($0) }
            ))
            Toggle("Keypress sound", isOn: Binding(
                get: { settings.values.soundEnabled },
                set: { model.setSoundEnabled($0) }
            ))
        }
    }

    private var appearanceCard: some View {
        settingsCard("Appearance") {
            Picker("Appearance", selection: Binding(
                get: { settings.values.appearance },
                set: { model.setAppearance($0) }
            )) {
                Text("System").tag(KeyboardAppearance.system)
                Text("Light").tag(KeyboardAppearance.light)
                Text("Dark").tag(KeyboardAppearance.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var clipboardCard: some View {
        settingsCard("Clipboard") {
            if settings.values.hasAcceptedClipboardNotice {
                Toggle("Tap to save", isOn: Binding(
                    get: { settings.values.effectiveClipboardCaptureMode != .off },
                    set: { model.setClipboardCaptureMode($0 ? .manual : .off) }
                ))
                Text("Automatic capture stays unavailable until paste permissions and password-manager behavior pass on-device tests.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.hintGlyph)
            } else {
                Text("Clipboard history is disabled until you accept the local-retention notice in the Clipboard panel.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.hintGlyph)
                Button("Review clipboard notice") { model.showPanel(.clipboard) }
                    .font(.system(size: 11, weight: .semibold))
            }

            if clipboard.canClearStorage {
                Button("Clear all history", role: .destructive) { confirmingClear = true }
                    .font(.system(size: 11, weight: .semibold))
                    .disabled(clipboard.isBusy)
            }
        }
    }

    private func settingsCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.hintGlyph)
            content()
                .font(.system(size: 12))
                .foregroundStyle(theme.keyLabel)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.letterKeyFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
