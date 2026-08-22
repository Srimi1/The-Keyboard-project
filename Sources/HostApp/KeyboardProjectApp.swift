import SwiftUI

@main
struct KeyboardProjectApp: App {

    /// Launch with `-keyboardPreview` to open straight into the keyboard preview, so
    /// screenshot capture for the Gboard side-by-side comparison can be scripted:
    ///
    ///     xcrun simctl launch <device> com.srijan.keyboardproject -keyboardPreview
    ///
    /// Debug-only, like the rest of the development surface (ADR-011). The preview exists to
    /// compare against Gboard reference screenshots; it is not a feature, and a launch
    /// argument is not a supported way for anyone to reach a screen in a shipping build.
    #if DEBUG
    private var opensPreviewDirectly: Bool {
        ProcessInfo.processInfo.arguments.contains("-keyboardPreview")
    }
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if opensPreviewDirectly {
                NavigationStack { KeyboardPreviewView() }
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
        }
    }
}
