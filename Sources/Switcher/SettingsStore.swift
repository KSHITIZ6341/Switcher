import Foundation

@MainActor
final class SettingsStore {
    private enum Keys {
        struct KeyPair {
            let current: String
            let legacy: String
        }

        static let appConfigs = KeyPair(
            current: "switcher.app_configs",
            legacy: "sidebar_pin.app_configs"
        )
        static let launchAtLogin = KeyPair(
            current: "switcher.launch_at_login",
            legacy: "sidebar_pin.launch_at_login"
        )
        static let autoHover = KeyPair(
            current: "switcher.auto_hover",
            legacy: "sidebar_pin.auto_hover"
        )
        static let blueButtonBundleIDs = KeyPair(
            current: "switcher.blue_button_bundle_ids",
            legacy: "sidebar_pin.blue_button_bundle_ids"
        )
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func config(for bundleId: String) -> PinnedAppConfig? {
        allConfigs()[bundleId]
    }

    func save(config: PinnedAppConfig) {
        var current = allConfigs()
        current[config.bundleId] = config
        persist(configs: current)
    }

    func saveWidth(bundleId: String, width: CGFloat) {
        guard var existing = config(for: bundleId) else {
            return
        }
        existing.preferredWidth = PinnedAppConfig.clampedWidth(width)
        save(config: existing)
    }

    func resolvedConfig(for bundleId: String, fallbackDisplayId: String) -> PinnedAppConfig {
        if let existing = config(for: bundleId) {
            return existing
        }
        return PinnedAppConfig(
            bundleId: bundleId,
            preferredEdge: .right,
            preferredDisplayId: fallbackDisplayId,
            preferredWidth: PinnedAppConfig.defaultWidth
        )
    }

    var launchAtLoginEnabled: Bool {
        get {
            bool(for: Keys.launchAtLogin, defaultValue: false)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.launchAtLogin.current)
        }
    }

    var autoHoverEnabled: Bool {
        get {
            bool(for: Keys.autoHover, defaultValue: false)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.autoHover.current)
        }
    }

    var blueButtonBundleIDs: Set<String> {
        get {
            let values = stringArray(for: Keys.blueButtonBundleIDs)
            return Set(values)
        }
        set {
            userDefaults.set(Array(newValue).sorted(), forKey: Keys.blueButtonBundleIDs.current)
        }
    }

    private func allConfigs() -> [String: PinnedAppConfig] {
        if let data = userDefaults.data(forKey: Keys.appConfigs.current) {
            return decodedConfigs(from: data) ?? [:]
        }

        guard let legacyData = userDefaults.data(forKey: Keys.appConfigs.legacy) else {
            return [:]
        }

        guard let configs = decodedConfigs(from: legacyData) else {
            return [:]
        }

        persist(configs: configs)
        return configs
    }

    private func persist(configs: [String: PinnedAppConfig]) {
        do {
            let data = try JSONEncoder().encode(configs)
            userDefaults.set(data, forKey: Keys.appConfigs.current)
        } catch {
            // Ignore persistence failures and keep runtime behavior intact.
        }
    }

    private func decodedConfigs(from data: Data) -> [String: PinnedAppConfig]? {
        try? JSONDecoder().decode([String: PinnedAppConfig].self, from: data)
    }

    private func bool(for keys: Keys.KeyPair, defaultValue: Bool) -> Bool {
        if let value = userDefaults.object(forKey: keys.current) as? Bool {
            return value
        }

        guard let legacyValue = userDefaults.object(forKey: keys.legacy) as? Bool else {
            return defaultValue
        }

        userDefaults.set(legacyValue, forKey: keys.current)
        return legacyValue
    }

    private func stringArray(for keys: Keys.KeyPair) -> [String] {
        if let values = userDefaults.array(forKey: keys.current) as? [String] {
            return values
        }

        guard let legacyValues = userDefaults.array(forKey: keys.legacy) as? [String] else {
            return []
        }

        userDefaults.set(legacyValues, forKey: keys.current)
        return legacyValues
    }
}
