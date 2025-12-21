import Foundation

/// Represents how alpha channel is handled in textures
/// Based on MetalPetal's MTIAlphaType pattern
public enum AlphaType: String, Sendable, Codable {
    /// RGB channels are not premultiplied by alpha
    /// Color values represent actual color regardless of transparency
    /// Formula: RGB independent of A
    case straight

    /// RGB channels are premultiplied by alpha (most common in Metal/GPU)
    /// Color values are adjusted for opacity
    /// Formula: RGB = originalRGB * A
    case premultiplied

    /// No alpha channel or image is fully opaque
    /// Optimization: skip alpha blending
    /// Alpha value is always 1.0
    case opaque

    /// Default for most GPU textures (CGImage, CVPixelBuffer)
    public static let `default`: AlphaType = .premultiplied
}

public extension AlphaType {
    /// Whether this alpha type requires conversion when blending
    func requiresConversion(to target: AlphaType) -> Bool {
        self != target && self != .opaque && target != .opaque
    }

    /// MTLBlendOperation for this alpha type
    var blendOperation: String {
        switch self {
        case .straight:
            return "straight alpha blending"
        case .premultiplied:
            return "premultiplied alpha blending (standard)"
        case .opaque:
            return "no blending (opaque)"
        }
    }
}

/// Protocol for objects that have an alpha type
public protocol AlphaTypeProvider {
    var alphaType: AlphaType { get }
}
