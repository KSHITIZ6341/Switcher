enum PinMonitorPolicy {
    static func shouldRun(hasActiveSession: Bool, autoHoverEnabled: Bool) -> Bool {
        hasActiveSession || autoHoverEnabled
    }
}
