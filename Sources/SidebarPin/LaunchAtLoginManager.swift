import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw PinError.generic("Launch at login requires macOS 13 or later.")
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
