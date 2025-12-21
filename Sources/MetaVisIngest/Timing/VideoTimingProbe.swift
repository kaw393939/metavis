import Foundation
import AVFoundation
import CoreMedia

/// Summary of observed video timing behavior.
public struct VideoTimingProfile: Codable, Sendable, Equatable {
    public struct FrameDeltaStats: Codable, Sendable, Equatable {
        public let sampleCount: Int
        public let minSeconds: Double
        public let maxSeconds: Double
        public let meanSeconds: Double
        public let stdDevSeconds: Double
        public let distinctDeltaCount: Int

        public init(
            sampleCount: Int,
            minSeconds: Double,
            maxSeconds: Double,
            meanSeconds: Double,
            stdDevSeconds: Double,
            distinctDeltaCount: Int
        ) {
            self.sampleCount = sampleCount
            self.minSeconds = minSeconds
            self.maxSeconds = maxSeconds
            self.meanSeconds = meanSeconds
            self.stdDevSeconds = stdDevSeconds
            self.distinctDeltaCount = distinctDeltaCount
        }
    }

    public let nominalFPS: Double?
    public let estimatedFPS: Double?
    public let isVFRLikely: Bool
    public let deltas: FrameDeltaStats?

    public init(nominalFPS: Double?, estimatedFPS: Double?, isVFRLikely: Bool, deltas: FrameDeltaStats?) {
        self.nominalFPS = nominalFPS
        self.estimatedFPS = estimatedFPS
        self.isVFRLikely = isVFRLikely
        self.deltas = deltas
    }
}

/// Probes a video file for timing characteristics using PTS deltas.
///
/// This is a deliberately lightweight, deterministic heuristic intended to support
/// Sprint 12 VFR detection/normalization work without committing to a full pipeline yet.
public enum VideoTimingProbe {

    public struct Config: Sendable {
        public let sampleLimit: Int
        public let minSamplesForDecision: Int
        public let vfrDistinctDeltaThreshold: Int
        public let vfrRelativeRangeThreshold: Double
        public let vfrStdDevThreshold: Double

        public init(
            sampleLimit: Int = 600,
            minSamplesForDecision: Int = 30,
            vfrDistinctDeltaThreshold: Int = 2,
            vfrRelativeRangeThreshold: Double = 0.02,
            vfrStdDevThreshold: Double = 0.01
        ) {
            self.sampleLimit = max(10, sampleLimit)
            self.minSamplesForDecision = max(5, minSamplesForDecision)
            self.vfrDistinctDeltaThreshold = max(2, vfrDistinctDeltaThreshold)
            self.vfrRelativeRangeThreshold = max(0, vfrRelativeRangeThreshold)
            self.vfrStdDevThreshold = max(0, vfrStdDevThreshold)
        }
    }

    public static func probe(url: URL, config: Config = Config()) async throws -> VideoTimingProfile {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            return VideoTimingProfile(nominalFPS: nil, estimatedFPS: nil, isVFRLikely: false, deltas: nil)
        }

        let nominal = try? await track.load(.nominalFrameRate)
        let nominalFPS = nominal.map { Double($0) }.flatMap { $0 > 0 ? $0 : nil }

        // Use compressed samples (outputSettings: nil) to avoid expensive decode.
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return VideoTimingProfile(nominalFPS: nominalFPS, estimatedFPS: nil, isVFRLikely: false, deltas: nil)
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? NSError(
                domain: "MetaVisIngest",
                code: 910,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed to start"]
            )
        }

        // IMPORTANT: when reading compressed samples, AVAssetReader can emit buffers in decode order.
        // For codecs with B-frames this can produce non-monotonic PTS even for CFR content.
        // To keep the probe stable and meaningful, collect PTS samples, sort by PTS, then compute deltas.
        var ptsSamples: [CMTime] = []
        ptsSamples.reserveCapacity(min(config.sampleLimit + 1, 601))

        while ptsSamples.count < (config.sampleLimit + 1) {
            guard let sample = output.copyNextSampleBuffer() else { break }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if pts.isValid {
                ptsSamples.append(pts)
            }
        }

        reader.cancelReading()

        guard ptsSamples.count >= 2 else {
            return VideoTimingProfile(nominalFPS: nominalFPS, estimatedFPS: nil, isVFRLikely: false, deltas: nil)
        }

        let sortedPTS = ptsSamples.sorted { a, b in
            CMTimeCompare(a, b) < 0
        }

        var deltas: [Double] = []
        deltas.reserveCapacity(max(0, sortedPTS.count - 1))

        var lastPTS: CMTime? = nil
        for pts in sortedPTS {
            if let prev = lastPTS {
                let d = (pts - prev).seconds
                if d.isFinite, d > 0 {
                    deltas.append(d)
                }
            }
            lastPTS = pts
        }

        guard deltas.count >= 2 else {
            return VideoTimingProfile(nominalFPS: nominalFPS, estimatedFPS: nil, isVFRLikely: false, deltas: nil)
        }

        let stats = computeDeltaStats(deltas)
        let estimatedFPS = stats.meanSeconds > 0 ? (1.0 / stats.meanSeconds) : nil

        let isVFRLikely: Bool
        if stats.sampleCount < config.minSamplesForDecision {
            isVFRLikely = false
        } else {
            let relativeRange = stats.meanSeconds > 0 ? (stats.maxSeconds - stats.minSeconds) / stats.meanSeconds : 0
            let relativeStdDev = stats.meanSeconds > 0 ? stats.stdDevSeconds / stats.meanSeconds : 0
            isVFRLikely = (stats.distinctDeltaCount >= config.vfrDistinctDeltaThreshold)
                && (relativeRange >= config.vfrRelativeRangeThreshold || relativeStdDev >= config.vfrStdDevThreshold)
        }

        return VideoTimingProfile(
            nominalFPS: nominalFPS,
            estimatedFPS: estimatedFPS,
            isVFRLikely: isVFRLikely,
            deltas: stats
        )
    }

    private static func computeDeltaStats(_ deltas: [Double]) -> VideoTimingProfile.FrameDeltaStats {
        let finite = deltas.filter { $0.isFinite && $0 > 0 }
        let n = finite.count
        guard n > 0 else {
            return .init(sampleCount: 0, minSeconds: 0, maxSeconds: 0, meanSeconds: 0, stdDevSeconds: 0, distinctDeltaCount: 0)
        }

        var minV = finite[0]
        var maxV = finite[0]
        var sum = 0.0

        // Quantize to microseconds to count distinct deltas robustly.
        var distinct: Set<Int> = []
        distinct.reserveCapacity(min(n, 8))

        for d in finite {
            if d < minV { minV = d }
            if d > maxV { maxV = d }
            sum += d
            distinct.insert(Int((d * 1_000_000.0).rounded()))
        }

        let mean = sum / Double(n)
        var variance = 0.0
        for d in finite {
            let diff = d - mean
            variance += diff * diff
        }
        variance /= Double(max(1, n - 1))
        let stdDev = variance.squareRoot()

        return .init(
            sampleCount: n,
            minSeconds: minV,
            maxSeconds: maxV,
            meanSeconds: mean,
            stdDevSeconds: stdDev,
            distinctDeltaCount: distinct.count
        )
    }
}
