import Foundation
import CoreVideo
import CoreGraphics
import MetaVisCore

/// Convenience pipeline: detect mouth ROI via FacePartsDevice and apply mouth-local whitening.
public enum FacePartsWhitening {

    public struct Result: @unchecked Sendable, Equatable {
        public var outputFrame: CVPixelBuffer
        public var didApply: Bool
        public var mouthRectTopLeft: CGRect?
        public var evidenceConfidence: ConfidenceRecordV1

        public init(outputFrame: CVPixelBuffer, didApply: Bool, mouthRectTopLeft: CGRect?, evidenceConfidence: ConfidenceRecordV1) {
            self.outputFrame = outputFrame
            self.didApply = didApply
            self.mouthRectTopLeft = mouthRectTopLeft
            self.evidenceConfidence = evidenceConfidence
        }
    }

    /// Applies whitening when a mouth ROI is available.
    ///
    /// - Parameters:
    ///   - frame: Input 32BGRA frame.
    ///   - strength: [0,1]
    ///   - facePartsDevice: Optional injected device to reuse across frames.
    public static func apply(
        frame: CVPixelBuffer,
        strength: Double,
        facePartsDevice: FacePartsDevice? = nil
    ) async -> Result {
        let device = facePartsDevice ?? FacePartsDevice()
        do {
            try await device.warmUp()
            let parts = try await device.facePartsResult(in: frame)

            guard let mouthRect = parts.mouthRectTopLeft else {
                return Result(
                    outputFrame: frame,
                    didApply: false,
                    mouthRectTopLeft: nil,
                    evidenceConfidence: parts.evidenceConfidence
                )
            }

            do {
                let out = try MouthWhitening.apply(in: frame, mouthRectTopLeft: mouthRect, strength: strength)
                return Result(
                    outputFrame: out,
                    didApply: true,
                    mouthRectTopLeft: mouthRect,
                    evidenceConfidence: parts.evidenceConfidence
                )
            } catch {
                // Whitening failed; keep original frame but surface a governed failure reason.
                var mergedReasons = parts.evidenceConfidence.reasons
                mergedReasons.append(.faceparts_infer_failed)
                let merged = ConfidenceRecordV1.evidence(
                    score: min(parts.evidenceConfidence.score, 0.20),
                    sources: parts.evidenceConfidence.sources.isEmpty ? [.vision] : parts.evidenceConfidence.sources,
                    reasons: mergedReasons,
                    evidenceRefs: parts.evidenceConfidence.evidenceRefs + [.metric("mouthWhitening.applied", value: 0.0)]
                )
                return Result(
                    outputFrame: frame,
                    didApply: false,
                    mouthRectTopLeft: mouthRect,
                    evidenceConfidence: merged
                )
            }
        } catch {
            let conf = ConfidenceRecordV1.evidence(
                score: 0.0,
                sources: [.vision],
                reasons: [.faceparts_infer_failed],
                evidenceRefs: [.metric("mouthWhitening.applied", value: 0.0)]
            )
            return Result(outputFrame: frame, didApply: false, mouthRectTopLeft: nil, evidenceConfidence: conf)
        }
    }
}
