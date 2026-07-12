import CoreAudio
import Foundation

/// Queries the default output device's end-to-end latency so the rendered
/// playhead can show what is *audible now* instead of what the player has
/// already queued (#611). macOS has no `AVAudioSession.outputLatency`; the
/// CoreAudio properties below are the platform's equivalent.
enum AudioOutputLatency {

    /// Total output latency in seconds: device latency + safety offset +
    /// IO buffer + stream latency, over the device sample rate. Pure math,
    /// unit-testable; `currentSeconds()` feeds it live values.
    static func seconds(
        deviceLatencyFrames: UInt32,
        safetyOffsetFrames: UInt32,
        bufferFrames: UInt32,
        streamLatencyFrames: UInt32,
        sampleRate: Double
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        let totalFrames = Double(deviceLatencyFrames) + Double(safetyOffsetFrames)
            + Double(bufferFrames) + Double(streamLatencyFrames)
        return totalFrames / sampleRate
    }

    /// Live latency of the current default output device, clamped to a sane
    /// range — a garbage device report must never yank the playhead around.
    static func currentSeconds() -> TimeInterval {
        guard let device = defaultOutputDevice() else { return 0 }
        let raw = seconds(
            deviceLatencyFrames: property(kAudioDevicePropertyLatency, of: device) ?? 0,
            safetyOffsetFrames: property(kAudioDevicePropertySafetyOffset, of: device) ?? 0,
            bufferFrames: property(kAudioDevicePropertyBufferFrameSize, of: device) ?? 0,
            streamLatencyFrames: streamLatency(of: device) ?? 0,
            sampleRate: sampleRate(of: device) ?? 0
        )
        return min(max(raw, 0), 0.5)
    }

    // MARK: - CoreAudio plumbing

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func property(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> UInt32? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func sampleRate(of device: AudioDeviceID) -> Double? {
        var value = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Latency of the device's first output stream — CoreAudio splits total
    /// latency between the device object and each stream.
    private static func streamLatency(of device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr,
              let stream = streams.first else { return nil }

        var value = UInt32(0)
        var valueSize = UInt32(MemoryLayout<UInt32>.size)
        var latencyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyLatency,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(stream, &latencyAddress, 0, nil, &valueSize, &value) == noErr else {
            return nil
        }
        return value
    }
}
