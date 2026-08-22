import UIKit
import SwiftUI

/// The keyboard extension's principal class (C-01).
///
/// Owns everything that touches UIKit or the text field; the SwiftUI layer reaches the
/// document only through ``KeyboardActionHandler``.
final class KeyboardViewController: UIInputViewController {

    private let model = KeyboardViewModel()
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        model.handler = self
        installHostingController()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // C-21 says this is false on Face ID iPhones, where iOS draws globe and dictation
        // below the keyboard — so the key must not be drawn there. ⚠️ That fact is
        // **unverified** (Q-10), and the failure mode if it is wrong is severe: no globe key
        // and no system globe means the user is stranded on this keyboard, which is also a
        // confirmed App Review rejection (C-30, 4.4.1). Debug builds surface the live value
        // in the strip; read it on device before trusting this branch.
        model.needsGlobe = needsInputModeSwitchKey

        // Read here rather than in viewDidLoad: before the host connection exists the value
        // is unreliable, and there is no notification when it changes (C-41).
        model.feedback.hasFullAccess = hasFullAccess
        model.feedback.prepare()

        // The one thing a shipping keyboard tells the host app: that it ran, and whether
        // Full Access is on — the host app cannot read either for itself (C-06). Throttled
        // and written off the main thread, so appearing stays free (see KeyboardHandshake).
        KeyboardHandshakeStore.recordKeyboardSeen(hasFullAccess: hasFullAccess)

        #if DEBUG
        model.diagnostics.startMemoryMonitor()
        model.diagnostics.runSafeProbes(hasFullAccess: hasFullAccess)
        #endif

        model.syncWithTextField()
    }

    /// The text field can change under us — a different field, or the cursor moved — with no
    /// notification, so re-read the traits and the auto-capitalization state each time.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.syncWithTextField()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        model.syncWithTextField()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The height constraint has no effect until the view has drawn once, and applying
        // it too early produces the 0x0-then-fullscreen flicker (C-22).
        applyKeyboardHeight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        #if DEBUG
        model.diagnostics.stopMemoryMonitor()
        #endif
    }

    deinit {
        // Each host app instantiates a fresh controller whose view is retained after
        // dismissal, so per-appearance allocations accumulate (C-02).
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
    }

    // MARK: - Setup

    private func installHostingController() {
        let rootView = KeyboardRootView(model: model)
        let controller = UIHostingController(rootView: rootView)
        controller.view.backgroundColor = .clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false

        // UIHostingController adds a bottom safe-area inset that `.ignoresSafeArea()` inside
        // the SwiftUI view cannot remove; only this clears it. iOS 16.4+, and the deployment
        // target is 16.0, so it needs the guard.
        if #available(iOS 16.4, *) {
            controller.safeAreaRegions = []
        }

        addChild(controller)
        view.addSubview(controller.view)
        controller.didMove(toParent: self)

        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController = controller

        // Opaque backgrounds render as a gray bar under iOS 26's glass container, and it
        // has to be cleared on all three layers — the input view included, not just this
        // controller's view (CONSTRAINTS §8 gotcha ledger).
        view.backgroundColor = .clear
        inputView?.backgroundColor = .clear
    }

    private func applyKeyboardHeight() {
        // Width is always system-set; only height is ours to choose (C-22). Deriving it from
        // the actual width keeps key proportions constant across device classes.
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let height = KeyboardMetrics.preferredKeyboardHeight(
            rowCount: model.rows.count,
            width: width,
            stripHeight: KeyboardTheme.stripHeight
        )

        if let heightConstraint {
            guard abs(heightConstraint.constant - height) > 0.5 else { return }
            heightConstraint.constant = height
            return
        }

        let constraint = view.heightAnchor.constraint(equalToConstant: height)
        // Just below required: at required it conflicts with the system's own
        // UIView-Encapsulated-Layout-Height and spams constraint-breakage logs (C-45).
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint
    }

    /// The 0×0 → fullscreen → settling pass means the width we sized against can change
    /// after the first layout, and rotation changes it again.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.applyKeyboardHeight()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if heightConstraint != nil { applyKeyboardHeight() }
    }
}

// MARK: - Audio feedback

/// `UIDevice.playInputClick()` plays nothing unless the **on-screen input view** adopts this
/// and returns true.
///
/// The object iOS consults is the system-vended `UIInputView` (`self.inputView`), not the view
/// controller — Apple's docs are explicit that the conformance belongs on the `UIView`
/// subclass. Adopting it only on the controller is a silent no-op that looks exactly like
/// "Full Access is off", which is how it could hide behind Q-03 indefinitely.
///
/// `@retroactive` is required because both the class and the protocol come from UIKit.
extension UIInputView: @retroactive UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}

/// Kept as well — it costs nothing, and the controller conformance is the widely-used form.
extension KeyboardViewController: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

// MARK: - KeyboardActionHandler

extension KeyboardViewController: KeyboardActionHandler {

    func insert(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    /// An offset of zero is a no-op inside the proxy, so skip the round trip entirely.
    func adjustTextPosition(by offset: Int) {
        guard offset != 0 else { return }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    /// `.allTouchEvents` rather than `.touchUpInside`: `handleInputModeList(from:with:)`
    /// needs the full event stream to distinguish a tap (advance) from a touch-and-hold
    /// (show the keyboard picker).
    func configureNextKeyboardButton(_ button: UIButton) {
        button.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    }

    var contextBeforeInput: String? {
        textDocumentProxy.documentContextBeforeInput
    }

    var autocapitalizationType: UITextAutocapitalizationType {
        textDocumentProxy.autocapitalizationType ?? .sentences
    }

    var returnKeyType: UIReturnKeyType {
        textDocumentProxy.returnKeyType ?? .default
    }
}
