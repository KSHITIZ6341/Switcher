import AppKit
import Combine
import CoreGraphics

@MainActor
final class PinSessionManager: ObservableObject, PinManaging {
    @Published private(set) var pinStatus = PinStatus()
    @Published private(set) var statusMessage: String?
    @Published private(set) var isSidebarCollapsed = false
    @Published private(set) var autoHoverEnabled = false

    private let permissionManager: PermissionManaging
    private let windowController: WindowController
    private let displayManager: DisplayManager
    private let settingsStore: SettingsStore
    private let edgeToggleController = SidebarEdgeToggleWindowController()

    private var stateMachine = PinSessionStateMachine()
    private var monitorTimer: Timer?
    private var sidebarAnimationTimer: Timer?
    private var activeSession: SidebarSession?

    private(set) var lastRequest: PinRequest?
    private let manualBreakTolerance: CGFloat = 24
    private let enforceTolerance: CGFloat = 2
    private let sidebarWidthRatio: CGFloat = 0.25
    private let hiddenPeekWidth: CGFloat = 4
    private let edgeTriggerDistance: CGFloat = 8
    private let maxStackCount = 3

    private let hoverOpenDelay: TimeInterval = 0.15
    private let hoverCloseDelay: TimeInterval = 0.15
    private let dragCaptureDelay: TimeInterval = 0.5
    private let slideDuration: TimeInterval = 0.24

    private var edgeHoverStartedAt: Date?
    private var mouseAwayStartedAt: Date?
    private var dragCandidate: DragCaptureCandidate?
    private var isAutoPinInProgress = false
    private var isAnimatingSidebarTransition = false

    var currentSidebarEdge: SidebarEdge? {
        activeSession?.edge
    }

    init(
        permissionManager: PermissionManaging,
        windowController: WindowController,
        displayManager: DisplayManager,
        settingsStore: SettingsStore
    ) {
        self.permissionManager = permissionManager
        self.windowController = windowController
        self.displayManager = displayManager
        self.settingsStore = settingsStore
        startMonitorTimerIfNeeded()
    }

    func setAutoHoverEnabled(_ enabled: Bool) {
        autoHoverEnabled = enabled
        settingsStore.autoHoverEnabled = enabled

        if !enabled {
            edgeHoverStartedAt = nil
            mouseAwayStartedAt = nil
            dragCandidate = nil
            if isSidebarCollapsed {
                pullOut()
            }
        }

        if activeSession != nil {
            statusMessage = enabled
                ? "Automatic sidebar mode enabled."
                : "Automatic sidebar mode disabled."
        }
    }

    func startPin(request: PinRequest) async throws {
        guard permissionManager.isAccessibilityGranted() else {
            throw PinError.permissionDenied
        }

        let managedWindow = try await windowController.resolveWindow(bundleId: request.bundleId, preferredWindowID: request.windowID)

        guard let display = displayManager.display(withID: request.displayId) ?? displayManager.primaryDisplay() else {
            throw PinError.generic("No displays found.")
        }

        var normalizedRequest = request
        normalizedRequest.displayId = display.id
        normalizedRequest.width = nil

        var session = existingOrFreshSession(for: normalizedRequest, displayID: display.id)

        if let index = indexOfEntry(in: session, matching: normalizedRequest) {
            session.entries[index] = SidebarEntry(request: normalizedRequest, window: managedWindow)
        } else {
            guard session.entries.count < maxStackCount else {
                throw PinError.generic("Sidebar supports up to 3 apps on one side.")
            }
            session.entries.append(SidebarEntry(request: normalizedRequest, window: managedWindow))
        }

        try layout(session: &session, on: display, collapsed: isSidebarCollapsed, detectManualMove: false)
        activeSession = session
        lastRequest = normalizedRequest

        persistConfig(for: normalizedRequest.bundleId, edge: normalizedRequest.edge, displayID: display.id)
        windowController.bringToFront(managedWindow)

        stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
        pinStatus = stateMachine.status
        statusMessage = session.entries.count > 1
            ? "Pinned \(session.entries.count) apps on \(normalizedRequest.edge.title.lowercased()) edge."
            : nil

        updateEdgeToggle(for: session, display: display, collapsed: isSidebarCollapsed)
    }

    func stopPin(reason: StopReason) {
        sidebarAnimationTimer?.invalidate()
        sidebarAnimationTimer = nil
        isAnimatingSidebarTransition = false

        activeSession = nil
        isSidebarCollapsed = false
        edgeHoverStartedAt = nil
        mouseAwayStartedAt = nil
        dragCandidate = nil
        edgeToggleController.hide()

        stateMachine.didStop(reason: reason)
        pinStatus = stateMachine.status
    }

    func repin() async throws {
        if var session = activeSession,
           let display = displayManager.display(withID: session.displayID) ?? displayManager.primaryDisplay() {
            try layout(session: &session, on: display, collapsed: isSidebarCollapsed, detectManualMove: false)
            activeSession = session
            stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
            pinStatus = stateMachine.status
            updateEdgeToggle(for: session, display: display, collapsed: isSidebarCollapsed)
            return
        }

        guard let request = lastRequest else {
            throw PinError.generic("No previous pin request is available for repin.")
        }

        try await startPin(request: request)
    }

    func bringPinnedWindowForward() {
        guard let session = activeSession else {
            return
        }

        session.entries.forEach { entry in
            windowController.bringToFront(entry.window)
        }
    }

    func containsPinnedWindow(windowID: CGWindowID, bundleID: String) -> Bool {
        guard let session = activeSession else {
            return false
        }

        return session.entries.contains { entry in
            if let entryWindowID = entry.request.windowID {
                return entryWindowID == windowID
            }
            return entry.request.bundleId == bundleID
        }
    }

    func unpinWindow(windowID: CGWindowID, bundleID: String) {
        guard var session = activeSession else {
            return
        }

        let originalCount = session.entries.count

        session.entries.removeAll { entry in
            if let entryWindowID = entry.request.windowID {
                return entryWindowID == windowID
            }
            return entry.request.bundleId == bundleID
        }

        guard session.entries.count != originalCount else {
            return
        }

        if session.entries.isEmpty {
            stopPin(reason: .userUnpinned)
            return
        }

        activeSession = session
        relayoutActiveSession(detectManualMove: false)
        statusMessage = "Unpinned one app. \(session.entries.count) app(s) remain in sidebar."
    }

    func unpinMostRecent() {
        guard var session = activeSession else {
            return
        }

        guard !session.entries.isEmpty else {
            stopPin(reason: .userUnpinned)
            return
        }

        _ = session.entries.removeLast()

        if session.entries.isEmpty {
            stopPin(reason: .userUnpinned)
            return
        }

        activeSession = session
        relayoutActiveSession(detectManualMove: false)
        statusMessage = "Unpinned one app. \(session.entries.count) app(s) remain in sidebar."
    }

    func moveSidebar(to edge: SidebarEdge) throws {
        guard var session = activeSession else {
            throw PinError.generic("No pinned apps to move.")
        }

        guard session.edge != edge else {
            return
        }

        guard let display = displayManager.display(withID: session.displayID) ?? displayManager.primaryDisplay() else {
            throw PinError.generic("No displays found.")
        }

        session.edge = edge

        try layout(session: &session, on: display, collapsed: isSidebarCollapsed, detectManualMove: false)
        activeSession = session

        for entry in session.entries {
            persistConfig(for: entry.request.bundleId, edge: edge, displayID: session.displayID)
        }

        stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
        pinStatus = stateMachine.status
        statusMessage = "Sidebar moved to \(edge.title.lowercased()) edge."
        updateEdgeToggle(for: session, display: display, collapsed: isSidebarCollapsed)
    }

    func pushIn() {
        setCollapsed(true)
    }

    func pullOut() {
        setCollapsed(false)
    }

    func toggleSidebarVisibility() {
        setCollapsed(!isSidebarCollapsed)
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard let session = activeSession,
              let display = displayManager.display(withID: session.displayID) ?? displayManager.primaryDisplay() else {
            return
        }

        guard isSidebarCollapsed != collapsed else {
            return
        }

        let previousCollapsed = isSidebarCollapsed
        isSidebarCollapsed = collapsed
        edgeHoverStartedAt = nil
        mouseAwayStartedAt = nil

        animateSidebarTransition(
            session: session,
            display: display,
            fromCollapsed: previousCollapsed,
            toCollapsed: collapsed
        )
    }

    private func animateSidebarTransition(
        session: SidebarSession,
        display: DisplayDescriptor,
        fromCollapsed: Bool,
        toCollapsed: Bool
    ) {
        sidebarAnimationTimer?.invalidate()
        sidebarAnimationTimer = nil
        isAnimatingSidebarTransition = true

        let fromFallbackFrames = stackedFrames(
            count: session.entries.count,
            displayFrame: display.frame,
            edge: session.edge,
            collapsed: fromCollapsed
        )

        let toFrames = stackedFrames(
            count: session.entries.count,
            displayFrame: display.frame,
            edge: session.edge,
            collapsed: toCollapsed
        )

        let fromFrames: [CGRect] = session.entries.enumerated().map { index, entry in
            if let current = try? windowController.frame(of: entry.window) {
                return current
            }
            if index < fromFallbackFrames.count {
                return fromFallbackFrames[index]
            }
            return .zero
        }

        let fromRegion = regionFrame(for: display.frame, edge: session.edge, collapsed: fromCollapsed)
        let toRegion = regionFrame(for: display.frame, edge: session.edge, collapsed: toCollapsed)
        let start = Date()

        sidebarAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                guard let liveSession = self.activeSession else {
                    self.sidebarAnimationTimer?.invalidate()
                    self.sidebarAnimationTimer = nil
                    self.isAnimatingSidebarTransition = false
                    return
                }

                let elapsed = Date().timeIntervalSince(start)
                let progress = min(1, max(0, elapsed / self.slideDuration))
                let eased = 1 - pow(1 - progress, 3)

                for index in liveSession.entries.indices {
                    guard index < toFrames.count else {
                        continue
                    }

                    let from = index < fromFrames.count ? fromFrames[index] : toFrames[index]
                    let to = toFrames[index]
                    let interpolated = self.interpolateRect(from: from, to: to, progress: eased)
                    try? self.windowController.setFrame(interpolated, for: liveSession.entries[index].window)
                }

                let region = self.interpolateRect(from: fromRegion, to: toRegion, progress: eased)
                self.edgeToggleController.show(
                    sidebarRegion: region,
                    edge: liveSession.edge,
                    collapsed: toCollapsed,
                    autoModeEnabled: self.autoHoverEnabled,
                    onToggle: { [weak self] in
                        self?.toggleSidebarVisibility()
                    },
                    onToggleAutoMode: { [weak self] in
                        guard let self else { return }
                        self.setAutoHoverEnabled(!self.autoHoverEnabled)
                    }
                )

                if progress >= 1 {
                    self.sidebarAnimationTimer?.invalidate()
                    self.sidebarAnimationTimer = nil
                    self.isAnimatingSidebarTransition = false
                    self.relayoutActiveSession(detectManualMove: false)
                }
            }
        }

        if let sidebarAnimationTimer {
            RunLoop.main.add(sidebarAnimationTimer, forMode: .common)
        }
    }

    private func startMonitorTimerIfNeeded() {
        guard monitorTimer == nil else {
            return
        }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitorLoop()
            }
        }
    }

    private func monitorLoop() {
        if autoHoverEnabled {
            monitorDragCapture()
        } else {
            dragCandidate = nil
            edgeHoverStartedAt = nil
            mouseAwayStartedAt = nil
        }

        guard permissionManager.isAccessibilityGranted() else {
            if activeSession != nil {
                statusMessage = "Accessibility permission was revoked."
                stopPin(reason: .permissionRevoked)
            }
            return
        }

        guard activeSession != nil else {
            edgeToggleController.hide()
            return
        }

        guard !isAnimatingSidebarTransition else {
            return
        }

        relayoutActiveSession(detectManualMove: true)
    }

    private func relayoutActiveSession(detectManualMove: Bool) {
        guard var session = activeSession else {
            return
        }

        guard let display = displayManager.display(withID: session.displayID) ?? displayManager.primaryDisplay() else {
            return
        }

        if display.id != session.displayID {
            session.displayID = display.id
            statusMessage = "Original display is unavailable. Sidebar moved to primary display."
        }

        do {
            try layout(session: &session, on: display, collapsed: isSidebarCollapsed, detectManualMove: detectManualMove)
            activeSession = session

            stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
            pinStatus = stateMachine.status

            updateEdgeToggle(for: session, display: display, collapsed: isSidebarCollapsed)

            if autoHoverEnabled {
                handleAutoReveal(session: session, display: display)
            }
        } catch let error as PinError {
            switch error {
            case .generic(let message):
                if message == StopReason.manualWindowMoveOrResize.message {
                    statusMessage = StopReason.manualWindowMoveOrResize.message
                    stopPin(reason: .manualWindowMoveOrResize)
                } else if message == StopReason.targetWindowClosed.message {
                    statusMessage = StopReason.targetWindowClosed.message
                    stopPin(reason: .targetWindowClosed)
                } else {
                    statusMessage = message
                }
            default:
                statusMessage = error.localizedDescription
            }
        } catch {
            statusMessage = StopReason.targetWindowClosed.message
            stopPin(reason: .targetWindowClosed)
        }
    }

    private func layout(
        session: inout SidebarSession,
        on display: DisplayDescriptor,
        collapsed: Bool,
        detectManualMove: Bool
    ) throws {
        var closedIndices: [Int] = []
        let expectedFrames = stackedFrames(
            count: session.entries.count,
            displayFrame: display.frame,
            edge: session.edge,
            collapsed: collapsed
        )

        for (index, entry) in session.entries.enumerated() {
            guard index < expectedFrames.count else {
                continue
            }

            let expected = expectedFrames[index]

            guard let actual = try? windowController.frame(of: entry.window) else {
                closedIndices.append(index)
                continue
            }

            if detectManualMove {
                let positionDelta = abs(actual.origin.x - expected.origin.x) + abs(actual.origin.y - expected.origin.y)
                if positionDelta > manualBreakTolerance {
                    throw PinError.generic(StopReason.manualWindowMoveOrResize.message)
                }
            }

            if frameDistance(actual, expected) > enforceTolerance {
                try windowController.setFrame(expected, for: entry.window)
            }
        }

        if !closedIndices.isEmpty {
            for index in closedIndices.sorted(by: >) {
                session.entries.remove(at: index)
            }

            if session.entries.isEmpty {
                throw PinError.generic(StopReason.targetWindowClosed.message)
            }

            let correctedFrames = stackedFrames(
                count: session.entries.count,
                displayFrame: display.frame,
                edge: session.edge,
                collapsed: collapsed
            )

            for (index, entry) in session.entries.enumerated() where index < correctedFrames.count {
                try windowController.setFrame(correctedFrames[index], for: entry.window)
            }
        }
    }

    private func handleAutoReveal(session: SidebarSession, display: DisplayDescriptor) {
        let mousePoint = NSEvent.mouseLocation
        let sidebarRegion = regionFrame(for: display.frame, edge: session.edge, collapsed: isSidebarCollapsed)

        if isSidebarCollapsed {
            if isNearEdge(mousePoint, displayFrame: display.frame, edge: session.edge) {
                if edgeHoverStartedAt == nil {
                    edgeHoverStartedAt = Date()
                }

                if let edgeHoverStartedAt,
                   Date().timeIntervalSince(edgeHoverStartedAt) >= hoverOpenDelay {
                    pullOut()
                }
            } else {
                edgeHoverStartedAt = nil
            }
            return
        }

        if sidebarRegion.insetBy(dx: -18, dy: -8).contains(mousePoint) {
            mouseAwayStartedAt = nil
            return
        }

        if mouseAwayStartedAt == nil {
            mouseAwayStartedAt = Date()
        }

        if let mouseAwayStartedAt,
           Date().timeIntervalSince(mouseAwayStartedAt) >= hoverCloseDelay {
            pushIn()
        }
    }

    private func monitorDragCapture() {
        guard autoHoverEnabled else {
            return
        }

        guard !isAutoPinInProgress else {
            return
        }

        let leftMouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard leftMouseDown else {
            dragCandidate = nil
            return
        }

        let mousePoint = NSEvent.mouseLocation
        guard let display = displayManager.allDisplays().first(where: { $0.frame.contains(mousePoint) }) else {
            dragCandidate = nil
            return
        }

        let edge = edgeNear(point: mousePoint, displayFrame: display.frame)
        guard let edge else {
            dragCandidate = nil
            return
        }

        guard let window = topWindowCandidateUnderCursor() else {
            dragCandidate = nil
            return
        }

        if let session = activeSession,
           session.entries.contains(where: { $0.request.windowID == window.windowID }) {
            dragCandidate = nil
            return
        }

        let now = Date()

        if let current = dragCandidate,
           current.windowID == window.windowID,
           current.edge == edge,
           current.displayID == display.id {
            if now.timeIntervalSince(current.startedAt) >= dragCaptureDelay {
                dragCandidate = nil
                performAutoPin(from: window, edge: edge, displayID: display.id)
            }
            return
        }

        dragCandidate = DragCaptureCandidate(
            windowID: window.windowID,
            bundleID: window.bundleId,
            edge: edge,
            displayID: display.id,
            startedAt: now
        )
    }

    private func performAutoPin(from window: RunningWindow, edge: SidebarEdge, displayID: String) {
        isAutoPinInProgress = true

        let request = PinRequest(
            source: .runningWindow,
            bundleId: window.bundleId,
            edge: edge,
            displayId: displayID,
            windowID: window.windowID,
            width: nil
        )

        Task { @MainActor in
            defer { self.isAutoPinInProgress = false }

            do {
                try await self.startPin(request: request)
                self.statusMessage = "Auto-pinned \(window.appName)."
            } catch {
                self.statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func existingOrFreshSession(for request: PinRequest, displayID: String) -> SidebarSession {
        guard var session = activeSession else {
            return SidebarSession(entries: [], edge: request.edge, displayID: displayID)
        }

        if session.edge != request.edge || session.displayID != displayID {
            session = SidebarSession(entries: [], edge: request.edge, displayID: displayID)
            isSidebarCollapsed = false
        }

        return session
    }

    private func indexOfEntry(in session: SidebarSession, matching request: PinRequest) -> Int? {
        session.entries.firstIndex { entry in
            if let requestWindowID = request.windowID,
               let entryWindowID = entry.request.windowID,
               requestWindowID == entryWindowID {
                return true
            }

            return entry.request.bundleId == request.bundleId
        }
    }

    private func stackedFrames(
        count: Int,
        displayFrame: CGRect,
        edge: SidebarEdge,
        collapsed: Bool
    ) -> [CGRect] {
        guard count > 0 else {
            return []
        }

        let width = targetSidebarWidth(for: displayFrame)
        let segmentHeight = displayFrame.height / CGFloat(count)
        let visibleX = edge == .left ? displayFrame.minX : displayFrame.maxX - width
        let collapsedX = edge == .left
            ? displayFrame.minX - width + hiddenPeekWidth
            : displayFrame.maxX - hiddenPeekWidth

        var frames: [CGRect] = []
        frames.reserveCapacity(count)

        for index in 0..<count {
            let top = displayFrame.maxY - (CGFloat(index) * segmentHeight)
            let bottom: CGFloat
            if index == count - 1 {
                bottom = displayFrame.minY
            } else {
                bottom = displayFrame.maxY - (CGFloat(index + 1) * segmentHeight)
            }

            frames.append(
                CGRect(
                    x: (collapsed ? collapsedX : visibleX).rounded(.toNearestOrAwayFromZero),
                    y: bottom.rounded(.toNearestOrAwayFromZero),
                    width: width.rounded(.toNearestOrAwayFromZero),
                    height: (top - bottom).rounded(.toNearestOrAwayFromZero)
                )
            )
        }

        return frames
    }

    private func regionFrame(for displayFrame: CGRect, edge: SidebarEdge, collapsed: Bool) -> CGRect {
        let width = targetSidebarWidth(for: displayFrame)
        let visibleX = edge == .left ? displayFrame.minX : displayFrame.maxX - width
        let collapsedX = edge == .left
            ? displayFrame.minX - width + hiddenPeekWidth
            : displayFrame.maxX - hiddenPeekWidth

        return CGRect(
            x: collapsed ? collapsedX : visibleX,
            y: displayFrame.minY,
            width: width,
            height: displayFrame.height
        )
    }

    private func edgeNear(point: CGPoint, displayFrame: CGRect) -> SidebarEdge? {
        if abs(point.x - displayFrame.minX) <= edgeTriggerDistance {
            return .left
        }

        if abs(point.x - displayFrame.maxX) <= edgeTriggerDistance {
            return .right
        }

        return nil
    }

    private func isNearEdge(_ point: CGPoint, displayFrame: CGRect, edge: SidebarEdge) -> Bool {
        guard point.y >= displayFrame.minY, point.y <= displayFrame.maxY else {
            return false
        }

        switch edge {
        case .left:
            return abs(point.x - displayFrame.minX) <= edgeTriggerDistance
        case .right:
            return abs(point.x - displayFrame.maxX) <= edgeTriggerDistance
        }
    }

    private func targetSidebarWidth(for displayFrame: CGRect) -> CGFloat {
        let ratioWidth = displayFrame.width * sidebarWidthRatio
        let maxAllowed = max(220, displayFrame.width * 0.95)
        return min(max(ratioWidth, PinnedAppConfig.minWidth), maxAllowed)
    }

    private func topWindowCandidateUnderCursor() -> RunningWindow? {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            guard let windowID = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else {
                continue
            }

            if bundleID == Bundle.main.bundleIdentifier {
                continue
            }

            let appName = (entry[kCGWindowOwnerName as String] as? String) ?? app.localizedName ?? bundleID
            let title = (entry[kCGWindowName as String] as? String) ?? ""

            return RunningWindow(
                windowID: windowID,
                bundleId: bundleID,
                appName: appName,
                title: title,
                pid: pid
            )
        }

        return nil
    }

    private func updateEdgeToggle(for session: SidebarSession, display: DisplayDescriptor, collapsed: Bool) {
        let region = regionFrame(for: display.frame, edge: session.edge, collapsed: collapsed)
        edgeToggleController.show(
            sidebarRegion: region,
            edge: session.edge,
            collapsed: collapsed,
            autoModeEnabled: autoHoverEnabled,
            onToggle: { [weak self] in
                self?.toggleSidebarVisibility()
            },
            onToggleAutoMode: { [weak self] in
                guard let self else { return }
                self.setAutoHoverEnabled(!self.autoHoverEnabled)
            }
        )
    }

    private func interpolateRect(from: CGRect, to: CGRect, progress: Double) -> CGRect {
        let t = CGFloat(progress)
        return CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * t,
            y: from.origin.y + (to.origin.y - from.origin.y) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        )
    }

    private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private func persistConfig(for bundleID: String, edge: SidebarEdge, displayID: String) {
        settingsStore.save(
            config: PinnedAppConfig(
                bundleId: bundleID,
                preferredEdge: edge,
                preferredDisplayId: displayID,
                preferredWidth: PinnedAppConfig.defaultWidth
            )
        )
    }
}

private struct SidebarSession {
    var entries: [SidebarEntry]
    var edge: SidebarEdge
    var displayID: String
}

private struct SidebarEntry {
    var request: PinRequest
    var window: ManagedWindow
}

private struct DragCaptureCandidate {
    var windowID: CGWindowID
    var bundleID: String
    var edge: SidebarEdge
    var displayID: String
    var startedAt: Date
}
