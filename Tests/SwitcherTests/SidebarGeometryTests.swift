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

    func testConversionAndHitTestingForDisplayAbovePrimary() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 0, y: 800, width: 1000, height: 600)
        ]
        let quartzBounds = CGRect(x: 100, y: -500, width: 300, height: 200)

        XCTAssertEqual(
            SidebarGeometry.convertQuartzBoundsToAppKit(quartzBounds, screenFrames: screens),
            CGRect(x: 100, y: 1100, width: 300, height: 200)
        )
        XCTAssertTrue(SidebarGeometry.appKitFrameContainsCursor(
            quartzBounds: quartzBounds,
            cursor: CGPoint(x: 150, y: 1150),
            screenFrames: screens
        ))
    }

    func testTallerSecondaryDisplayDoesNotShiftPrimaryCoordinateOrigin() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 1000, y: 0, width: 800, height: 1200)
        ]

        XCTAssertEqual(
            SidebarGeometry.convertQuartzBoundsToAppKit(
                CGRect(x: 1100, y: -100, width: 300, height: 200),
                screenFrames: screens
            ),
            CGRect(x: 1100, y: 700, width: 300, height: 200)
        )
    }

    func testAppKitSidebarStackMapsToTopToBottomAccessibilityCoordinates() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let frames = SidebarGeometry.stackedFrames(
            count: 3, displayFrame: display, edge: .right, collapsed: false, width: 300
        )

        XCTAssertEqual(frames.map {
            SidebarGeometry.convertAppKitBoundsToQuartz($0, screenFrames: [display])
        }, [
            CGRect(x: 700, y: 0, width: 300, height: 300),
            CGRect(x: 700, y: 300, width: 300, height: 300),
            CGRect(x: 700, y: 600, width: 300, height: 300)
        ])
    }

    func testCoordinateRoundTripForDisplaysAboveBelowAndLeft() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),
            CGRect(x: 0, y: 800, width: 1000, height: 600),
            CGRect(x: -800, y: 0, width: 800, height: 900),
            CGRect(x: 0, y: -600, width: 800, height: 600)
        ]
        let appKitFrames = [
            CGRect(x: 100, y: 1100, width: 300, height: 200),
            CGRect(x: -700, y: 100, width: 300, height: 200),
            CGRect(x: 100, y: -500, width: 300, height: 200)
        ]
        let quartzFrames = [
            CGRect(x: 100, y: -500, width: 300, height: 200),
            CGRect(x: -700, y: 500, width: 300, height: 200),
            CGRect(x: 100, y: 1100, width: 300, height: 200)
        ]

        for (appKit, quartz) in zip(appKitFrames, quartzFrames) {
            XCTAssertEqual(SidebarGeometry.convertAppKitBoundsToQuartz(appKit, screenFrames: screens), quartz)
            XCTAssertEqual(SidebarGeometry.convertQuartzBoundsToAppKit(quartz, screenFrames: screens), appKit)
        }
        XCTAssertEqual(SidebarGeometry.convertQuartzBoundsToAppKit(appKitFrames[0], screenFrames: []), appKitFrames[0])
        XCTAssertEqual(SidebarGeometry.convertAppKitBoundsToQuartz(appKitFrames[0], screenFrames: []), appKitFrames[0])
    }
}
