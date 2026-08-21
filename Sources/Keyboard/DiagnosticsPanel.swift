import SwiftUI

/// The M0 test results, shown inside the keyboard itself.
///
/// This lives in the keyboard rather than the host app because the answers only count when
/// measured in the extension process. Read the verdicts here, then record them in
/// CONSTRAINTS.md §10 against Q-01, Q-03 and Q-05.
struct DiagnosticsPanel: View {
    @ObservedObject var model: KeyboardViewModel
    let theme: KeyboardTheme

    private var runner: DiagnosticsRunner { model.diagnostics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                row("Device", DeviceInfo.model)
                row("OS", DeviceInfo.osVersion)

                divider

                // Q-01 — the decisive M0 test. If this is not "working", buy the
                // $99 program today (ADR-004).
                sectionTitle("Test 1 — App Groups (Q-01)")
                verdictRow(
                    "Container + write",
                    value: runner.appGroupAvailability?.summary ?? "not run",
                    ok: runner.appGroupAvailability?.isWorking
                )
                verdictRow(
                    "Report saved for host app",
                    value: saveStatusText,
                    ok: runner.reportSaveSucceeded
                )
                Text("Open the host app to confirm it can read this report back.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.hintGlyph)

                divider

                sectionTitle("Full Access (C-06)")
                verdictRow(
                    "hasFullAccess",
                    value: (model.handler?.hasFullAccess ?? false) ? "enabled" : "OFF",
                    ok: model.handler?.hasFullAccess
                )

                divider

                // Q-05 — prompt-free probes always run; the value read is user-initiated
                // because it is the call that can prompt (C-14).
                sectionTitle("Test 3 — Pasteboard (Q-05)")
                if let probe = runner.pasteboard {
                    row("changeCount", "\(probe.changeCount)")
                    row("hasStrings", probe.hasStrings ? "yes" : "no")

                    if probe.valueReadAttempted {
                        verdictRow(
                            "Verdict",
                            value: probe.outcome.rawValue,
                            ok: probe.outcome == .allowedSilently
                        )
                        if probe.valueReceived {
                            row("Received", "\(probe.characterCount ?? 0) chars")
                        }
                        if let ms = probe.readDurationMS {
                            row("Read took", String(format: "%.0f ms", ms))
                        }
                    } else {
                        Text("Prompt-free probes only. The value read is the call that can prompt.")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.hintGlyph)
                    }
                } else {
                    Text("not run").font(.system(size: 12)).foregroundStyle(theme.hintGlyph)
                }

                Button {
                    runner.readPasteboardValue(hasFullAccess: model.handler?.hasFullAccess ?? false)
                } label: {
                    Text("Read pasteboard value (may prompt)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                divider

                sectionTitle("Memory (C-10, Q-04)")
                verdictRow(
                    "phys_footprint",
                    value: String(format: "%.1f MB / %.0f MB budget", runner.memoryMB, MemoryReporter.budgetMB),
                    ok: runner.memoryVerdict == .withinBudget
                )
                if let ceiling = runner.measuredCeilingMB {
                    row("Jetsam limit (measured)", String(format: "%.0f MB", ceiling))
                } else {
                    Text("Kernel did not report limit_bytes_remaining — falling back to the ~60 MB estimate.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.hintGlyph)
                }

                divider

                if let host = runner.hostAppReport() {
                    sectionTitle("Host app report (round trip ✓)")
                    row("Written", host.recordedAt.formatted(date: .abbreviated, time: .standard))
                    row("App Group", host.appGroupSummary)
                } else {
                    Text("No host-app report yet — open the host app and tap Run diagnostics.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.hintGlyph)
                }

                Button {
                    runner.runSafeProbes(hasFullAccess: model.handler?.hasFullAccess ?? false)
                } label: {
                    Text("Re-run safe probes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
        }
    }

    private var saveStatusText: String {
        switch runner.reportSaveSucceeded {
        case .some(true): return "saved"
        case .some(false): return "WRITE FAILED"
        case nil: return "not run"
        }
    }

    private var divider: some View {
        Rectangle().fill(theme.hintGlyph.opacity(0.25)).frame(height: 1)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.keyLabel)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.hintGlyph)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.keyLabel)
                .multilineTextAlignment(.trailing)
        }
    }

    private func verdictRow(_ label: String, value: String, ok: Bool?) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.hintGlyph)
            Spacer()
            HStack(spacing: 4) {
                if let ok {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ok ? Color.green : Color.red)
                }
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.keyLabel)
            }
        }
    }
}
