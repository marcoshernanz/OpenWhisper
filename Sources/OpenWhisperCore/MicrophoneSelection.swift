import Foundation

public struct AudioInputDeviceInfo: Equatable, Sendable {
    public enum Transport: Equatable, Sendable {
        case builtIn
        case bluetooth
        case other
    }

    public let id: UInt32
    public let transport: Transport

    public init(id: UInt32, transport: Transport) {
        self.id = id
        self.transport = transport
    }
}

public enum MicrophoneSelection {
    /// Returns the device to record from, or nil to follow the macOS default input.
    ///
    /// Recording from Bluetooth headphones such as AirPods switches them to their headset profile,
    /// which lowers playback quality, briefly cuts audio when recording starts and stops, and can
    /// change their volume. The built-in microphone avoids that, except with the lid closed, when it
    /// cannot hear anything.
    public static func preferredInputDeviceID(
        defaultInput: AudioInputDeviceInfo?,
        availableInputs: [AudioInputDeviceInfo],
        isLidClosed: Bool
    ) -> UInt32? {
        guard defaultInput?.transport == .bluetooth, !isLidClosed else {
            return nil
        }

        return availableInputs.first { $0.transport == .builtIn }?.id
    }
}
