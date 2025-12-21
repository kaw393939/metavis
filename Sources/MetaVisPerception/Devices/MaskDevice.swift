import Foundation
import Vision
import CoreVideo
import CoreImage
import MetaVisCore

/// Tier-0 segmentation device stream.
///
/// Goal: produce a GPU-friendly 8-bit mask (`kCVPixelFormatType_OneComponent8`) for foreground/person.
///
/// Notes:
/// - Prefer `VNGenerateForegroundInstanceMaskRequest` when available.
/// - Fall back to `VNGeneratePersonSegmentationRequest` (coarser but broadly available).
public actor MaskDevice {

    public struct MaskMetrics: Sendable, Equatable {
        /// Foreground coverage ratio in [0,1] computed from mean mask value / 255.
        public var coverage: Double

        /// Absolute delta in coverage since previous call, if any.
        public var coverageDelta: Double?

        public init(coverage: Double, coverageDelta: Double?) {
            self.coverage = coverage
            self.coverageDelta = coverageDelta
        }
    }

    public struct MaskResult: @unchecked Sendable, Equatable {
        public var mask: CVPixelBuffer
        public var metrics: MaskMetrics
        public var evidenceConfidence: ConfidenceRecordV1

        public init(mask: CVPixelBuffer, metrics: MaskMetrics, evidenceConfidence: ConfidenceRecordV1) {
            self.mask = mask
            self.metrics = metrics
            self.evidenceConfidence = evidenceConfidence
        }
    }

    public enum Kind: Sendable {
        /// Foreground instance / subject (preferred).
        case foreground
        /// People/person mask (fallback).
        case person
    }

    public enum MaskDeviceError: Error, Sendable, Equatable {
        case unsupported
        case noResult
        case invalidPixelFormat
    }

    private var foregroundRequest: AnyObject?
    private var personRequest: VNGeneratePersonSegmentationRequest?
    private let ciContext = CIContext(options: nil)
    private var previousCoverage: Double?

    public init() {}

    public func warmUp(kind: Kind = .foreground) async throws {
        switch kind {
        case .foreground:
            if foregroundRequest == nil {
                if #available(macOS 14.0, iOS 17.0, *) {
                    let req = VNGenerateForegroundInstanceMaskRequest()
                    foregroundRequest = req
                } else {
                    // Will fall back to person segmentation at inference-time.
                    foregroundRequest = nil
                }
            }
        case .person:
            break
        }

        if personRequest == nil {
            let req = VNGeneratePersonSegmentationRequest()
            req.qualityLevel = .balanced
            req.outputPixelFormat = kCVPixelFormatType_OneComponent8
            personRequest = req
        }
    }

    public func coolDown() async {
        foregroundRequest = nil
        personRequest = nil
    }

    /// Generate a mask for the given frame.
    /// - Returns: OneComponent8 mask pixel buffer (0=background, 255=foreground/person)
    public func generateMask(in pixelBuffer: CVPixelBuffer, kind: Kind = .foreground) async throws -> CVPixelBuffer {
        if foregroundRequest == nil && personRequest == nil {
            try await warmUp(kind: kind)
        }

        // 1) Preferred: foreground instance mask.
        if kind == .foreground {
            if #available(macOS 14.0, iOS 17.0, *), let req = foregroundRequest as? VNGenerateForegroundInstanceMaskRequest {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
                try handler.perform([req])

                guard let obs = req.results?.first as? VNInstanceMaskObservation else {
                    // fall back below
                    return try await generatePersonMask(in: pixelBuffer)
                }

                // Create a scaled mask for all detected instances.
                let instances = obs.allInstances
                let maskPB = try obs.generateScaledMaskForImage(forInstances: instances, from: handler)

                return try normalizeToOneComponent8(maskPB)
            }
        }

        // 2) Fallback: person segmentation.
        return try await generatePersonMask(in: pixelBuffer)
    }

    /// Generate a mask plus deterministic metrics + governed EvidenceConfidence.
    ///
    /// This is the preferred API for Sprint 24a.
    public func generateMaskResult(in pixelBuffer: CVPixelBuffer, kind: Kind = .foreground) async throws -> MaskResult {
        let mask = try await generateMask(in: pixelBuffer, kind: kind)
        let coverage = meanByteValue(mask) / 255.0
        let delta: Double? = previousCoverage.map { abs(coverage - $0) }
        previousCoverage = coverage

        var reasons: [ReasonCodeV1] = []

        // Deterministic heuristics (v1):
        // - Very low coverage is likely unusable for subject lift.
        if coverage < 0.02 {
            reasons.append(.mask_low_coverage)
        }

        // - Large coverage swings frame-to-frame are treated as instability.
        if let delta, delta > 0.15 {
            reasons.append(.mask_unstable_iou)
        }

        // Evidence score: base on coverage and penalize instability.
        // Note: score is supporting; grade + reasons are primary.
        let coverageScore = max(0.0, min(1.0, Float(coverage * 3.0)))
        let instabilityPenalty: Float
        if let delta {
            instabilityPenalty = max(0.0, min(1.0, Float(delta / 0.30)))
        } else {
            instabilityPenalty = 0.0
        }
        let score = max(0.0, min(1.0, coverageScore * (1.0 - instabilityPenalty)))

        let refs: [EvidenceRefV1] = [
            .metric("mask.coverage", value: coverage),
        ] + (delta.map { [.metric("mask.coverageDelta", value: $0)] } ?? [])

        let conf = ConfidenceRecordV1.evidence(
            score: score,
            sources: [.vision],
            reasons: reasons,
            evidenceRefs: refs
        )

        return MaskResult(
            mask: mask,
            metrics: MaskMetrics(coverage: coverage, coverageDelta: delta),
            evidenceConfidence: conf
        )
    }

    private func generatePersonMask(in pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        if personRequest == nil {
            try await warmUp(kind: .person)
        }
        guard let req = personRequest else {
            throw MaskDeviceError.unsupported
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([req])

        guard let pb = req.results?.first?.pixelBuffer else {
            throw MaskDeviceError.noResult
        }
        let fmt = CVPixelBufferGetPixelFormatType(pb)
        if fmt == kCVPixelFormatType_OneComponent8 {
            return pb
        }
        return try normalizeToOneComponent8(pb)
    }

    private func normalizeToOneComponent8(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_OneComponent8),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let outPB = out else {
            throw MaskDeviceError.invalidPixelFormat
        }

        let img = CIImage(cvPixelBuffer: pixelBuffer)
        ciContext.render(img, to: outPB)
        return outPB
    }

    private func meanByteValue(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var sum: UInt64 = 0
        for y in 0..<height {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                sum += UInt64(row[x])
            }
        }

        let denom = max(1, width * height)
        return Double(sum) / Double(denom)
    }
}
