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
    /// Moves the caret by whole characters, for the spacebar cursor slide (UI-SPEC §6).
    func adjustTextPosition(by offset: Int)

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
    @Published var needsGlobe = false
    @Published var returnLabel = "return"

    weak var handler: KeyboardActionHandler?

    // The M0 harness is a development tool, not a keyboard feature. Gating the property
    // rather than no-op'ing the calls is what actually keeps `DiagnosticsRunner` and its
    // 1 Hz timer out of the shipping binary.
    #if DEBUG
    @Published var showDiagnostics = false
    let diagnostics = DiagnosticsRunner()
    #endif

    /// The accent / punctuation callout currently open, if any.
    @Published private(set) var callout: CalloutState?

    struct CalloutState: Equatable {
        let keyID: String
        /// The held key's visual rect, so the callout can anchor above it.
        let anchor: CGRect
        let options: [String]
        /// Columns before wrapping. The punctuation grid is 8 wide; letter callouts are one row.
        let columns: Int
        var selectedIndex: Int

        var rows: Int { Int(ceil(Double(options.count) / Double(max(columns, 1)))) }
    }

    let feedback = FeedbackService()

    private var shift = ShiftController()
    private let repeater = KeyRepeater()
    private var lastSpaceAt: Date?

    /// Set when double-space just produced ". ", so an immediate backspace can put the two
    /// spaces back rather than leaving a bare ".".
    private var revertibleDoubleSpace = false

    private var longPressTask: Task<Void, Never>?
    /// Accumulated horizontal travel of a finger sliding on the spacebar, in points.
    private var spaceSlideDistance: CGFloat = 0

    /// Ordered by press time so rollover commits in the order keys were pressed, not the
    /// order fingers happened to lift.
    private var activeTouches: [ActiveTouch] = []

    private struct ActiveTouch {
        let id: ObjectIdentifier
        let keyID: String
        var committed: Bool
        /// Where the finger landed, for measuring spacebar slide travel.
        var startLocation: CGPoint
        /// Once a finger opens a callout or starts sliding the caret, releasing it must not
        /// also type the key it started on.
        var suppressesKeyOnRelease: Bool = false
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
        // UIKit recycles UITouch objects between sequences, so an identity can collide with a
        // stale entry that never saw its ended/cancelled.
        activeTouches.removeAll { $0.id == touch.id }

        guard let positioned = KeyboardMetrics.key(at: touch.location, in: positionedKeys) else { return }

        // Rollover: a new finger landing means every key still held has been "typed past",
        // so flush them in press order before registering this one (UI-SPEC §3).
        commitPendingPresses(positionedKeys: positionedKeys)

        activeTouches.append(
            ActiveTouch(id: touch.id, keyID: positioned.id, committed: false, startLocation: touch.location)
        )
        pressedKeyIDs.insert(positioned.id)
        spaceSlideDistance = 0

        // On press, not release: the tap should feel immediate, the way a real key does.
        feedback.keyPressed()

        // Backspace is the one key that acts on press and repeats while held.
        if positioned.key.action == .backspace {
            markCommitted(touch.id)
            repeater.start { [weak self] characterCount in
                guard let self, let handler = self.handler else { return }
                for _ in 0..<characterCount { handler.deleteBackward() }
                self.revertibleDoubleSpace = false
                self.syncWithTextField()
            }
            return
        }

        scheduleLongPress(for: positioned, touchID: touch.id)
    }

    // MARK: - Long press (UI-SPEC §5)

    private func scheduleLongPress(for positioned: PositionedKey, touchID: ObjectIdentifier) {
        longPressTask?.cancel()
        guard let options = MoreKeys.options(for: positioned.key, shift: shiftState) else { return }

        longPressTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(KeyboardTimings.longPressTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Only open if that same finger is still down and has not been committed by
            // rollover in the meantime.
            guard let active = self.activeTouches.first(where: { $0.id == touchID }), !active.committed else { return }

            self.callout = CalloutState(
                keyID: positioned.id,
                anchor: positioned.rect,
                options: options,
                columns: MoreKeys.columns(for: positioned.key, options: options),
                selectedIndex: 0
            )
            self.suppressKeyOnRelease(touchID)
        }
    }

    private func suppressKeyOnRelease(_ id: ObjectIdentifier) {
        guard let index = activeTouches.firstIndex(where: { $0.id == id }) else { return }
        activeTouches[index].suppressesKeyOnRelease = true
    }

    /// Maps the finger's position across the callout grid to a selected option.
    private func updateCalloutSelection(at point: CGPoint) {
        guard var callout else { return }
        guard let index = calloutIndex(at: point, in: callout) else { return }
        guard index != callout.selectedIndex else { return }

        callout.selectedIndex = index
        self.callout = callout
        feedback.selectionChanged()
    }

    // Callout geometry lives here rather than in the view so selection and drawing agree —
    // the same reason hit-testing and rendering share ``KeyboardMetrics``.

    func calloutOptionSize(for callout: CalloutState) -> CGSize {
        CGSize(width: max(callout.anchor.width, 34), height: callout.anchor.height)
    }

    /// Top-left of the callout grid.
    func calloutOrigin(for callout: CalloutState) -> CGPoint {
        let option = calloutOptionSize(for: callout)
        let width = option.width * CGFloat(min(callout.columns, callout.options.count))
        let height = option.height * CGFloat(callout.rows)
        // A keyboard cannot draw above its own top edge, so a callout on the top row sits
        // just below it rather than floating outside (C-45).
        let y = max(0, callout.anchor.minY - height - 2)
        return CGPoint(x: callout.anchor.midX - width / 2, y: y)
    }

    /// AOSP fills the row nearest the finger first, so resource item 0 is bottom-left.
    func calloutIndex(at point: CGPoint, in callout: CalloutState) -> Int? {
        let option = calloutOptionSize(for: callout)
        let origin = calloutOrigin(for: callout)

        let column = min(max(Int((point.x - origin.x) / option.width), 0), callout.columns - 1)
        let rowFromTop = min(max(Int((point.y - origin.y) / option.height), 0), callout.rows - 1)
        let rowFromBottom = callout.rows - 1 - rowFromTop

        let index = rowFromBottom * callout.columns + column
        return index < callout.options.count ? index : nil
    }

    private func move(_ touch: KeyboardTouch, positionedKeys: [PositionedKey]) {
        guard let index = activeTouches.firstIndex(where: { $0.id == touch.id }) else { return }
        let active = activeTouches[index]

        // A finger inside an open callout is choosing an accent, not still pressing the key.
        if callout?.keyID == active.keyID {
            updateCalloutSelection(at: touch.location)
            return
        }

        // Sliding on the spacebar moves the caret instead of typing (UI-SPEC §6).
        if active.keyID == spaceKeyID {
            handleSpaceSlide(touch, index: index)
            return
        }

        guard !active.committed else { return }

        // Hysteresis so a slight drift keeps the key — without it, fast typing drops
        // characters at key edges. Measured from the visual rect (see isStillOnKey).
        let stillOnKey = positionedKeys
            .first { $0.id == active.keyID }
            .map { KeyboardMetrics.isStillOnKey(touch.location, key: $0, hysteresis: KeyboardTimings.keyHysteresis) }
            ?? false

        if !stillOnKey {
            longPressTask?.cancel()
            pressedKeyIDs.remove(active.keyID)
            activeTouches.remove(at: index)
        }
    }

    private let spaceKeyID = "key-space"

    /// Slide the caret one character per threshold crossed, via `adjustTextPosition`.
    ///
    /// The proxy moves by grapheme clusters and clamps at the edge of the cached context
    /// (C-18), so this cannot run off the end of what we can see.
    private func handleSpaceSlide(_ touch: KeyboardTouch, index: Int) {
        let travel = touch.location.x - activeTouches[index].startLocation.x
        let steps = Int((travel - spaceSlideDistance) / Self.spaceSlideStep)
        guard steps != 0 else { return }

        spaceSlideDistance += CGFloat(steps) * Self.spaceSlideStep
        handler?.adjustTextPosition(by: steps)
        feedback.selectionChanged()

        // Once the caret has moved, releasing must not also insert a space.
        activeTouches[index].suppressesKeyOnRelease = true
        longPressTask?.cancel()
        syncWithTextField()
    }

    /// 📐 MEASURE (UI-SPEC §6): the points of travel per character step. AOSP does not expose
    /// a constant for this, so it needs tuning against Gboard by feel.
    private static let spaceSlideStep: CGFloat = 10

    private func end(_ touch: KeyboardTouch, positionedKeys: [PositionedKey]) {
        guard let index = activeTouches.firstIndex(where: { $0.id == touch.id }) else { return }
        let active = activeTouches.remove(at: index)
        pressedKeyIDs.remove(active.keyID)
        longPressTask?.cancel()

        if active.keyID == backspaceKeyID {
            repeater.stop()
            return
        }

        // Releasing inside a callout picks the accent rather than typing the base letter.
        if let callout, callout.keyID == active.keyID {
            let selection = callout.options[callout.selectedIndex]
            self.callout = nil
            handler?.insert(selection)
            shift.didInsertCharacter()
            revertibleDoubleSpace = false
            syncWithTextField()
            return
        }

        guard !active.committed, !active.suppressesKeyOnRelease,
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

    /// Drops every tracked finger and clears the pressed highlight. Called when the geometry
    /// or layer changes underneath the touches, since the view is never rebuilt and a
    /// stranded pointer would otherwise stay pressed for the life of the extension.
    func releaseAllTouches() {
        activeTouches.removeAll()
        pressedKeyIDs.removeAll()
        repeater.stop()
        longPressTask?.cancel()
        callout = nil
    }

    // MARK: - Actions

    func perform(_ action: KeyAction) {
        guard let handler else { return }

        switch action {
        case .character(let text):
            handler.insert(text)
            shift.didInsertCharacter()
            lastSpaceAt = nil
            revertibleDoubleSpace = false
            syncAfterEdit()

        case .space:
            insertSpace(handler: handler)

        case .newline:
            handler.insert("\n")
            lastSpaceAt = nil
            syncAfterEdit()

        case .backspace:
            // Backspace straight after double-space put a period in restores the two spaces,
            // rather than leaving a bare "." the user never asked for.
            if revertibleDoubleSpace {
                handler.deleteBackward()   // the space
                handler.deleteBackward()   // the period
                handler.insert("  ")
                revertibleDoubleSpace = false
            } else {
                handler.deleteBackward()
            }
            lastSpaceAt = nil
            syncAfterEdit()

        case .shift:
            shift.handleTap()
            shiftState = shift.state

        case .switchLayer(let target):
            layer = target
            // The extension's view is never torn down, so a finger still down across a layer
            // switch would stay "pressed" forever and its key would never clear.
            releaseAllTouches()

        case .nextKeyboard:
            break   // handled by NextKeyboardButton — needs UIKit target-action (C-47)

        case .diagnostics:
            // The key exists in `KeyAction` so the switch stays exhaustive; nothing can
            // reach it in Release, where the button that sends it is compiled out.
            #if DEBUG
            showDiagnostics.toggle()
            if showDiagnostics {
                diagnostics.runSafeProbes(hasFullAccess: handler.hasFullAccess)
            }
            #endif
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
            revertibleDoubleSpace = true
        } else {
            handler.insert(" ")
            lastSpaceAt = now
            revertibleDoubleSpace = false
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
