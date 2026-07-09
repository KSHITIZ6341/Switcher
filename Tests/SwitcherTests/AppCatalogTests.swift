import CoreGraphics
import XCTest
@testable import Switcher

final class AppCatalogTests: XCTestCase {
    func testInstalledApplicationSearchRootsIncludeSystemApplications() {
        let paths = AppCatalog.installedApplicationSearchRoots().map(\.path)

        XCTAssertTrue(paths.contains("/Applications"))
        XCTAssertTrue(paths.contains("/System/Applications"))
    }

    func testRunningWindowPickerRejectsSwitcherWindow() {
        let entry = windowEntry(width: 640, height: 480)

        XCTAssertFalse(
            AppCatalog.isRunningWindowPickerCandidate(
                entry: entry,
                bundleID: "dev.switcher.app",
                mainBundleID: "dev.switcher.app"
            )
        )
    }

    func testRunningWindowPickerRejectsTinyWindows() {
        let narrowEntry = windowEntry(width: AppCatalog.minimumUsefulWindowSize.width - 1, height: 480)
        let shortEntry = windowEntry(width: 640, height: AppCatalog.minimumUsefulWindowSize.height - 1)

        XCTAssertFalse(
            AppCatalog.isRunningWindowPickerCandidate(
                entry: narrowEntry,
                bundleID: "com.example.app",
                mainBundleID: "dev.switcher.app"
            )
        )
        XCTAssertFalse(
            AppCatalog.isRunningWindowPickerCandidate(
                entry: shortEntry,
                bundleID: "com.example.app",
                mainBundleID: "dev.switcher.app"
            )
        )
    }

    func testRunningWindowPickerRejectsNearTransparentWindows() {
        let entry = windowEntry(width: 640, height: 480, alpha: AppCatalog.minimumUsefulWindowAlpha)

        XCTAssertFalse(
            AppCatalog.isRunningWindowPickerCandidate(
                entry: entry,
                bundleID: "com.example.app",
                mainBundleID: "dev.switcher.app"
            )
        )
    }

    func testRunningWindowPickerAcceptsUsefulWindow() {
        let entry = windowEntry(width: 640, height: 480)

        XCTAssertTrue(
            AppCatalog.isRunningWindowPickerCandidate(
                entry: entry,
                bundleID: "com.example.app",
                mainBundleID: "dev.switcher.app"
            )
        )
    }

    private func windowEntry(width: CGFloat, height: CGFloat, alpha: Double = 1) -> [String: Any] {
        [
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: CGRect(x: 10, y: 20, width: width, height: height).dictionaryRepresentation! as NSDictionary
        ]
    }
}
