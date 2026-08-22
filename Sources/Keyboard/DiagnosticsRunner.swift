// Development-only. The M0/M1 empirical harness — a 1 Hz memory timer plus a probe suite
// that wrote to the shared container on every keyboard appearance. Useful at a Mac, far
// too expensive to leave in a keyboard people type on, so the whole file compiles out of
// Release. What ships instead is `KeyboardHandshake` (Sources/Shared): one throttled
// record, written off the main thread.
#if DEBUG

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
    /// The jetsam ceiling as the kernel reports it for this process — the actual answer to
    /// Q-04, rather than the ~60 MB figure inferred from third-party reports.
    @Published private(set) var measuredCeilingMB: Double?
    @Published private(set) var lastRunAt: Date?

    private var memoryTimer: Timer?

    // MARK: - Memory (C-10)

    func startMemoryMonitor() {
        refreshMemory()
        memoryTimer?.invalidate()
        // `guard let` first: capturing the weak `var self` directly inside the Task is a
        // concurrency error in Swift 6 mode. The timer holds self weakly, so no cycle.
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshMemory() }
        }
    }

    func stopMemoryMonitor() {
        memoryTimer?.invalidate()
        memoryTimer = nil
    }

    func refreshMemory() {
        guard let reading = MemoryReporter.read() else { return }
        memoryMB = reading.physFootprintMB
        measuredCeilingMB = reading.jetsamLimitMB
    }

    var memoryVerdict: MemoryReporter.Verdict {
        MemoryReporter.verdict(forMB: memoryMB, ceilingMB: measuredCeilingMB)
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
            readDurationMS: nil,
            hadFullAccess: nil
        )
    }

    /// Reads the actual pasteboard value — **this is the call that can prompt** (C-14).
    /// User-initiated only.
    ///
    /// Two things make this deliberately different from the M3 capture pipeline:
    /// it runs on the main actor, which freezes the keyboard for as long as the alert is up
    /// (acceptable for a button the user tapped knowing it may prompt, but M3 must move the
    /// read off the main thread), and it records `hasFullAccess` because without it the
    /// sandbox blocks the pasteboard outright and the result would otherwise read as "empty".
    func readPasteboardValue(hasFullAccess: Bool) {
        let general = UIPasteboard.general
        let changeCount = general.changeCount
        let hasStrings = general.hasStrings

        guard hasFullAccess else {
            pasteboard = DiagnosticsReport.PasteboardProbe(
                changeCount: changeCount,
                hasStrings: hasStrings,
                valueReadAttempted: true,
                valueReceived: false,
                characterCount: nil,
                readDurationMS: nil,
                hadFullAccess: false
            )
            runSafeProbesPreservingPasteboard(hasFullAccess: false)
            return
        }

        let start = Date()
        let value = general.string
        let elapsedMS = Date().timeIntervalSince(start) * 1000

        pasteboard = DiagnosticsReport.PasteboardProbe(
            changeCount: changeCount,
            hasStrings: hasStrings,
            valueReadAttempted: true,
            valueReceived: value != nil,
            characterCount: value?.count,
            readDurationMS: elapsedMS,
            hadFullAccess: true
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

#endif
