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
    /// which cuts playback for about a second when recording starts and stops, and lowers its quality
    /// in between. That only matters while something is playing through them, so only then does the
    /// built-in microphone take over. With the lid closed, it cannot hear anything.
    public static func preferredInputDeviceID(
        defaultInput: AudioInputDeviceInfo?,
        availableInputs: [AudioInputDeviceInfo],
        isHeadphoneAudioPlaying: Bool,
        isLidClosed: Bool
    ) -> UInt32? {
        guard defaultInput?.transport == .bluetooth, isHeadphoneAudioPlaying, !isLidClosed else {
            return nil
        }

        return availableInputs.first { $0.transport == .builtIn }?.id
    }
}
