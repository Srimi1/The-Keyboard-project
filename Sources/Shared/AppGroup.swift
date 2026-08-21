import Foundation

/// The single definition of the App Group identifier (ADR-008).
///
/// Never write this string anywhere else — not in a plist read, not in a call site.
/// Both targets compile this file, so both get the same value by construction.
enum AppGroup {

    static let identifier = "group.com.srimi.keyboardproject"

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

    /// Writes a probe value and reads it back to distinguish "entitlement missing"
    /// from "write silently failed". This is the M0 Test 1 primitive (Q-01).
    static func probeAvailability() -> Availability {
        guard let container = containerURL else {
            return .unavailable("containerURL(forSecurityApplicationGroupIdentifier:) returned nil")
        }

        // File-container round trip — the strongest signal, since UserDefaults can
        // return a usable-looking suite that silently drops writes.
        let probeURL = container.appendingPathComponent("appgroup-probe.txt")
        let token = UUID().uuidString
        do {
            try token.write(to: probeURL, atomically: true, encoding: .utf8)
            let readBack = try String(contentsOf: probeURL, encoding: .utf8)
            guard readBack == token else {
                return .readOnly("file wrote but read back a different value")
            }
        } catch {
            return .readOnly("file write failed: \(error.localizedDescription)")
        }

        // UserDefaults round trip — what settings mirroring depends on.
        guard let defaults else {
            return .readOnly("UserDefaults(suiteName:) returned nil")
        }
        let key = "appgroup.probe"
        defaults.set(token, forKey: key)
        guard defaults.string(forKey: key) == token else {
            return .readOnly("UserDefaults write did not read back")
        }

        return .working
    }
}
