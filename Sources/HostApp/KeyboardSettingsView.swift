import SwiftUI

struct KeyboardSettingsView: View {
    @ObservedObject var settings: KeyboardSettingsStore
    @ObservedObject var clipboard: ClipboardController
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section("Feedback") {
                Toggle("Haptic feedback", isOn: Binding(
                    get: { settings.values.hapticsEnabled },
                    set: { settings.setHapticsEnabled($0) }
                ))
                Toggle("Keypress sound", isOn: Binding(
                    get: { settings.values.soundEnabled },
                    set: { settings.setSoundEnabled($0) }
                ))
            }

            Section("Appearance") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(KeyboardAppearance.allCases, id: \.self) { appearance in
                            Button {
                                settings.setAppearance(appearance)
                            } label: {
                                ThemeSwatch(
                                    appearance: appearance,
                                    theme: theme(for: appearance),
                                    isSelected: settings.values.appearance == appearance
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                if settings.values.hasAcceptedClipboardNotice {
                    Toggle("Tap to save", isOn: Binding(
                        get: { settings.values.effectiveClipboardCaptureMode != .off },
                        set: { settings.setClipboardCaptureMode($0 ? .manual : .off) }
                    ))
                } else {
                    Button("Enable tap-to-save") { settings.acceptClipboardNotice() }
                }

                if clipboard.canClearStorage {
                    Button("Clear all clipboard history", role: .destructive) {
                        confirmingClear = true
                    }
                    .disabled(clipboard.isBusy)
                }
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Clipboard history is local and manual-first. Automatic capture remains unavailable until physical-device privacy tests pass.")
            }

            if let error = settings.persistenceError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Keyboard settings")
        .onAppear {
            settings.refresh(canUseShared: true)
            clipboard.refreshHistory()
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

    private func theme(for appearance: KeyboardAppearance) -> KeyboardTheme {
        switch appearance {
        case .system: KeyboardTheme.forColorScheme(colorScheme)
        case .light: .light
        case .dark: .black
        case .neon: .neon
        }
    }
}

private struct ThemeSwatch: View {
    let appearance: KeyboardAppearance
    let theme: KeyboardTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.keyGradient(for: index == 2 ? .function : .letter))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(theme.keyBorder, lineWidth: theme.keyBorderWidth)
                        }
                        .shadow(color: theme.glowColor, radius: theme.glowRadius)
                        .frame(width: 20, height: 25)
                }
            }

            Text(appearance.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.keyLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(theme.canvasGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? theme.accent : theme.keyBorder, lineWidth: isSelected ? 2 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appearance.displayName) theme")
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}
