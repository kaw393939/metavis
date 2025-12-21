import Foundation
import CoreVideo
import MetaVisCore

/// Tier-0 depth device stream.
///
/// Purpose: provide a depth map aligned to the input frame when available, or emit explicit
/// "missing"/"invalid" confidence with governed reason codes.
///
/// This implementation is intentionally conservative on macOS: it does not attempt to synthesize
/// depth from RGB; it only validates and summarizes provided depth samples.
public actor DepthDevice {

    public struct DepthMetrics: Sendable, Equatable {
        /// Ratio of pixels considered valid depth (finite, >0, within a reasonable range).
        public var validPixelRatio: Double

        /// Minimum valid depth in meters.
        public var minDepthMeters: Double?

        /// Maximum valid depth in meters.
        public var maxDepthMeters: Double?

        public init(validPixelRatio: Double, minDepthMeters: Double?, maxDepthMeters: Double?) {
            self.validPixelRatio = validPixelRatio
            self.minDepthMeters = minDepthMeters
            self.maxDepthMeters = maxDepthMeters
        }
    }

    public struct DepthResult: @unchecked Sendable, Equatable {
        public var depth: CVPixelBuffer?
        public var confidence: CVPixelBuffer?
        public var metrics: DepthMetrics
        public var evidenceConfidence: ConfidenceRecordV1

        public init(depth: CVPixelBuffer?, confidence: CVPixelBuffer?, metrics: DepthMetrics, evidenceConfidence: ConfidenceRecordV1) {
            self.depth = depth
            self.confidence = confidence
            self.metrics = metrics
            self.evidenceConfidence = evidenceConfidence
        }
    }

    public enum DepthDeviceError: Error, Sendable, Equatable {
        case invalidPixelFormat
    }

    public init() {}

    public func warmUp() async throws {
        // No-op (placeholder for future model/sidecar warmup).
    }

    public func coolDown() async {
        // No-op.
    }

    /// Compute depth metrics and governed EvidenceConfidence.
    ///
    /// - Parameters:
    ///   - rgbFrame: The associated RGB frame (used for alignment sanity checks).
    ///   - depthSample: Optional depth pixel buffer (meters) aligned to `rgbFrame`.
    ///   - confidenceSample: Optional confidence map (0..255).
    public func depthResult(
        in rgbFrame: CVPixelBuffer,
        depthSample: CVPixelBuffer?,
        confidenceSample: CVPixelBuffer? = nil
    ) async throws -> DepthResult {
        guard let depth = depthSample else {
            let metrics = DepthMetrics(validPixelRatio: 0.0, minDepthMeters: nil, maxDepthMeters: nil)
            let conf = ConfidenceRecordV1.evidence(
                score: 0.0,
                sources: [.vision],
                reasons: [.depth_missing],
                evidenceRefs: [
                    .metric("depth.validPixelRatio", value: metrics.validPixelRatio)
                ]
            )
            return DepthResult(depth: nil, confidence: nil, metrics: metrics, evidenceConfidence: conf)
        }

        // Basic alignment sanity check.
        let rgbW = CVPixelBufferGetWidth(rgbFrame)
        let rgbH = CVPixelBufferGetHeight(rgbFrame)
        let depthW = CVPixelBufferGetWidth(depth)
        let depthH = CVPixelBufferGetHeight(depth)
        let dimsMatch = (rgbW == depthW && rgbH == depthH)

        let fmt = CVPixelBufferGetPixelFormatType(depth)
        let isDepthFloat16 = (fmt == kCVPixelFormatType_DepthFloat16)
        let isDepthFloat32 = (fmt == kCVPixelFormatType_DepthFloat32)
        let isOneComponent32F = (fmt == kCVPixelFormatType_OneComponent32Float)

        guard isDepthFloat16 || isDepthFloat32 || isOneComponent32F else {
            throw DepthDeviceError.invalidPixelFormat
        }

        let metrics = computeMetrics(depth: depth, is16F: isDepthFloat16)

        var reasons: [ReasonCodeV1] = []
        if !dimsMatch {
            reasons.append(.depth_invalid_range)
        }
        if metrics.validPixelRatio < 0.01 {
            // Distinguish "no depth provided" from "depth provided but values look wrong".
            if let minD = metrics.minDepthMeters, let maxD = metrics.maxDepthMeters {
                if minD <= 0.0 || maxD > 50.0 {
                    reasons.append(.depth_invalid_range)
                } else {
                    reasons.append(.depth_missing)
                }
            } else {
                reasons.append(.depth_missing)
            }
        } else {
            // Flag obviously invalid ranges.
            if let minD = metrics.minDepthMeters, minD <= 0.0 { reasons.append(.depth_invalid_range) }
            if let maxD = metrics.maxDepthMeters, maxD > 50.0 { reasons.append(.depth_invalid_range) }
            if metrics.minDepthMeters == nil || metrics.maxDepthMeters == nil {
                reasons.append(.depth_invalid_range)
            }
        }

        // Score is supporting detail; reasons are primary.
        // Conservative: if missing/invalid, score is forced low.
        var score: Float
        if reasons.contains(.depth_missing) {
            score = 0.0
        } else if reasons.contains(.depth_invalid_range) {
            score = 0.15
        } else {
            // Prefer high confidence when a large fraction of pixels are valid.
            score = Float(max(0.0, min(1.0, metrics.validPixelRatio)))
            score = max(0.60, min(0.95, score))
        }

        let refs: [EvidenceRefV1] = [
            .metric("depth.validPixelRatio", value: metrics.validPixelRatio)
        ]
        + (metrics.minDepthMeters.map { [.metric("depth.minDepthMeters", value: $0)] } ?? [])
        + (metrics.maxDepthMeters.map { [.metric("depth.maxDepthMeters", value: $0)] } ?? [])

        let conf = ConfidenceRecordV1.evidence(
            score: score,
            sources: [.vision],
            reasons: reasons,
            evidenceRefs: refs
        )

        // Accept confidenceSample only if it is the expected pixel format.
        let confPB: CVPixelBuffer?
        if let c = confidenceSample, CVPixelBufferGetPixelFormatType(c) == kCVPixelFormatType_OneComponent8 {
            confPB = c
        } else {
            confPB = nil
        }

        return DepthResult(depth: depth, confidence: confPB, metrics: metrics, evidenceConfidence: conf)
    }

    private func computeMetrics(depth: CVPixelBuffer, is16F: Bool) -> DepthMetrics {
        // Treat non-finite values as invalid. Track observed finite min/max even if values are
        // out of the "valid" range so callers can distinguish "missing" from "present but invalid".
        let maxReasonableMeters: Float = 50.0

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depth) else {
            return DepthMetrics(validPixelRatio: 0.0, minDepthMeters: nil, maxDepthMeters: nil)
        }

        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        let bpr = CVPixelBufferGetBytesPerRow(depth)

        var valid: Int64 = 0
        let total: Int64 = Int64(max(1, w * h))

        var observedMin: Float = .infinity
        var observedMax: Float = -.infinity
        var finiteCount: Int64 = 0

        if is16F {
            for y in 0..<h {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt16.self)
                for x in 0..<w {
                    let f = Float(Float16(bitPattern: row[x]))
                    if !f.isFinite { continue }
                    finiteCount += 1
                    if f < observedMin { observedMin = f }
                    if f > observedMax { observedMax = f }
                    if f > 0.0, f <= maxReasonableMeters {
                        valid += 1
                    }
                }
            }
        } else {
            for y in 0..<h {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float.self)
                for x in 0..<w {
                    let f = row[x]
                    if !f.isFinite { continue }
                    finiteCount += 1
                    if f < observedMin { observedMin = f }
                    if f > observedMax { observedMax = f }
                    if f > 0.0, f <= maxReasonableMeters {
                        valid += 1
                    }
                }
            }
        }

        let ratio = Double(valid) / Double(total)
        if finiteCount == 0 {
            return DepthMetrics(validPixelRatio: ratio, minDepthMeters: nil, maxDepthMeters: nil)
        }

        return DepthMetrics(validPixelRatio: ratio, minDepthMeters: Double(observedMin), maxDepthMeters: Double(observedMax))
    }
}
