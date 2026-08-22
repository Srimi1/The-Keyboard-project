import Foundation
import SwiftUI

/// Host-app state behind the setup checklist.
///
/// The host app cannot answer any of the interesting questions itself — Full Access and
/// pasteboard behavior only mean something in the extension process (C-06). What it reads is
/// the handshake the keyboard leaves in the App Group: proof the keyboard ran, and the one
/// fact only the extension can see.
///
/// The M0 diagnostics round trip is still here, but Debug-only — in a shipping build the app
/// has no reason to write probe files every time it foregrounds.
@MainActor
final class HostDiagnostics: ObservableObject {

    @Published private(set) var handshake: KeyboardHandshake?
    @Published private(set) var signingDaysRemaining: Int?
    @Published private(set) var lastRefresh: Date?

    #if DEBUG
    @Published private(set) var appGroupAvailability: AppGroup.Availability?
    @Published private(set) var keyboardReport: DiagnosticsReport?
    @Published private(set) var ownReportSaved: Bool?
    #endif

    func refresh() {
        handshake = KeyboardHandshakeStore.load()
        signingDaysRemaining = ProvisioningProfile.daysRemaining()

        #if DEBUG
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
        #endif

        lastRefresh = Date()
    }

    // MARK: - Onboarding status
    //
    // Derived from what the keyboard reported rather than from any private API. If the
    // keyboard has never run, we simply do not know — which is itself accurate, and is why
    // every step distinguishes "unknown" from "failed".

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
        handshake == nil ? .unknown : .done
    }

    /// Step 2 — Full Access, as reported by the extension itself (C-06).
    var fullAccessStatus: StepStatus {
        guard let value = handshake?.hasFullAccess else { return .unknown }
        return value ? .done : .failed
    }

    /// Step 3 — no API exposes this setting.
    ///
    /// Deciding it needs a pasteboard **value** read, which is the one call that can fire the
    /// system paste alert (C-14). A shipping build has no business making that call before
    /// M3's capture pipeline needs the value anyway, so outside Debug this stays an
    /// instruction rather than a verdict.
    var pasteWithoutPromptStatus: StepStatus {
        #if DEBUG
        guard let probe = keyboardReport?.pasteboard else { return .unknown }
        switch probe.outcome {
        case .allowedSilently:
            return .done
        case .likelyPrompted, .deniedBySetting, .blockedNoFullAccess:
            return .failed
        // An empty pasteboard says nothing about the setting — copy something and retry.
        case .pasteboardEmpty, .notRun:
            return .unknown
        }
        #else
        return .unknown
        #endif
    }

    /// When the keyboard last reported in. Absent is not a failure: App Group writes from the
    /// extension are unreliable without Full Access (C-12).
    var keyboardLastSeen: Date? { handshake?.lastSeenAt }

    #if DEBUG
    /// The keyboard's own reading of the pasteboard outcome, for display.
    var pasteboardOutcome: String? {
        keyboardReport?.pasteboard.map(\.outcome.rawValue)
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
    #endif
}
