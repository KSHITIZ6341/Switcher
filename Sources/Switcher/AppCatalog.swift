import AppKit
import CoreGraphics

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var runningWindows: [RunningWindow] = []

    nonisolated static let minimumUsefulWindowSize = CGSize(width: 220, height: 120)
    nonisolated static let minimumUsefulWindowAlpha = 0.01

    func refresh() {
        installedApps = fetchInstalledApps()
        runningWindows = fetchRunningWindows()
    }

    nonisolated static func installedApplicationSearchRoots(fileManager: FileManager = .default) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    nonisolated static func isRunningWindowPickerCandidate(
        entry: [String: Any],
        bundleID: String,
        mainBundleID: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        guard bundleID != mainBundleID else {
            return false
        }

        guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
            return false
        }

        let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1
        guard alpha > minimumUsefulWindowAlpha else {
            return false
        }

        guard let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return false
        }

        return bounds.width >= minimumUsefulWindowSize.width
            && bounds.height >= minimumUsefulWindowSize.height
    }

    private func fetchInstalledApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = Self.installedApplicationSearchRoots(fileManager: fileManager)

        var appsByBundleID: [String: InstalledApp] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .nameKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else {
                    continue
                }

                enumerator.skipDescendants()

                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
                    continue
                }

                if appsByBundleID[bundleID] != nil {
                    continue
                }

                let displayName =
                    (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                appsByBundleID[bundleID] = InstalledApp(bundleId: bundleID, name: displayName, url: url)
            }
        }

        return appsByBundleID.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func fetchRunningWindows() -> [RunningWindow] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [RunningWindow] = []

        for entry in raw {
            guard let windowNumber = entry[kCGWindowNumber as String] as? UInt32 else {
                continue
            }

            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let runningApp = NSRunningApplication(processIdentifier: pid),
                  let bundleID = runningApp.bundleIdentifier else {
                continue
            }

            guard Self.isRunningWindowPickerCandidate(entry: entry, bundleID: bundleID) else {
                continue
            }

            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? runningApp.localizedName ?? bundleID
            let windowTitle = (entry[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            windows.append(
                RunningWindow(
                    windowID: windowNumber,
                    bundleId: bundleID,
                    appName: ownerName,
                    title: windowTitle,
                    pid: pid
                )
            )
        }

        return windows.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
