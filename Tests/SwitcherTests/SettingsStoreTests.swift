import XCTest
@testable import Switcher

final class SettingsStoreTests: XCTestCase {
    private enum TestKeys {
        static let appConfigs = "switcher.app_configs"
        static let launchAtLogin = "switcher.launch_at_login"
        static let autoHover = "switcher.auto_hover"
        static let blueButtonBundleIDs = "switcher.blue_button_bundle_ids"

        static let legacyAppConfigs = "sidebar_pin.app_configs"
        static let legacyLaunchAtLogin = "sidebar_pin.launch_at_login"
        static let legacyAutoHover = "sidebar_pin.auto_hover"
        static let legacyBlueButtonBundleIDs = "sidebar_pin.blue_button_bundle_ids"
    }

    @MainActor
    func testWidthIsClampedToBounds() {
        XCTAssertEqual(PinnedAppConfig.clampedWidth(120), PinnedAppConfig.minWidth)
        XCTAssertEqual(PinnedAppConfig.clampedWidth(999), PinnedAppConfig.maxWidth)
        XCTAssertEqual(PinnedAppConfig.clampedWidth(360), 360)
    }

    @MainActor
    func testSavesAndLoadsPerAppConfig() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)

        let config = PinnedAppConfig(
            bundleId: "com.example.test",
            preferredEdge: .left,
            preferredDisplayId: "123",
            preferredWidth: 420
        )

        store.save(config: config)

        XCTAssertEqual(store.config(for: "com.example.test"), config)
        XCTAssertNotNil(defaults.data(forKey: TestKeys.appConfigs))
        XCTAssertNil(defaults.object(forKey: TestKeys.legacyAppConfigs))
    }

    @MainActor
    func testMigratesLegacyAppConfigsWhenNewValueIsMissing() throws {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)
        let config = PinnedAppConfig(
            bundleId: "com.example.legacy",
            preferredEdge: .right,
            preferredDisplayId: "display-legacy",
            preferredWidth: 390
        )
        let legacyConfigs = ["com.example.legacy": config]
        defaults.set(try JSONEncoder().encode(legacyConfigs), forKey: TestKeys.legacyAppConfigs)

        XCTAssertEqual(store.config(for: "com.example.legacy"), config)

        let migratedConfigs = try XCTUnwrap(decodedConfigs(from: defaults, key: TestKeys.appConfigs))
        XCTAssertEqual(migratedConfigs["com.example.legacy"], config)
    }

    @MainActor
    func testNewAppConfigsOverrideLegacyValues() throws {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)
        let legacyConfig = PinnedAppConfig(
            bundleId: "com.example.override",
            preferredEdge: .left,
            preferredDisplayId: "legacy-display",
            preferredWidth: 300
        )
        let newConfig = PinnedAppConfig(
            bundleId: "com.example.override",
            preferredEdge: .right,
            preferredDisplayId: "new-display",
            preferredWidth: 500
        )
        defaults.set(try JSONEncoder().encode(["com.example.override": legacyConfig]), forKey: TestKeys.legacyAppConfigs)
        defaults.set(try JSONEncoder().encode(["com.example.override": newConfig]), forKey: TestKeys.appConfigs)

        XCTAssertEqual(store.config(for: "com.example.override"), newConfig)
    }

    @MainActor
    func testPersistsAutoHoverSetting() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)
        XCTAssertFalse(store.autoHoverEnabled)

        store.autoHoverEnabled = true
        XCTAssertTrue(store.autoHoverEnabled)
        XCTAssertEqual(defaults.object(forKey: TestKeys.autoHover) as? Bool, true)
        XCTAssertNil(defaults.object(forKey: TestKeys.legacyAutoHover))
    }

    @MainActor
    func testMigratesLegacyAutoHoverSettingWhenNewValueIsMissing() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: TestKeys.legacyAutoHover)
        let store = SettingsStore(userDefaults: defaults)

        XCTAssertTrue(store.autoHoverEnabled)
        XCTAssertEqual(defaults.object(forKey: TestKeys.autoHover) as? Bool, true)
    }

    @MainActor
    func testPersistsLaunchAtLoginSetting() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)
        XCTAssertFalse(store.launchAtLoginEnabled)

        store.launchAtLoginEnabled = true

        XCTAssertTrue(store.launchAtLoginEnabled)
        XCTAssertEqual(defaults.object(forKey: TestKeys.launchAtLogin) as? Bool, true)
        XCTAssertNil(defaults.object(forKey: TestKeys.legacyLaunchAtLogin))
    }

    @MainActor
    func testMigratesLegacyLaunchAtLoginSettingWhenNewValueIsMissing() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: TestKeys.legacyLaunchAtLogin)
        let store = SettingsStore(userDefaults: defaults)

        XCTAssertTrue(store.launchAtLoginEnabled)
        XCTAssertEqual(defaults.object(forKey: TestKeys.launchAtLogin) as? Bool, true)
    }

    @MainActor
    func testNewLaunchAtLoginValueOverridesLegacySetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: TestKeys.legacyLaunchAtLogin)
        defaults.set(false, forKey: TestKeys.launchAtLogin)
        let store = SettingsStore(userDefaults: defaults)

        XCTAssertFalse(store.launchAtLoginEnabled)
    }

    @MainActor
    func testPersistsBlueButtonAppSelection() {
        let defaults = makeDefaults()
        let store = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(store.blueButtonBundleIDs, [])

        store.blueButtonBundleIDs = ["com.apple.Safari", "com.apple.TextEdit"]
        XCTAssertEqual(store.blueButtonBundleIDs, ["com.apple.Safari", "com.apple.TextEdit"])
        XCTAssertEqual(defaults.array(forKey: TestKeys.blueButtonBundleIDs) as? [String], ["com.apple.Safari", "com.apple.TextEdit"])
        XCTAssertNil(defaults.object(forKey: TestKeys.legacyBlueButtonBundleIDs))
    }

    @MainActor
    func testMigratesLegacyBlueButtonBundleIDsWhenNewValueIsMissing() {
        let defaults = makeDefaults()
        defaults.set(["com.apple.TextEdit", "com.apple.Safari"], forKey: TestKeys.legacyBlueButtonBundleIDs)
        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.blueButtonBundleIDs, ["com.apple.Safari", "com.apple.TextEdit"])
        XCTAssertEqual(defaults.array(forKey: TestKeys.blueButtonBundleIDs) as? [String], ["com.apple.TextEdit", "com.apple.Safari"])
    }

    private func makeDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
        let suiteName = "SwitcherTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults", file: file, line: line)
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func decodedConfigs(from defaults: UserDefaults, key: String) throws -> [String: PinnedAppConfig]? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode([String: PinnedAppConfig].self, from: data)
    }
}
