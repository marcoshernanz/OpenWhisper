@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Records from one specific input device through a HAL audio unit.
///
/// AVAudioEngine's input node always opens the default input first. When that is Bluetooth headphones,
/// opening it is enough to switch them to their headset profile, even if another device is selected
/// right after. This unit is pointed at its device before it opens anything, so the headphones keep
/// playing at full quality.
final class AudioDeviceCapture {
    private let unit: AudioUnit
    private let buffer: AVAudioPCMBuffer
    private let tapBlock: AVAudioNodeTapBlock
    private var isStopped = false

    init(deviceID: AudioDeviceID, tapBlock: @escaping AVAudioNodeTapBlock) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var instance: AudioUnit?
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw RecordingError.inputUnavailable
        }
        try Self.check(AudioComponentInstanceNew(component, &instance))
        guard let unit = instance else { throw RecordingError.inputUnavailable }

        do {
            self.buffer = try Self.configure(unit, deviceID: deviceID)
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
        self.unit = unit
        self.tapBlock = tapBlock

        var callback = AURenderCallbackStruct(
            inputProc: { refCon, actionFlags, timeStamp, _, frameCount, _ in
                Unmanaged<AudioDeviceCapture>.fromOpaque(refCon)
                    .takeUnretainedValue()
                    .render(actionFlags: actionFlags, timeStamp: timeStamp, frameCount: frameCount)
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        do {
            try Self.check(AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ))
            try Self.check(AudioUnitInitialize(unit))
            try Self.check(AudioOutputUnitStart(unit))
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    /// Returns once the input callback can no longer run.
    func stop() {
        guard !isStopped else { return }
        isStopped = true

        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
    }

    /// Called on the device's I/O thread.
    private func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard frameCount <= buffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }

        buffer.frameLength = frameCount
        let status = AudioUnitRender(unit, actionFlags, timeStamp, 1, frameCount, buffer.mutableAudioBufferList)
        guard status == noErr else { return status }

        tapBlock(buffer, AVAudioTime(audioTimeStamp: timeStamp, sampleRate: buffer.format.sampleRate))
        return noErr
    }

    /// Selects the device and returns a buffer in the device's own sample rate and channel count.
    private static func configure(_ unit: AudioUnit, deviceID: AudioDeviceID) throws -> AVAudioPCMBuffer {
        var enabled: UInt32 = 1
        var disabled: UInt32 = 0
        var deviceID = deviceID
        let flagSize = UInt32(MemoryLayout<UInt32>.size)

        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, flagSize))
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, flagSize))
        try check(AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        ))

        var hardwareFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardwareFormat, &formatSize))

        guard hardwareFormat.mSampleRate > 0,
              hardwareFormat.mChannelsPerFrame > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: hardwareFormat.mSampleRate,
                  channels: AVAudioChannelCount(hardwareFormat.mChannelsPerFrame),
                  interleaved: false
              )
        else {
            throw RecordingError.inputUnavailable
        }

        try check(AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            format.streamDescription,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ))

        var maximumFrames: UInt32 = 0
        var maximumFramesSize = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFrames,
            &maximumFramesSize
        ))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(maximumFrames, 4096)) else {
            throw RecordingError.inputUnavailable
        }
        return buffer
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
