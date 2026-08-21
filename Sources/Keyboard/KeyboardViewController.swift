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

        // False on Face ID iPhones, where iOS draws globe and dictation below the
        // keyboard — the key must not be drawn at all there (C-21).
        model.needsGlobe = needsInputModeSwitchKey

        model.diagnostics.startMemoryMonitor()
        model.diagnostics.runSafeProbes(hasFullAccess: hasFullAccess)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The height constraint has no effect until the view has drawn once, and applying
        // it too early produces the 0x0-then-fullscreen flicker (C-22).
        applyKeyboardHeight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.diagnostics.stopMemoryMonitor()
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

        // Opaque backgrounds render as a gray bar under iOS 26's glass container
        // (CONSTRAINTS §8 gotcha ledger).
        view.backgroundColor = .clear
    }

    private func applyKeyboardHeight() {
        let rowCount = CGFloat(model.rows.count)
        let height = rowCount * KeyboardTheme.keyRowHeight
            + (rowCount - 1) * KeyboardTheme.rowSpacing
            + KeyboardTheme.keyboardVerticalPadding * 2
            + KeyboardTheme.diagnosticsBarHeight

        if let heightConstraint {
            heightConstraint.constant = height
            return
        }

        let constraint = view.heightAnchor.constraint(equalToConstant: height)
        // Just below required so it cannot conflict with the system's own layout pass
        // while the input view is still settling (C-22).
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint
    }
}

// MARK: - KeyboardActionHandler

extension KeyboardViewController: KeyboardActionHandler {

    func insert(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func advanceToNextKeyboard() {
        advanceToNextInputMode()
    }
}
