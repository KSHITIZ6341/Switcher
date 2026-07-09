import XCTest
@testable import Switcher

final class PinMonitorPolicyTests: XCTestCase {
    func testMonitorRunsOnlyForActiveSessionOrAutoHover() {
        XCTAssertFalse(PinMonitorPolicy.shouldRun(hasActiveSession: false, autoHoverEnabled: false))
        XCTAssertTrue(PinMonitorPolicy.shouldRun(hasActiveSession: true, autoHoverEnabled: false))
        XCTAssertTrue(PinMonitorPolicy.shouldRun(hasActiveSession: false, autoHoverEnabled: true))
        XCTAssertTrue(PinMonitorPolicy.shouldRun(hasActiveSession: true, autoHoverEnabled: true))
    }
}
