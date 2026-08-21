import Foundation

/// A snapshot of what actually works on this device, produced by whichever process ran it.
///
/// The keyboard extension writes one of these into the App Group so the host app can read
/// it back. That round trip **is** M0 Test 1: if the host app can display a report the
/// keyboard wrote, App Groups provisioned on this account (Q-01).
struct DiagnosticsReport: Codable, Equatable {

    enum Source: String, Codable {
        case keyboard
        case hostApp

        var display: String {
            switch self {
            case .keyboard: return "Keyboard extension"
            case .hostApp: return "Host app"
            }
        }
    }

    var source: Source
    var recordedAt: Date
    var osVersion: String
    var deviceModel: String

    // M0 Test 1 — App Groups (Q-01)
    var appGroupSummary: String
    var appGroupWorking: Bool

    // Full Access (C-06) — nil when the process cannot know (the host app can't)
    var hasFullAccess: Bool?

    // M0 Test 3 — pasteboard (Q-05)
    var pasteboard: PasteboardProbe?

    // Memory (C-10)
    var physFootprintMB: Double?

    struct PasteboardProbe: Codable, Equatable {
        /// Prompt-free (C-16).
        var changeCount: Int
        /// Prompt-free (C-16).
        var hasStrings: Bool
        /// The prompting call (C-14) — nil when it was skipped.
        var valueReadAttempted: Bool
        var valueReceived: Bool
        var characterCount: Int?
        /// Wall-clock of the value read. A fast return means no prompt appeared;
        /// multi-second means the user had to tap "Allow" (Q-05 has no programmatic signal).
        var readDurationMS: Double?

        var promptLikelyAppeared: Bool? {
            guard valueReadAttempted, let ms = readDurationMS else { return nil }
            return ms > 400
        }
    }
}

/// Persists reports into the App Group so the other process can read them.
enum DiagnosticsStore {

    private static func key(for source: DiagnosticsReport.Source) -> String {
        "diagnostics.report.\(source.rawValue)"
    }

    /// Returns false when the write did not survive — which is itself a finding, not an error.
    @discardableResult
    static func save(_ report: DiagnosticsReport) -> Bool {
        guard let defaults = AppGroup.defaults,
              let data = try? JSONEncoder().encode(report) else { return false }

        let storageKey = key(for: report.source)
        defaults.set(data, forKey: storageKey)
        return defaults.data(forKey: storageKey) == data
    }

    static func load(_ source: DiagnosticsReport.Source) -> DiagnosticsReport? {
        guard let data = AppGroup.defaults?.data(forKey: key(for: source)) else { return nil }
        return try? JSONDecoder().decode(DiagnosticsReport.self, from: data)
    }
}
