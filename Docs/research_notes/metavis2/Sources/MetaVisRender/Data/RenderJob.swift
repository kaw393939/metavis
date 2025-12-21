import Foundation
import Metal
import MetalKit

public enum RenderOutputTarget {
    case offscreen((MTLTexture, Double) async -> Void)
    case view(MTKView)
    case texture(MTLTexture)
}

public struct RenderJob {
    public let manifest: RenderManifest
    public let timeRange: Range<Double>
    public let resolution: SIMD2<Int>
    public let fps: Double
    public let output: RenderOutputTarget
    
    public init(
        manifest: RenderManifest,
        timeRange: Range<Double>? = nil, // Optional override
        resolution: SIMD2<Int>? = nil, // Optional override
        fps: Double? = nil, // Optional override
        output: RenderOutputTarget
    ) {
        self.manifest = manifest
        // Use overrides or defaults from manifest
        self.timeRange = timeRange ?? 0.0..<manifest.metadata.duration
        self.resolution = resolution ?? manifest.metadata.resolution
        self.fps = fps ?? manifest.metadata.fps
        self.output = output
    }
}
