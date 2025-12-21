@preconcurrency import Metal
import CoreML
import Vision
import QuartzCore

// MARK: - DepthMap

/// A depth map texture with metadata
public struct DepthMap: Sendable {
    /// The depth texture (R32Float, values 0-1 where 0=near, 1=far)
    public let texture: MTLTexture
    
    /// Minimum depth value in the map
    public let minDepth: Float
    
    /// Maximum depth value in the map
    public let maxDepth: Float
    
    /// Timestamp when this depth map was generated
    public let timestamp: CFTimeInterval
    
    public var width: Int { texture.width }
    public var height: Int { texture.height }
    
    public init(texture: MTLTexture, minDepth: Float = 0.0, maxDepth: Float = 1.0, timestamp: CFTimeInterval = CACurrentMediaTime()) {
        self.texture = texture
        self.minDepth = minDepth
        self.maxDepth = maxDepth
        self.timestamp = timestamp
    }
}

// MARK: - DepthEstimator Protocol

/// Protocol for depth estimation from single images
public protocol DepthEstimator: Sendable {
    /// Estimate depth from a single RGB texture
    /// - Parameter texture: Input RGB texture
    /// - Returns: Depth map with normalized depth values [0,1]
    func estimateDepth(from texture: MTLTexture) async throws -> DepthMap
    
    /// Clear any cached depth maps
    func clearCache()
}

// MARK: - Errors

public enum DepthEstimatorError: Error, LocalizedError {
    case modelNotAvailable
    case noResults
    case bufferCreationFailed
    case textureCreationFailed
    case unsupportedTextureFormat
    case inferenceError(String)
    
    public var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Depth estimation model is not available"
        case .noResults:
            return "Depth estimation produced no results"
        case .bufferCreationFailed:
            return "Failed to create pixel buffer"
        case .textureCreationFailed:
            return "Failed to create depth texture"
        case .unsupportedTextureFormat:
            return "Input texture format is not supported"
        case .inferenceError(let message):
            return "Depth inference error: \(message)"
        }
    }
}

// MARK: - Compute Device

public enum ComputeDevice: Sendable {
    case cpu
    case gpu
    case ane  // Apple Neural Engine
    case auto // Let the system decide
    
    var mlComputeUnits: MLComputeUnits {
        switch self {
        case .cpu: return .cpuOnly
        case .gpu: return .cpuAndGPU
        case .ane, .auto: return .all
        }
    }
}
