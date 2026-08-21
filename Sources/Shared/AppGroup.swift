import Foundation

/// The single definition of the App Group identifier (ADR-008).
///
/// Never write this string anywhere else — not in a plist read, not in a call site.
/// Both targets compile this file, so both get the same value by construction.
enum AppGroup {

    static let identifier = "group.com.srijan.keyboardproject"

    /// Shared defaults suite. Non-nil does **not** prove the entitlement provisioned —
    /// use ``availability`` for that (see Q-01).
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// The shared file container. Returns nil when the App Group entitlement is missing
    /// or failed to provision, which is the reliable signal that App Groups is unavailable.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    // MARK: - Availability probe (Q-01)

    enum Availability: Equatable {
        /// Container reachable and a write round-tripped.
        case working
        /// Container reachable but the write did not survive a read-back.
        /// Expected in the extension without Full Access (C-12).
        case readOnly(String)
        /// No container — entitlement missing or not provisioned.
        case unavailable(String)

        var isWorking: Bool { self == .working }

        var summary: String {
            switch self {
            case .working: return "working"
            case .readOnly(let why): return "read-only — \(why)"
            case .unavailable(let why): return "unavailable — \(why)"
            }
        }
    }

    /// Distinguishes "entitlement missing" from "write silently failed" (Q-01).
    ///
    /// ⚠️ The trap this deliberately avoids: `UserDefaults(suiteName:)` returns a **non-nil**
    /// instance for a group you are not entitled to, and an in-process write/read-back
    /// **succeeds off the in-process cache** — so a panel that "verifies" App Groups that way
    /// reports a pass on a completely unprovisioned group. `containerURL` returning nil is the
    /// reliable entitlement signal, because iOS processes are always sandboxed.
    ///
    /// Even this only proves the entitlement provisioned for *this* process. Proof that the
    /// group is genuinely **shared** requires a cross-process token — which is what the
    /// keyboard-writes / host-app-reads report round trip provides (`DiagnosticsStore`).
    static func probeAvailability() -> Availability {
        guard let container = containerURL else {
            return .unavailable("containerURL(forSecurityApplicationGroupIdentifier:) returned nil")
        }

        let probeURL = container.appendingPathComponent("appgroup-probe.txt")
        let token = UUID().uuidString
        do {
            try Data(token.utf8).write(to: probeURL, options: .atomic)
            let readBack = String(decoding: try Data(contentsOf: probeURL), as: UTF8.self)
            try? FileManager.default.removeItem(at: probeURL)
            guard readBack == token else {
                return .readOnly("file wrote but read back a different value")
            }
        } catch {
            return .readOnly("file write failed: \(error.localizedDescription)")
        }

        return .working
    }
}
