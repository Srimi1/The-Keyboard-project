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

    enum Panel: Equatable {
        case keys
        case clipboard
        case settings
        case diagnostics
    }

    @Published private(set) var layer: KeyboardLayer = .base
    @Published private(set) var shiftState: ShiftState = .off
    @Published private(set) var pressedKeyIDs: Set<String> = []
    @Published var needsGlobe = false
    @Published var returnLabel = "return"

    weak var handler: KeyboardActionHandler?

    let settings: KeyboardSettingsStore
    /// The clipboard manager owns manual paste transfers, history and the paste chip.
    let clipboard: ClipboardController
    /// Exactly one surface can replace the keys at a time.
    @Published private(set) var panel: Panel = .keys

    // The M0 harness is a development tool, not a keyboard feature. Gating the property
    // rather than no-op'ing the calls is what actually keeps `DiagnosticsRunner` and its
    // 1 Hz timer out of the shipping binary.
    #if DEBUG
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
        let containerWidth: CGFloat
        var selectedIndex: Int

        var rows: Int { Int(ceil(Double(options.count) / Double(max(columns, 1)))) }
    }

    let feedback = FeedbackService()

    private var shift = ShiftController()
    private let repeater = KeyRepeater()
    private var lastSpaceAt: Date?
    private var lastSpaceContext: String?

    /// Exact document context after double-space produced ". ". An immediate backspace may
    /// restore the two spaces only while the caret is still at that exact context. Keeping the
    /// snapshot prevents a later cursor move or host edit from rewriting unrelated text.
    private var revertibleDoubleSpaceContext: String?

    /// Ordered by press time so rollover commits in the order keys were pressed, not the
    /// order fingers happened to lift.
    private var activeTouches: [ActiveTouch] = []

    private struct ActiveTouch {
        let id: ObjectIdentifier
        let keyID: String
        /// Action and hit bounds resolved at press time. SwiftUI may not have delivered the
        /// rerendered layout by release, so consulting a callback's old key array can type the
        /// wrong case/layer or drop the press entirely.
        let action: KeyAction
        let visualRect: CGRect
        var committed: Bool
        /// Where the finger landed, for measuring spacebar slide travel.
        var startLocation: CGPoint
        /// Per-finger state: another finger landing must not reset a spacebar slide.
        var spaceSlideDistance: CGFloat = 0
        var longPressTask: Task<Void, Never>?
        /// Once a finger opens a callout or starts sliding the caret, releasing it must not
        /// also type the key it started on.
        var suppressesKeyOnRelease: Bool = false
    }

    init(
        settings: KeyboardSettingsStore = KeyboardSettingsStore(),
        repository: any ClipboardRepositoryProtocol = ClipboardRepository()
    ) {
        self.settings = settings
        self.clipboard = ClipboardController(repository: repository, settings: settings)
        feedback.apply(settings.values)
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

    /// The host calls this when its text or selection changes outside a key action. Preserve the
    /// double-space rollback only if the proxy still exposes the exact post-transform context.
    func inputContextDidChange() {
        clipboard.cancelPendingInsertion()
        if let expected = revertibleDoubleSpaceContext,
           handler?.contextBeforeInput != expected {
            clearDoubleSpaceState()
        } else if let expected = lastSpaceContext,
                  handler?.contextBeforeInput != expected {
            clearDoubleSpaceState()
        }
        syncWithTextField()
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
        if let staleIndex = activeTouches.firstIndex(where: { $0.id == touch.id }) {
            tearDownActiveTouch(at: staleIndex)
        }

        guard KeyboardMetrics.key(at: touch.location, in: positionedKeys) != nil else { return }

        // Rollover: a new finger landing means every key still held has been "typed past",
        // so flush them in press order before registering this one (UI-SPEC §3).
        commitPendingPresses()

        // The committed key may have switched layer or shift state. Rebuild geometry from the
        // same tiled bounds and hit-test again, so the new finger belongs to the layout now on
        // screen instead of carrying an obsolete letter/symbol action until release.
        let layoutSize = CGSize(
            width: positionedKeys.map(\.hitRect.maxX).max() ?? 0,
            height: positionedKeys.map(\.hitRect.maxY).max() ?? 0
        )
        let currentKeys = KeyboardMetrics.positionedKeys(rows: rows, in: layoutSize)
        guard let positioned = KeyboardMetrics.key(at: touch.location, in: currentKeys) else { return }

        activeTouches.append(
            ActiveTouch(
                id: touch.id,
                keyID: positioned.id,
                action: positioned.key.action,
                visualRect: positioned.rect,
                committed: false,
                startLocation: touch.location
            )
        )
        pressedKeyIDs.insert(positioned.id)

        // On press, not release: the tap should feel immediate, the way a real key does.
        feedback.keyPressed()

        // Backspace is the one key that acts on press and repeats while held.
        if positioned.key.action == .backspace {
            markCommitted(touch.id)
            repeater.start { [weak self] in
                self?.perform(.backspace)
            } repeatFire: { [weak self] characterCount in
                guard let self, let handler = self.handler else { return }
                for _ in 0..<characterCount { handler.deleteBackward() }
                self.clearDoubleSpaceState()
                self.didEditText()
                self.syncWithTextField()
            }
            return
        }

        scheduleLongPress(for: positioned, touchID: touch.id, positionedKeys: positionedKeys)
    }

    // MARK: - Long press (UI-SPEC §5)

    private func scheduleLongPress(
        for positioned: PositionedKey,
        touchID: ObjectIdentifier,
        positionedKeys: [PositionedKey]
    ) {
        guard let options = MoreKeys.options(for: positioned.key, shift: shiftState) else { return }

        let task = Task { [weak self] in
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
                containerWidth: positionedKeys.map(\.rect.maxX).max() ?? positioned.rect.maxX,
                selectedIndex: 0
            )
            self.suppressKeyOnRelease(touchID)
        }
        if let index = activeTouches.firstIndex(where: { $0.id == touchID }) {
            activeTouches[index].longPressTask = task
        } else {
            task.cancel()
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
        let proposedX = callout.anchor.midX - width / 2
        let x = min(max(0, proposedX), max(0, callout.containerWidth - width))
        return CGPoint(x: x, y: y)
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

        // Backspace acts on press and is therefore already marked committed, but moving the
        // finger off it must still stop that finger's repeat stream.
        if active.keyID == backspaceKeyID {
            let stillOnKey = active.visualRect
                .insetBy(dx: -KeyboardTimings.keyHysteresis, dy: -KeyboardTimings.keyHysteresis)
                .contains(touch.location)
            if !stillOnKey {
                pressedKeyIDs.remove(active.keyID)
                activeTouches.remove(at: index)
                stopRepeaterIfNoBackspaceTouchesRemain()
            }
            return
        }

        // Rollover can commit a held key before that finger moves again. A committed space
        // must not continue moving the caret after another key has taken over.
        guard !active.committed else { return }

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

        // Hysteresis so a slight drift keeps the key — without it, fast typing drops
        // characters at key edges. Measured from the visual rect (see isStillOnKey).
        let stillOnKey = active.visualRect
            .insetBy(dx: -KeyboardTimings.keyHysteresis, dy: -KeyboardTimings.keyHysteresis)
            .contains(touch.location)

        if !stillOnKey {
            activeTouches[index].longPressTask?.cancel()
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
        let steps = Int((travel - activeTouches[index].spaceSlideDistance) / Self.spaceSlideStep)
        guard steps != 0 else { return }

        activeTouches[index].spaceSlideDistance += CGFloat(steps) * Self.spaceSlideStep
        clearDoubleSpaceState()
        clipboard.cancelPendingInsertion()
        handler?.adjustTextPosition(by: steps)
        feedback.selectionChanged()

        // Once the caret has moved, releasing must not also insert a space.
        activeTouches[index].suppressesKeyOnRelease = true
        activeTouches[index].longPressTask?.cancel()
        syncWithTextField()
    }

    /// 📐 MEASURE (UI-SPEC §6): the points of travel per character step. AOSP does not expose
    /// a constant for this, so it needs tuning against Gboard by feel.
    private static let spaceSlideStep: CGFloat = 10

    private func end(_ touch: KeyboardTouch, positionedKeys: [PositionedKey]) {
        guard let index = activeTouches.firstIndex(where: { $0.id == touch.id }) else { return }
        let active = activeTouches.remove(at: index)
        pressedKeyIDs.remove(active.keyID)
        active.longPressTask?.cancel()

        if active.keyID == backspaceKeyID {
            stopRepeaterIfNoBackspaceTouchesRemain()
            return
        }

        // Releasing inside a callout picks the accent rather than typing the base letter.
        if let callout, callout.keyID == active.keyID {
            insertCalloutSelection(callout)
            return
        }

        guard !active.committed, !active.suppressesKeyOnRelease else { return }
        perform(active.action)
    }

    private func cancel(_ touch: KeyboardTouch) {
        guard let index = activeTouches.firstIndex(where: { $0.id == touch.id }) else { return }
        let active = activeTouches.remove(at: index)
        pressedKeyIDs.remove(active.keyID)
        active.longPressTask?.cancel()
        if active.keyID == backspaceKeyID { stopRepeaterIfNoBackspaceTouchesRemain() }
        if callout?.keyID == active.keyID { callout = nil }
    }

    private func commitPendingPresses() {
        let pending = activeTouches.filter { !$0.committed }
        for active in pending {
            if active.suppressesKeyOnRelease {
                if let callout, callout.keyID == active.keyID {
                    insertCalloutSelection(callout)
                }
                // A cursor slide suppresses its original space. No other suppressed gesture
                // should fall through and type its base key during rollover.
                continue
            }
            perform(active.action)
        }
        for index in activeTouches.indices {
            activeTouches[index].longPressTask?.cancel()
            activeTouches[index].committed = true
        }
    }

    private func insertCalloutSelection(_ callout: CalloutState) {
        let selection = callout.options[callout.selectedIndex]
        self.callout = nil
        handler?.insert(selection)
        shift.didInsertCharacter()
        clearDoubleSpaceState()
        didEditText()
        syncWithTextField()
    }

    private func stopRepeaterIfNoBackspaceTouchesRemain() {
        guard !activeTouches.contains(where: { $0.keyID == backspaceKeyID }) else { return }
        repeater.stop()
    }

    private func tearDownActiveTouch(at index: Int) {
        let stale = activeTouches.remove(at: index)
        stale.longPressTask?.cancel()
        if !activeTouches.contains(where: { $0.keyID == stale.keyID }) {
            pressedKeyIDs.remove(stale.keyID)
        }
        if stale.keyID == backspaceKeyID { stopRepeaterIfNoBackspaceTouchesRemain() }
        if callout?.keyID == stale.keyID { callout = nil }
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
        for active in activeTouches { active.longPressTask?.cancel() }
        activeTouches.removeAll()
        pressedKeyIDs.removeAll()
        repeater.stop()
        callout = nil
    }

    // MARK: - Clipboard

    func toggleClipboard() {
        showPanel(panel == .clipboard ? .keys : .clipboard)
    }

    func closeClipboard() {
        showPanel(.keys)
    }

    func toggleSettings() {
        showPanel(panel == .settings ? .keys : .settings)
    }

    func showPanel(_ destination: Panel) {
        guard panel != destination else { return }
        releaseAllTouches()
        clipboard.cancelPendingInteractions()
        panel = destination
        if destination == .clipboard { clipboard.refreshHistory() }
    }

    func setHapticsEnabled(_ enabled: Bool) {
        settings.setHapticsEnabled(enabled)
        feedback.apply(settings.values)
        if enabled { feedback.prepare() }
    }

    func setSoundEnabled(_ enabled: Bool) {
        settings.setSoundEnabled(enabled)
        feedback.apply(settings.values)
    }

    func setAppearance(_ appearance: KeyboardAppearance) {
        settings.setAppearance(appearance)
    }

    func setClipboardCaptureMode(_ mode: ClipboardCaptureMode) {
        settings.setClipboardCaptureMode(mode)
    }

    func acceptClipboardNotice() {
        settings.acceptClipboardNotice()
    }

    func activate(hasFullAccess: Bool) {
        settings.refresh(canUseShared: hasFullAccess)
        feedback.hasFullAccess = hasFullAccess
        feedback.apply(settings.values)
        feedback.prepare()
        clipboard.activate(.keyboard(hasFullAccess: hasFullAccess))
        panel = .keys
        clearDoubleSpaceState()
    }

    func deactivate() {
        releaseAllTouches()
        clipboard.deactivate()
        panel = .keys
        clearDoubleSpaceState()
    }

    /// Tap-to-insert from the panel or the paste chip. The panel stays open afterwards
    /// (CLIPBOARD.md §5) so several items can be pasted in a row.
    func insertClipboardText(_ text: String) {
        guard let handler else { return }
        clearDoubleSpaceState()
        handler.insert(text)
        shift.didInsertCharacter()
        didEditText()
        feedback.keyPressed()
        syncAfterEdit()
    }

    func insertClipboardItem(_ item: ClipboardItem) {
        // Strip actions live above the touch surface and can arrive while a key is held. Commit
        // older presses first, then stop repeat/gesture state so paste ordering is deterministic.
        commitPendingPresses()
        releaseAllTouches()
        clipboard.resolveTextForInsertion(id: item.id) { [weak self] text in
            self?.insertClipboardText(text)
        }
    }

    // MARK: - Actions

    func perform(_ action: KeyAction) {
        guard let handler else { return }
        clipboard.cancelPendingInsertion()
        if action != .shift { shift.cancelTapSequence() }

        switch action {
        case .character(let text):
            handler.insert(text)
            shift.didInsertCharacter()
            clearDoubleSpaceState()
            didEditText()
            syncAfterEdit()

        case .space:
            insertSpace(handler: handler)

        case .newline:
            handler.insert("\n")
            clearDoubleSpaceState()
            didEditText()
            syncAfterEdit()

        case .backspace:
            // Backspace straight after double-space put a period in restores the two spaces,
            // rather than leaving a bare "." the user never asked for.
            if let expected = revertibleDoubleSpaceContext,
               handler.contextBeforeInput == expected {
                handler.deleteBackward()   // the space
                handler.deleteBackward()   // the period
                handler.insert("  ")
            } else {
                handler.deleteBackward()
            }
            clearDoubleSpaceState()
            didEditText()
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
            showPanel(panel == .diagnostics ? .keys : .diagnostics)
            if panel == .diagnostics {
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
           handler.contextBeforeInput == lastSpaceContext,
           canConvertDoubleSpaceToPeriod(context: handler.contextBeforeInput) {
            handler.deleteBackward()      // remove the first space
            handler.insert(". ")
            lastSpaceAt = nil
            revertibleDoubleSpaceContext = handler.contextBeforeInput
        } else {
            handler.insert(" ")
            lastSpaceAt = now
            lastSpaceContext = handler.contextBeforeInput
            revertibleDoubleSpaceContext = nil
        }

        shift.didInsertCharacter()
        didEditText()
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

    private func clearDoubleSpaceState() {
        lastSpaceAt = nil
        lastSpaceContext = nil
        revertibleDoubleSpaceContext = nil
    }

    private func didEditText() {
        clipboard.userDidType()
    }
}
