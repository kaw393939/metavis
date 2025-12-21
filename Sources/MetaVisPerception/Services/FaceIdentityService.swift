import Foundation
import Vision
import CoreImage
import MetaVisCore

/// A service that generates Face Identifiers (FacePrints) for re-identification.
public actor FaceIdentityService: AIInferenceService {
    
    public let name = "FaceIdentityService"
    
    // We reuse requests to keep things fast.
    // Note: We intentionally do not rely on `VNGenerateFaceprintRequest` here because it is not
    // consistently available across SDK/toolchains. Instead we compute a deterministic perceptual
    // fingerprint (aHash) over a downsampled face crop.
    private var identityRequest: VNDetectFaceRectanglesRequest?

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    public init() {}
    
    public func isSupported() async -> Bool {
        return true
    }
    
    public func warmUp() async throws {
        if identityRequest == nil {
            identityRequest = VNDetectFaceRectanglesRequest()
        }
    }
    
    public func coolDown() async {
        identityRequest = nil
    }
    
    public struct FacePrintV1: Codable, Sendable, Equatable {
        public var rect: CGRect
        public var hash64: UInt64

        public init(rect: CGRect, hash64: UInt64) {
            self.rect = rect
            self.hash64 = hash64
        }
    }

    /// Computes deterministic face fingerprints for all detected faces in the frame.
    ///
    /// Output rects are normalized to a top-left origin coordinate system (to match MetaVis standard).
    public func computeFacePrints(in pixelBuffer: CVPixelBuffer, maxFaces: Int = 6) async throws -> [FacePrintV1] {
        if identityRequest == nil {
            try await warmUp()
        }

        guard let request = identityRequest else { return [] }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        guard let faces = request.results, !faces.isEmpty else { return [] }

        let clampedFaces = faces.prefix(max(0, maxFaces))
        var out: [FacePrintV1] = []
        out.reserveCapacity(clampedFaces.count)

        for f in clampedFaces {
            let rect = normalizeObservation(f)
            if let hash = computeAverageHash64(pixelBuffer: pixelBuffer, normalizedRectTopLeft: rect) {
                out.append(FacePrintV1(rect: rect, hash64: hash))
            }
        }

        return out
    }

    /// Convenience: returns the first face print (if any).
    public func computeFacePrint(in pixelBuffer: CVPixelBuffer) async throws -> FacePrintV1? {
        return try await computeFacePrints(in: pixelBuffer, maxFaces: 1).first
    }

    // MARK: - Deterministic hashing

    /// Computes a 64-bit average hash (aHash) from 8×8 luma values.
    ///
    /// This is pure + deterministic and intentionally testable.
    public static func averageHash64(fromLuma8x8 luma: [UInt8]) -> UInt64 {
        precondition(luma.count == 64, "Expected 8x8 = 64 luma samples")

        var sum: Int = 0
        for v in luma { sum += Int(v) }
        let avg = sum / 64

        var hash: UInt64 = 0
        for i in 0..<64 {
            // Set bit when pixel >= average.
            if Int(luma[i]) >= avg {
                hash |= (UInt64(1) << UInt64(i))
            }
        }
        return hash
    }

    private func computeAverageHash64(pixelBuffer: CVPixelBuffer, normalizedRectTopLeft: CGRect) -> UInt64? {
        let clamped = normalizedRectTopLeft
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard clamped.width > 0.0001, clamped.height > 0.0001 else { return nil }

        // Convert normalized top-left rect into pixel coordinates. PixelBuffer origin is top-left.
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let px = CGFloat(width) * clamped.origin.x
        let py = CGFloat(height) * clamped.origin.y
        let pw = CGFloat(width) * clamped.width
        let ph = CGFloat(height) * clamped.height

        let cropRect = CGRect(x: px, y: py, width: pw, height: ph).integral
        guard cropRect.width >= 2, cropRect.height >= 2 else { return nil }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let cropped = image.cropped(to: cropRect)

        // Downsample to 8x8 and convert to grayscale.
        // We use CIContext to render into a small RGBA8 buffer and then compute luma.
        let targetW = 8
        let targetH = 8

        let sx = CGFloat(targetW) / cropRect.width
        let sy = CGFloat(targetH) / cropRect.height
        let scale = min(sx, sy)

        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Move the image to the origin before cropping to a fixed 8x8 rect.
        let moved = scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.origin.x, y: -scaled.extent.origin.y))
        let finalRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        let finalImage = moved.cropped(to: finalRect)

        guard let cg = ciContext.createCGImage(finalImage, from: finalRect) else { return nil }

        guard let cfData = cg.dataProvider?.data else { return nil }
        let data = cfData as Data
        if data.isEmpty { return nil }

        // Compute luma from RGBA (or BGRA) byte order; for robustness we compute from RGB channels.
        // We assume 8-bit components.
        let bytes = [UInt8](data)
        let bytesPerPixel = 4
        guard bytes.count >= targetW * targetH * bytesPerPixel else { return nil }

        var luma: [UInt8] = []
        luma.reserveCapacity(64)

        for i in 0..<(targetW * targetH) {
            let base = i * bytesPerPixel
            let r = Int(bytes[base + 0])
            let g = Int(bytes[base + 1])
            let b = Int(bytes[base + 2])
            // ITU-R BT.601 luma approximation.
            let y = (299 * r + 587 * g + 114 * b) / 1000
            luma.append(UInt8(max(0, min(255, y))))
        }

        return Self.averageHash64(fromLuma8x8: luma)
    }

    private func normalizeObservation(_ observation: VNFaceObservation) -> CGRect {
        // Vision observation.boundingBox is normalized with origin in bottom-left.
        // Convert to top-left origin for MetaVis standard.
        let oldRect = observation.boundingBox
        let newY = 1.0 - (oldRect.origin.y + oldRect.height)
        return CGRect(x: oldRect.origin.x, y: newY, width: oldRect.width, height: oldRect.height)
    }
    
    public func infer<Request, Result>(request: Request) async throws -> Result where Request : AIInferenceRequest, Result : AIInferenceResult {
        throw MetaVisPerceptionError.unsupportedGenericInfer(
            service: name,
            requestType: String(describing: Request.self),
            resultType: String(describing: Result.self)
        )
    }
}
