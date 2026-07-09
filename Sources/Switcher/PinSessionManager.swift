import AppKit
import Combine
import CoreGraphics

@MainActor
final class PinSessionManager: ObservableObject, PinManaging {
    @Published private(set) var pinStatus = PinStatus()
    @Published private(set) var statusMessage: String?
    @Published private(set) var isSidebarCollapsed = false
    @Published private(set) var autoHoverEnabled = false
    @Published private(set) var pinnedItems: [PinnedSidebarItem] = []
    @Published private(set) var sidebarWidth = PinnedAppConfig.defaultWidth

    private let permissionManager: PermissionManaging
    private let windowController: WindowController
    private let displayManager: DisplayManager
    private let settingsStore: SettingsStore
    private let edgeToggleController = SidebarEdgeToggleWindowController()
    private let resizeHandleController = ResizeHandleWindowController()

    private var stateMachine = PinSessionStateMachine()
    private var monitorTimer: Timer?
    private var sidebarAnimationTimer: Timer?
    private var activeSession: SidebarSession?

    private(set) var lastRequest: PinRequest?
    private let manualBreakTolerance: CGFloat = 24
    private let enforceTolerance: CGFloat = 2
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

    var currentSidebarWidth: CGFloat? {
        activeSession?.width
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

        updateMonitorTimer()
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
        normalizedRequest.width = clampedSidebarWidth(
            request.width ?? settingsStore.resolvedConfig(
                for: request.bundleId,
                fallbackDisplayId: display.id
            ).preferredWidth,
            displayFrame: display.frame
        )

        var session = existingOrFreshSession(
            for: normalizedRequest,
            displayID: display.id,
            displayFrame: display.frame
        )
        normalizedRequest.width = session.width

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
        updateMonitorTimer()

        persistConfig(
            for: normalizedRequest.bundleId,
            edge: normalizedRequest.edge,
            displayID: display.id,
            width: session.width
        )
        windowController.bringToFront(managedWindow)

        stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
        pinStatus = stateMachine.status
        publishPinnedItems(from: session)
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
        resizeHandleController.hide()

        stateMachine.didStop(reason: reason)
        pinStatus = stateMachine.status
        pinnedItems = []
        sidebarWidth = PinnedAppConfig.defaultWidth
        updateMonitorTimer()
    }

    func repin() async throws {
        if var session = activeSession,
           let display = displayManager.display(withID: session.displayID) ?? displayManager.primaryDisplay() {
            try layout(session: &session, on: display, collapsed: isSidebarCollapsed, detectManualMove: false)
            activeSession = session
            stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
            pinStatus = stateMachine.status
            publishPinnedItems(from: session)
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

    func focusPinnedItem(id: String) {
        guard let entry = entry(for: id) else {
            return
        }

        windowController.bringToFront(entry.window)
    }

    func unpinPinnedItem(id: String) {
        removePinnedItem(where: { itemID(for: $0.request) == id })
    }

    func unpinWindow(windowID: CGWindowID, bundleID: String) {
        removePinnedItem { entry in
            if let entryWindowID = entry.request.windowID {
                return entryWindowID == windowID
            }
            return entry.request.bundleId == bundleID
        }
    }

    func movePinnedItem(id: String, direction: PinnedMoveDirection) {
        guard var session = activeSession else {
            return
        }

        guard let index = session.entries.firstIndex(where: { itemID(for: $0.request) == id }) else {
            return
        }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index - 1
        case .down:
            targetIndex = index + 1
        }

        guard session.entries.indices.contains(targetIndex) else {
            return
        }

        session.entries.swapAt(index, targetIndex)

        activeSession = session
        relayoutActiveSession(detectManualMove: false)
        statusMessage = "Updated pinned app order."
    }

    func resizeSidebar(deltaX: CGFloat) {
        guard var session = activeSession,
              let display = displayManager.display(withID: session.displayID) ?? displayManager.primaryDisplay() else {
            return
        }

        let signedDelta = session.edge == .left ? deltaX : -deltaX
        let newWidth = clampedSidebarWidth(session.width + signedDelta, displayFrame: display.frame)
        guard abs(newWidth - session.width) >= 1 else {
            return
        }

        session.width = newWidth
        syncEntryWidths(in: &session)

        do {
            try layout(session: &session, on: display, collapsed: isSidebarCollapsed, detectManualMove: false)
            activeSession = session
            publishPinnedItems(from: session)
            updateEdgeToggle(for: session, display: display, collapsed: isSidebarCollapsed)
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func finishSidebarResize() {
        guard let session = activeSession else {
            return
        }

        persistConfig(for: session)
        statusMessage = "Sidebar width set to \(Int(session.width.rounded())) px."
    }

    private func removePinnedItem(where shouldRemove: (SidebarEntry) -> Bool) {
        guard var session = activeSession else {
            return
        }

        let originalCount = session.entries.count
        session.entries.removeAll(where: shouldRemove)

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

        persistConfig(for: session)

        stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
        pinStatus = stateMachine.status
        publishPinnedItems(from: session)
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

        let fromFallbackFrames = SidebarGeometry.stackedFrames(
            count: session.entries.count,
            displayFrame: display.frame,
            edge: session.edge,
            collapsed: fromCollapsed,
            width: session.width
        )

        let toFrames = SidebarGeometry.stackedFrames(
            count: session.entries.count,
            displayFrame: display.frame,
            edge: session.edge,
            collapsed: toCollapsed,
            width: session.width
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

        let fromRegion = SidebarGeometry.regionFrame(for: display.frame, edge: session.edge, collapsed: fromCollapsed, width: session.width)
        let toRegion = SidebarGeometry.regionFrame(for: display.frame, edge: session.edge, collapsed: toCollapsed, width: session.width)
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
                self.resizeHandleController.hide()
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

    private func stopMonitorTimer() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func updateMonitorTimer() {
        if PinMonitorPolicy.shouldRun(hasActiveSession: activeSession != nil, autoHoverEnabled: autoHoverEnabled) {
            startMonitorTimerIfNeeded()
        } else {
            stopMonitorTimer()
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

        session.width = clampedSidebarWidth(session.width, displayFrame: display.frame)
        syncEntryWidths(in: &session)

        do {
            try layout(session: &session, on: display, collapsed: isSidebarCollapsed, detectManualMove: detectManualMove)
            activeSession = session

            stateMachine.didUpdate(bundleId: session.entries.last?.request.bundleId, pinnedCount: session.entries.count)
            pinStatus = stateMachine.status
            publishPinnedItems(from: session)

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
        let expectedFrames = SidebarGeometry.stackedFrames(
            count: session.entries.count,
            displayFrame: display.frame,
            edge: session.edge,
            collapsed: collapsed,
            width: session.width
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
                if SidebarGeometry.hasManualFrameBreak(actual: actual, expected: expected, tolerance: manualBreakTolerance) {
                    throw PinError.generic(StopReason.manualWindowMoveOrResize.message)
                }
            }

            if SidebarGeometry.frameDistance(actual, expected) > enforceTolerance {
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

            let correctedFrames = SidebarGeometry.stackedFrames(
                count: session.entries.count,
                displayFrame: display.frame,
                edge: session.edge,
                collapsed: collapsed,
                width: session.width
            )

            for (index, entry) in session.entries.enumerated() where index < correctedFrames.count {
                try windowController.setFrame(correctedFrames[index], for: entry.window)
            }
        }
    }

    private func handleAutoReveal(session: SidebarSession, display: DisplayDescriptor) {
        let mousePoint = NSEvent.mouseLocation
        let sidebarRegion = SidebarGeometry.regionFrame(
            for: display.frame,
            edge: session.edge,
            collapsed: isSidebarCollapsed,
            width: session.width
        )

        if isSidebarCollapsed {
            if SidebarGeometry.isNearEdge(mousePoint, displayFrame: display.frame, edge: session.edge) {
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

        let edge = SidebarGeometry.edgeNear(point: mousePoint, displayFrame: display.frame)
        guard let edge else {
            dragCandidate = nil
            return
        }

        guard let window = topWindowCandidateUnderCursor(at: mousePoint) else {
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
        let preferredWidth = settingsStore.resolvedConfig(for: window.bundleId, fallbackDisplayId: displayID).preferredWidth

        let request = PinRequest(
            source: .runningWindow,
            bundleId: window.bundleId,
            edge: edge,
            displayId: displayID,
            windowID: window.windowID,
            width: preferredWidth
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

    private func existingOrFreshSession(
        for request: PinRequest,
        displayID: String,
        displayFrame: CGRect
    ) -> SidebarSession {
        let requestedWidth = clampedSidebarWidth(
            request.width ?? PinnedAppConfig.defaultWidth,
            displayFrame: displayFrame
        )

        guard var session = activeSession else {
            return SidebarSession(entries: [], edge: request.edge, displayID: displayID, width: requestedWidth)
        }

        if session.edge != request.edge || session.displayID != displayID {
            session = SidebarSession(entries: [], edge: request.edge, displayID: displayID, width: requestedWidth)
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

    private func clampedSidebarWidth(_ width: CGFloat, displayFrame: CGRect) -> CGFloat {
        SidebarGeometry.clampedSidebarWidth(width, displayFrame: displayFrame)
    }

    private func topWindowCandidateUnderCursor(at mousePoint: CGPoint) -> RunningWindow? {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let screenFrames = NSScreen.screens.map(\.frame)

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

            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.01 else {
                continue
            }

            guard let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let quartzBounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  SidebarGeometry.appKitFrameContainsCursor(
                      quartzBounds: quartzBounds,
                      cursor: mousePoint,
                      screenFrames: screenFrames
                  ) else {
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
        let region = SidebarGeometry.regionFrame(
            for: display.frame,
            edge: session.edge,
            collapsed: collapsed,
            width: session.width
        )
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

        if collapsed {
            resizeHandleController.hide()
        } else {
            resizeHandleController.show(
                for: region,
                edge: session.edge,
                onDeltaX: { [weak self] deltaX in
                    self?.resizeSidebar(deltaX: deltaX)
                },
                onDragEnd: { [weak self] in
                    self?.finishSidebarResize()
                }
            )
        }
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

    private func publishPinnedItems(from session: SidebarSession) {
        pinnedItems = session.entries.enumerated().map { index, entry in
            PinnedSidebarItem(
                id: itemID(for: entry.request),
                bundleId: entry.request.bundleId,
                windowID: entry.request.windowID,
                source: entry.request.source,
                index: index
            )
        }
        sidebarWidth = session.width
    }

    private func entry(for id: String) -> SidebarEntry? {
        activeSession?.entries.first { itemID(for: $0.request) == id }
    }

    private func itemID(for request: PinRequest) -> String {
        if let windowID = request.windowID {
            return "window-\(windowID)"
        }
        return "bundle-\(request.bundleId)"
    }

    private func syncEntryWidths(in session: inout SidebarSession) {
        for index in session.entries.indices {
            session.entries[index].request.width = session.width
        }
    }

    private func persistConfig(for session: SidebarSession) {
        for entry in session.entries {
            persistConfig(
                for: entry.request.bundleId,
                edge: session.edge,
                displayID: session.displayID,
                width: session.width
            )
        }
    }

    private func persistConfig(for bundleID: String, edge: SidebarEdge, displayID: String, width: CGFloat) {
        settingsStore.save(
            config: PinnedAppConfig(
                bundleId: bundleID,
                preferredEdge: edge,
                preferredDisplayId: displayID,
                preferredWidth: PinnedAppConfig.clampedWidth(width)
            )
        )
    }
}

private struct SidebarSession {
    var entries: [SidebarEntry]
    var edge: SidebarEdge
    var displayID: String
    var width: CGFloat
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
