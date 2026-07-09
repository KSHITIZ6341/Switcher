import ApplicationServices
import AppKit
import CoreGraphics

struct ManagedWindow {
    var app: NSRunningApplication
    var appElement: AXUIElement
    var windowElement: AXUIElement
    var bundleId: String
    var windowID: CGWindowID?
}

@MainActor
final class WindowController {
    private let permissionManager: PermissionManaging

    init(permissionManager: PermissionManaging) {
        self.permissionManager = permissionManager
    }

    func ensureAppRunning(bundleId: String) async throws -> NSRunningApplication {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first(where: { !$0.isTerminated }) {
            return running
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw PinError.appNotFound(bundleId)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        do {
            return try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                    if let app {
                        continuation.resume(returning: app)
                        return
                    }
                    continuation.resume(throwing: error ?? PinError.failedToLaunch(bundleId))
                }
            }
        } catch {
            throw PinError.failedToLaunch(bundleId)
        }
    }

    func resolveWindow(bundleId: String, preferredWindowID: CGWindowID?) async throws -> ManagedWindow {
        guard permissionManager.isAccessibilityGranted() else {
            throw PinError.permissionDenied
        }

        let app = try await ensureAppRunning(bundleId: bundleId)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let targetSnapshot = preferredWindowID.flatMap { snapshotForWindow(windowID: $0, pid: app.processIdentifier) }

        let timeout = Date().addingTimeInterval(12)
        var nextWindowNudgeAt = Date.distantPast

        while Date() < timeout {
            if let window = findCandidateWindow(appElement: appElement, targetSnapshot: targetSnapshot) {
                if canControl(window: window) {
                    return ManagedWindow(app: app, appElement: appElement, windowElement: window, bundleId: bundleId, windowID: preferredWindowID)
                }
                throw PinError.windowNotResizable(bundleId)
            }

            let now = Date()
            if now >= nextWindowNudgeAt {
                await requestWindowPresentation(bundleId: bundleId, app: app)
                nextWindowNudgeAt = now.addingTimeInterval(0.9)
            }

            try? await Task.sleep(for: .milliseconds(220))
        }

        throw PinError.windowNotFound(bundleId)
    }

    func frame(of window: ManagedWindow) throws -> CGRect {
        try frame(of: window.windowElement)
    }

    func setFrame(_ frame: CGRect, for window: ManagedWindow) throws {
        _ = AXUIElementSetAttributeValue(window.windowElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)

        var size = CGSize(width: frame.width, height: frame.height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw PinError.generic("Could not create AX size value.")
        }

        let sizeError = AXUIElementSetAttributeValue(window.windowElement, kAXSizeAttribute as CFString, sizeValue)
        guard sizeError == .success else {
            throw PinError.windowNotResizable(window.bundleId)
        }

        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw PinError.generic("Could not create AX position value.")
        }

        let positionError = AXUIElementSetAttributeValue(window.windowElement, kAXPositionAttribute as CFString, positionValue)
        guard positionError == .success else {
            throw PinError.windowNotResizable(window.bundleId)
        }
    }

    func bringToFront(_ window: ManagedWindow) {
        window.app.activate(options: [.activateAllWindows])
        _ = AXUIElementSetAttributeValue(window.appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    func isWindowAlive(_ window: ManagedWindow) -> Bool {
        (try? frame(of: window)) != nil
    }

    private func findCandidateWindow(appElement: AXUIElement, targetSnapshot: WindowSnapshot?) -> AXUIElement? {
        let windows = copyWindows(from: appElement)
        guard !windows.isEmpty else {
            return nil
        }

        if let targetSnapshot {
            if let matchedByTitle = windows.first(where: { title(of: $0).localizedCaseInsensitiveCompare(targetSnapshot.title) == .orderedSame }) {
                return matchedByTitle
            }

            if let matchedByFrame = windows.first(where: { window in
                guard let candidateFrame = try? frame(of: window) else {
                    return false
                }
                return frameDistance(candidateFrame, targetSnapshot.frame) <= 24
            }) {
                return matchedByFrame
            }
        }

        if let focusedRef = copyAttribute(of: appElement, attribute: kAXFocusedWindowAttribute as CFString),
           CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            return unsafeDowncast(focusedRef, to: AXUIElement.self)
        }

        return windows.first
    }

    private func copyWindows(from appElement: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(of: appElement, attribute: kAXWindowsAttribute as CFString),
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }

        let windows = unsafeDowncast(value, to: NSArray.self) as [AnyObject]
        return windows.compactMap { object in
            guard CFGetTypeID(object) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(object, to: AXUIElement.self)
        }
    }

    private func canControl(window: AXUIElement) -> Bool {
        var canSetPosition = DarwinBoolean(false)
        var canSetSize = DarwinBoolean(false)

        let positionResult = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canSetPosition)
        let sizeResult = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canSetSize)

        return positionResult == .success && sizeResult == .success && canSetPosition.boolValue && canSetSize.boolValue
    }

    private func title(of window: AXUIElement) -> String {
        if let value = copyAttribute(of: window, attribute: kAXTitleAttribute as CFString) as? String {
            return value
        }
        return ""
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        guard let positionValue = copyAXValue(of: window, attribute: kAXPositionAttribute as CFString) else {
            throw PinError.generic("Could not read window position.")
        }

        guard let sizeValue = copyAXValue(of: window, attribute: kAXSizeAttribute as CFString) else {
            throw PinError.generic("Could not read window size.")
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            throw PinError.generic("Could not decode window frame.")
        }

        return CGRect(origin: position, size: size)
    }

    private func copyAttribute(of element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func copyAXValue(of element: AXUIElement, attribute: CFString) -> AXValue? {
        guard let rawValue = copyAttribute(of: element, attribute: attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(rawValue, to: AXValue.self)
    }

    private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private func snapshotForWindow(windowID: CGWindowID, pid: pid_t) -> WindowSnapshot? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] else {
            return nil
        }

        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                continue
            }

            let title = (info[kCGWindowName as String] as? String) ?? ""
            guard let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                continue
            }

            return WindowSnapshot(title: title, frame: bounds)
        }

        return nil
    }

    private func requestWindowPresentation(bundleId: String, app: NSRunningApplication) async {
        app.unhide()
        app.activate(options: [.activateAllWindows])

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        _ = try? await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                continuation.resume(returning: ())
            }
        }
    }
}

private struct WindowSnapshot {
    var title: String
    var frame: CGRect
}
