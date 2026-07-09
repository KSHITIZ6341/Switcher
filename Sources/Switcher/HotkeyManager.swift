import Carbon.HIToolbox
import Foundation

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    enum RegistrationError: LocalizedError {
        case installHandlerFailed(OSStatus)
        case registerHotKeyFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installHandlerFailed(let status):
                return "Failed to install the keyboard shortcut handler (Carbon status \(status))."
            case .registerHotKeyFailed(let status):
                return "Failed to register Control-Option-S as the global shortcut (Carbon status \(status))."
            }
        }
    }

    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyIDValue: UInt32 = 1
    private let signature: OSType = 0x5344504E // SDPN

    private init() {}

    func registerDefaultHotKey() throws {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef,
                  let userData else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return noErr
            }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            if hotKeyID.id == manager.hotKeyIDValue {
                manager.onHotKeyPressed?()
            }

            return noErr
        }

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType, userData, &eventHandlerRef)
        guard installStatus == noErr else {
            unregister()
            throw RegistrationError.installHandlerFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: hotKeyIDValue)
        let modifiers = UInt32(controlKey) | UInt32(optionKey)
        let registerStatus = RegisterEventHotKey(UInt32(kVK_ANSI_S), modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            unregister()
            throw RegistrationError.registerHotKeyFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
