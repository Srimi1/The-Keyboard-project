import XCTest
import UIKit
@testable import KeyboardProject

/// Deterministic coverage for touch ordering that XCUITest cannot express at two chosen
/// coordinates. The UI suite separately proves that UIKit delivers two simultaneous fingers.
@MainActor
final class KeyboardTouchTests: XCTestCase {
    private let size = CGSize(width: 390, height: 216)

    func testDistinctKeyRolloverCommitsInPressOrder() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let firstToken = NSObject()
        let secondToken = NSObject()
        let first = touch(for: "key-g", token: firstToken, phase: .began, keys: keys)
        let second = touch(for: "key-h", token: secondToken, phase: .began, keys: keys)

        // The second press commits the first while it is still held. Releasing the second
        // types it, and releasing the already-committed first must not duplicate it.
        model.handle(touches: [first, second], positionedKeys: keys)
        model.handle(
            touches: [touch(for: "key-h", token: secondToken, phase: .ended, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-g", token: firstToken, phase: .ended, keys: keys)],
            positionedKeys: keys
        )

        XCTAssertEqual(handler.text, "gh")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testShiftedRolloverSurvivesTheLowercaseLayoutRerender() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        model.perform(.shift)

        let shiftedKeys = positionedKeys(shift: .shifted)
        let firstToken = NSObject()
        let secondToken = NSObject()
        model.handle(
            touches: [
                touch(for: "key-g", token: firstToken, phase: .began, keys: shiftedKeys),
                touch(for: "key-h", token: secondToken, phase: .began, keys: shiftedKeys),
            ],
            positionedKeys: shiftedKeys
        )
        XCTAssertEqual(handler.text, "G", "the second press commits the shifted first key")

        // The first insertion consumes one-shot shift. Deliberately keep supplying the stale
        // shifted array to model the interval before SwiftUI completes its rerender.
        let lowercaseKeys = positionedKeys(shift: .off)
        model.handle(
            touches: [touch(for: "key-h", token: secondToken, phase: .ended, keys: shiftedKeys)],
            positionedKeys: shiftedKeys
        )
        model.handle(
            touches: [touch(for: "key-g", token: firstToken, phase: .ended, keys: lowercaseKeys)],
            positionedKeys: lowercaseKeys
        )

        XCTAssertEqual(handler.text, "Gh")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testHeldShiftRolloverUsesTheNewUppercaseAction() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let baseKeys = positionedKeys()
        let shiftToken = NSObject()
        let letterToken = NSObject()

        model.handle(
            touches: [
                touch(for: "key-shift", token: shiftToken, phase: .began, keys: baseKeys),
                touch(for: "key-g", token: letterToken, phase: .began, keys: baseKeys),
            ],
            positionedKeys: baseKeys
        )
        model.handle(
            touches: [touch(for: "key-g", token: letterToken, phase: .ended, keys: baseKeys)],
            positionedKeys: baseKeys
        )

        XCTAssertEqual(handler.text, "G")
    }

    func testLayerKeyRolloverReHitTestsSecondFingerOnSymbolLayout() throws {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let baseKeys = positionedKeys()
        let symbolKeys = KeyboardMetrics.positionedKeys(
            rows: KeyboardLayout.rows(layer: .symbols, shift: .off, needsGlobe: false),
            in: size
        )
        let layerToken = NSObject()
        let symbolToken = NSObject()
        let baseTarget = try XCTUnwrap(baseKeys.first(where: { $0.id == "key-g" }))
        let symbolTarget = try XCTUnwrap(
            KeyboardMetrics.key(at: CGPoint(x: baseTarget.rect.midX, y: baseTarget.rect.midY), in: symbolKeys)
        )
        guard case .character(let expectedText) = symbolTarget.key.action else {
            return XCTFail("test coordinate did not map to a symbol")
        }
        let secondBegan = KeyboardTouch(
            id: ObjectIdentifier(symbolToken),
            phase: .began,
            location: CGPoint(x: baseTarget.rect.midX, y: baseTarget.rect.midY)
        )

        model.handle(
            touches: [
                touch(for: "key-layer", token: layerToken, phase: .began, keys: baseKeys),
                secondBegan,
            ],
            positionedKeys: baseKeys
        )
        model.handle(
            touches: [KeyboardTouch(
                id: ObjectIdentifier(symbolToken),
                phase: .ended,
                location: secondBegan.location
            )],
            positionedKeys: baseKeys
        )

        XCTAssertEqual(model.layer, .symbols)
        XCTAssertEqual(handler.text, expectedText)
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testLifecycleCancellationPreventsLateReleaseInsertion() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let token = NSObject()

        model.handle(
            touches: [touch(for: "key-g", token: token, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        XCTAssertEqual(model.pressedKeyIDs, ["key-g"])

        model.releaseAllTouches()
        model.handle(
            touches: [touch(for: "key-g", token: token, phase: .ended, keys: keys)],
            positionedKeys: keys
        )

        XCTAssertEqual(handler.text, "")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testMoveBeyondVisualHysteresisCancelsLetterEvenInsideTiledHitArea() throws {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let token = NSObject()
        let key = try XCTUnwrap(keys.first(where: { $0.id == "key-g" }))

        model.handle(
            touches: [touch(for: "key-g", token: token, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [KeyboardTouch(
                id: ObjectIdentifier(token),
                phase: .moved,
                location: CGPoint(
                    x: key.rect.maxX + KeyboardTimings.keyHysteresis + 1,
                    y: key.rect.midY
                )
            )],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-g", token: token, phase: .ended, keys: keys)],
            positionedKeys: keys
        )

        XCTAssertEqual(handler.text, "")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testCursorSlideIsNotTurnedBackIntoSpaceByRollover() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let spaceToken = NSObject()
        let letterToken = NSObject()
        guard let space = keys.first(where: { $0.id == "key-space" }) else {
            return XCTFail("missing space key")
        }

        model.handle(
            touches: [touch(for: "key-space", token: spaceToken, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [KeyboardTouch(
                id: ObjectIdentifier(spaceToken),
                phase: .moved,
                location: CGPoint(x: space.rect.midX + 25, y: space.rect.midY)
            )],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-h", token: letterToken, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-h", token: letterToken, phase: .ended, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-space", token: spaceToken, phase: .ended, keys: keys)],
            positionedKeys: keys
        )

        XCTAssertEqual(handler.text, "h")
        XCTAssertEqual(handler.cursorOffset, 2)
    }

    func testOpenAccentCommitsOnceWhenAnotherFingerLands() async throws {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let accentToken = NSObject()
        let letterToken = NSObject()

        model.handle(
            touches: [touch(for: "key-a", token: accentToken, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotNil(model.callout)

        model.handle(
            touches: [touch(for: "key-h", token: letterToken, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-h", token: letterToken, phase: .ended, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-a", token: accentToken, phase: .ended, keys: keys)],
            positionedKeys: keys
        )

        XCTAssertEqual(handler.text, "àh", "the base letter must not be inserted beside its accent")
        XCTAssertNil(model.callout)
    }

    func testSlidingOffBackspaceStopsItsRepeatTask() async throws {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let token = NSObject()
        handler.text = "abcd"

        model.handle(
            touches: [touch(for: "key-backspace", token: token, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        XCTAssertEqual(handler.text, "abc")
        model.handle(
            touches: [KeyboardTouch(
                id: ObjectIdentifier(token),
                phase: .moved,
                location: CGPoint(x: -100, y: -100)
            )],
            positionedKeys: keys
        )

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(handler.text, "abc")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testPhysicalBackspaceRestoresTwoSpacesAfterDoubleSpacePeriod() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let token = NSObject()

        model.perform(.character("h"))
        model.perform(.space)
        model.perform(.space)
        XCTAssertEqual(handler.text, "h. ")

        model.handle(
            touches: [touch(for: "key-backspace", token: token, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [touch(for: "key-backspace", token: token, phase: .ended, keys: keys)],
            positionedKeys: keys
        )

        XCTAssertEqual(handler.text, "h  ")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testCaretSlideDisarmsDoubleSpaceRollbackBeforeBackspace() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let keys = positionedKeys()
        let spaceToken = NSObject()
        guard let space = keys.first(where: { $0.id == "key-space" }) else {
            return XCTFail("missing space key")
        }

        model.perform(.character("h"))
        model.perform(.space)
        model.perform(.space)
        model.handle(
            touches: [touch(for: "key-space", token: spaceToken, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [KeyboardTouch(
                id: ObjectIdentifier(spaceToken),
                phase: .moved,
                location: CGPoint(x: space.rect.midX + 25, y: space.rect.midY)
            )],
            positionedKeys: keys
        )
        model.perform(.backspace)

        XCTAssertEqual(handler.text, "h.", "backspace after a caret move must not restore old spaces")
    }

    func testHostContextChangeDisarmsDoubleSpaceRollback() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        model.perform(.character("h"))
        model.perform(.space)
        model.perform(.space)
        handler.text = "other"
        model.inputContextDidChange()
        model.perform(.backspace)

        XCTAssertEqual(handler.text, "othe")
    }

    func testHostContextChangeDisarmsPendingDoubleSpaceConversion() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        model.perform(.character("h"))
        model.perform(.space)
        handler.text = "other "
        model.inputContextDidChange()
        model.perform(.space)

        XCTAssertEqual(handler.text, "other  ")
    }

    func testClipboardInsertionDisarmsDoubleSpaceRollback() {
        let (model, handler, domain) = makeModel()
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        model.perform(.character("h"))
        model.perform(.space)
        model.perform(.space)
        model.insertClipboardText("paste")
        model.perform(.backspace)

        XCTAssertEqual(handler.text, "h. past")
    }

    func testLaterShiftCancelsEarlierSuspendedClipboardInsertion() async throws {
        let repository = ClipboardTestRepository()
        let (model, handler, domain) = makeModel(repository: repository)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        model.settings.acceptClipboardNotice()
        model.clipboard.activate(.hostApp)
        model.clipboard.saveProvidedText("older")
        try await waitUntil { !model.clipboard.isBusy && model.clipboard.history.items.count == 1 }
        let item = try XCTUnwrap(model.clipboard.history.items.first)
        await repository.suspendNextSweep()

        model.insertClipboardItem(item)
        try await waitUntil { await repository.sweepIsSuspended() }
        model.perform(.shift)
        await repository.resumeSweep()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(handler.text, "")
        XCTAssertEqual(model.shiftState, .shifted)
    }

    func testSpaceSlideCancelsEarlierSuspendedClipboardInsertion() async throws {
        let repository = ClipboardTestRepository()
        let (model, handler, domain) = makeModel(repository: repository)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        model.settings.acceptClipboardNotice()
        model.clipboard.activate(.hostApp)
        model.clipboard.saveProvidedText("older")
        try await waitUntil { !model.clipboard.isBusy && model.clipboard.history.items.count == 1 }
        let item = try XCTUnwrap(model.clipboard.history.items.first)
        await repository.suspendNextSweep()
        let keys = positionedKeys()
        let token = NSObject()
        let space = try XCTUnwrap(keys.first(where: { $0.id == "key-space" }))

        model.insertClipboardItem(item)
        try await waitUntil { await repository.sweepIsSuspended() }
        model.handle(
            touches: [touch(for: "key-space", token: token, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.handle(
            touches: [KeyboardTouch(
                id: ObjectIdentifier(token),
                phase: .moved,
                location: CGPoint(x: space.rect.midX + 25, y: space.rect.midY)
            )],
            positionedKeys: keys
        )
        await repository.resumeSweep()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(handler.text, "")
        XCTAssertNotEqual(handler.cursorOffset, 0)
    }

    func testClipboardTapCommitsOlderHeldLetterBeforePaste() async throws {
        let repository = ClipboardTestRepository()
        let (model, handler, domain) = makeModel(repository: repository)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        model.settings.acceptClipboardNotice()
        model.clipboard.activate(.hostApp)
        model.clipboard.saveProvidedText("paste")
        try await waitUntil { !model.clipboard.isBusy && model.clipboard.history.items.count == 1 }
        let item = try XCTUnwrap(model.clipboard.history.items.first)
        let keys = positionedKeys()
        let token = NSObject()

        model.handle(
            touches: [touch(for: "key-g", token: token, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.insertClipboardItem(item)
        try await waitUntil { !model.clipboard.isBusy && handler.text == "gpaste" }

        XCTAssertEqual(handler.text, "gpaste")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    func testClipboardTapStopsOlderHeldBackspaceBeforePaste() async throws {
        let repository = ClipboardTestRepository()
        let (model, handler, domain) = makeModel(repository: repository)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        model.settings.acceptClipboardNotice()
        model.clipboard.activate(.hostApp)
        model.clipboard.saveProvidedText("paste")
        try await waitUntil { !model.clipboard.isBusy && model.clipboard.history.items.count == 1 }
        let item = try XCTUnwrap(model.clipboard.history.items.first)
        let keys = positionedKeys()
        let token = NSObject()
        handler.text = "abc"

        model.handle(
            touches: [touch(for: "key-backspace", token: token, phase: .began, keys: keys)],
            positionedKeys: keys
        )
        model.insertClipboardItem(item)
        try await waitUntil { !model.clipboard.isBusy && handler.text == "abpaste" }
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(handler.text, "abpaste", "paste must stop the older delete repeater")
        XCTAssertTrue(model.pressedKeyIDs.isEmpty)
    }

    private func makeModel(
        repository: any ClipboardRepositoryProtocol = ClipboardRepository(fileURL: nil)
    ) -> (KeyboardViewModel, TouchTestHandler, String) {
        let domain = "KeyboardProjectTests.touch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain) ?? .standard
        let settings = KeyboardSettingsStore(localDefaults: defaults, sharedDefaults: nil)
        settings.refresh(canUseShared: false)
        settings.setHapticsEnabled(false)

        let model = KeyboardViewModel(
            settings: settings,
            repository: repository
        )
        let handler = TouchTestHandler()
        model.handler = handler
        return (model, handler, domain)
    }

    private func waitUntil(
        attempts: Int = 200,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition did not become true")
    }

    private func positionedKeys(shift: ShiftState = .off) -> [PositionedKey] {
        KeyboardMetrics.positionedKeys(
            rows: KeyboardLayout.rows(layer: .base, shift: shift, needsGlobe: false),
            in: size
        )
    }

    private func touch(
        for keyID: String,
        token: NSObject,
        phase: KeyboardTouch.Phase,
        keys: [PositionedKey]
    ) -> KeyboardTouch {
        guard let key = keys.first(where: { $0.id == keyID }) else {
            preconditionFailure("Missing test key \(keyID)")
        }
        return KeyboardTouch(
            id: ObjectIdentifier(token),
            phase: phase,
            location: CGPoint(x: key.rect.midX, y: key.rect.midY)
        )
    }
}

@MainActor
private final class TouchTestHandler: KeyboardActionHandler {
    var text = ""
    var cursorOffset = 0

    func insert(_ inserted: String) { text += inserted }
    func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }
    func adjustTextPosition(by offset: Int) { cursorOffset += offset }
    func configureNextKeyboardButton(_ button: UIButton) {}

    var hasFullAccess: Bool { false }
    var contextBeforeInput: String? { text }
    var autocapitalizationType: UITextAutocapitalizationType { .none }
    var returnKeyType: UIReturnKeyType { .default }
}
