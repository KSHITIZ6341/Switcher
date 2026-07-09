import AppKit
import CoreGraphics

enum AppVersion {
    static let current = "1.1.0"
}

enum SidebarEdge: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }
}

enum AppSelectionSource: String, Codable, CaseIterable {
    case installedApp
    case runningWindow
}

enum StopReason: String, Codable, Equatable {
    case manualWindowMoveOrResize
    case targetWindowClosed
    case userUnpinned
    case permissionRevoked

    var message: String {
        switch self {
        case .manualWindowMoveOrResize:
            return "Pinning stopped because the window was moved or resized manually."
        case .targetWindowClosed:
            return "Pinned window was closed."
        case .userUnpinned:
            return "Window unpinned."
        case .permissionRevoked:
            return "Accessibility permission was revoked."
        }
    }
}

struct PinnedAppConfig: Codable, Equatable {
    static let defaultWidth: CGFloat = 360
    static let minWidth: CGFloat = 260
    static let maxWidth: CGFloat = 640

    var bundleId: String
    var preferredEdge: SidebarEdge
    var preferredDisplayId: String
    var preferredWidth: CGFloat

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }
}

struct PinRequest: Equatable {
    var source: AppSelectionSource
    var bundleId: String
    var edge: SidebarEdge
    var displayId: String
    var windowID: CGWindowID?
    var width: CGFloat?
}

struct PinStatus: Equatable {
    var isPinned: Bool = false
    var reason: StopReason?
    var targetBundleId: String?
    var pinnedCount: Int = 0
}

struct PinnedSidebarItem: Identifiable, Equatable {
    var id: String
    var bundleId: String
    var windowID: CGWindowID?
    var source: AppSelectionSource
    var index: Int
}

enum PinnedMoveDirection {
    case up
    case down
}

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleId }
    var bundleId: String
    var name: String
    var url: URL
}

struct RunningWindow: Identifiable, Hashable {
    var windowID: CGWindowID
    var bundleId: String
    var appName: String
    var title: String
    var pid: pid_t

    var id: CGWindowID { windowID }

    var displayName: String {
        if title.isEmpty {
            return appName
        }
        return "\(appName) — \(title)"
    }
}

struct DisplayDescriptor: Identifiable, Hashable {
    var id: String
    var name: String
    var frame: CGRect
}

@MainActor
protocol PermissionManaging: AnyObject {
    func isAccessibilityGranted() -> Bool
    func requestAccessibilityPermission()
}

@MainActor
protocol PinManaging: AnyObject {
    func startPin(request: PinRequest) async throws
    func stopPin(reason: StopReason)
    func repin() async throws
}

enum PinError: LocalizedError {
    case permissionDenied
    case appNotFound(String)
    case windowNotFound(String)
    case windowNotResizable(String)
    case failedToLaunch(String)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission is required to pin app windows."
        case .appNotFound(let bundleId):
            return "Could not find app with bundle id \(bundleId)."
        case .windowNotFound(let bundleId):
            return "Could not find a controllable window for \(bundleId)."
        case .windowNotResizable(let bundleId):
            return "Selected app window cannot be resized or moved (\(bundleId))."
        case .failedToLaunch(let bundleId):
            return "Failed to launch app \(bundleId)."
        case .generic(let message):
            return message
        }
    }
}
