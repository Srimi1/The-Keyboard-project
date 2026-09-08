import SwiftUI

struct SupportView: View {
    private let issuesURL = URL(string: "https://github.com/Srimi1/The-Keyboard-project/issues")
    private let advisoryURL = URL(string: "https://github.com/Srimi1/The-Keyboard-project/security/advisories/new")

    var body: some View {
        List {
            Section("Keyboard does not appear") {
                Text("Open Settings → General → Keyboard → Keyboards → Add New Keyboard, then choose Keyboard Project.")
                Text("For a development build, confirm Developer Mode, device trust and that its provisioning profile has not expired.")
            }

            Section("Clipboard does not save") {
                Text("Accept the retention notice, keep Tap to save enabled and enable Full Access if you want shared history inside the keyboard.")
                Text("Tap Save current clipboard. Merely opening the app or keyboard never captures a value.")
            }

            Section("Report a problem") {
                Text("Include the app version, iPhone model, iOS version, Full Access state and exact reproduction steps. Never attach real passwords, private messages or clipboard contents.")
                if let issuesURL {
                    Link(destination: issuesURL) {
                        Label("Open GitHub issues", systemImage: "exclamationmark.bubble")
                    }
                }
                if let advisoryURL {
                    Link(destination: advisoryURL) {
                        Label("Report a security issue privately", systemImage: "lock.shield")
                    }
                }
            }
        }
        .navigationTitle("Help and support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
