import Foundation
import CoreVideo
import MetaVisCore

/// Tier-0 tracking device stream.
///
/// MVP implementation: uses the existing Vision-based `FaceDetectionService` tracking.
/// The output is a stable (per-run) `TrackID -> rect` map in normalized coordinates.
public actor TracksDevice {

    public struct TrackMetrics: Sendable, Equatable {
        public var trackCount: Int
        public var reacquired: Bool

        public init(trackCount: Int, reacquired: Bool) {
            self.trackCount = trackCount
            self.reacquired = reacquired
        }
    }

    public struct TrackResult: @unchecked Sendable, Equatable {
        public var tracks: [UUID: CGRect]
        public var metrics: TrackMetrics
        public var evidenceConfidence: ConfidenceRecordV1

        public init(tracks: [UUID: CGRect], metrics: TrackMetrics, evidenceConfidence: ConfidenceRecordV1) {
            self.tracks = tracks
            self.metrics = metrics
            self.evidenceConfidence = evidenceConfidence
        }
    }

    public enum TracksDeviceError: Error, Sendable, Equatable {
        case unsupported
    }

    private let faceTracker: FaceDetectionService
    private var previousNonEmptyTrackIds: Set<UUID>?
    private var hasTrackedAtLeastOnce: Bool = false

    public init(faceTracker: FaceDetectionService = FaceDetectionService()) {
        self.faceTracker = faceTracker
    }

    public func warmUp() async throws {
        try await faceTracker.warmUp()
    }

    public func coolDown() async {
        await faceTracker.coolDown()
    }

    /// Track face-like objects across frames.
    /// - Returns: A map of Vision tracking UUID -> normalized rect (0..1), top-left origin.
    public func track(in pixelBuffer: CVPixelBuffer) async throws -> [UUID: CGRect] {
        return try await faceTracker.trackFaces(in: pixelBuffer)
    }

    /// Track plus deterministic metrics + governed EvidenceConfidence.
    ///
    /// This is the preferred API for Sprint 24a.
    public func trackResult(in pixelBuffer: CVPixelBuffer) async throws -> TrackResult {
        let tracks = try await track(in: pixelBuffer)

        let ids = Set(tracks.keys)
        let hasNow = !ids.isEmpty

        // Reacquire definition (v1): we previously had at least one stable non-empty track set,
        // and now we have tracks again, but none of the prior non-empty IDs persist.
        let reacquired: Bool = {
            guard hasNow else { return false }
            guard let prev = previousNonEmptyTrackIds, !prev.isEmpty else { return false }
            return prev.intersection(ids).isEmpty
        }()

        if hasNow {
            previousNonEmptyTrackIds = ids
            hasTrackedAtLeastOnce = true
        }

        var reasons: [ReasonCodeV1] = []
        if ids.isEmpty {
            reasons.append(.track_missing)
        }
        if reacquired {
            reasons.append(.track_reacquired)
        }
        if ids.count >= 4 {
            reasons.append(.track_ambiguous)
        }

        // Evidence score: start from presence, penalize reacquire and ambiguity.
        var score: Float = ids.isEmpty ? 0.0 : 1.0
        if reacquired { score *= 0.6 }
        if ids.count >= 4 { score *= 0.7 }

        // If we've previously tracked and now have nothing, treat as a weak-but-not-invalid signal.
        if ids.isEmpty && hasTrackedAtLeastOnce {
            score = max(score, 0.25)
        }

        let refs: [EvidenceRefV1] = [
            .metric("tracks.trackCount", value: Double(ids.count))
        ]

        let conf = ConfidenceRecordV1.evidence(
            score: score,
            sources: [.vision],
            reasons: reasons,
            evidenceRefs: refs
        )

        return TrackResult(
            tracks: tracks,
            metrics: TrackMetrics(trackCount: ids.count, reacquired: reacquired),
            evidenceConfidence: conf
        )
    }
}
