import SwiftUI
import UIKit

/// The host app is a **setup screen**, not a dashboard.
///
/// Once the three steps below are done the keyboard lives on the globe key and this app never
/// needs opening again. Everything that exists to serve development — the M0 verdicts, the
/// keyboard's own report, memory readings — is Debug-only and sits at the bottom.
struct RootView: View {
    @StateObject private var diagnostics = HostDiagnostics()
    @StateObject private var settings: KeyboardSettingsStore
    @StateObject private var clipboard: ClipboardController
    @Environment(\.scenePhase) private var scenePhase
    @State private var scratchText = ""
    private let testingClipboardText: String?
    private let testingNow: Date?

    init() {
        #if DEBUG
        let process = ProcessInfo.processInfo
        let isUITest = process.arguments.contains("-uiTesting")
        let testID = isUITest
            ? process.environment["KB_UI_STORE_ID"].flatMap(UUID.init(uuidString:))
            : nil
        let testText = isUITest ? process.environment["KB_UI_CLIPBOARD_TEXT"] : nil
        let testNow = process.environment["KB_UI_NOW"]
            .flatMap(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0) }

        let settings: KeyboardSettingsStore
        let repository: ClipboardRepository
        if let testID {
            let suitePrefix = "com.srijan.keyboardproject.uitests.\(testID.uuidString)"
            let local = UserDefaults(suiteName: suitePrefix + ".local") ?? .standard
            let shared = UserDefaults(suiteName: suitePrefix + ".shared")
            settings = KeyboardSettingsStore(localDefaults: local, sharedDefaults: shared)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("KeyboardProjectUITests", isDirectory: true)
                .appendingPathComponent(testID.uuidString, isDirectory: true)
            repository = ClipboardRepository(
                fileURL: directory.appendingPathComponent(ClipboardRepository.fileName)
            )
        } else {
            settings = KeyboardSettingsStore()
            repository = ClipboardRepository()
        }
        _settings = StateObject(wrappedValue: settings)
        let clock: @Sendable () -> Date
        if let testNow {
            clock = { testNow }
        } else {
            clock = { Date() }
        }
        _clipboard = StateObject(wrappedValue: ClipboardController(
            repository: repository,
            settings: settings,
            now: clock
        ))
        testingClipboardText = testText.map { ClipboardLimits.truncate($0).text }
        testingNow = testNow
        #else
        let settings = KeyboardSettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _clipboard = StateObject(wrappedValue: ClipboardController(
            repository: ClipboardRepository(),
            settings: settings,
            now: { Date() }
        ))
        testingClipboardText = nil
        testingNow = nil
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                setupSection
                settingsSection
                clipboardSection
                #if DEBUG
                previewSection
                #endif
                signingSection
                tryItSection
                privacySection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Keyboard Project")
        }
        .onAppear {
            diagnostics.refresh()
            settings.refresh(canUseShared: true)
            clipboard.activate(.hostApp)
        }
        // Explicit `perform:` selects the single-value overload; the zero- and
        // two-parameter forms of onChange are iOS 17+.
        .onChange(of: scenePhase, perform: { phase in
            // Coming back from Settings is the moment a step most often flips to done, so
            // this is what makes the checklist feel live. Clipboard reads remain tied only
            // to an explicit PasteButton action, never to this lifecycle callback.
            if phase == .active {
                diagnostics.refresh()
                settings.refresh(canUseShared: true)
                clipboard.activate(.hostApp)
            } else if phase == .background {
                // A system Paste permission sheet temporarily makes the app inactive. The
                // provider transfer must survive that transition; only a real backgrounding
                // ends the controller lifetime.
                clipboard.deactivate()
            }
        })
        // Clipboard text must not appear in an app-switcher snapshot.
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    Label("Keyboard Project", systemImage: "keyboard")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Setup — the reason this app exists

    private var setupSection: some View {
        Section {
            step(
                number: 1,
                title: "Add the keyboard",
                detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Keyboard Project",
                status: diagnostics.keyboardHasRun,
                doneNote: "Added, and the keyboard has run at least once.",
                pendingNote: nil
            )
            step(
                number: 2,
                title: "Optional: Allow Full Access",
                detail: "Settings → General → Keyboard → Keyboards → Keyboard Project → Allow Full Access. Typing works without it; shared clipboard history and feedback need it.",
                status: diagnostics.fullAccessStatus,
                doneNote: "Reported enabled by the keyboard itself.",
                pendingNote: nil
            )
            // Not force-unwrapped: `openSettingsURLString` is a system constant that has
            // always parsed, but a crash on the setup screen is a poor trade for one `!`.
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settingsURL) {
                    Label("Open this app's Settings page", systemImage: "gear")
                }
            }
        } header: {
            Text("Setup")
        } footer: {
            // Honest about the limit: there is no public deep link to the Keyboards list, and
            // launching Settings is the only app a keyboard may open at all (C-30, 4.4.1).
            Text("The button opens this app's Settings page. Adding the keyboard still has to be done from the Keyboards screen. After setup, switch with the globe key.")
        }
    }

    // MARK: - Keyboard preview (Debug only)
    //
    // A development tool: it renders the real `KeyboardRootView` inside the app so it can be
    // compared side by side against the Gboard reference screenshots (the M1/M2 exit
    // criteria) without switching keyboards. It is also what the XCUITest suite drives —
    // keeping it high in the list is what keeps those coordinate taps reachable.

    #if DEBUG
    private var previewSection: some View {
        Section {
            NavigationLink {
                KeyboardPreviewView()
            } label: {
                Label("Keyboard preview", systemImage: "keyboard")
            }
        } footer: {
            Text("Renders the real keyboard inside this app, for side-by-side comparison against the Gboard reference screenshots. Debug builds only.")
        }
    }
    #endif

    // MARK: - Clipboard

    private var settingsSection: some View {
        Section {
            NavigationLink {
                KeyboardSettingsView(settings: settings, clipboard: clipboard)
            } label: {
                Label("Keyboard settings", systemImage: "gearshape")
            }
        }
    }

    private var clipboardSection: some View {
        Section {
            NavigationLink {
                ClipboardHistoryView(
                    clipboard: clipboard,
                    settings: settings,
                    testingClipboardText: testingClipboardText,
                    testingNow: testingNow
                )
            } label: {
                HStack {
                    Label("Clipboard history", systemImage: "doc.on.clipboard")
                    Spacer()
                    Text(clipboardCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Clipboard history is manual-first and stays on this phone. Save text from here or from the keyboard's clipboard panel.")
        }
    }

    private var clipboardCountLabel: String {
        let visible = clipboard.history.visible(at: Date())
        let total = visible.pinned.count + visible.recent.count
        return total == 0 ? "empty" : "\(total)"
    }

    // MARK: - Signing expiry (C-23)

    @ViewBuilder
    private var signingSection: some View {
        if let signing = diagnostics.signing {
            let urgent = signing.isExpired || signing.daysRemaining <= 2
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: urgent ? "exclamationmark.triangle.fill" : "clock")
                        .foregroundStyle(urgent ? (signing.isExpired ? .red : .orange) : .secondary)
                        .font(.title3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(signingHeadline(signing))
                            .font(.subheadline.weight(.semibold))
                        Text("A free personal team signs builds for 7 days (C-23). When it lapses the keyboard stops working until the app is re-deployed from Xcode — run Scripts/redeploy.sh. The paid program raises this to a year.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Signing")
            }
        }
    }

    // MARK: - Try it

    private var tryItSection: some View {
        Section {
            TextField("Tap here, switch keyboards with the globe key, and type", text: $scratchText, axis: .vertical)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !scratchText.isEmpty {
                HStack {
                    Text("\(scratchText.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { scratchText = "" }
                        .font(.caption)
                }
            }
        } header: {
            Text("Try the keyboard")
        }
    }

    // MARK: - Privacy
    //
    // Real, load-bearing content rather than filler: guideline 4.4 requires a host app that
    // contains an extension to do something itself, and 5.1.1 requires the privacy position
    // to be reachable in-app. A hosted policy URL is still owed before submission (C-30).

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Nothing you type leaves this phone", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Text("The keyboard has no network code at all — not for sync, not analytics, not crash reporting (ADR-005). There are no accounts and no servers. Clipboard history and settings are stored only in this app's shared container on this device, and are deleted when you delete the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy policy", systemImage: "hand.raised.fill")
            }
        } header: {
            Text("Privacy")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            labeled("Version", "\(AppInfo.version) (\(AppInfo.build))")
            if let seen = diagnostics.keyboardLastSeen {
                labeled("Keyboard last used", seen.formatted(date: .abbreviated, time: .shortened))
            }
            NavigationLink {
                SupportView()
            } label: {
                Label("Help and support", systemImage: "questionmark.circle")
            }
        }
    }

    // MARK: - Developer (Debug only)

    #if DEBUG
    private var developerSection: some View {
        Section {
            statusRow(
                title: "App Groups round trip (Q-01)",
                subtitle: diagnostics.appGroupAvailability?.summary ?? "not probed",
                status: diagnostics.appGroupRoundTripStatus
            )
            if !diagnostics.verdictIsConclusive {
                Label(
                    "Simulator — not a valid Q-01 answer. The simulator has no provisioning profile, so this only exercises the code. Run on a real iPhone signed with your free personal team before recording a verdict.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.blue)
            }

            if let report = diagnostics.keyboardReport {
                labeled("Report recorded", report.recordedAt.formatted(date: .abbreviated, time: .standard))
                labeled("Device", report.deviceModel)
                labeled("OS", report.osVersion)
                labeled("App Group", report.appGroupSummary)
                if let mb = report.physFootprintMB {
                    labeled("Keyboard memory", String(format: "%.1f MB / %.0f MB budget", mb, MemoryReporter.budgetMB))
                }
                if let outcome = diagnostics.pasteboardOutcome {
                    labeled("Pasteboard", outcome)
                }
            } else {
                Text("No keyboard report yet — switch to the keyboard and tap Diagnostics in its strip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            labeled("Host app memory", MemoryReporter.physFootprintMB().map { String(format: "%.1f MB", $0) } ?? "unknown")
            labeled("App Group", AppGroup.identifier)
            Button("Refresh") { diagnostics.refresh() }
        } header: {
            Text("Developer")
        } footer: {
            Text("Debug builds only — compiled out of Release.")
        }
    }
    #endif

    // MARK: - Building blocks

    private func step(
        number: Int,
        title: String,
        detail: String,
        status: HostDiagnostics.StepStatus,
        doneNote: String,
        pendingNote: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)").font(.subheadline.weight(.semibold))
                Text(status == .done ? doneNote : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if status != .done, let pendingNote {
                    Text(pendingNote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Reads the lapsed case honestly. A profile that expired four hours ago is still
    /// "0 days" by `dateComponents`, and rendering that as *expires in 0 days* would be
    /// reassuring on exactly the screen that exists to warn you.
    private func signingHeadline(_ signing: HostDiagnostics.SigningStatus) -> String {
        guard !signing.isExpired else {
            return "Signing has expired — the keyboard will not run until you re-deploy"
        }
        switch signing.daysRemaining {
        case 0: return "Signing expires today"
        case 1: return "Signing expires tomorrow"
        case let days: return "Signing expires in \(days) days"
        }
    }

    private func statusRow(title: String, subtitle: String, status: HostDiagnostics.StepStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).multilineTextAlignment(.trailing)
        }
    }
}
