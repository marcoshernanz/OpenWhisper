import Carbon.HIToolbox
import Foundation

final class ManualPasteHotKeyMonitor {
    private static let signature = fourCharacterCode("OWPV")
    private static let hotKeyIdentifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let onHotKey: @Sendable () -> Void

    init(onHotKey: @escaping @Sendable () -> Void) {
        self.onHotKey = onHotKey
    }

    deinit {
        stop()
    }

    func start() throws {
        guard eventHandler == nil, hotKey == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var eventHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr,
                      hotKeyID.signature == ManualPasteHotKeyMonitor.signature,
                      hotKeyID.id == ManualPasteHotKeyMonitor.hotKeyIdentifier
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let monitor = Unmanaged<ManualPasteHotKeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                monitor.onHotKey()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr, let eventHandler else {
            throw ManualPasteHotKeyError.registrationFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.hotKeyIdentifier
        )
        var hotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr, let hotKey else {
            RemoveEventHandler(eventHandler)
            throw ManualPasteHotKeyError.registrationFailed(registerStatus)
        }

        self.eventHandler = eventHandler
        self.hotKey = hotKey
    }

    private func stop() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKey = nil
        eventHandler = nil
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}

enum ManualPasteHotKeyError: Error, LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Could not register ctrl+cmd+V paste shortcut. Carbon status: \(status)."
        }
    }
}
