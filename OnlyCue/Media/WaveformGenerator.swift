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

        let duration = try await asset.load(.duration)
        let totalSeconds = max(CMTimeGetSeconds(duration), 0.001)
        let sampleRate: Double = 44100
        let totalSamples = max(Int(totalSeconds * sampleRate), resolution)
        let samplesPerBucket = max(totalSamples / resolution, 1)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readerFailed
        }

        var peaks = [Float](repeating: 0, count: resolution)
        var bucketIndex = 0
        var samplesInBucket = 0
        var bucketPeak: Int16 = 0

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else {
                CMSampleBufferInvalidate(buffer)
                continue
            }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }
            data.withUnsafeBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: Int16.self)
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
            CMSampleBufferInvalidate(buffer)
        }

        if bucketIndex < resolution {
            peaks[bucketIndex] = Float(bucketPeak) / Float(Int16.max)
        }

        if reader.status == .failed {
            throw WaveformError.readerFailed
        }

        return peaks
    }
}
