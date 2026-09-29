import CoreAudio
import Foundation
import IOKit
import OpenWhisperCore

enum SystemAudioInputs {
    /// The input device OpenWhisper should record from, or nil for the macOS default input.
    static func preferredInputDeviceID() -> AudioDeviceID? {
        let usesBuiltInMicrophoneDuringPlayback = UserDefaults.standard
            .object(forKey: OpenWhisperDefaultsKey.useBuiltInMicrophoneDuringPlayback) as? Bool ?? true
        guard usesBuiltInMicrophoneDuringPlayback else { return nil }

        return MicrophoneSelection.preferredInputDeviceID(
            defaultInput: defaultInputDevice(),
            availableInputs: inputDevices(),
            isHeadphoneAudioPlaying: isBluetoothOutputPlaying(),
            isLidClosed: isLidClosed()
        )
    }

    /// Whether any app is playing through Bluetooth headphones that are the default output.
    /// OpenWhisper's own engine is stopped whenever this is checked, so it never counts itself.
    private static func isBluetoothOutputPlaying() -> Bool {
        let deviceID: AudioDeviceID = property(
            kAudioHardwarePropertyDefaultOutputDevice,
            of: AudioObjectID(kAudioObjectSystemObject),
            default: kAudioObjectUnknown
        )
        guard deviceID != kAudioObjectUnknown, deviceInfo(deviceID).transport == .bluetooth else {
            return false
        }

        return property(kAudioDevicePropertyDeviceIsRunningSomewhere, of: deviceID, default: UInt32(0)) != 0
    }

    private static func defaultInputDevice() -> AudioInputDeviceInfo? {
        let deviceID: AudioDeviceID = property(
            kAudioHardwarePropertyDefaultInputDevice,
            of: AudioObjectID(kAudioObjectSystemObject),
            default: kAudioObjectUnknown
        )
        guard deviceID != kAudioObjectUnknown else { return nil }

        return deviceInfo(deviceID)
    }

    private static func inputDevices() -> [AudioInputDeviceInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else {
            return []
        }

        var deviceIDs = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs
            .filter { hasInputStreams($0) && property(kAudioDevicePropertyDeviceIsAlive, of: $0, default: UInt32(0)) != 0 }
            .map(deviceInfo)
    }

    private static func deviceInfo(_ deviceID: AudioDeviceID) -> AudioInputDeviceInfo {
        let transport: UInt32 = property(kAudioDevicePropertyTransportType, of: deviceID, default: 0)

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return AudioInputDeviceInfo(id: deviceID, transport: .builtIn)
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return AudioInputDeviceInfo(id: deviceID, transport: .bluetooth)
        default:
            return AudioInputDeviceInfo(id: deviceID, transport: .other)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func property<Value>(
        _ selector: AudioObjectPropertySelector,
        of objectID: AudioObjectID,
        default defaultValue: Value
    ) -> Value {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = defaultValue
        var size = UInt32(MemoryLayout<Value>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        return status == noErr ? value : defaultValue
    }

    private static func isLidClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }

        let state = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return state?.takeRetainedValue() as? Bool ?? false
    }
}
