import ApplicationServices
import Combine

@MainActor
final class PermissionManager: ObservableObject, PermissionManaging {
    @Published private(set) var accessibilityGranted: Bool

    init() {
        self.accessibilityGranted = AXIsProcessTrusted()
    }

    func isAccessibilityGranted() -> Bool {
        let granted = AXIsProcessTrusted()
        accessibilityGranted = granted
        return granted
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        accessibilityGranted = AXIsProcessTrusted()
    }
}
