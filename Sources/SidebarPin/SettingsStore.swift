import Foundation

@MainActor
final class SettingsStore {
    private enum Keys {
        static let appConfigs = "sidebar_pin.app_configs"
        static let launchAtLogin = "sidebar_pin.launch_at_login"
        static let autoHover = "sidebar_pin.auto_hover"
        static let blueButtonBundleIDs = "sidebar_pin.blue_button_bundle_ids"
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
            userDefaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    var autoHoverEnabled: Bool {
        get {
            userDefaults.object(forKey: Keys.autoHover) as? Bool ?? false
        }
        set {
            userDefaults.set(newValue, forKey: Keys.autoHover)
        }
    }

    var blueButtonBundleIDs: Set<String> {
        get {
            let values = userDefaults.array(forKey: Keys.blueButtonBundleIDs) as? [String] ?? []
            return Set(values)
        }
        set {
            userDefaults.set(Array(newValue).sorted(), forKey: Keys.blueButtonBundleIDs)
        }
    }

    private func allConfigs() -> [String: PinnedAppConfig] {
        guard let data = userDefaults.data(forKey: Keys.appConfigs) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: PinnedAppConfig].self, from: data)
        } catch {
            return [:]
        }
    }

    private func persist(configs: [String: PinnedAppConfig]) {
        do {
            let data = try JSONEncoder().encode(configs)
            userDefaults.set(data, forKey: Keys.appConfigs)
        } catch {
            // Ignore persistence failures and keep runtime behavior intact.
        }
    }
}
