import Foundation
import CoreVideo
import Vision
import MetaVisCore

/// Tier-0 optical flow device stream.
///
/// Produces a dense flow field between two frames. Used for warping masks forward
/// to compute stability (IoU) and to support future mask propagation.
public actor FlowDevice {

    public struct FlowMetrics: Sendable, Equatable {
        /// Mean magnitude of flow vectors (in pixels) over a subsample grid.
        public var meanMagnitude: Double

        public init(meanMagnitude: Double) {
            self.meanMagnitude = meanMagnitude
        }
    }

    public struct FlowResult: @unchecked Sendable, Equatable {
        public var flow: CVPixelBuffer
        public var metrics: FlowMetrics
        public var evidenceConfidence: ConfidenceRecordV1

        public init(flow: CVPixelBuffer, metrics: FlowMetrics, evidenceConfidence: ConfidenceRecordV1) {
            self.flow = flow
            self.metrics = metrics
            self.evidenceConfidence = evidenceConfidence
        }
    }

    public enum FlowDeviceError: Error, Sendable, Equatable {
        case unsupported
        case noResult
    }

    private var flowRequest: AnyObject?

    public init() {}

    public func warmUp() async throws {
        if flowRequest != nil { return }
        if #available(macOS 12.0, iOS 15.0, *) {
            // We keep a configured template request around, but create a fresh request per call
            // because VNGenerateOpticalFlowRequest does not support updating the targeted buffer.
            let req = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: dummyBGRA(width: 32, height: 32))
            req.computationAccuracy = .low
            req.keepNetworkOutput = false
            // Sprint 24a contract prefers 16F for bandwidth/perf on Apple Silicon.
            req.outputPixelFormat = kCVPixelFormatType_TwoComponent16Half
            flowRequest = req
        } else {
            flowRequest = nil
        }
    }

    public func coolDown() async {
        flowRequest = nil
    }

    /// Computes optical flow from `previous` -> `current`.
    ///
    /// Both buffers should be 32BGRA for best compatibility.
    public func flowResult(previous: CVPixelBuffer, current: CVPixelBuffer) async throws -> FlowResult {
        if flowRequest == nil {
            try await warmUp()
        }
        guard #available(macOS 12.0, iOS 15.0, *), let template = flowRequest as? VNGenerateOpticalFlowRequest else {
            throw FlowDeviceError.unsupported
        }

        let req = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: current)
        req.computationAccuracy = template.computationAccuracy
        req.keepNetworkOutput = template.keepNetworkOutput
        req.outputPixelFormat = template.outputPixelFormat

        let handler = VNImageRequestHandler(cvPixelBuffer: previous, options: [:])
        try handler.perform([req])

        guard let obs = req.results?.first as? VNPixelBufferObservation else {
            throw FlowDeviceError.noResult
        }

        let pb = obs.pixelBuffer

        let meanMag = Self.meanFlowMagnitude(pb, step: 8)

        var reasons: [ReasonCodeV1] = []
        // Very large mean flow is a proxy for a cut / mismatch; mark as unstable evidence.
        if meanMag > 25.0 {
            reasons.append(.flow_unstable)
        }

        // Score decays as mean magnitude grows (heuristic; reasons are primary).
        let score = max(0.0, min(1.0, Float(1.0 - (meanMag / 40.0))))

        let conf = ConfidenceRecordV1.evidence(
            score: score,
            sources: [.vision],
            reasons: reasons,
            evidenceRefs: [
                .metric("flow.meanMagnitude", value: meanMag)
            ]
        )

        return FlowResult(
            flow: pb,
            metrics: FlowMetrics(meanMagnitude: meanMag),
            evidenceConfidence: conf
        )
    }

    private static func meanFlowMagnitude(_ flow: CVPixelBuffer, step: Int) -> Double {
        let w = CVPixelBufferGetWidth(flow)
        let h = CVPixelBufferGetHeight(flow)
        let fmt = CVPixelBufferGetPixelFormatType(flow)

        guard w > 0, h > 0 else { return 0.0 }

        CVPixelBufferLockBaseAddress(flow, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(flow) else { return 0.0 }
        let bpr = CVPixelBufferGetBytesPerRow(flow)

        var sum: Double = 0.0
        var count: Int = 0

        func add(dx: Double, dy: Double) {
            let mag = (dx * dx + dy * dy).squareRoot()
            if mag.isFinite {
                sum += mag
                count += 1
            }
        }

        if fmt == kCVPixelFormatType_TwoComponent16Half {
            for y in stride(from: 0, to: h, by: max(1, step)) {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt16.self)
                for x in stride(from: 0, to: w, by: max(1, step)) {
                    let i = x * 2
                    let dx = Double(Float(Float16(bitPattern: row[i])))
                    let dy = Double(Float(Float16(bitPattern: row[i + 1])))
                    add(dx: dx, dy: dy)
                }
            }
        } else if fmt == kCVPixelFormatType_TwoComponent32Float {
            for y in stride(from: 0, to: h, by: max(1, step)) {
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float.self)
                for x in stride(from: 0, to: w, by: max(1, step)) {
                    let i = x * 2
                    let dx = Double(row[i])
                    let dy = Double(row[i + 1])
                    add(dx: dx, dy: dy)
                }
            }
        } else {
            // Unknown/unsupported format; avoid crashing.
            return 0.0
        }

        return count > 0 ? (sum / Double(count)) : 0.0
    }

    @available(macOS 12.0, iOS 15.0, *)
    private func dummyBGRA(width: Int, height: Int) -> CVPixelBuffer {
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        return out!
    }
}
