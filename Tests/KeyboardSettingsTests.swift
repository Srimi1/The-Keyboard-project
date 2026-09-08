import Foundation
import XCTest
@testable import KeyboardProject

@MainActor
final class KeyboardSettingsTests: XCTestCase {
    func testDefaultsAreManualButRequireNoticeAcceptance() {
        withStores { store, _, _ in
            XCTAssertTrue(store.values.hapticsEnabled)
            XCTAssertFalse(store.values.soundEnabled)
            XCTAssertEqual(store.values.appearance, .system)
            XCTAssertEqual(store.values.clipboardCaptureMode, .manual)
            XCTAssertEqual(store.values.effectiveClipboardCaptureMode, .off)
        }
    }

    func testAcceptedSettingsPersistLocally() {
        withStores { store, local, shared in
            store.refresh(canUseShared: false)
            store.acceptClipboardNotice(at: Date(timeIntervalSince1970: 1))
            store.setHapticsEnabled(false, at: Date(timeIntervalSince1970: 2))
            store.setSoundEnabled(true, at: Date(timeIntervalSince1970: 3))

            let reopened = KeyboardSettingsStore(localDefaults: local, sharedDefaults: shared)
            XCTAssertTrue(reopened.values.hasAcceptedClipboardNotice)
            XCTAssertFalse(reopened.values.hapticsEnabled)
            XCTAssertTrue(reopened.values.soundEnabled)
            XCTAssertEqual(reopened.values.effectiveClipboardCaptureMode, .manual)
        }
    }

    func testSharedNewerValueWinsWhenFullAccessIsAvailable() {
        withStores { localStore, local, shared in
            localStore.refresh(canUseShared: false)
            localStore.setSoundEnabled(false, at: Date(timeIntervalSince1970: 1))

            let host = KeyboardSettingsStore(localDefaults: shared, sharedDefaults: shared)
            host.refresh(canUseShared: true)
            host.setSoundEnabled(true, at: Date(timeIntervalSince1970: 2))

            let extensionStore = KeyboardSettingsStore(localDefaults: local, sharedDefaults: shared)
            extensionStore.refresh(canUseShared: true)
            XCTAssertTrue(extensionStore.values.soundEnabled)
        }
    }

    func testSharedWinnerIsMirroredLocallyBeforeFullAccessIsRevoked() {
        withStores { _, local, shared in
            let host = KeyboardSettingsStore(localDefaults: shared, sharedDefaults: shared)
            host.refresh(canUseShared: true)
            host.setAppearance(.dark, at: Date(timeIntervalSince1970: 10))

            let extensionStore = KeyboardSettingsStore(localDefaults: local, sharedDefaults: shared)
            extensionStore.refresh(canUseShared: true)
            XCTAssertEqual(extensionStore.values.appearance, .dark)

            let relaunchedWithoutAccess = KeyboardSettingsStore(
                localDefaults: local,
                sharedDefaults: shared
            )
            relaunchedWithoutAccess.refresh(canUseShared: false)
            XCTAssertEqual(relaunchedWithoutAccess.values.appearance, .dark)
        }
    }

    func testAutomaticModeCannotBeEnabledBeforeDeviceValidation() {
        withStores { store, _, _ in
            store.refresh(canUseShared: true)
            store.acceptClipboardNotice()
            store.setClipboardCaptureMode(.automatic)
            XCTAssertEqual(store.values.clipboardCaptureMode, .manual)
        }
    }

    func testStaleStoreEditMergesNewerChangeFromOtherProcess() {
        withStores { first, local, shared in
            let second = KeyboardSettingsStore(localDefaults: shared, sharedDefaults: shared)
            first.refresh(canUseShared: true)
            second.refresh(canUseShared: true)

            first.setHapticsEnabled(false, at: Date(timeIntervalSince1970: 10))
            second.setSoundEnabled(true, at: Date(timeIntervalSince1970: 20))

            let reopened = KeyboardSettingsStore(localDefaults: local, sharedDefaults: shared)
            reopened.refresh(canUseShared: true)
            XCTAssertFalse(reopened.values.hapticsEnabled)
            XCTAssertTrue(reopened.values.soundEnabled)
        }
    }

    private func withStores(
        _ operation: (KeyboardSettingsStore, UserDefaults, UserDefaults) -> Void
    ) {
        let localName = "KeyboardProjectTests.local.\(UUID().uuidString)"
        let sharedName = "KeyboardProjectTests.shared.\(UUID().uuidString)"
        let local = UserDefaults(suiteName: localName)!
        let shared = UserDefaults(suiteName: sharedName)!
        defer {
            UserDefaults.standard.removePersistentDomain(forName: localName)
            UserDefaults.standard.removePersistentDomain(forName: sharedName)
        }
        operation(KeyboardSettingsStore(localDefaults: local, sharedDefaults: shared), local, shared)
    }
}
