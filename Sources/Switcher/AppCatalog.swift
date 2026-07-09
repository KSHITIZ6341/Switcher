import AppKit
import CoreGraphics

@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var runningWindows: [RunningWindow] = []

    func refresh() {
        installedApps = fetchInstalledApps()
        runningWindows = fetchRunningWindows()
    }

    private func fetchInstalledApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

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
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            guard let windowNumber = entry[kCGWindowNumber as String] as? UInt32 else {
                continue
            }

            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let runningApp = NSRunningApplication(processIdentifier: pid),
                  let bundleID = runningApp.bundleIdentifier else {
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
