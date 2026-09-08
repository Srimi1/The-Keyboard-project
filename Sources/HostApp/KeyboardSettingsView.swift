import SwiftUI

struct KeyboardSettingsView: View {
    @ObservedObject var settings: KeyboardSettingsStore
    @ObservedObject var clipboard: ClipboardController
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
                Picker("Theme", selection: Binding(
                    get: { settings.values.appearance },
                    set: { settings.setAppearance($0) }
                )) {
                    Text("System").tag(KeyboardAppearance.system)
                    Text("Light").tag(KeyboardAppearance.light)
                    Text("Dark").tag(KeyboardAppearance.dark)
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
}
