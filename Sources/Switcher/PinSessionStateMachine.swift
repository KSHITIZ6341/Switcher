struct PinSessionStateMachine {
    private(set) var status = PinStatus()

    mutating func didStart(bundleId: String, pinnedCount: Int) {
        status = PinStatus(
            isPinned: true,
            reason: nil,
            targetBundleId: bundleId,
            pinnedCount: pinnedCount
        )
    }

    mutating func didStop(reason: StopReason) {
        status = PinStatus(
            isPinned: false,
            reason: reason,
            targetBundleId: status.targetBundleId,
            pinnedCount: 0
        )
    }

    mutating func didUpdate(bundleId: String?, pinnedCount: Int) {
        status = PinStatus(
            isPinned: pinnedCount > 0,
            reason: nil,
            targetBundleId: bundleId,
            pinnedCount: pinnedCount
        )
    }
}
