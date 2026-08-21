import Foundation
import SwiftUI
import UIKit

/// What the keyboard can do to the text field, and what it needs to read from it.
///
/// Implemented by the view controller so the SwiftUI layer never touches `textDocumentProxy`
/// directly — the proxy's limits (C-18) then live in exactly one place.
@MainActor
protocol KeyboardActionHandler: AnyObject {
    func insert(_ text: String)
    func deleteBackward()
    func deleteWordBackward()

    /// Wires a real UIButton to `handleInputModeList(from:with:)`. A SwiftUI Button handles
    /// only tap and silently loses the long-press keyboard picker (C-47).
    func configureNextKeyboardButton(_ button: UIButton)

    var hasFullAccess: Bool { get }
    var contextBeforeInput: String? { get }
    var autocapitalizationType: UITextAutocapitalizationType { get }
    var returnKeyType: UIReturnKeyType { get }
}

@MainActor
final class KeyboardViewModel: ObservableObject {

    @Published private(set) var layer: KeyboardLayer = .base
    @Published private(set) var shiftState: ShiftState = .off
    @Published private(set) var pressedKeyIDs: Set<String> = []
    @Published var showDiagnostics = false
    @Published var needsGlobe = false
    @Published var returnLabel = "return"

    let diagnostics = DiagnosticsRunner()
    weak var handler: KeyboardActionHandler?

    private var shift = ShiftController()
    private let repeater = KeyRepeater()
    private var lastSpaceAt: Date?

    /// Ordered by press time so rollover commits in the order keys were pressed, not the
    /// order fingers happened to lift.
    private var activeTouches: [ActiveTouch] = []

    private struct ActiveTouch {
        let id: ObjectIdentifier
        let keyID: String
        var committed: Bool
    }

    var rows: [KeyRow] {
        KeyboardLayout.rows(
            layer: layer,
            shift: shiftState,
            needsGlobe: needsGlobe,
            returnLabel: returnLabel
        )
    }

    // MARK: - Text field context

    /// Re-reads the field's traits and raises shift if the cursor sits at a sentence start.
    /// Called on every appearance and after each edit, since the proxy has no change
    /// notification.
    func syncWithTextField() {
        guard let handler else { return }

        returnLabel = ReturnKeyLabel.label(for: handler.returnKeyType)

        let shouldCapitalize = AutoCapitalization.shouldCapitalize(
            before: handler.contextBeforeInput,
            type: handler.autocapitalizationType
        )
        shift.applyAutoCapitalization(shouldCapitalize)
        shiftState = shift.state
    }

    // MARK: - Touch handling

    func handle(touches: [KeyboardTouch], positionedKeys: [PositionedKey]) {
        for touch in touches {
            switch touch.phase {
            case .began:
                begin(touch, positionedKeys: positionedKeys)
            case .moved:
                move(touch, positionedKeys: positionedKeys)
            case .ended:
                end(touch, positionedKeys: positionedKeys)
            case .cancelled:
                cancel(touch)
            }
        }
    }

    private func begin(_ touch: KeyboardTouch, positionedKeys: [PositionedKey]) {
        guard let positioned = KeyboardMetrics.key(at: touch.location, in: positionedKeys) else { return }

        // Rollover: a new finger landing means every key still held has been "typed past",
        // so flush them in press order before registering this one (UI-SPEC §3).
        commitPendingPresses(positionedKeys: positionedKeys)

        activeTouches.append(ActiveTouch(id: touch.id, keyID: positioned.id, committed: false))
        pressedKeyIDs.insert(positioned.id)

        // Backspace is the one key that acts on press and repeats while held.
        if positioned.key.action == .backspace {
            markCommitted(touch.id)
            repeater.start { [weak self] deletesWord in
                guard let self, let handler = self.handler else { return }
                if deletesWord {
                    handler.deleteWordBackward()
                } else {
                    handler.deleteBackward()
                }
                self.syncWithTextField()
            }
        }
    }

    private func move(_ touch: KeyboardTouch, positionedKeys: [PositionedKey]) {
        guard let index = activeTouches.firstIndex(where: { $0.id == touch.id }) else { return }
        let active = activeTouches[index]
        guard !active.committed else { return }

        // Hysteresis so a slight drift keeps the key — without it, fast typing drops
        // characters at key edges.
        let stillOnKey = positionedKeys
            .first { $0.id == active.keyID }
            .map { $0.rect.insetBy(dx: -KeyboardTimings.keyHysteresis, dy: -KeyboardTimings.keyHysteresis).contains(touch.location) }
            ?? false

        if !stillOnKey {
            pressedKeyIDs.remove(active.keyID)
            activeTouches.remove(at: index)
        }
    }

    private func end(_ touch: KeyboardTouch, positionedKeys: [PositionedKey]) {
        guard let index = activeTouches.firstIndex(where: { $0.id == touch.id }) else { return }
        let active = activeTouches.remove(at: index)
        pressedKeyIDs.remove(active.keyID)

        if active.keyID == backspaceKeyID {
            repeater.stop()
            return
        }

        guard !active.committed,
              let positioned = positionedKeys.first(where: { $0.id == active.keyID }) else { return }
        perform(positioned.key.action)
    }

    private func cancel(_ touch: KeyboardTouch) {
        guard let index = activeTouches.firstIndex(where: { $0.id == touch.id }) else { return }
        let active = activeTouches.remove(at: index)
        pressedKeyIDs.remove(active.keyID)
        if active.keyID == backspaceKeyID { repeater.stop() }
    }

    private func commitPendingPresses(positionedKeys: [PositionedKey]) {
        for active in activeTouches where !active.committed {
            guard let positioned = positionedKeys.first(where: { $0.id == active.keyID }) else { continue }
            perform(positioned.key.action)
        }
        for index in activeTouches.indices {
            activeTouches[index].committed = true
        }
    }

    private func markCommitted(_ id: ObjectIdentifier) {
        guard let index = activeTouches.firstIndex(where: { $0.id == id }) else { return }
        activeTouches[index].committed = true
    }

    private let backspaceKeyID = "key-backspace"

    // MARK: - Actions

    func perform(_ action: KeyAction) {
        guard let handler else { return }

        switch action {
        case .character(let text):
            handler.insert(text)
            shift.didInsertCharacter()
            lastSpaceAt = nil
            syncAfterEdit()

        case .space:
            insertSpace(handler: handler)

        case .newline:
            handler.insert("\n")
            lastSpaceAt = nil
            syncAfterEdit()

        case .backspace:
            handler.deleteBackward()
            lastSpaceAt = nil
            syncAfterEdit()

        case .shift:
            shift.handleTap()
            shiftState = shift.state

        case .switchLayer(let target):
            layer = target

        case .nextKeyboard:
            break   // handled by NextKeyboardButton — needs UIKit target-action (C-47)

        case .diagnostics:
            showDiagnostics.toggle()
            if showDiagnostics {
                diagnostics.runSafeProbes(hasFullAccess: handler.hasFullAccess)
            }
        }
    }

    /// Double-space inserts ". " — but only when a real word precedes it, so it does not fire
    /// after punctuation or at the start of a line.
    private func insertSpace(handler: KeyboardActionHandler) {
        let now = Date()

        if let last = lastSpaceAt,
           now.timeIntervalSince(last) <= KeyboardTimings.doubleSpacePeriodTimeout,
           canConvertDoubleSpaceToPeriod(context: handler.contextBeforeInput) {
            handler.deleteBackward()      // remove the first space
            handler.insert(". ")
            lastSpaceAt = nil
        } else {
            handler.insert(" ")
            lastSpaceAt = now
        }

        shift.didInsertCharacter()
        syncAfterEdit()
    }

    private func canConvertDoubleSpaceToPeriod(context: String?) -> Bool {
        guard let context else { return false }
        // The context still ends in the space we just inserted; look at what came before it.
        var characters = Array(context)
        guard characters.last == " " else { return false }
        characters.removeLast()
        guard let preceding = characters.last else { return false }
        return preceding.isLetter || preceding.isNumber
    }

    private func syncAfterEdit() {
        syncWithTextField()
    }
}
