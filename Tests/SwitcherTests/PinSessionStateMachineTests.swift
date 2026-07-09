import XCTest
@testable import Switcher

final class PinSessionStateMachineTests: XCTestCase {
    func testStateTransitionsStartAndStop() {
        var machine = PinSessionStateMachine()

        machine.didStart(bundleId: "com.example.app", pinnedCount: 1)
        XCTAssertEqual(machine.status, PinStatus(isPinned: true, reason: nil, targetBundleId: "com.example.app", pinnedCount: 1))

        machine.didStop(reason: .manualWindowMoveOrResize)
        XCTAssertEqual(machine.status, PinStatus(isPinned: false, reason: .manualWindowMoveOrResize, targetBundleId: "com.example.app"))

        machine.didStart(bundleId: "com.other.app", pinnedCount: 2)
        XCTAssertEqual(machine.status, PinStatus(isPinned: true, reason: nil, targetBundleId: "com.other.app", pinnedCount: 2))
    }
}
