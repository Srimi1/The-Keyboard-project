import Combine
import Foundation

nonisolated enum KeyboardAppearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
    case neon

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Black"
        case .neon: "Neon"
        }
    }
}

nonisolated enum ClipboardCaptureMode: String, Codable, CaseIterable, Sendable {
    case off
    case manual
    case automatic
}

nonisolated struct KeyboardSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let currentClipboardNoticeVersion = 1

    var schemaVersion = currentSchemaVersion
    var updatedAt = Date.distantPast
    var hapticsEnabled = true
    var soundEnabled = false
    var appearance = KeyboardAppearance.system
    var clipboardCaptureMode = ClipboardCaptureMode.manual
    var clipboardNoticeVersion = 0

    var hasAcceptedClipboardNotice: Bool {
        clipboardNoticeVersion >= Self.currentClipboardNoticeVersion
    }

    /// Automatic capture remains deliberately unavailable until the target-device paste and
    /// password-manager matrix is recorded. A stored future/experimental value degrades to the
    /// explicit Save action rather than starting surprise reads.
    var effectiveClipboardCaptureMode: ClipboardCaptureMode {
        guard hasAcceptedClipboardNotice else { return .off }
        if clipboardCaptureMode == .automatic, !KeyboardSettingsStore.automaticCaptureValidated {
            return .manual
        }
        return clipboardCaptureMode
    }
}

/// Mirrored settings: extension-local defaults keep typing preferences usable without Full
/// Access, while the App Group copy shares changes with the host whenever access is available.
@MainActor
final class KeyboardSettingsStore: ObservableObject {
    nonisolated static let automaticCaptureValidated = false

    @Published private(set) var values: KeyboardSettings
    @Published private(set) var persistenceError: String?

    private static let storageKey = "keyboard.settings.v1"
    private let localDefaults: UserDefaults
    private let sharedDefaults: UserDefaults?
    private var canUseSharedDefaults = false

    init(
        localDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults? = AppGroup.defaults
    ) {
        self.localDefaults = localDefaults
        self.sharedDefaults = sharedDefaults
        self.values = Self.decode(from: localDefaults) ?? KeyboardSettings()
    }

    func refresh(canUseShared: Bool) {
        canUseSharedDefaults = canUseShared
        let local = Self.decode(from: localDefaults)
        let shared = canUseShared ? sharedDefaults.flatMap(Self.decode(from:)) : nil
        let selected = [local, shared]
            .compactMap { $0 }
            .filter { $0.schemaVersion == KeyboardSettings.currentSchemaVersion }
            .max(by: { $0.updatedAt < $1.updatedAt })
            ?? KeyboardSettings()
        values = selected

        // Reconcile the winning whole record into every store we can currently reach.
        // Without this, a preference changed by the host is visible to the extension while
        // Full Access is on, then silently rolls back to the extension's stale local copy
        // when Full Access is revoked.
        do {
            let data = try JSONEncoder().encode(selected)
            if localDefaults.data(forKey: Self.storageKey) != data {
                localDefaults.set(data, forKey: Self.storageKey)
            }
            if canUseShared,
               let sharedDefaults,
               sharedDefaults.data(forKey: Self.storageKey) != data {
                sharedDefaults.set(data, forKey: Self.storageKey)
            }
            persistenceError = nil
        } catch {
            persistenceError = "Settings could not be reconciled."
        }
    }

    func setHapticsEnabled(_ enabled: Bool, at now: Date = Date()) {
        update(at: now) { $0.hapticsEnabled = enabled }
    }

    func setSoundEnabled(_ enabled: Bool, at now: Date = Date()) {
        update(at: now) { $0.soundEnabled = enabled }
    }

    func setAppearance(_ appearance: KeyboardAppearance, at now: Date = Date()) {
        update(at: now) { $0.appearance = appearance }
    }

    func setClipboardCaptureMode(_ mode: ClipboardCaptureMode, at now: Date = Date()) {
        guard mode != .automatic || Self.automaticCaptureValidated else { return }
        update(at: now) { $0.clipboardCaptureMode = mode }
    }

    func acceptClipboardNotice(at now: Date = Date()) {
        update(at: now) {
            $0.clipboardNoticeVersion = KeyboardSettings.currentClipboardNoticeVersion
            if $0.clipboardCaptureMode == .off { $0.clipboardCaptureMode = .manual }
        }
    }

    private func update(at now: Date, mutation: (inout KeyboardSettings) -> Void) {
        // Another process may have changed a different field since this object last appeared.
        // Merge the newest reachable record immediately before applying this field mutation so
        // a stale host/extension instance does not overwrite that change wholesale.
        refresh(canUseShared: canUseSharedDefaults)
        var updated = values
        mutation(&updated)
        updated.schemaVersion = KeyboardSettings.currentSchemaVersion
        updated.updatedAt = now

        do {
            let data = try JSONEncoder().encode(updated)
            localDefaults.set(data, forKey: Self.storageKey)
            if canUseSharedDefaults {
                sharedDefaults?.set(data, forKey: Self.storageKey)
            }
            values = updated
            persistenceError = nil
        } catch {
            persistenceError = "Settings could not be saved."
        }
    }

    private static func decode(from defaults: UserDefaults) -> KeyboardSettings? {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(KeyboardSettings.self, from: data),
              decoded.schemaVersion == KeyboardSettings.currentSchemaVersion else {
            return nil
        }
        return decoded
    }
}
