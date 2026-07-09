import CoreGraphics
import XCTest
@testable import Switcher

final class SidebarGeometryTests: XCTestCase {
    func testClampsSidebarWidthToDisplayAndConfigBounds() {
        let narrowDisplay = CGRect(x: 0, y: 0, width: 280, height: 900)
        let standardDisplay = CGRect(x: 0, y: 0, width: 1200, height: 900)

        XCTAssertEqual(SidebarGeometry.clampedSidebarWidth(100, displayFrame: standardDisplay), PinnedAppConfig.minWidth)
        XCTAssertEqual(SidebarGeometry.clampedSidebarWidth(900, displayFrame: standardDisplay), PinnedAppConfig.maxWidth)
        XCTAssertEqual(SidebarGeometry.clampedSidebarWidth(500, displayFrame: narrowDisplay), 266)
    }

    func testStackedFramesForOneTwoAndThreePinnedApps() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 900)

        XCTAssertEqual(
            SidebarGeometry.stackedFrames(count: 1, displayFrame: display, edge: .right, collapsed: false, width: 300),
            [CGRect(x: 700, y: 0, width: 300, height: 900)]
        )

        XCTAssertEqual(
            SidebarGeometry.stackedFrames(count: 2, displayFrame: display, edge: .right, collapsed: false, width: 300),
            [
                CGRect(x: 700, y: 450, width: 300, height: 450),
                CGRect(x: 700, y: 0, width: 300, height: 450)
            ]
        )

        XCTAssertEqual(
            SidebarGeometry.stackedFrames(count: 3, displayFrame: display, edge: .left, collapsed: false, width: 300),
            [
                CGRect(x: 0, y: 600, width: 300, height: 300),
                CGRect(x: 0, y: 300, width: 300, height: 300),
                CGRect(x: 0, y: 0, width: 300, height: 300)
            ]
        )
    }

    func testCollapsedFramesLeavePeekWidthAtDisplayEdge() {
        let display = CGRect(x: 100, y: 0, width: 1000, height: 800)

        XCTAssertEqual(
            SidebarGeometry.stackedFrames(count: 1, displayFrame: display, edge: .left, collapsed: true, width: 300),
            [CGRect(x: -196, y: 0, width: 300, height: 800)]
        )
        XCTAssertEqual(
            SidebarGeometry.stackedFrames(count: 1, displayFrame: display, edge: .right, collapsed: true, width: 300),
            [CGRect(x: 1096, y: 0, width: 300, height: 800)]
        )
    }

    func testManualFrameBreakIncludesResizeDeltas() {
        let expected = CGRect(x: 10, y: 20, width: 300, height: 400)
        let tinyResize = CGRect(x: 10, y: 20, width: 305, height: 410)
        let manualResize = CGRect(x: 10, y: 20, width: 325, height: 400)

        XCTAssertFalse(SidebarGeometry.hasManualFrameBreak(actual: tinyResize, expected: expected, tolerance: 24))
        XCTAssertTrue(SidebarGeometry.hasManualFrameBreak(actual: manualResize, expected: expected, tolerance: 24))
    }

    func testQuartzBoundsConvertToAppKitCoordinatesForCursorHitTesting() {
        let screenFrames = [CGRect(x: 0, y: 0, width: 1000, height: 800)]
        let quartzBounds = CGRect(x: 100, y: 50, width: 300, height: 200)

        XCTAssertEqual(
            SidebarGeometry.convertQuartzBoundsToAppKit(quartzBounds, screenFrames: screenFrames),
            CGRect(x: 100, y: 550, width: 300, height: 200)
        )
        XCTAssertTrue(
            SidebarGeometry.appKitFrameContainsCursor(
                quartzBounds: quartzBounds,
                cursor: CGPoint(x: 150, y: 600),
                screenFrames: screenFrames
            )
        )
        XCTAssertFalse(
            SidebarGeometry.appKitFrameContainsCursor(
                quartzBounds: quartzBounds,
                cursor: CGPoint(x: 150, y: 500),
                screenFrames: screenFrames
            )
        )
    }
}
