import Foundation

public struct AudioInputDeviceInfo: Equatable, Sendable {
    public enum Transport: Equatable, Sendable {
        case builtIn
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
    /// The built-in microphone hears speech about a tenth of a second after recording starts. Bluetooth
    /// headphones such as AirPods first switch to their headset profile, which takes from a third of a second
    /// to two seconds and loses the first words, and cuts and degrades whatever plays through them. With the
    /// lid closed, the built-in microphone cannot hear anything, so the default input takes over.
    public static func preferredInputDeviceID(
        availableInputs: [AudioInputDeviceInfo],
        isLidClosed: Bool
    ) -> UInt32? {
        guard !isLidClosed else { return nil }

        return availableInputs.first { $0.transport == .builtIn }?.id
    }
}
