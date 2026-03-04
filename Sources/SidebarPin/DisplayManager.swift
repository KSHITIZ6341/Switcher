import AppKit

@MainActor
final class DisplayManager {
    func allDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayDescriptor(
                id: Self.displayID(for: screen),
                name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
                frame: screen.frame
            )
        }
    }

    func display(withID id: String) -> DisplayDescriptor? {
        allDisplays().first { $0.id == id }
    }

    func primaryDisplay() -> DisplayDescriptor? {
        guard let primary = NSScreen.screens.first else {
            return nil
        }
        return DisplayDescriptor(
            id: Self.displayID(for: primary),
            name: primary.localizedName,
            frame: primary.frame
        )
    }

    static func displayID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }

        let frame = screen.frame
        return "fallback-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(Int(frame.width))-\(Int(frame.height))"
    }
}
