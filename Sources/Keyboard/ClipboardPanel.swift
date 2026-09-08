import SwiftUI
import UniformTypeIdentifiers

/// Manual-first clipboard history. The strip remains visible while this replaces the keys.
struct ClipboardPanel: View {
    @ObservedObject var model: KeyboardViewModel
    @ObservedObject var clipboard: ClipboardController
    @ObservedObject var settings: KeyboardSettingsStore
    let theme: KeyboardTheme

    private var sections: (pinned: [ClipboardItem], recent: [ClipboardItem]) {
        clipboard.history.visible(at: Date())
    }

    private var isEmpty: Bool {
        sections.pinned.isEmpty && sections.recent.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = clipboard.lastError {
                statusBanner(error, systemImage: "exclamationmark.triangle.fill", color: .red)
            } else if let notice = clipboard.notice {
                statusBanner(notice, systemImage: "info.circle.fill", color: theme.accent)
            }

            if !settings.values.hasAcceptedClipboardNotice {
                consentState
            } else if clipboard.needsFullAccess && isEmpty {
                noAccessState
            } else if settings.values.effectiveClipboardCaptureMode == .off && isEmpty {
                captureOffState
            } else if isEmpty {
                emptyState
            } else {
                itemGrid
            }
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
            .accessibilityIdentifier("keyboard.clipboard.back")

            Text("Clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.keyLabel)

            Spacer(minLength: 4)

            if clipboard.canSave {
                PasteButton(supportedContentTypes: [.plainText]) { providers in
                    clipboard.save(itemProviders: providers)
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
                .tint(theme.accent)
                .disabled(clipboard.isBusy)
                .accessibilityLabel("Save current clipboard")
                .accessibilityIdentifier("keyboard.clipboard.save")
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 44)
    }

    private var itemGrid: some View {
        VStack(spacing: 0) {
            if clipboard.needsFullAccess {
                statusBanner(
                    "Full Access is off. Cached items can still be pasted, but new items cannot be saved.",
                    systemImage: "lock.fill",
                    color: theme.hintGlyph
                )
            } else if settings.values.effectiveClipboardCaptureMode == .off {
                statusBanner(
                    "Saving is off. Existing history stays available until you clear it.",
                    systemImage: "pause.circle.fill",
                    color: theme.hintGlyph
                )
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !sections.pinned.isEmpty {
                        sectionHeader("PINNED")
                        grid(for: sections.pinned)
                    }
                    if !sections.recent.isEmpty {
                        sectionHeader("RECENT")
                        grid(for: sections.recent)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    private func grid(for items: [ClipboardItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            ForEach(items) { item in
                ClipboardCell(item: item, theme: theme) {
                    model.insertClipboardItem(item)
                } onPin: {
                    clipboard.setPinned(!item.pinned, id: item.id)
                } onDelete: {
                    clipboard.delete(id: item.id)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(theme.hintGlyph)
            .padding(.top, 4)
    }

    private var consentState: some View {
        VStack(spacing: 10) {
            message(
                icon: "hand.raised.fill",
                title: "Save clipboard history on this iPhone?",
                detail: "Only text you explicitly save is stored. Recent items expire after one hour; pinned items remain until you delete them. Nothing is sent off this phone."
            )
            Button("Enable tap-to-save") { model.acceptClipboardNotice() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .accessibilityIdentifier("keyboard.clipboard.enable")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        message(
            icon: "doc.on.clipboard",
            title: "Nothing saved yet",
            detail: "Tap Save after copying text. Automatic capture stays off until its privacy behavior is verified on your iPhone."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noAccessState: some View {
        message(
            icon: "lock.fill",
            title: "Full Access is off",
            detail: "Typing still works. To save shared clipboard history, enable Full Access in Settings → General → Keyboard → Keyboards → Keyboard Project."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captureOffState: some View {
        VStack(spacing: 10) {
            message(
                icon: "pause.circle.fill",
                title: "Clipboard saving is off",
                detail: "Turn tap-to-save back on when you want to keep text locally."
            )
            Button("Turn on tap-to-save") { model.setClipboardCaptureMode(.manual) }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusBanner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .lineLimit(2)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(theme.functionKeyFill.opacity(0.75))
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(theme.hintGlyph)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.keyLabel)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(theme.hintGlyph)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

private struct ClipboardCell: View {
    let item: ClipboardItem
    let theme: KeyboardTheme
    let onTap: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.keyLabel)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 3) {
                    if item.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 8))
                    }
                    Text(item.pinned ? "Pinned" : RelativeAge.string(for: item.createdAt))
                    if item.wasTruncated { Text("· shortened") }
                    Spacer()
                }
                .font(.system(size: 9))
                .foregroundStyle(theme.hintGlyph)
            }
            .padding(8)
            .frame(height: 72, alignment: .topLeading)
            .background(theme.letterKeyFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(CellPressStyle())
        .contextMenu {
            Button(action: onPin) {
                Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(String(item.text.prefix(120)))
        .accessibilityValue(item.pinned ? "Pinned clipboard item" : "Recent clipboard item")
        .accessibilityHint("Double tap to paste")
        .accessibilityAction(named: item.pinned ? "Unpin" : "Pin", onPin)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

private struct CellPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

nonisolated enum RelativeAge {
    static func string(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<120: return "1 min ago"
        default: return "\(seconds / 60) min ago"
        }
    }
}
