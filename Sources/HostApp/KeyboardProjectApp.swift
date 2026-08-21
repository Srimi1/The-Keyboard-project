import SwiftUI

@main
struct KeyboardProjectApp: App {

    /// Launch with `-keyboardPreview` to open straight into the keyboard preview, so
    /// screenshot capture for the Gboard side-by-side comparison can be scripted:
    ///
    ///     xcrun simctl launch <device> com.srijan.keyboardproject -keyboardPreview
    private var opensPreviewDirectly: Bool {
        ProcessInfo.processInfo.arguments.contains("-keyboardPreview")
    }

    var body: some Scene {
        WindowGroup {
            if opensPreviewDirectly {
                NavigationStack { KeyboardPreviewView() }
            } else {
                RootView()
            }
        }
    }
}
