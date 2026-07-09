import AppKit
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var permissionGranted = false
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var runningWindows: [RunningWindow] = []
    @Published private(set) var displays: [DisplayDescriptor] = []
    @Published private(set) var pinStatus = PinStatus()
    @Published private(set) var pinnedItems: [PinnedSidebarItem] = []
    @Published private(set) var activeSidebarWidth = PinnedAppConfig.defaultWidth

    @Published var statusMessage: String?
    @Published var errorMessage: String?

    @Published var launchAtLoginEnabled = false
    @Published var autoHoverEnabled = false
    @Published var blueButtonEnabledBundleIDs: Set<String> = []
    @Published private(set) var isSidebarCollapsed = false

    @Published var isComposerPresented = false
    @Published var composerSource: AppSelectionSource = .installedApp
    @Published var composerSelectedBundleID = ""
    @Published var composerSelectedAppName = ""
    @Published var composerSelectedWindowID = ""
    @Published var composerSelectedDisplayID = ""
    @Published var composerSelectedEdge: SidebarEdge = .right
    @Published var composerWidth = Double(PinnedAppConfig.defaultWidth)

    private let permissionManager: PermissionManager
    private let settingsStore: SettingsStore
    private let displayManager: DisplayManager
    private let appCatalog: AppCatalog
    private let windowController: WindowController
    private let pinManager: PinSessionManager
    private let launchAtLoginManager: LaunchAtLoginManager
    private let blueButtonManager = AppWindowBlueButtonManager()
    private var iconCache: [String: NSImage] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var didStart = false

    init(
        permissionManager: PermissionManager = PermissionManager(),
        settingsStore: SettingsStore = SettingsStore(),
        displayManager: DisplayManager = DisplayManager(),
        appCatalog: AppCatalog = AppCatalog(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        self.displayManager = displayManager
        self.appCatalog = appCatalog
        self.windowController = WindowController(permissionManager: permissionManager)
        self.pinManager = PinSessionManager(
            permissionManager: permissionManager,
            windowController: windowController,
            displayManager: displayManager,
            settingsStore: settingsStore
        )
        self.launchAtLoginManager = launchAtLoginManager

        blueButtonManager.onBlueButtonPressed = { [weak self] runningWindow in
            Task { @MainActor in
                await self?.handleBlueButtonTap(runningWindow)
            }
        }

        blueButtonManager.onBlueButtonEdgeSelected = { [weak self] runningWindow, edge in
            Task { @MainActor in
                await self?.handleBlueButtonEdgeSelection(runningWindow, edge: edge)
            }
        }

        bindManagers()
    }

    var canRepin: Bool {
        pinManager.lastRequest != nil
    }

    var canToggleSidebarVisibility: Bool {
        pinStatus.isPinned
    }

    var pinnedTargetDisplayName: String {
        guard let bundleID = pinStatus.targetBundleId else {
            return "No app pinned"
        }
        return displayName(for: bundleID)
    }

    var selectedComposerAppDisplayName: String {
        if !composerSelectedAppName.isEmpty {
            return composerSelectedAppName
        }
        guard !composerSelectedBundleID.isEmpty else {
            return "No app selected"
        }
        return displayName(for: composerSelectedBundleID)
    }

    var sidebarWidthDisplayText: String {
        "\(Int(activeSidebarWidth.rounded())) px"
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        refreshCatalogAndDisplays()
        refreshPermissionState()

        launchAtLoginEnabled = settingsStore.launchAtLoginEnabled || launchAtLoginManager.isEnabled()
        autoHoverEnabled = settingsStore.autoHoverEnabled
        pinManager.setAutoHoverEnabled(autoHoverEnabled)
        isSidebarCollapsed = pinManager.isSidebarCollapsed
        blueButtonEnabledBundleIDs = settingsStore.blueButtonBundleIDs
        blueButtonManager.setEnabledBundleIDs(blueButtonEnabledBundleIDs)
        blueButtonManager.start()

        HotkeyManager.shared.onHotKeyPressed = { [weak self] in
            Task { @MainActor in
                self?.handleHotkey()
            }
        }
        HotkeyManager.shared.registerDefaultHotKey()
    }

    func refreshCatalogAndDisplays() {
        appCatalog.refresh()
        installedApps = appCatalog.installedApps
        runningWindows = appCatalog.runningWindows
        displays = displayManager.allDisplays()

        if composerSelectedDisplayID.isEmpty {
            composerSelectedDisplayID = displays.first?.id ?? ""
        }

        blueButtonManager.refreshNow()
    }

    func refreshPermissionState() {
        permissionGranted = permissionManager.isAccessibilityGranted()
    }

    func requestAccessibilityPermission() {
        permissionManager.requestAccessibilityPermission()
        refreshPermissionState()
    }

    func openComposer(for source: AppSelectionSource) {
        refreshCatalogAndDisplays()

        composerSource = source
        errorMessage = nil

        switch source {
        case .installedApp:
            guard let firstApp = installedApps.first else {
                errorMessage = "No installed apps were found in /Applications or ~/Applications."
                return
            }
            composerSelectedBundleID = firstApp.bundleId
            composerSelectedAppName = firstApp.name
            composerSelectedWindowID = ""
            applyDefaults(for: firstApp.bundleId)
        case .runningWindow:
            guard let firstWindow = runningWindows.first else {
                errorMessage = "No running windows were detected. Open an app window and try again."
                return
            }
            composerSelectedWindowID = String(firstWindow.windowID)
            composerSelectedBundleID = firstWindow.bundleId
            composerSelectedAppName = firstWindow.appName
            applyDefaults(for: firstWindow.bundleId)
        }

        isComposerPresented = true
    }

    func updateRunningWindowSelection(windowIDString: String) {
        composerSelectedWindowID = windowIDString

        guard let windowID = UInt32(windowIDString),
              let selectedWindow = runningWindows.first(where: { $0.windowID == windowID }) else {
            return
        }

        composerSelectedBundleID = selectedWindow.bundleId
        composerSelectedAppName = selectedWindow.appName
        applyDefaults(for: selectedWindow.bundleId)
    }

    func updateBundleSelection(bundleID: String) {
        composerSelectedBundleID = bundleID
        composerSelectedAppName = installedApps.first(where: { $0.bundleId == bundleID })?.name ?? bundleID
        applyDefaults(for: bundleID)
    }

    func icon(for app: InstalledApp) -> NSImage {
        if let cached = iconCache[app.bundleId] {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: 64, height: 64)
        iconCache[app.bundleId] = image
        return image
    }

    func icon(forBundleID bundleID: String) -> NSImage? {
        if let installed = installedApps.first(where: { $0.bundleId == bundleID }) {
            return icon(for: installed)
        }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let appURL = running.bundleURL {
            let image = NSWorkspace.shared.icon(forFile: appURL.path)
            image.size = NSSize(width: 64, height: 64)
            iconCache[bundleID] = image
            return image
        }

        return nil
    }

    func confirmPin() async {
        refreshPermissionState()

        guard permissionGranted else {
            errorMessage = PinError.permissionDenied.errorDescription
            return
        }

        guard !composerSelectedBundleID.isEmpty else {
            errorMessage = "Select an app before pinning."
            return
        }

        let displayID = composerSelectedDisplayID.isEmpty ? (displays.first?.id ?? "") : composerSelectedDisplayID
        guard !displayID.isEmpty else {
            errorMessage = "No display is available."
            return
        }

        let selectedWindowID: CGWindowID?
        if composerSource == .runningWindow {
            selectedWindowID = UInt32(composerSelectedWindowID)
        } else {
            selectedWindowID = nil
        }

        let request = PinRequest(
            source: composerSource,
            bundleId: composerSelectedBundleID,
            edge: composerSelectedEdge,
            displayId: displayID,
            windowID: selectedWindowID,
            width: CGFloat(composerWidth)
        )

        do {
            try await pinManager.startPin(request: request)
            statusMessage = "Pinned \(selectedComposerAppDisplayName)."
            isComposerPresented = false
            refreshCatalogAndDisplays()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func repin() async {
        do {
            try await pinManager.repin()
            statusMessage = "Repin applied."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func unpin() {
        pinManager.unpinMostRecent()
    }

    func bringPinnedWindowForward() {
        pinManager.bringPinnedWindowForward()
    }

    func toggleSidebarVisibility() {
        pinManager.toggleSidebarVisibility()
    }

    func focusPinnedItem(_ item: PinnedSidebarItem) {
        pinManager.focusPinnedItem(id: item.id)
    }

    func unpinPinnedItem(_ item: PinnedSidebarItem) {
        pinManager.unpinPinnedItem(id: item.id)
    }

    func movePinnedItem(_ item: PinnedSidebarItem, direction: PinnedMoveDirection) {
        pinManager.movePinnedItem(id: item.id, direction: direction)
    }

    func moveSidebar(to edge: SidebarEdge) {
        do {
            try pinManager.moveSidebar(to: edge)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func displayName(for pinnedItem: PinnedSidebarItem) -> String {
        if let windowID = pinnedItem.windowID,
           let window = runningWindows.first(where: { $0.windowID == windowID }) {
            return window.displayName
        }

        return displayName(for: pinnedItem.bundleId)
    }

    func subtitle(for pinnedItem: PinnedSidebarItem) -> String {
        if pinnedItem.source == .runningWindow {
            return "Running window"
        }

        return pinnedItem.bundleId
    }

    func setAutoHoverEnabled(_ enabled: Bool) {
        autoHoverEnabled = enabled
        pinManager.setAutoHoverEnabled(enabled)
        statusMessage = enabled
            ? "Automatic sidebar mode enabled."
            : "Automatic sidebar mode disabled."
    }

    func isBlueButtonEnabled(for bundleID: String) -> Bool {
        blueButtonEnabledBundleIDs.contains(bundleID)
    }

    func setBlueButtonEnabled(_ enabled: Bool, for bundleID: String) {
        if enabled {
            blueButtonEnabledBundleIDs.insert(bundleID)
        } else {
            blueButtonEnabledBundleIDs.remove(bundleID)
        }

        settingsStore.blueButtonBundleIDs = blueButtonEnabledBundleIDs
        blueButtonManager.setEnabledBundleIDs(blueButtonEnabledBundleIDs)
    }

    func setLaunchAtLogin(enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            settingsStore.launchAtLoginEnabled = enabled
            launchAtLoginEnabled = enabled
            statusMessage = enabled ? "Launch at login enabled." : "Launch at login disabled."
        } catch {
            launchAtLoginEnabled = settingsStore.launchAtLoginEnabled
            errorMessage = "Failed to update launch-at-login: \(error.localizedDescription)"
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func bindManagers() {
        pinManager.$pinStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.pinStatus = status
                if let reason = status.reason {
                    self?.statusMessage = reason.message
                }
            }
            .store(in: &cancellables)

        pinManager.$statusMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let message else {
                    return
                }
                self?.statusMessage = message
            }
            .store(in: &cancellables)

        pinManager.$isSidebarCollapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] collapsed in
                self?.isSidebarCollapsed = collapsed
            }
            .store(in: &cancellables)

        pinManager.$autoHoverEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.autoHoverEnabled = enabled
            }
            .store(in: &cancellables)

        pinManager.$pinnedItems
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.pinnedItems = items
            }
            .store(in: &cancellables)

        pinManager.$sidebarWidth
            .receive(on: RunLoop.main)
            .sink { [weak self] width in
                self?.activeSidebarWidth = width
            }
            .store(in: &cancellables)

    }

    private func displayName(for bundleID: String) -> String {
        if let app = installedApps.first(where: { $0.bundleId == bundleID }) {
            return app.name
        }

        if let window = runningWindows.first(where: { $0.bundleId == bundleID }) {
            return window.appName
        }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let localizedName = running.localizedName,
           !localizedName.isEmpty {
            return localizedName
        }

        return bundleID
    }

    private func applyDefaults(for bundleID: String) {
        let fallbackDisplayID = displays.first?.id ?? ""
        let config = settingsStore.resolvedConfig(for: bundleID, fallbackDisplayId: fallbackDisplayID)

        composerSelectedEdge = config.preferredEdge
        composerWidth = Double(PinnedAppConfig.clampedWidth(config.preferredWidth))

        let resolvedDisplayID: String
        if displays.contains(where: { $0.id == config.preferredDisplayId }) {
            resolvedDisplayID = config.preferredDisplayId
        } else {
            resolvedDisplayID = fallbackDisplayID
        }

        composerSelectedDisplayID = resolvedDisplayID
    }

    private func handleHotkey() {
        if pinStatus.isPinned {
            toggleSidebarVisibility()
            if isSidebarCollapsed {
                bringPinnedWindowForward()
            }
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        refreshCatalogAndDisplays()
        openComposer(for: runningWindows.isEmpty ? .installedApp : .runningWindow)
    }

    private func handleBlueButtonTap(_ window: RunningWindow) async {
        refreshCatalogAndDisplays()
        refreshPermissionState()

        guard permissionGranted else {
            errorMessage = PinError.permissionDenied.errorDescription
            return
        }

        if pinManager.containsPinnedWindow(windowID: window.windowID, bundleID: window.bundleId) {
            pinManager.unpinWindow(windowID: window.windowID, bundleID: window.bundleId)
            statusMessage = "Unpinned \(window.appName) from sidebar."
            return
        }

        await pinWindowFromBlueButton(window, forcedEdge: nil)
    }

    private func handleBlueButtonEdgeSelection(_ window: RunningWindow, edge: SidebarEdge) async {
        refreshCatalogAndDisplays()
        refreshPermissionState()

        guard permissionGranted else {
            errorMessage = PinError.permissionDenied.errorDescription
            return
        }

        if pinManager.containsPinnedWindow(windowID: window.windowID, bundleID: window.bundleId) {
            do {
                try pinManager.moveSidebar(to: edge)
                statusMessage = "Moved sidebar to \(edge.title.lowercased()) edge."
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            return
        }

        await pinWindowFromBlueButton(window, forcedEdge: edge)
    }

    private func pinWindowFromBlueButton(_ window: RunningWindow, forcedEdge: SidebarEdge?) async {
        let fallbackDisplayID = displays.first?.id ?? ""
        let config = settingsStore.resolvedConfig(for: window.bundleId, fallbackDisplayId: fallbackDisplayID)
        let displayID = displays.contains(where: { $0.id == config.preferredDisplayId }) ? config.preferredDisplayId : fallbackDisplayID
        let targetEdge = forcedEdge ?? pinManager.currentSidebarEdge ?? config.preferredEdge

        if let currentEdge = pinManager.currentSidebarEdge, currentEdge != targetEdge {
            do {
                try pinManager.moveSidebar(to: targetEdge)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        }

        guard !displayID.isEmpty else {
            errorMessage = "No display is available."
            return
        }

        let request = PinRequest(
            source: .runningWindow,
            bundleId: window.bundleId,
            edge: targetEdge,
            displayId: displayID,
            windowID: window.windowID,
            width: pinManager.currentSidebarWidth ?? config.preferredWidth
        )

        do {
            try await pinManager.startPin(request: request)
            statusMessage = "Pinned \(window.appName) from blue button."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
