import XCTest
@testable import Switcher

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testWidthIsClampedToBounds() {
        XCTAssertEqual(PinnedAppConfig.clampedWidth(120), PinnedAppConfig.minWidth)
        XCTAssertEqual(PinnedAppConfig.clampedWidth(999), PinnedAppConfig.maxWidth)
        XCTAssertEqual(PinnedAppConfig.clampedWidth(360), 360)
    }

    @MainActor
    func testSavesAndLoadsPerAppConfig() {
        let suiteName = "SwitcherTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        let config = PinnedAppConfig(
            bundleId: "com.example.test",
            preferredEdge: .left,
            preferredDisplayId: "123",
            preferredWidth: 420
        )

        store.save(config: config)

        XCTAssertEqual(store.config(for: "com.example.test"), config)
    }

    @MainActor
    func testPersistsAutoHoverSetting() {
        let suiteName = "SwitcherTests-Auto-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        XCTAssertFalse(store.autoHoverEnabled)

        store.autoHoverEnabled = true
        XCTAssertTrue(store.autoHoverEnabled)
    }

    @MainActor
    func testPersistsBlueButtonAppSelection() {
        let suiteName = "SwitcherTests-BlueButtons-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(store.blueButtonBundleIDs, [])

        store.blueButtonBundleIDs = ["com.apple.Safari", "com.apple.TextEdit"]
        XCTAssertEqual(store.blueButtonBundleIDs, ["com.apple.Safari", "com.apple.TextEdit"])
    }
}
