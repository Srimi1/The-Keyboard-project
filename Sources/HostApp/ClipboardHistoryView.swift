import SwiftUI
import UniformTypeIdentifiers

/// Full-size, manual-first history manager for the shared on-device store.
struct ClipboardHistoryView: View {
    @ObservedObject var clipboard: ClipboardController
    @ObservedObject var settings: KeyboardSettingsStore
    let testingClipboardText: String?
    let testingNow: Date?
    @State private var confirmingClear = false

    init(
        clipboard: ClipboardController,
        settings: KeyboardSettingsStore,
        testingClipboardText: String? = nil,
        testingNow: Date? = nil
    ) {
        self.clipboard = clipboard
        self.settings = settings
        self.testingClipboardText = testingClipboardText
        self.testingNow = testingNow
    }

    private var sections: (pinned: [ClipboardItem], recent: [ClipboardItem]) {
        clipboard.history.visible(at: Date())
    }

    var body: some View {
        List {
            consentAndSaveSection

            if let error = clipboard.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            } else if let notice = clipboard.notice {
                Section { Label(notice, systemImage: "info.circle") }
            }

            if sections.pinned.isEmpty && sections.recent.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing saved yet").font(.subheadline.weight(.semibold))
                        Text("Copy text, then tap Save current clipboard. Recent items disappear after one hour; pinned items remain until you delete them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !sections.pinned.isEmpty {
                Section("Pinned") { ForEach(sections.pinned) { row($0) } }
            }

            if !sections.recent.isEmpty {
                Section {
                    ForEach(sections.recent) { row($0) }
                } header: {
                    Text("Recent")
                } footer: {
                    Text("Unpinned items are hidden at the one-hour boundary and removed from storage the next time history is updated.")
                }
            }

            Section {
                Label {
                    Text("This app never watches the clipboard in the background. Only text supplied through the Save button is stored, and nothing is sent off this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.blue)
                }
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Clipboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { clipboard.refreshHistory() }
        .onDisappear {
            // Provider/capture work belongs to this screen. Confirmed pin/delete/clear work
            // is preserved by the controller and may finish after navigation.
            clipboard.cancelPendingInteractions()
        }
        .toolbar {
            if clipboard.canClearStorage {
                Button("Clear", role: .destructive) { confirmingClear = true }
                    .disabled(clipboard.isBusy)
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

    @ViewBuilder
    private var consentAndSaveSection: some View {
        Section {
            if !settings.values.hasAcceptedClipboardNotice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save clipboard history on this iPhone?")
                        .font(.subheadline.weight(.semibold))
                    Text("Only text you explicitly save is retained locally. Recent items expire after one hour; pinned items stay until you unpin, delete or clear them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Enable tap-to-save") { settings.acceptClipboardNotice() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            } else if settings.values.effectiveClipboardCaptureMode == .off {
                Button("Turn on tap-to-save") { settings.setClipboardCaptureMode(.manual) }
            } else {
                #if DEBUG
                if let testingClipboardText {
                    Button("Save test clipboard") {
                        clipboard.saveProvidedText(
                            testingClipboardText,
                            capturedAt: testingNow ?? Date()
                        )
                    }
                    .disabled(clipboard.isBusy)
                    .accessibilityIdentifier("host.clipboard.save")
                } else {
                    manualPasteButton
                }
                #else
                manualPasteButton
                #endif
            }
        } header: {
            Text("Save")
        } footer: {
            if settings.values.hasAcceptedClipboardNotice {
                Text("Automatic capture is unavailable until its permission and password-manager tests pass on a physical iPhone.")
            }
        }
    }

    private var manualPasteButton: some View {
                PasteButton(supportedContentTypes: [.plainText]) { providers in
                    clipboard.save(itemProviders: providers)
                }
                .disabled(clipboard.isBusy)
                .accessibilityIdentifier("host.clipboard.save")
    }

    private func row(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text).font(.callout).lineLimit(4)
            HStack(spacing: 4) {
                Text(item.pinned ? "Pinned" : RelativeAge.string(for: item.createdAt))
                if item.wasTruncated { Text("· shortened") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { clipboard.delete(id: item.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { clipboard.setPinned(!item.pinned, id: item.id) } label: {
                Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .accessibilityAction(named: item.pinned ? "Unpin" : "Pin") {
            clipboard.setPinned(!item.pinned, id: item.id)
        }
        .accessibilityAction(named: "Delete") { clipboard.delete(id: item.id) }
    }
}
