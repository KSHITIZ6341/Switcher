import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AppWindowBlueButtonManager {
    var onBlueButtonPressed: ((RunningWindow) -> Void)?
    var onBlueButtonEdgeSelected: ((RunningWindow, SidebarEdge) -> Void)?

    private var enabledBundleIDs: Set<String> = []
    private var monitorTimer: Timer?
    private var monitorMode: MonitorMode = .idle
    private var currentPollInterval: TimeInterval?
    private var lastFramesByWindowID: [CGWindowID: CGRect] = [:]
    private var activeTrackingDeadline: Date?
    private var controlsByWindowID: [CGWindowID: BlueButtonWindowController] = [:]

    private let idlePollInterval: TimeInterval = 0.9
    private let activeHoldDuration: TimeInterval = 0.28
    private let movementThreshold: CGFloat = 1.0
    private let minimumWindowSize = CGSize(width: 220, height: 120)

    func start() {
        guard monitorTimer == nil else {
            return
        }
        guard !enabledBundleIDs.isEmpty else {
            return
        }

        configureMonitorTimer(for: .idle)
        refreshNow()
    }

    func stop() {
        invalidateMonitorTimer()
        monitorMode = .idle
        currentPollInterval = nil
        activeTrackingDeadline = nil
        lastFramesByWindowID.removeAll()
        removeAllButtons()
    }

    func setEnabledBundleIDs(_ bundleIDs: Set<String>) {
        enabledBundleIDs = bundleIDs

        guard !enabledBundleIDs.isEmpty else {
            invalidateMonitorTimer()
            monitorMode = .idle
            currentPollInterval = nil
            activeTrackingDeadline = nil
            lastFramesByWindowID.removeAll()
            removeAllButtons()
            return
        }

        if monitorTimer == nil {
            configureMonitorTimer(for: .idle)
        }

        refreshNow()
    }

    func refreshNow() {
        guard !enabledBundleIDs.isEmpty else {
            invalidateMonitorTimer()
            monitorMode = .idle
            currentPollInterval = nil
            activeTrackingDeadline = nil
            lastFramesByWindowID.removeAll()
            removeAllButtons()
            return
        }

        let now = Date()
        let snapshots = fetchEligibleWindows()
        let movementDetected = detectMovement(in: snapshots)
        let leftMouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        if movementDetected || leftMouseDown {
            activeTrackingDeadline = now.addingTimeInterval(activeHoldDuration)
        }

        let shouldRunActively = (activeTrackingDeadline?.timeIntervalSince(now) ?? 0) > 0
        configureMonitorTimer(for: shouldRunActively ? .active : .idle)

        let aliveWindowIDs = Set(snapshots.map(\.runningWindow.windowID))

        for snapshot in snapshots {
            let buttonFrame = blueButtonFrame(for: snapshot.frame)
            let controller = controlsByWindowID[snapshot.runningWindow.windowID] ?? {
                let newController = BlueButtonWindowController()
                controlsByWindowID[snapshot.runningWindow.windowID] = newController
                return newController
            }()

            controller.show(
                at: buttonFrame,
                onClick: { [weak self] in
                    self?.onBlueButtonPressed?(snapshot.runningWindow)
                },
                onChooseEdge: { [weak self] edge in
                    self?.onBlueButtonEdgeSelected?(snapshot.runningWindow, edge)
                }
            )
        }

        for windowID in controlsByWindowID.keys where !aliveWindowIDs.contains(windowID) {
            controlsByWindowID[windowID]?.hide()
            controlsByWindowID.removeValue(forKey: windowID)
        }

        lastFramesByWindowID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.runningWindow.windowID, $0.frame) })
    }

    private func fetchEligibleWindows() -> [WindowSnapshot] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var snapshots: [WindowSnapshot] = []

        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            guard let windowID = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier,
                  enabledBundleIDs.contains(bundleID),
                  bundleID != Bundle.main.bundleIdentifier else {
                continue
            }

            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.01 else {
                continue
            }

            guard let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let cgWindowBounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                continue
            }

            let appKitFrame = convertQuartzBoundsToAppKit(cgWindowBounds)
            guard appKitFrame.width >= minimumWindowSize.width,
                  appKitFrame.height >= minimumWindowSize.height else {
                continue
            }

            let appName = (entry[kCGWindowOwnerName as String] as? String) ?? app.localizedName ?? bundleID
            let title = (entry[kCGWindowName as String] as? String) ?? ""

            let runningWindow = RunningWindow(
                windowID: windowID,
                bundleId: bundleID,
                appName: appName,
                title: title,
                pid: pid
            )

            snapshots.append(WindowSnapshot(runningWindow: runningWindow, frame: appKitFrame))
        }

        return snapshots
    }

    private func convertQuartzBoundsToAppKit(_ quartzBounds: CGRect) -> CGRect {
        let virtualDesktop = NSScreen.screens.reduce(CGRect.null) { partial, screen in
            partial.union(screen.frame)
        }

        guard !virtualDesktop.isNull else {
            return quartzBounds
        }

        let convertedY = virtualDesktop.maxY - quartzBounds.origin.y - quartzBounds.height
        return CGRect(x: quartzBounds.origin.x, y: convertedY, width: quartzBounds.width, height: quartzBounds.height)
    }

    private func blueButtonFrame(for windowFrame: CGRect) -> CGRect {
        let size: CGFloat = 14
        let horizontalInset: CGFloat = 16
        let verticalInset: CGFloat = 14
        let centerX = windowFrame.maxX - horizontalInset
        let centerY = windowFrame.maxY - verticalInset

        return CGRect(
            x: (centerX - size / 2).rounded(.toNearestOrAwayFromZero),
            y: (centerY - size / 2).rounded(.toNearestOrAwayFromZero),
            width: size,
            height: size
        )
    }

    private func removeAllButtons() {
        for controller in controlsByWindowID.values {
            controller.hide()
        }
        controlsByWindowID.removeAll()
    }

    private func detectMovement(in snapshots: [WindowSnapshot]) -> Bool {
        guard !lastFramesByWindowID.isEmpty else {
            return false
        }

        for snapshot in snapshots {
            guard let previousFrame = lastFramesByWindowID[snapshot.runningWindow.windowID] else {
                continue
            }

            if frameDistance(previousFrame, snapshot.frame) > movementThreshold {
                return true
            }
        }

        return false
    }

    private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private func configureMonitorTimer(for mode: MonitorMode) {
        let interval = pollInterval(for: mode)
        let needsRestart = monitorTimer == nil
            || monitorMode != mode
            || abs((currentPollInterval ?? 0) - interval) > 0.0001

        guard needsRestart else {
            return
        }

        invalidateMonitorTimer()
        monitorMode = mode
        currentPollInterval = interval

        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }

        if let monitorTimer {
            monitorTimer.tolerance = mode == .active ? interval * 0.15 : interval * 0.4
            RunLoop.main.add(monitorTimer, forMode: .common)
        }
    }

    private func invalidateMonitorTimer() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func pollInterval(for mode: MonitorMode) -> TimeInterval {
        switch mode {
        case .idle:
            return idlePollInterval
        case .active:
            return activeFrameInterval()
        }
    }

    private func activeFrameInterval() -> TimeInterval {
        let maxFPS = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60
        let clampedFPS = max(30, min(120, maxFPS))
        return 1.0 / TimeInterval(clampedFPS)
    }
}

private struct WindowSnapshot {
    var runningWindow: RunningWindow
    var frame: CGRect
}

private enum MonitorMode {
    case idle
    case active
}

@MainActor
private final class BlueButtonWindowController {
    private var window: NSWindow?
    private var hostingView: BlueButtonHostingView?

    func show(at frame: CGRect, onClick: @escaping () -> Void, onChooseEdge: @escaping (SidebarEdge) -> Void) {
        let window = self.window ?? makeWindow()
        self.window = window

        if hostingView == nil {
            let host = BlueButtonHostingView(rootView: BlueWindowButtonView())
            host.toolTip = "Click to pin or unpin. Press and hold to choose left or right sidebar."
            hostingView = host
            window.contentView = host
        }

        hostingView?.onClick = onClick
        hostingView?.onEdgeSelected = onChooseEdge
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = BlueButtonWindow(
            contentRect: CGRect(x: 0, y: 0, width: 14, height: 14),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = false
        return window
    }
}

private final class BlueButtonWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BlueButtonHostingView: NSHostingView<BlueWindowButtonView> {
    var onClick: (() -> Void)?
    var onEdgeSelected: ((SidebarEdge) -> Void)?

    private var holdTimer: Timer?
    private var didTriggerLongPress = false
    private let holdDuration: TimeInterval = 0.4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        didTriggerLongPress = false
        scheduleHoldTimer()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !bounds.insetBy(dx: -8, dy: -8).contains(point) {
            cancelHoldTimer()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let triggeredLongPress = didTriggerLongPress
        cancelHoldTimer()

        if !triggeredLongPress {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showEdgeMenu()
    }

    override func rightMouseUp(with event: NSEvent) {}

    private func scheduleHoldTimer() {
        cancelHoldTimer()

        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showEdgeMenu()
            }
        }

        if let holdTimer {
            RunLoop.main.add(holdTimer, forMode: .common)
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func showEdgeMenu() {
        didTriggerLongPress = true
        cancelHoldTimer()

        let menu = NSMenu(title: "Choose Sidebar Side")

        let leftItem = NSMenuItem(title: "Place on Left", action: #selector(selectLeftEdge), keyEquivalent: "")
        leftItem.target = self
        menu.addItem(leftItem)

        let rightItem = NSMenuItem(title: "Place on Right", action: #selector(selectRightEdge), keyEquivalent: "")
        rightItem.target = self
        menu.addItem(rightItem)

        menu.popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.minY - 4), in: self)
    }

    @objc private func selectLeftEdge() {
        onEdgeSelected?(.left)
    }

    @objc private func selectRightEdge() {
        onEdgeSelected?(.right)
    }
}

private struct BlueWindowButtonView: View {

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.23, green: 0.58, blue: 1), Color(red: 0.11, green: 0.39, blue: 0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 0.8))
            .overlay(
                Image(systemName: "sidebar.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}
