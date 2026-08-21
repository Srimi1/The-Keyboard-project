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

    /// Deletes back to the start of the preceding word, which is where held backspace
    /// accelerates to. Falls back to a single character when there is no word boundary to
    /// find — `documentContextBeforeInput` only reaches back a sentence or so (C-18).
    func deleteWordBackward() {
        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            textDocumentProxy.deleteBackward()
            return
        }

        // Trailing whitespace goes first, then the word itself — deleting a word from
        // "hello world " should leave "hello ", not "hello world".
        var remaining = Substring(context)
        var deletions = 0

        while let last = remaining.last, last.isWhitespace, !last.isNewline {
            remaining = remaining.dropLast()
            deletions += 1
        }
        while let last = remaining.last, !last.isWhitespace {
            remaining = remaining.dropLast()
            deletions += 1
        }

        for _ in 0..<max(deletions, 1) {
            textDocumentProxy.deleteBackward()
        }
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
