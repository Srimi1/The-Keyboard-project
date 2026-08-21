import Foundation
import SwiftUI

/// Host-app side of the M0 tests.
///
/// The host app cannot answer the interesting questions itself — Full Access and pasteboard
/// behavior only mean something in the extension process. What it *can* prove is the other
/// half of Test 1: that a report the keyboard wrote crosses the App Group boundary and
/// arrives here (Q-01).
@MainActor
final class HostDiagnostics: ObservableObject {

    @Published private(set) var appGroupAvailability: AppGroup.Availability?
    @Published private(set) var keyboardReport: DiagnosticsReport?
    @Published private(set) var ownReportSaved: Bool?
    @Published private(set) var lastRefresh: Date?

    func refresh() {
        let availability = AppGroup.probeAvailability()
        appGroupAvailability = availability
        keyboardReport = DiagnosticsStore.load(.keyboard)

        let report = DiagnosticsReport(
            source: .hostApp,
            recordedAt: Date(),
            osVersion: DeviceInfo.osVersion,
            deviceModel: DeviceInfo.model,
            appGroupSummary: availability.summary,
            appGroupWorking: availability.isWorking,
            hasFullAccess: nil,   // meaningless outside the extension
            pasteboard: nil,      // deliberately not probed here — see CLAUDE.md tripwires
            physFootprintMB: MemoryReporter.physFootprintMB()
        )
        ownReportSaved = DiagnosticsStore.save(report)
        lastRefresh = Date()
    }

    // MARK: - Onboarding status
    //
    // Derived from what the keyboard reported rather than from any private API. If the
    // keyboard has never run, we simply do not know — which is itself accurate.

    enum StepStatus {
        case unknown
        case done
        case failed

        var symbol: String {
            switch self {
            case .unknown: return "circle"
            case .done: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .unknown: return .secondary
            case .done: return .green
            case .failed: return .red
            }
        }
    }

    /// Step 1 — the keyboard has been added and has actually run at least once.
    var keyboardHasRun: StepStatus {
        keyboardReport == nil ? .unknown : .done
    }

    /// Step 2 — Full Access, as reported by the extension itself (C-06).
    var fullAccessStatus: StepStatus {
        guard let value = keyboardReport?.hasFullAccess else { return .unknown }
        return value ? .done : .failed
    }

    /// Step 3 — no API exposes this setting, so it is inferred from whether the keyboard's
    /// pasteboard read returned fast (no prompt) or slow (the user had to tap Allow) — the
    /// only signal available (Q-05).
    var pasteWithoutPromptStatus: StepStatus {
        guard let probe = keyboardReport?.pasteboard, probe.valueReadAttempted else { return .unknown }
        guard let prompted = probe.promptLikelyAppeared else { return .unknown }
        return prompted ? .failed : .done
    }

    /// The decisive M0 verdict (Q-01).
    var appGroupRoundTripStatus: StepStatus {
        guard let availability = appGroupAvailability else { return .unknown }
        guard availability.isWorking else { return .failed }
        return keyboardReport == nil ? .unknown : .done
    }

    /// Q-01 asks whether App Groups provisions on a **free personal team on real hardware**.
    /// The simulator has no provisioning profile at all, so any result it produces —
    /// working or not — is evidence about this code, not about the developer account.
    /// Without this guard a green simulator run would look like a closed question.
    var verdictIsConclusive: Bool { !DeviceInfo.isSimulator }
}
