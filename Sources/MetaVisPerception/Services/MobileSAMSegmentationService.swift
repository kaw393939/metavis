import Foundation
import CoreGraphics
import CoreVideo
import MetaVisCore

/// Thin service wrapper around `MobileSAMDevice`.
///
/// Purpose: provide a stable, shared place to define a canonical `cacheKey` scheme
/// for interactive prompting (encode once, prompt many).
public actor MobileSAMSegmentationService: AIInferenceService {

    public let name = "MobileSAMSegmentationService"

    public struct CacheKey {
        /// Canonical cache key for a specific source + frame.
        ///
        /// Notes:
        /// - `timeSeconds` is quantized to 1/60000s to match common media timebases.
        /// - `sourceKey` should be stable across sessions for the same asset (e.g. file URL, assetID).
        public static func make(sourceKey: String, timeSeconds: Double, width: Int, height: Int) -> String {
            let t = timeSeconds.isFinite ? timeSeconds : 0.0
            let quantized = Int64((t * 60_000.0).rounded())
            return "mobilesam|v1|src=\(sourceKey)|t=\(quantized)|\(max(1, width))x\(max(1, height))"
        }

        /// Convenience overload that uses a stable content hash for the URL (rename/machine independent).
        ///
        /// Use this when you have a file URL and want cache hits across relinks.
        public static func make(url: URL, timeSeconds: Double, width: Int, height: Int) throws -> String {
            let sourceKey = try SourceContentHashV1.shared.contentHashHex(for: url)
            return make(sourceKey: sourceKey, timeSeconds: timeSeconds, width: width, height: height)
        }
    }

    private let device: MobileSAMDevice

    public init(options: MobileSAMDevice.Options = .init()) {
        self.device = MobileSAMDevice(options: options)
    }

    public func isSupported() async -> Bool {
        true
    }

    public func warmUp() async throws {
        try await device.warmUp()
    }

    public func coolDown() async {
        await device.coolDown()
    }

    public func segment(
        pixelBuffer: CVPixelBuffer,
        prompt: MobileSAMDevice.PointPrompt,
        cacheKey: String?
    ) async -> MobileSAMDevice.MobileSAMResult {
        await device.segment(pixelBuffer: pixelBuffer, prompt: prompt, cacheKey: cacheKey)
    }

    // Protocol conformance (generic interface is intentionally stubbed across services).
    public func infer<Request, Result>(request: Request) async throws -> Result where Request: AIInferenceRequest, Result: AIInferenceResult {
        throw MetaVisPerceptionError.unsupportedGenericInfer(
            service: name,
            requestType: String(describing: Request.self),
            resultType: String(describing: Result.self)
        )
    }
}
