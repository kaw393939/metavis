import Foundation
import AVFoundation

public enum AudioMovieProbe {

    public static func hasAudioTrack(at url: URL) async throws -> Bool {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        return !tracks.isEmpty
    }

    public static func peak(at url: URL, startSeconds: Double, durationSeconds: Double) async throws -> Float {
        let (peak, _) = try await readPeakAndRMS(at: url, startSeconds: startSeconds, durationSeconds: durationSeconds)
        return peak
    }

    public static func rms(at url: URL, startSeconds: Double, durationSeconds: Double) async throws -> Float {
        let (_, rms) = try await readPeakAndRMS(at: url, startSeconds: startSeconds, durationSeconds: durationSeconds)
        return rms
    }

    private static func readPeakAndRMS(at url: URL, startSeconds: Double, durationSeconds: Double) async throws -> (peak: Float, rms: Float) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw NSError(domain: "MetaVisTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track"])
        }

        let reader = try AVAssetReader(asset: asset)
        let start = CMTime(seconds: max(0.0, startSeconds), preferredTimescale: 600)
        let duration = CMTime(seconds: max(0.01, durationSeconds), preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: start, duration: duration)

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw NSError(domain: "MetaVisTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio reader output"])
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "MetaVisTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed to start"])
        }

        var peak: Float = 0
        var sumSq: Double = 0
        var count: Int = 0

        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if status != kCMBlockBufferNoErr { continue }
            guard let dataPointer else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            let floats = dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { ptr in
                UnsafeBufferPointer(start: ptr, count: floatCount)
            }

            for v in floats {
                let a = abs(v)
                if a > peak { peak = a }
                let d = Double(v)
                sumSq += d * d
            }

            count += floats.count
        }

        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "MetaVisTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed"])
        }

        let rms: Float
        if count > 0 {
            rms = Float(sqrt(sumSq / Double(count)))
        } else {
            rms = 0
        }

        return (peak, rms)
    }
}
