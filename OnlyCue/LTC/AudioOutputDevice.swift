import CoreAudio
import Foundation

/// A Core Audio output device the LTC generator could route to.
struct AudioOutputDevice: Identifiable, Equatable, Sendable {

    /// Core Audio `AudioObjectID` — valid only for this process / session.
    /// Persist `uid` instead.
    let id: AudioDeviceID

    /// Stable identifier that survives restarts / re-plugs (`kAudioDevicePropertyDeviceUID`).
    let uid: String

    /// Human-readable name (`kAudioObjectPropertyName`).
    let name: String

    /// Number of output channels across all output streams.
    let outputChannelCount: Int
}

/// Enumerates the system's Core Audio output devices. All calls hit Core Audio
/// HAL synchronously; returns `[]` (and `nil` for the default) if the HAL is
/// unavailable rather than throwing.
enum AudioOutputDeviceList {

    /// Every device with at least one output channel, in HAL order.
    static func current() -> [AudioOutputDevice] {
        deviceIDs().compactMap { device(for: $0) }
    }

    /// The current device with this stable UID, if it's still present.
    static func device(forUID uid: String) -> AudioOutputDevice? {
        current().first { $0.uid == uid }
    }

    /// The system default output device, if it has output channels.
    static func defaultOutput() -> AudioOutputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return device(for: deviceID)
    }

    // MARK: Internals

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        )
        return status == noErr ? ids : []
    }

    private static func device(for deviceID: AudioDeviceID) -> AudioOutputDevice? {
        let channels = outputChannelCount(of: deviceID)
        guard channels > 0,
              let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: deviceID)
        else { return nil }
        let name = stringProperty(kAudioObjectPropertyName, of: deviceID) ?? uid
        return AudioOutputDevice(id: deviceID, uid: uid, name: name, outputChannelCount: channels)
    }

    private static func outputChannelCount(of deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(0)
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize >= UInt32(MemoryLayout<AudioBufferList>.size)
        else { return 0 }
        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }
        guard AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &dataSize, bufferListPointer
        ) == noErr else { return 0 }
        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return audioBufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector, of deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              let cfString = value?.takeRetainedValue()
        else { return nil }
        return cfString as String
    }
}
