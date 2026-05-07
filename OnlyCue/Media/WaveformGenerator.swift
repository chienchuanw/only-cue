import AVFoundation

enum WaveformError: Error, Equatable {
    case noAudioTrack
    case readerFailed
}

enum WaveformGenerator {

    static func peaks(for asset: AVAsset, resolution: Int) async throws -> [Float] {
        guard resolution > 0 else { return [] }

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        let reader = try makeReader(asset: asset, track: track)
        guard reader.startReading() else {
            throw WaveformError.readerFailed
        }
        guard let output = reader.outputs.first as? AVAssetReaderTrackOutput else {
            throw WaveformError.readerFailed
        }

        let totalSamples = try await estimatedSampleCount(asset: asset, resolution: resolution)
        var accumulator = PeakAccumulator(
            resolution: resolution,
            samplesPerBucket: max(totalSamples / resolution, 1)
        )

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try accumulator.ingest(sampleBuffer: buffer)
            CMSampleBufferInvalidate(buffer)
        }

        if reader.status == .failed {
            throw WaveformError.readerFailed
        }

        return accumulator.finalize()
    }

    private static let outputSampleRate: Double = 44100

    private static func makeReader(asset: AVAsset, track: AVAssetTrack) throws -> AVAssetReader {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.outputSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        return reader
    }

    private static func estimatedSampleCount(asset: AVAsset, resolution: Int) async throws -> Int {
        let duration = try await asset.load(.duration)
        let totalSeconds = max(CMTimeGetSeconds(duration), 0.001)
        return max(Int(totalSeconds * Self.outputSampleRate), resolution)
    }
}

private struct PeakAccumulator {

    let resolution: Int
    let samplesPerBucket: Int
    private(set) var peaks: [Float]
    private var bucketIndex = 0
    private var samplesInBucket = 0
    private var bucketPeak: Int16 = 0

    init(resolution: Int, samplesPerBucket: Int) {
        self.resolution = resolution
        self.samplesPerBucket = samplesPerBucket
        self.peaks = [Float](repeating: 0, count: resolution)
    }

    mutating func ingest(sampleBuffer: CMSampleBuffer) throws {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }
        data.withUnsafeBytes { rawBuffer in
            ingest(samples: rawBuffer.bindMemory(to: Int16.self))
        }
    }

    mutating func finalize() -> [Float] {
        if bucketIndex < resolution {
            peaks[bucketIndex] = Float(bucketPeak) / Float(Int16.max)
        }
        return peaks
    }

    private mutating func ingest(samples: UnsafeBufferPointer<Int16>) {
        for sample in samples {
            let absSample = Int16(clamping: abs(Int32(sample)))
            if absSample > bucketPeak {
                bucketPeak = absSample
            }
            samplesInBucket += 1
            if samplesInBucket >= samplesPerBucket && bucketIndex < resolution {
                peaks[bucketIndex] = Float(bucketPeak) / Float(Int16.max)
                bucketIndex += 1
                samplesInBucket = 0
                bucketPeak = 0
            }
        }
    }
}
