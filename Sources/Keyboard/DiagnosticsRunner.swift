import Foundation
import SwiftUI
import UIKit

/// Runs the M0 empirical tests from inside the keyboard extension process, which is the
/// only place they mean anything — App Group writes, Full Access, and pasteboard reads all
/// behave differently here than in the host app.
///
/// Results are shown in the keyboard's own panel *and* written to the App Group. The host
/// app reading one back is the proof that App Groups provisioned (Q-01, ROADMAP M0 Test 1).
@MainActor
final class DiagnosticsRunner: ObservableObject {

    @Published private(set) var appGroupAvailability: AppGroup.Availability?
    @Published private(set) var reportSaveSucceeded: Bool?
    @Published private(set) var pasteboard: DiagnosticsReport.PasteboardProbe?
    @Published private(set) var memoryMB: Double = 0
    @Published private(set) var lastRunAt: Date?

    private var memoryTimer: Timer?

    // MARK: - Memory (C-10)

    func startMemoryMonitor() {
        refreshMemory()
        memoryTimer?.invalidate()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMemory() }
        }
    }

    func stopMemoryMonitor() {
        memoryTimer?.invalidate()
        memoryTimer = nil
    }

    func refreshMemory() {
        memoryMB = MemoryReporter.physFootprintMB() ?? 0
    }

    var memoryVerdict: MemoryReporter.Verdict {
        MemoryReporter.verdict(forMB: memoryMB)
    }

    // MARK: - Test 1: App Groups + report round trip (Q-01)

    /// Safe to call any time — touches nothing that can prompt the user.
    func runSafeProbes(hasFullAccess: Bool) {
        refreshMemory()

        let availability = AppGroup.probeAvailability()
        appGroupAvailability = availability

        let probe = probePasteboardWithoutReading()
        pasteboard = probe

        let report = DiagnosticsReport(
            source: .keyboard,
            recordedAt: Date(),
            osVersion: DeviceInfo.osVersion,
            deviceModel: DeviceInfo.model,
            appGroupSummary: availability.summary,
            appGroupWorking: availability.isWorking,
            hasFullAccess: hasFullAccess,
            pasteboard: probe,
            physFootprintMB: memoryMB
        )

        reportSaveSucceeded = DiagnosticsStore.save(report)
        lastRunAt = Date()
    }

    /// The most recent report the *host app* wrote, if any — confirms the channel works
    /// in both directions.
    func hostAppReport() -> DiagnosticsReport? {
        DiagnosticsStore.load(.hostApp)
    }

    // MARK: - Test 3: Pasteboard (Q-05)

    /// changeCount and hasStrings never trigger the "Allow Paste" alert (C-16), so this
    /// costs nothing and can run on every appearance.
    private func probePasteboardWithoutReading() -> DiagnosticsReport.PasteboardProbe {
        let pasteboard = UIPasteboard.general
        return DiagnosticsReport.PasteboardProbe(
            changeCount: pasteboard.changeCount,
            hasStrings: pasteboard.hasStrings,
            valueReadAttempted: false,
            valueReceived: false,
            characterCount: nil,
            readDurationMS: nil
        )
    }

    /// Reads the actual pasteboard value — **this is the call that can prompt** (C-14).
    /// User-initiated only. Timing it is the only available signal for whether the prompt
    /// appeared, since iOS exposes none (Q-05).
    func readPasteboardValue(hasFullAccess: Bool) {
        let general = UIPasteboard.general
        let changeCount = general.changeCount
        let hasStrings = general.hasStrings

        let start = Date()
        let value = general.string
        let elapsedMS = Date().timeIntervalSince(start) * 1000

        pasteboard = DiagnosticsReport.PasteboardProbe(
            changeCount: changeCount,
            hasStrings: hasStrings,
            valueReadAttempted: true,
            valueReceived: value != nil,
            characterCount: value?.count,
            readDurationMS: elapsedMS
        )

        runSafeProbesPreservingPasteboard(hasFullAccess: hasFullAccess)
    }

    private func runSafeProbesPreservingPasteboard(hasFullAccess: Bool) {
        let probe = pasteboard
        runSafeProbes(hasFullAccess: hasFullAccess)
        if let probe {
            pasteboard = probe
            // Re-save so the host app sees the richer result, not the safe-probe one.
            let report = DiagnosticsReport(
                source: .keyboard,
                recordedAt: Date(),
                osVersion: DeviceInfo.osVersion,
                deviceModel: DeviceInfo.model,
                appGroupSummary: appGroupAvailability?.summary ?? "unknown",
                appGroupWorking: appGroupAvailability?.isWorking ?? false,
                hasFullAccess: hasFullAccess,
                pasteboard: probe,
                physFootprintMB: memoryMB
            )
            reportSaveSucceeded = DiagnosticsStore.save(report)
        }
    }
}
