import ApplicationServices
import AppKit
import XCTest
@testable import Switcher

@MainActor
final class PinSessionManagerTests: XCTestCase {
    func testPinsThreeAppsAndRejectsFourthWithoutChangingSession() async throws {
        let fixture = Fixture()
        defer { fixture.stop() }
        for id in 1...3 {
            try await fixture.pin(CGWindowID(id))
        }

        do {
            try await fixture.pin(4)
            XCTFail("A fourth pinned app should be rejected")
        } catch {}

        XCTAssertEqual(fixture.manager.pinnedItems.map(\.windowID), [1, 2, 3])
        XCTAssertEqual(fixture.manager.pinStatus.pinnedCount, 3)
        XCTAssertEqual(fixture.windows.frames[1], CGRect(x: 640, y: 600, width: 360, height: 300))
        XCTAssertEqual(fixture.windows.frames[2], CGRect(x: 640, y: 300, width: 360, height: 300))
        XCTAssertEqual(fixture.windows.frames[3], CGRect(x: 640, y: 0, width: 360, height: 300))
    }

    func testReorderingUpdatesPublishedItemsAndWindowFrames() async throws {
        let fixture = Fixture()
        defer { fixture.stop() }
        try await fixture.pin(1)
        try await fixture.pin(2)
        try await fixture.pin(3)

        fixture.manager.movePinnedItem(id: "window-3", direction: .up)

        XCTAssertEqual(fixture.manager.pinnedItems.map(\.windowID), [1, 3, 2])
        XCTAssertEqual(fixture.manager.pinnedItems.map(\.index), [0, 1, 2])
        XCTAssertEqual(fixture.windows.frames[3]?.minY, 300)
        XCTAssertEqual(fixture.windows.frames[2]?.minY, 0)

        fixture.manager.movePinnedItem(id: "window-1", direction: .up)
        fixture.manager.movePinnedItem(id: "missing", direction: .down)
        XCTAssertEqual(fixture.manager.pinnedItems.map(\.windowID), [1, 3, 2])
    }

    func testUnpinningRelayoutsRemainingWindowsAndStopsAfterLast() async throws {
        let fixture = Fixture()
        defer { fixture.stop() }
        try await fixture.pin(1)
        try await fixture.pin(2)
        try await fixture.pin(3)

        fixture.manager.unpinPinnedItem(id: "window-2")

        XCTAssertEqual(fixture.manager.pinnedItems.map(\.windowID), [1, 3])
        XCTAssertEqual(fixture.windows.frames[1]?.height, 450)
        XCTAssertEqual(fixture.windows.frames[3]?.height, 450)
        XCTAssertEqual(fixture.manager.pinStatus.pinnedCount, 2)

        fixture.manager.unpinMostRecent()
        XCTAssertEqual(fixture.manager.pinnedItems.map(\.windowID), [1])
        XCTAssertEqual(fixture.windows.frames[1]?.height, 900)

        fixture.manager.unpinWindow(windowID: 1, bundleID: "example.app1")
        XCTAssertTrue(fixture.manager.pinnedItems.isEmpty)
        XCTAssertFalse(fixture.manager.pinStatus.isPinned)
        XCTAssertEqual(fixture.manager.pinStatus.reason, .userUnpinned)
        XCTAssertTrue(fixture.controls.isHidden)
    }

    func testResizingAndMovingSidebarPersistConfigForEveryPinnedApp() async throws {
        let fixture = Fixture()
        defer { fixture.stop() }
        try await fixture.pin(1)
        try await fixture.pin(2)

        fixture.manager.resizeSidebar(deltaX: -100)
        fixture.manager.finishSidebarResize()
        try fixture.manager.moveSidebar(to: .left)
        fixture.manager.resizeSidebar(deltaX: 50)
        fixture.manager.finishSidebarResize()

        // Reload from the same isolated defaults to verify persistence, not just memory.
        let reloaded = SettingsStore(userDefaults: fixture.defaults)
        for id in 1...2 {
            XCTAssertEqual(reloaded.config(for: "example.app\(id)"), PinnedAppConfig(
                bundleId: "example.app\(id)",
                preferredEdge: .left,
                preferredDisplayId: "test-display",
                preferredWidth: 510
            ))
            XCTAssertEqual(fixture.windows.frames[CGWindowID(id)]?.width, 510)
            XCTAssertEqual(fixture.windows.frames[CGWindowID(id)]?.minX, 0)
        }
    }

    func testMissingDisplayFallsBackAndWidthClampsToActualDisplay() async throws {
        let fixture = Fixture(displayWidth: 280)
        defer { fixture.stop() }
        try await fixture.pin(1, displayID: "disconnected", width: 600)

        XCTAssertEqual(fixture.manager.currentSidebarWidth, 266)
        XCTAssertEqual(fixture.windows.frames[1]?.width, 266)
        XCTAssertEqual(fixture.settings.config(for: "example.app1")?.preferredDisplayId, "test-display")
        XCTAssertEqual(fixture.settings.config(for: "example.app1")?.preferredWidth, 266)
    }

    func testMonitorRemovesClosedWindowAndRelayoutsSurvivor() async throws {
        let fixture = Fixture()
        defer { fixture.stop() }
        try await fixture.pin(1)
        try await fixture.pin(2)

        fixture.windows.frames.removeValue(forKey: 1)
        fixture.manager.monitorLoop()

        XCTAssertEqual(fixture.manager.pinnedItems.map(\.windowID), [2])
        XCTAssertEqual(fixture.manager.pinStatus.pinnedCount, 1)
        XCTAssertEqual(fixture.windows.frames[2]?.height, 900)

        fixture.windows.frames.removeValue(forKey: 2)
        fixture.manager.monitorLoop()

        XCTAssertFalse(fixture.manager.pinStatus.isPinned)
        XCTAssertEqual(fixture.manager.pinStatus.reason, .targetWindowClosed)
    }

    func testMonitorStopsSessionAfterManualMoveOrResize() async throws {
        for changedFrame in [
            CGRect(x: 500, y: 0, width: 360, height: 900),
            CGRect(x: 640, y: 0, width: 400, height: 900)
        ] {
            let fixture = Fixture()
            defer { fixture.stop() }
            try await fixture.pin(1)
            fixture.windows.frames[1] = changedFrame

            fixture.manager.monitorLoop()

            XCTAssertFalse(fixture.manager.pinStatus.isPinned)
            XCTAssertEqual(fixture.manager.pinStatus.reason, .manualWindowMoveOrResize)
        }
    }

    func testPermissionDenialAndRevocationDoNotControlWindows() async throws {
        let fixture = Fixture()
        defer { fixture.stop() }
        fixture.permissions.isGranted = false
        do {
            try await fixture.pin(1)
            XCTFail("Pinning without Accessibility permission should fail")
        } catch PinError.permissionDenied {} catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(fixture.windows.frames.isEmpty)

        fixture.permissions.isGranted = true
        try await fixture.pin(1)
        fixture.permissions.isGranted = false
        fixture.manager.monitorLoop()

        XCTAssertEqual(fixture.manager.pinStatus.reason, .permissionRevoked)
        XCTAssertTrue(fixture.manager.pinnedItems.isEmpty)
    }
}

@MainActor
private final class Fixture {
    let permissions = TestPermissions()
    let windows = TestWindows()
    let controls = TestControls()
    let defaults: UserDefaults
    let settings: SettingsStore
    let manager: PinSessionManager
    private let suiteName = "PinSessionManagerTests-\(UUID().uuidString)"

    init(displayWidth: CGFloat = 1000) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = SettingsStore(userDefaults: defaults)
        manager = PinSessionManager(
            permissionManager: permissions,
            windowController: windows,
            displayManager: TestDisplays(width: displayWidth),
            settingsStore: settings,
            edgeToggleController: controls,
            resizeHandleController: controls,
            monitorInterval: nil
        )
    }

    func pin(_ id: CGWindowID, displayID: String = "test-display", width: CGFloat = 360) async throws {
        try await manager.startPin(request: PinRequest(
            source: .runningWindow,
            bundleId: "example.app\(id)",
            edge: .right,
            displayId: displayID,
            windowID: id,
            width: width
        ))
    }

    func stop() {
        manager.stopPin(reason: .userUnpinned)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class TestPermissions: PermissionManaging {
    var isGranted = true
    func isAccessibilityGranted() -> Bool { isGranted }
    func requestAccessibilityPermission() {}
}

@MainActor
private final class TestDisplays: DisplayProviding {
    let display: DisplayDescriptor
    init(width: CGFloat) {
        display = DisplayDescriptor(id: "test-display", name: "Test", frame: CGRect(x: 0, y: 0, width: width, height: 900))
    }
    func allDisplays() -> [DisplayDescriptor] { [display] }
    func display(withID id: String) -> DisplayDescriptor? { id == display.id ? display : nil }
    func primaryDisplay() -> DisplayDescriptor? { display }
}

@MainActor
private final class TestWindows: WindowControlling {
    var frames: [CGWindowID: CGRect] = [:]

    func resolveWindow(bundleId: String, preferredWindowID: CGWindowID?) async throws -> ManagedWindow {
        let id = preferredWindowID!
        frames[id] = .zero
        // These opaque handles are never passed to Accessibility APIs by this double.
        let app = NSRunningApplication.current
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return ManagedWindow(app: app, appElement: element, windowElement: element, bundleId: bundleId, windowID: id)
    }

    func frame(of window: ManagedWindow) throws -> CGRect {
        guard let frame = frames[window.windowID!] else { throw PinError.windowNotFound(window.bundleId) }
        return frame
    }
    func setFrame(_ frame: CGRect, for window: ManagedWindow) throws { frames[window.windowID!] = frame }
    func bringToFront(_ window: ManagedWindow) {}
}

@MainActor
private final class TestControls: SidebarEdgeToggleControlling, ResizeHandleControlling {
    var isHidden = true
    func show(sidebarRegion: CGRect, edge: SidebarEdge, collapsed: Bool, autoModeEnabled: Bool,
              onToggle: @escaping () -> Void, onToggleAutoMode: @escaping () -> Void) {
        isHidden = false
    }
    func show(for pinnedFrame: CGRect, edge: SidebarEdge, onDeltaX: @MainActor @escaping (CGFloat) -> Void,
              onDragEnd: @MainActor @escaping () -> Void) {
        isHidden = false
    }
    func hide() { isHidden = true }
}
