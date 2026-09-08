import SwiftUI

/// The complete in-app policy. A separately hosted copy is still needed for App Store Connect,
/// but the installed app must remain useful and transparent even when the phone is offline.
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Summary") {
                Text("The Keyboard Project is offline. The developer does not collect, receive, sell or share typed text, clipboard history, settings, identifiers, diagnostics or usage analytics.")
                Text("There are no accounts, advertisements, analytics SDKs or app-owned network services.")
            }

            Section("Typed text") {
                Text("Text is inserted into the app you are using through Apple's keyboard-extension interface. The Keyboard Project does not store or transmit what you type.")
                Text("iOS may replace third-party keyboards in password, phone-pad or app-restricted fields.")
            }

            Section("Clipboard history") {
                Text("Opening or foregrounding the app or keyboard never reads clipboard values. A value is offered only after you accept the retention notice and tap Apple's system Paste button.")
                Text("Saved text stays in this app's local shared container. Recent items expire after one hour; pinned items remain until removed. Individual items and total storage are bounded, protected on disk and excluded from backups.")
                Text("Sensitive-content detection is best effort, not a guarantee. Do not save passwords, authentication codes, private keys or other secrets.")
            }

            Section("Full Access") {
                Text("Typing and switching keyboards do not require Full Access. It is optional and currently enables shared clipboard history plus sound and haptic feedback.")
                Text("Although iOS grants broader capability with Full Access, this app does not use it for network communication. If access is revoked, the extension hides cached history until coordinated storage is available again.")
            }

            Section("Control and deletion") {
                Text("You can delete individual clipboard items or clear all history in the app or keyboard while shared storage is available. Removing the app removes its local app data under iOS behavior.")
                Text("Development diagnostics are excluded from Release builds. Material policy changes will update the date and ship with release notes.")
            }

            Section("Policy date") {
                Text("Last updated September 8, 2026")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
