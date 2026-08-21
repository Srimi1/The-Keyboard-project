import SwiftUI

struct RootView: View {
    @StateObject private var diagnostics = HostDiagnostics()
    @Environment(\.scenePhase) private var scenePhase
    @State private var scratchText = ""
    @FocusState private var scratchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                milestoneSection
                previewSection
                tryItSection
                setupSection
                verdictSection
                keyboardReportSection
                aboutSection
            }
            .navigationTitle("Keyboard Project")
            .toolbar {
                Button("Refresh") { diagnostics.refresh() }
            }
        }
        .onAppear { diagnostics.refresh() }
        // Explicit `perform:` selects the single-value overload; the zero- and
        // two-parameter forms of onChange are iOS 17+.
        .onChange(of: scenePhase, perform: { phase in
            // The host app entering the foreground is one of the three clipboard capture
            // triggers (ARCHITECTURE.md §5); for now it just refreshes diagnostics.
            if phase == .active { diagnostics.refresh() }
        })
    }

    // MARK: - Sections

    private var milestoneSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("M0 — Foundations & feasibility spike")
                    .font(.headline)
                Text("Prove the extension loads, App Groups provisions, and the pasteboard behaves — before writing product code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var previewSection: some View {
        Section {
            NavigationLink {
                KeyboardPreviewView()
            } label: {
                Label("Keyboard preview", systemImage: "keyboard")
            }
        } footer: {
            Text("Renders the real keyboard inside this app — for comparing against Gboard reference screenshots without switching keyboards.")
        }
    }

    /// The M0 exit criterion is literally "type hello into a text field from your own
    /// keyboard" — this is that field, so the test does not depend on Notes or Safari.
    private var tryItSection: some View {
        Section {
            TextField("Tap here, switch to Keyboard Project, and type", text: $scratchText, axis: .vertical)
                .lineLimit(1...4)
                .focused($scratchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !scratchText.isEmpty {
                HStack {
                    Text("\(scratchText.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { scratchText = "" }
                        .font(.caption)
                }
            }
        } header: {
            Text("Try the keyboard")
        } footer: {
            Text("Switch keyboards with the globe key. Tap Diagnostics in the keyboard's own bar to run the M0 tests from inside the extension.")
        }
    }

    private var setupSection: some View {
        Section("Setup") {
            step(
                number: 1,
                title: "Add the keyboard",
                detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Keyboard Project",
                status: diagnostics.keyboardHasRun,
                doneNote: "The keyboard has run and reported back."
            )
            step(
                number: 2,
                title: "Allow Full Access",
                detail: "Same screen → tap Keyboard Project → Allow Full Access. Required for the clipboard, haptics and sound.",
                status: diagnostics.fullAccessStatus,
                doneNote: "Reported enabled by the extension."
            )
            step(
                number: 3,
                title: "Paste from Other Apps → Allow",
                detail: "Settings → Keyboard Project → Paste from Other Apps → Allow. Without it, every clipboard capture fires a system prompt.",
                status: diagnostics.pasteWithoutPromptStatus,
                doneNote: "The keyboard's pasteboard read returned without a prompt."
            )
        }
    }

    private var verdictSection: some View {
        Section {
            statusRow(
                title: "App Groups round trip",
                subtitle: diagnostics.appGroupAvailability?.summary ?? "not probed",
                status: diagnostics.appGroupRoundTripStatus
            )
            if !diagnostics.verdictIsConclusive {
                Label(
                    "Simulator — not a valid Q-01 answer. The simulator has no provisioning profile, so this only exercises the code. Run on a real iPhone signed with your free personal team before recording a verdict.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.blue)
            } else if diagnostics.appGroupRoundTripStatus == .failed {
                Label(
                    "App Groups did not provision on this account. Per ADR-004, buy the $99 Apple Developer Program today — the clipboard architecture depends on it.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Test 1 — the decisive one (Q-01)")
        } footer: {
            Text("A report written by the keyboard extension and read here proves the shared container works across processes.")
        }
    }

    @ViewBuilder
    private var keyboardReportSection: some View {
        if let report = diagnostics.keyboardReport {
            Section("Last report from the keyboard") {
                labeled("Recorded", report.recordedAt.formatted(date: .abbreviated, time: .standard))
                labeled("Device", report.deviceModel)
                labeled("OS", report.osVersion)
                labeled("App Group", report.appGroupSummary)
                labeled("Full Access", report.hasFullAccess.map { $0 ? "enabled" : "off" } ?? "unknown")
                if let mb = report.physFootprintMB {
                    labeled("Keyboard memory", String(format: "%.1f MB / %.0f MB budget", mb, MemoryReporter.budgetMB))
                }
                if let probe = report.pasteboard {
                    labeled("Pasteboard changeCount", "\(probe.changeCount)")
                    labeled("Pasteboard hasStrings", probe.hasStrings ? "yes" : "no")
                    if let ms = probe.readDurationMS {
                        labeled("Value read took", String(format: "%.0f ms", ms))
                    }
                }
            }
        } else {
            Section("Last report from the keyboard") {
                Text("None yet. Open any app, switch to the Keyboard Project keyboard, and tap Diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            labeled("Host app memory", MemoryReporter.physFootprintMB().map { String(format: "%.1f MB", $0) } ?? "unknown")
            labeled("App Group", AppGroup.identifier)
            if let last = diagnostics.lastRefresh {
                labeled("Last refresh", last.formatted(date: .omitted, time: .standard))
            }
        }
    }

    // MARK: - Building blocks

    private func step(number: Int, title: String, detail: String, status: HostDiagnostics.StepStatus, doneNote: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)").font(.subheadline.weight(.semibold))
                Text(status == .done ? doneNote : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusRow(title: String, subtitle: String, status: HostDiagnostics.StepStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).multilineTextAlignment(.trailing)
        }
    }
}
