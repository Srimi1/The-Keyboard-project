import Foundation

/// The **only** thing the keyboard extension writes to the App Group in a shipping build.
///
/// The host app's setup checklist needs two facts it cannot observe for itself: whether the
/// keyboard has ever actually run, and whether Full Access is on — only the extension can
/// read `hasFullAccess`, and there is no notification or KVO path for it (C-06, C-41).
/// Everything else the M0 harness recorded is a development tool and now compiles out of
/// Release along with `DiagnosticsRunner`.
///
/// Deliberately cheap. What this replaced ran on **every keyboard appearance in every app**:
/// a UUID file write + read-back + delete in the shared container (`AppGroup.probeAvailability`),
/// a pasteboard IPC round trip, a JSON encode and a second write with a read-back verify —
/// plus a 1 Hz timer for the whole time the keyboard was visible. That was M0 scaffolding
/// that was never gated out of Release.
/// `nonisolated` so the `Codable` conformance is too — the store below encodes and decodes
/// off the main thread, and the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
/// would otherwise bind the conformance to the main actor (an error in Swift 6 language mode).
nonisolated struct KeyboardHandshake: Codable, Equatable {

    var lastSeenAt: Date
    /// As reported by the extension itself — the host app has no way to read this (C-06).
    var hasFullAccess: Bool
    var appVersion: String

    /// Everything except the timestamp. Two records with the same payload say the same thing,
    /// so re-writing one only buys a fresher `lastSeenAt`.
    private var payload: String { "\(hasFullAccess)|\(appVersion)" }

    /// True when writing this record would tell the host app nothing new.
    ///
    /// `staleAfter` still forces a periodic refresh so "the keyboard has run recently" stays
    /// meaningful — without it a record written once would claim the keyboard was in use
    /// forever.
    func isRedundant(against stored: KeyboardHandshake?, staleAfter: TimeInterval, now: Date) -> Bool {
        guard let stored, stored.payload == payload else { return false }

        let age = now.timeIntervalSince(stored.lastSeenAt)
        // A record dated in the future — the clock moved backwards, or the container came
        // from a restored backup — would otherwise read as "fresh" forever and suppress
        // every write after it. Treat it as stale so the next appearance corrects it.
        guard age >= 0 else { return false }

        return age < staleAfter
    }
}

/// Reads and writes the handshake across the App Group boundary.
///
/// `nonisolated` because the write runs off the main thread: `viewWillAppear` is on the
/// critical path of the keyboard appearing, and nothing there should wait on storage. The
/// project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without this the whole type
/// would be main-actor-bound by default.
nonisolated enum KeyboardHandshakeStore {

    private static let storageKey = "keyboard.handshake"

    /// How long a record stays authoritative before the keyboard bothers to refresh it.
    /// Long enough that ordinary typing never writes; short enough that the host app's
    /// checklist reflects a Full Access toggle within the same session it was flipped.
    static let staleAfter: TimeInterval = 6 * 60 * 60

    private static let queue = DispatchQueue(label: "com.srijan.keyboardproject.handshake", qos: .utility)

    /// `AppGroup.identifier` is an immutable `Sendable` constant, so reaching it from a
    /// nonisolated context is safe — and it keeps the App Group ID typed exactly once
    /// (CLAUDE.md invariant 3, ADR-008).
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    static func load() -> KeyboardHandshake? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(KeyboardHandshake.self, from: data)
    }

    /// Best-effort, and silent about failure by design.
    ///
    /// App Group writes from the extension are unreliable without Full Access (C-12), so a
    /// missing record means "don't know" — never "broken". The host app's checklist is built
    /// to show `.unknown` rather than a false negative.
    static func recordKeyboardSeen(hasFullAccess: Bool, appVersion: String = AppInfo.version) {
        let record = KeyboardHandshake(
            lastSeenAt: Date(),
            hasFullAccess: hasFullAccess,
            appVersion: appVersion
        )

        queue.async {
            guard !record.isRedundant(against: load(), staleAfter: staleAfter, now: record.lastSeenAt),
                  let data = try? JSONEncoder().encode(record) else { return }
            defaults?.set(data, forKey: storageKey)
        }
    }
}

/// Marketing version of whichever bundle is asking. Inside the extension that is the
/// `.appex`, which shares `MARKETING_VERSION` with the host app via `project.yml`.
nonisolated enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
