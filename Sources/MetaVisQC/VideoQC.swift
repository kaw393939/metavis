import Foundation
import AVFoundation
import MetaVisCore

public enum VideoQC {
    public struct Expectations: Sendable {
        public var minDurationSeconds: Double
        public var maxDurationSeconds: Double
        public var expectedWidth: Int
        public var expectedHeight: Int
        public var expectedNominalFrameRate: Double
        public var minVideoSampleCount: Int

        public init(
            minDurationSeconds: Double,
            maxDurationSeconds: Double,
            expectedWidth: Int,
            expectedHeight: Int,
            expectedNominalFrameRate: Double,
            minVideoSampleCount: Int
        ) {
            self.minDurationSeconds = minDurationSeconds
            self.maxDurationSeconds = maxDurationSeconds
            self.expectedWidth = expectedWidth
            self.expectedHeight = expectedHeight
            self.expectedNominalFrameRate = expectedNominalFrameRate
            self.minVideoSampleCount = minVideoSampleCount
        }

        public static func hevc4K24fps(durationSeconds: Double) -> Expectations {
            // Tolerances: allow small encoder rounding and timescale differences.
            let tol = max(0.25, min(1.0, durationSeconds * 0.02))
            let expectedFrames = Int((durationSeconds * 24.0).rounded())
            return Expectations(
                minDurationSeconds: durationSeconds - tol,
                maxDurationSeconds: durationSeconds + tol,
                expectedWidth: 3840,
                expectedHeight: 2160,
                expectedNominalFrameRate: 24.0,
                // require most frames exist (encoder may drop a few; keep tolerant but strict)
                minVideoSampleCount: max(1, Int(Double(expectedFrames) * 0.85))
            )
        }
    }

    public struct Report: Sendable {
        public var durationSeconds: Double
        public var width: Int
        public var height: Int
        public var nominalFrameRate: Double
        public var estimatedDataRate: Float
        public var videoSampleCount: Int
    }

    public static func validateMovie(at url: URL, expectations: Expectations) async throws -> Report {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "MetaVisQC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing movie at \(url.path)"])
        }

        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(durationTime)

        guard durationSeconds.isFinite else {
            throw NSError(domain: "MetaVisQC", code: 2, userInfo: [NSLocalizedDescriptionKey: "Non-finite duration"])
        }
        guard durationSeconds >= expectations.minDurationSeconds, durationSeconds <= expectations.maxDurationSeconds else {
            throw NSError(domain: "MetaVisQC", code: 3, userInfo: [NSLocalizedDescriptionKey: "Duration out of range: \(durationSeconds)s"])
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw NSError(domain: "MetaVisQC", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track"])
        }

        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        // Account for transform rotation.
        let transformed = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())

        guard width == expectations.expectedWidth, height == expectations.expectedHeight else {
            throw NSError(domain: "MetaVisQC", code: 5, userInfo: [NSLocalizedDescriptionKey: "Resolution mismatch: \(width)x\(height)"])
        }

        // Frame rate can be reported as 0 for some assets; enforce if non-zero.
        if nominalFrameRate > 0 {
            let delta = abs(Double(nominalFrameRate) - expectations.expectedNominalFrameRate)
            if delta > 0.5 {
                throw NSError(domain: "MetaVisQC", code: 6, userInfo: [NSLocalizedDescriptionKey: "FPS mismatch: \(nominalFrameRate)"])
            }
        }

        let sampleCount = try countVideoSamples(asset: asset, track: videoTrack)
        guard sampleCount >= expectations.minVideoSampleCount else {
            throw NSError(domain: "MetaVisQC", code: 7, userInfo: [NSLocalizedDescriptionKey: "Too few video samples: \(sampleCount)"])
        }

        return Report(
            durationSeconds: durationSeconds,
            width: width,
            height: height,
            nominalFrameRate: Double(nominalFrameRate),
            estimatedDataRate: estimatedDataRate,
            videoSampleCount: sampleCount
        )
    }

    public static func validateMovie(at url: URL, policy: DeterministicQCPolicy) async throws -> Report {
        let expectations = Expectations(
            minDurationSeconds: policy.video.minDurationSeconds,
            maxDurationSeconds: policy.video.maxDurationSeconds,
            expectedWidth: policy.video.expectedWidth,
            expectedHeight: policy.video.expectedHeight,
            expectedNominalFrameRate: policy.video.expectedNominalFrameRate,
            minVideoSampleCount: policy.video.minVideoSampleCount
        )

        let report = try await validateMovie(at: url, expectations: expectations)

        if policy.requireAudioTrack {
            try await assertHasAudioTrack(at: url)
        }
        if policy.requireAudioNotSilent {
            try await assertAudioNotSilent(at: url, sampleSeconds: policy.audioSampleSeconds, minPeak: policy.minAudioPeak)
        }

        return report
    }

    public static func assertHasAudioTrack(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if audioTracks.isEmpty {
            throw NSError(domain: "MetaVisQC", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected an audio track, found none"])
        }
    }

    /// Reads a short audio time-range and asserts it's not effectively silent.
    public static func assertAudioNotSilent(at url: URL, sampleSeconds: Double = 0.5, minPeak: Float = 0.0005) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw NSError(domain: "MetaVisQC", code: 9, userInfo: [NSLocalizedDescriptionKey: "No audio track"])
        }

        let reader = try AVAssetReader(asset: asset)
        let duration = CMTime(seconds: max(0.05, sampleSeconds), preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(domain: "MetaVisQC", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio reader output"])
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "MetaVisQC", code: 11, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed to start"])
        }

        var peak: Float = 0
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
            }

            if peak >= minPeak { break }
        }

        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "MetaVisQC", code: 12, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed"])
        }

        if peak < minPeak {
            throw NSError(domain: "MetaVisQC", code: 13, userInfo: [NSLocalizedDescriptionKey: "Audio appears silent (peak=\(peak))"])
        }
    }

    private static func countVideoSamples(asset: AVAsset, track: AVAssetTrack) throws -> Int {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw NSError(domain: "MetaVisQC", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot add reader output"])
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "MetaVisQC", code: 11, userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"])
        }

        var count = 0
        while true {
            if let sample = output.copyNextSampleBuffer() {
                count += 1
                _ = sample
            } else {
                break
            }
        }

        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "MetaVisQC", code: 12, userInfo: [NSLocalizedDescriptionKey: "Reader failed"])
        }

        return count
    }
}
