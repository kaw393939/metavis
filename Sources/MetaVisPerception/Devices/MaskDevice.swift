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

    public struct Options: Sendable, Equatable {
        public enum Mode: Sendable, Equatable {
            /// Compute a fresh segmentation mask on every call.
            case everyFrame

            /// Compute a fresh segmentation mask on keyframes (by time), and propagate masks forward
            /// between keyframes using optical flow warping.
            ///
            /// This is the Sprint 24a sampling strategy (2–5 fps) for expensive segmentation.
            case keyframes(strideSeconds: Double)
        }

        public var mode: Mode

        public init(mode: Mode = .everyFrame) {
            self.mode = mode
        }
    }

    public struct MaskMetrics: Sendable, Equatable {
        /// Foreground coverage ratio in [0,1] computed from mean mask value / 255.
        public var coverage: Double

        /// Absolute delta in coverage since previous call, if any.
        public var coverageDelta: Double?

        /// Warp-based stability IoU against previous frame (downscaled), if available.
        public var stabilityIoU: Double?

        /// True when this call produced a fresh segmentation keyframe.
        public var isKeyframe: Bool

        public init(coverage: Double, coverageDelta: Double?, stabilityIoU: Double?, isKeyframe: Bool) {
            self.coverage = coverage
            self.coverageDelta = coverageDelta
            self.stabilityIoU = stabilityIoU
            self.isKeyframe = isKeyframe
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

    // Stability state (Sprint 24a): previous frame + previous mask at a small resolution.
    private let flowDevice = FlowDevice()
    private var previousFrameSmallBGRA: CVPixelBuffer?
    private var previousMaskSmall: CVPixelBuffer?

    // Keyframe / propagation state.
    private let options: Options
    private var lastKeyframeTimeSeconds: Double?
    private var previousMaskFull: CVPixelBuffer?

    public init(options: Options = Options()) {
        self.options = options
    }

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
        previousCoverage = nil
        previousFrameSmallBGRA = nil
        previousMaskSmall = nil
        lastKeyframeTimeSeconds = nil
        previousMaskFull = nil
        await flowDevice.coolDown()
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
        return try await generateMaskResult(in: pixelBuffer, kind: kind, timeSeconds: nil)
    }

    /// Generate a mask result using an optional timestamp (seconds).
    ///
    /// When `options.mode` is `.keyframes`, providing time enables deterministic keyframe sampling.
    public func generateMaskResult(in pixelBuffer: CVPixelBuffer, kind: Kind = .foreground, timeSeconds: Double?) async throws -> MaskResult {
        let nowT = timeSeconds

        let shouldKeyframe: Bool = {
            switch options.mode {
            case .everyFrame:
                return true
            case .keyframes(let strideSeconds):
                let stride = max(0.001, strideSeconds)
                guard let t = nowT else { return true }
                guard let last = lastKeyframeTimeSeconds else { return true }
                return (t - last) >= stride - 0.000001
            }
        }()

        let mask: CVPixelBuffer
        let isKeyframe: Bool

        if shouldKeyframe {
            mask = try await generateMask(in: pixelBuffer, kind: kind)
            isKeyframe = true
        } else if let prevMaskFull = previousMaskFull, let prevFrameSmall = previousFrameSmallBGRA {
            // Propagate previous mask forward using flow (computed on a small grid).
            let smallW = 160
            let smallH = 90
            let currentFrameSmall = try downscaleToBGRA(pixelBuffer, width: smallW, height: smallH)
            let flowRes = try await flowDevice.flowResult(previous: prevFrameSmall, current: currentFrameSmall)

            // IMPORTANT: flow is computed on the small grid, so the mask we warp must match that grid.
            // Warp small -> then upscale back to full size.
            let prevMaskSmallForProp = try downscaleToOneComponent8(prevMaskFull, width: smallW, height: smallH)
            let warpedSmall = warpMaskNearest(prevMask: prevMaskSmallForProp, flow: flowRes.flow)
            mask = try upscaleOneComponent8(warpedSmall, width: CVPixelBufferGetWidth(prevMaskFull), height: CVPixelBufferGetHeight(prevMaskFull))
            isKeyframe = false
        } else {
            // No prior state; fall back to a keyframe.
            mask = try await generateMask(in: pixelBuffer, kind: kind)
            isKeyframe = true
        }

        let coverage = meanByteValue(mask) / 255.0
        let delta: Double? = previousCoverage.map { abs(coverage - $0) }
        previousCoverage = coverage

        // Compute warp-based stability IoU on a downscaled grid.
        // Only compute a meaningful IoU when we have a fresh current mask (keyframe).
        let stability: Double? = isKeyframe
            ? (try await computeStabilityIoU(previousFrame: previousFrameSmallBGRA, previousMask: previousMaskSmall, currentFrame: pixelBuffer, currentMask: mask))
            : nil

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

        // Primary stability contract: warp-IoU below threshold.
        if let stability, stability.isFinite, stability > 0.000001, stability < 0.85 {
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
        var score = max(0.0, min(1.0, coverageScore * (1.0 - instabilityPenalty)))
        if reasons.contains(.mask_unstable_iou) {
            score = min(score, 0.85)
        }

        // If we're in propagation mode (not a keyframe), slightly reduce confidence to reflect drift risk.
        if !isKeyframe {
            score = min(score, 0.90)
        }

        let refs: [EvidenceRefV1] = [
            .metric("mask.coverage", value: coverage),
        ]
        + (delta.map { [.metric("mask.coverageDelta", value: $0)] } ?? [])
        + (stability.map { [.metric("mask.stabilityIoU", value: $0)] } ?? [])
        + [.metric("mask.isKeyframe", value: isKeyframe ? 1.0 : 0.0)]

        let conf = ConfidenceRecordV1.evidence(
            score: score,
            sources: [.vision],
            reasons: reasons,
            evidenceRefs: refs
        )

        // Update keyframe state after building the result.
        if isKeyframe, let t = nowT {
            lastKeyframeTimeSeconds = t
        }
        previousMaskFull = mask

        return MaskResult(
            mask: mask,
            metrics: MaskMetrics(coverage: coverage, coverageDelta: delta, stabilityIoU: stability, isKeyframe: isKeyframe),
            evidenceConfidence: conf
        )
    }

    private func computeStabilityIoU(
        previousFrame: CVPixelBuffer?,
        previousMask: CVPixelBuffer?,
        currentFrame: CVPixelBuffer,
        currentMask: CVPixelBuffer
    ) async throws -> Double? {
        // Downscale to keep runtime stable and fast.
        let smallW = 160
        let smallH = 90

        let currentFrameSmall = try downscaleToBGRA(currentFrame, width: smallW, height: smallH)
        let currentMaskSmall = try downscaleToOneComponent8(currentMask, width: smallW, height: smallH)

        defer {
            // Update state deterministically after computation.
            self.previousFrameSmallBGRA = currentFrameSmall
            self.previousMaskSmall = currentMaskSmall
        }

        guard let previousFrame, let previousMask else {
            return nil
        }

        // Flow can fail on some configurations; treat as missing stability metric.
        let flowRes: FlowDevice.FlowResult
        do {
            flowRes = try await flowDevice.flowResult(previous: previousFrame, current: currentFrameSmall)
        } catch {
            return nil
        }

        // If flow indicates a likely cut/mismatch, force instability.
        if flowRes.metrics.meanMagnitude > 25.0 {
            return 0.0
        }

        let warpedPrev = warpMaskNearest(prevMask: previousMask, flow: flowRes.flow)
        return iouBinary(maskA: warpedPrev, maskB: currentMaskSmall)
    }

    private func downscaleToBGRA(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let outPB = out else {
            throw MaskDeviceError.invalidPixelFormat
        }

        let img = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = img.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(img.extent.width), y: CGFloat(height) / CGFloat(img.extent.height)))
        ciContext.render(scaled, to: outPB)
        return outPB
    }

    private func downscaleToOneComponent8(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
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
        let scaled = img.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(img.extent.width), y: CGFloat(height) / CGFloat(img.extent.height)))
        ciContext.render(scaled, to: outPB)
        return outPB
    }

    private func upscaleOneComponent8(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
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
        let scaled = img.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(img.extent.width), y: CGFloat(height) / CGFloat(img.extent.height)))
        ciContext.render(scaled, to: outPB)
        return outPB
    }

    /// Warps a OneComponent8 mask forward using dense flow (TwoComponent32Float) with nearest-neighbor sampling.
    private func warpMaskNearest(prevMask: CVPixelBuffer, flow: CVPixelBuffer) -> CVPixelBuffer {
        let w = CVPixelBufferGetWidth(prevMask)
        let h = CVPixelBufferGetHeight(prevMask)

        // Safety: flow and mask must match dimensions for direct indexing.
        if CVPixelBufferGetWidth(flow) != w || CVPixelBufferGetHeight(flow) != h {
            return prevMask
        }

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_OneComponent8),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &out)
        let outPB = out!

        CVPixelBufferLockBaseAddress(prevMask, .readOnly)
        CVPixelBufferLockBaseAddress(flow, .readOnly)
        CVPixelBufferLockBaseAddress(outPB, [])
        defer {
            CVPixelBufferUnlockBaseAddress(outPB, [])
            CVPixelBufferUnlockBaseAddress(flow, .readOnly)
            CVPixelBufferUnlockBaseAddress(prevMask, .readOnly)
        }

        guard let maskBase = CVPixelBufferGetBaseAddress(prevMask),
              let flowBase = CVPixelBufferGetBaseAddress(flow),
              let outBase = CVPixelBufferGetBaseAddress(outPB) else {
            return outPB
        }

        let maskBpr = CVPixelBufferGetBytesPerRow(prevMask)
        let flowBpr = CVPixelBufferGetBytesPerRow(flow)
        let outBpr = CVPixelBufferGetBytesPerRow(outPB)

        // Initialize output to 0.
        for y in 0..<h {
            memset(outBase.advanced(by: y * outBpr), 0, w)
        }

        // For each pixel in previous mask, send it forward by flow (dx, dy).
        // (Forward splat) keeps edges sharp for binary mask stability estimation.
        let flowFmt = CVPixelBufferGetPixelFormatType(flow)
        let is16F = (flowFmt == kCVPixelFormatType_TwoComponent16Half)
        let is32F = (flowFmt == kCVPixelFormatType_TwoComponent32Float)
        if !(is16F || is32F) { return outPB }

        for y in 0..<h {
            let maskRow = maskBase.advanced(by: y * maskBpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                let v = maskRow[x]
                if v == 0 { continue }

                let i = x * 2
                let dx: Double
                let dy: Double
                if is16F {
                    let flowRow = flowBase.advanced(by: y * flowBpr).assumingMemoryBound(to: UInt16.self)
                    dx = Double(Float(Float16(bitPattern: flowRow[i])))
                    dy = Double(Float(Float16(bitPattern: flowRow[i + 1])))
                } else {
                    let flowRow = flowBase.advanced(by: y * flowBpr).assumingMemoryBound(to: Float.self)
                    dx = Double(flowRow[i])
                    dy = Double(flowRow[i + 1])
                }
                if !dx.isFinite || !dy.isFinite { continue }

                let nx = Int((Double(x) + dx).rounded())
                let ny = Int((Double(y) + dy).rounded())
                if nx < 0 || nx >= w || ny < 0 || ny >= h { continue }

                let outRow = outBase.advanced(by: ny * outBpr).assumingMemoryBound(to: UInt8.self)
                outRow[nx] = 255
            }
        }

        return outPB
    }

    private func iouBinary(maskA: CVPixelBuffer, maskB: CVPixelBuffer) -> Double {
        let w = CVPixelBufferGetWidth(maskA)
        let h = CVPixelBufferGetHeight(maskA)
        guard w == CVPixelBufferGetWidth(maskB), h == CVPixelBufferGetHeight(maskB) else { return 0.0 }
        guard CVPixelBufferGetPixelFormatType(maskA) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetPixelFormatType(maskB) == kCVPixelFormatType_OneComponent8 else { return 0.0 }

        CVPixelBufferLockBaseAddress(maskA, .readOnly)
        CVPixelBufferLockBaseAddress(maskB, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(maskB, .readOnly)
            CVPixelBufferUnlockBaseAddress(maskA, .readOnly)
        }

        guard let aBase = CVPixelBufferGetBaseAddress(maskA), let bBase = CVPixelBufferGetBaseAddress(maskB) else { return 0.0 }
        let aBpr = CVPixelBufferGetBytesPerRow(maskA)
        let bBpr = CVPixelBufferGetBytesPerRow(maskB)

        var inter: UInt64 = 0
        var uni: UInt64 = 0

        for y in 0..<h {
            let ar = aBase.advanced(by: y * aBpr).assumingMemoryBound(to: UInt8.self)
            let br = bBase.advanced(by: y * bBpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                let av = ar[x] > 127
                let bv = br[x] > 127
                if av && bv { inter += 1 }
                if av || bv { uni += 1 }
            }
        }

        if uni == 0 { return 1.0 }
        return Double(inter) / Double(uni)
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
