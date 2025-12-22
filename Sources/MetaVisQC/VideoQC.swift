import Foundation
import AVFoundation
import MetaVisCore

public enum VideoQC {
    public enum QCError: Error, LocalizedError, Sendable {
        case missingMovie(path: String)
        case nonFiniteDuration
        case durationOutOfRange(actualSeconds: Double, minSeconds: Double, maxSeconds: Double)
        case noVideoTrack
        case resolutionMismatch(actualWidth: Int, actualHeight: Int, expectedWidth: Int, expectedHeight: Int)
        case fpsMismatch(actualFPS: Float, expectedFPS: Double)
        case tooFewVideoSamples(actual: Int, minExpected: Int)

        case expectedAudioTrackMissing
        case noAudioTrack

        case cannotAddAudioReaderOutput
        case audioReaderFailedToStart(underlying: String?)
        case audioReaderFailed(underlying: String?)
        case audioAppearsSilent(peak: Float, minPeak: Float)

        case cannotAddVideoReaderOutput
        case videoReaderFailedToStart(underlying: String?)
        case videoReaderFailed(underlying: String?)

        public var errorDescription: String? {
            switch self {
            case .missingMovie(let path):
                return "Missing movie at \(path)"
            case .nonFiniteDuration:
                return "Non-finite duration"
            case .durationOutOfRange(let actual, let min, let max):
                return "Duration out of range: \(actual)s (expected \(min)s..\(max)s)"
            case .noVideoTrack:
                return "No video track"
            case .resolutionMismatch(let w, let h, let ew, let eh):
                return "Resolution mismatch: \(w)x\(h) (expected \(ew)x\(eh))"
            case .fpsMismatch(let actual, let expected):
                return "FPS mismatch: \(actual) (expected ~\(expected))"
            case .tooFewVideoSamples(let actual, let min):
                return "Too few video samples: \(actual) (min \(min))"
            case .expectedAudioTrackMissing:
                return "Expected an audio track, found none"
            case .noAudioTrack:
                return "No audio track"
            case .cannotAddAudioReaderOutput:
                return "Cannot add audio reader output"
            case .audioReaderFailedToStart(let underlying):
                return underlying.map { "Audio reader failed to start: \($0)" } ?? "Audio reader failed to start"
            case .audioReaderFailed(let underlying):
                return underlying.map { "Audio reader failed: \($0)" } ?? "Audio reader failed"
            case .audioAppearsSilent(let peak, let minPeak):
                return "Audio appears silent (peak=\(peak), minPeak=\(minPeak))"
            case .cannotAddVideoReaderOutput:
                return "Cannot add video reader output"
            case .videoReaderFailedToStart(let underlying):
                return underlying.map { "Video reader failed to start: \($0)" } ?? "Video reader failed to start"
            case .videoReaderFailed(let underlying):
                return underlying.map { "Video reader failed: \($0)" } ?? "Video reader failed"
            }
        }
    }

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
            throw QCError.missingMovie(path: url.path)
        }

        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(durationTime)

        guard durationSeconds.isFinite else {
            throw QCError.nonFiniteDuration
        }
        guard durationSeconds >= expectations.minDurationSeconds, durationSeconds <= expectations.maxDurationSeconds else {
            throw QCError.durationOutOfRange(
                actualSeconds: durationSeconds,
                minSeconds: expectations.minDurationSeconds,
                maxSeconds: expectations.maxDurationSeconds
            )
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw QCError.noVideoTrack
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
            throw QCError.resolutionMismatch(
                actualWidth: width,
                actualHeight: height,
                expectedWidth: expectations.expectedWidth,
                expectedHeight: expectations.expectedHeight
            )
        }

        // Frame rate can be reported as 0 for some assets; enforce if non-zero.
        if nominalFrameRate > 0 {
            let delta = abs(Double(nominalFrameRate) - expectations.expectedNominalFrameRate)
            if delta > 0.5 {
                throw QCError.fpsMismatch(actualFPS: nominalFrameRate, expectedFPS: expectations.expectedNominalFrameRate)
            }
        }

        let sampleCount = try countVideoSamples(asset: asset, track: videoTrack)
        guard sampleCount >= expectations.minVideoSampleCount else {
            throw QCError.tooFewVideoSamples(actual: sampleCount, minExpected: expectations.minVideoSampleCount)
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
            throw QCError.expectedAudioTrackMissing
        }
    }

    /// Reads a short audio time-range and asserts it's not effectively silent.
    public static func assertAudioNotSilent(at url: URL, sampleSeconds: Double = 0.5, minPeak: Float = 0.0005) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw QCError.noAudioTrack
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
            throw QCError.cannotAddAudioReaderOutput
        }
        reader.add(output)

        guard reader.startReading() else {
            throw QCError.audioReaderFailedToStart(underlying: reader.error?.localizedDescription)
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
            throw QCError.audioReaderFailed(underlying: reader.error?.localizedDescription)
        }

        if peak < minPeak {
            throw QCError.audioAppearsSilent(peak: peak, minPeak: minPeak)
        }
    }

    private static func countVideoSamples(asset: AVAsset, track: AVAssetTrack) throws -> Int {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw QCError.cannotAddVideoReaderOutput
        }
        reader.add(output)

        guard reader.startReading() else {
            throw QCError.videoReaderFailedToStart(underlying: reader.error?.localizedDescription)
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
            throw QCError.videoReaderFailed(underlying: reader.error?.localizedDescription)
        }

        return count
    }
}
