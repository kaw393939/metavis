import Foundation

public enum MetaVisQCError: LocalizedError, Sendable, Hashable {
    case failedToCreate8x8CGImage
    case missingCGImagePixelData
    case unexpectedCGImagePixelDataSize

    case failedToCreateDownsampledCGImage

    case framesTooSimilar(distance: Double, previousLabel: String, currentLabel: String)

    case meanLumaOutOfRange(label: String, meanLuma: Float, min: Float, max: Float)
    case averageRGBNotNeutralEnough(label: String, maxDelta: Float, allowed: Float)
    case tooLittleLowLumaContent(label: String, fraction: Float, min: Float)
    case tooLittleHighLumaContent(label: String, fraction: Float, min: Float)

    case failedToComputeFingerprint
    case failedToCreateCGContext

    case cvPixelBufferCreateFailed(status: Int32)
    case noPixelBufferBaseAddress

    case failedToCreateJPEGDestination
    case failedToFinalizeJPEG
    case imageIONotAvailable

    public var errorDescription: String? {
        func fmt(_ x: Double, _ places: Int) -> String {
            String(format: "%.*f", places, x)
        }

        switch self {
        case .failedToCreate8x8CGImage:
            return "Failed to create 8x8 CGImage"
        case .missingCGImagePixelData:
            return "Missing CGImage pixel data"
        case .unexpectedCGImagePixelDataSize:
            return "Unexpected CGImage pixel data size"
        case .failedToCreateDownsampledCGImage:
            return "Failed to create downsampled CGImage"
        case .framesTooSimilar(let distance, let prev, let cur):
            return "Frames too similar (d=\(fmt(distance, 5))) between \(prev) and \(cur). Possible stuck source."
        case .meanLumaOutOfRange(let label, let meanLuma, let min, let max):
            return "Mean luma out of range for \(label): \(fmt(Double(meanLuma), 4)) not in [\(fmt(Double(min), 4)), \(fmt(Double(max), 4))]"
        case .averageRGBNotNeutralEnough(let label, let maxDelta, let allowed):
            return "Average RGB not neutral enough for \(label): maxΔ=\(fmt(Double(maxDelta), 4)) > \(fmt(Double(allowed), 4))"
        case .tooLittleLowLumaContent(let label, let fraction, let min):
            return "Too little low-luma content for \(label): \(fmt(Double(fraction), 4)) < \(fmt(Double(min), 4))"
        case .tooLittleHighLumaContent(let label, let fraction, let min):
            return "Too little high-luma content for \(label): \(fmt(Double(fraction), 4)) < \(fmt(Double(min), 4))"
        case .failedToComputeFingerprint:
            return "Failed to compute fingerprint (Metal unavailable + CVPixelBuffer->CGImage conversion failed)"
        case .failedToCreateCGContext:
            return "Failed to create CGContext"
        case .cvPixelBufferCreateFailed(let status):
            return "CVPixelBufferCreate failed (\(status))"
        case .noPixelBufferBaseAddress:
            return "No pixel buffer base address"
        case .failedToCreateJPEGDestination:
            return "Failed to create JPEG destination"
        case .failedToFinalizeJPEG:
            return "Failed to finalize JPEG"
        case .imageIONotAvailable:
            return "ImageIO not available"
        }
    }
}
