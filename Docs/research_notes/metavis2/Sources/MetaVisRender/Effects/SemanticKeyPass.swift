import Metal
import Foundation
import QuartzCore

// MARK: - SemanticKeyPass

/// Auto-greenscreen effect using AI person segmentation
/// Removes background and replaces with custom image/video
public actor SemanticKeyPass {
    
    // MARK: - Configuration
    
    /// Configuration for semantic keying
    public struct Config: Sendable {
        public let edgeFeather: Float       // Edge softness (0.0-1.0)
        public let spillSuppression: Bool   // Remove color spill from edges
        public let quality: VisionProvider.SegmentationQuality
        
        public static let `default` = Config(
            edgeFeather: 0.02,
            spillSuppression: true,
            quality: .balanced
        )
        
        public init(
            edgeFeather: Float = 0.02,
            spillSuppression: Bool = true,
            quality: VisionProvider.SegmentationQuality = .balanced
        ) {
            self.edgeFeather = edgeFeather
            self.spillSuppression = spillSuppression
            self.quality = quality
        }
    }
    
    // MARK: - Errors
    
    public enum Error: Swift.Error, LocalizedError {
        case pipelineCreationFailed
        case textureCreationFailed
        case encodingFailed
        case segmentationFailed(underlying: Swift.Error)
        
        public var errorDescription: String? {
            switch self {
            case .pipelineCreationFailed:
                return "Failed to create compute pipeline for semantic keying"
            case .textureCreationFailed:
                return "Failed to create output texture"
            case .encodingFailed:
                return "Failed to encode compute commands"
            case .segmentationFailed(let error):
                return "Person segmentation failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let visionProvider: VisionProvider
    private var pipelineState: MTLComputePipelineState?
    
    // Mask cache for performance
    private var cachedMask: SegmentationMask?
    private var cachedFrameHash: Int = 0
    
    // MARK: - Initialization
    
    public init(device: MTLDevice, visionProvider: VisionProvider? = nil) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw Error.pipelineCreationFailed
        }
        self.commandQueue = queue
        self.visionProvider = visionProvider ?? VisionProvider(device: device)
        
        // Load pipeline
        // Try bundle library first, then default
        let library: MTLLibrary
        if let bundleLib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            library = bundleLib
        } else if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            throw Error.pipelineCreationFailed
        }
        
        guard let function = library.makeFunction(name: "maskComposite") else {
            throw Error.pipelineCreationFailed
        }
        
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
    

    
    // MARK: - Public API
    
    /// Apply semantic keying to a video frame
    /// - Parameters:
    ///   - foreground: Source video frame (with person)
    ///   - background: Replacement background texture
    ///   - config: Keying configuration
    ///   - commandBuffer: Optional external command buffer
    /// - Returns: Composited result with person on new background
    public func execute(
        foreground: MTLTexture,
        background: MTLTexture,
        config: Config = .default,
        commandBuffer: MTLCommandBuffer? = nil
    ) async throws -> MTLTexture {
        
        // 1. Get segmentation mask (with caching)
        let mask = try await getSegmentationMask(
            for: foreground,
            quality: config.quality
        )
        
        // 2. Composite foreground over background using mask
        let output = try await composite(
            foreground: foreground,
            background: background,
            mask: mask.texture,
            config: config,
            commandBuffer: commandBuffer
        )
        
        return output
    }
    
    /// Get just the segmentation mask without compositing
    public func getMask(
        for texture: MTLTexture,
        quality: VisionProvider.SegmentationQuality = .balanced
    ) async throws -> SegmentationMask {
        return try await getSegmentationMask(for: texture, quality: quality)
    }
    
    /// Clear the mask cache (call when scene changes significantly)
    public func clearCache() {
        cachedMask = nil
        cachedFrameHash = 0
    }
    
    // MARK: - Private Methods
    
    private func getSegmentationMask(
        for texture: MTLTexture,
        quality: VisionProvider.SegmentationQuality
    ) async throws -> SegmentationMask {
        // Simple frame hash for cache validation
        let frameHash = texture.width ^ texture.height ^ Int(CACurrentMediaTime() * 1000) % 100
        
        // Use cached mask if available and recent
        if let cached = cachedMask, 
           abs(cachedFrameHash - frameHash) < 10 {
            return cached
        }
        
        // Generate new mask
        do {
            let mask = try await visionProvider.segmentPeople(in: texture, quality: quality)
            cachedMask = mask
            cachedFrameHash = frameHash
            return mask
        } catch {
            throw Error.segmentationFailed(underlying: error)
        }
    }
    
    private func composite(
        foreground: MTLTexture,
        background: MTLTexture,
        mask: MTLTexture,
        config: Config,
        commandBuffer: MTLCommandBuffer?
    ) async throws -> MTLTexture {
        
        guard let pipelineState = pipelineState else {
            throw Error.pipelineCreationFailed
        }
        
        // Create output texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: foreground.pixelFormat,
            width: foreground.width,
            height: foreground.height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        outputDescriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: outputDescriptor) else {
            throw Error.textureCreationFailed
        }
        
        // Create uniforms (must match DepthCompositeUniforms in shader)
        var uniforms = SemanticKeyUniforms(
            depthThreshold: 0.5,
            edgeSoftness: config.edgeFeather,
            textDepth: 0.0,  // Not used for mask composite
            mode: 0          // Mode 0 = behind subject (mask-based)
        )
        
        guard let uniformBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<SemanticKeyUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw Error.encodingFailed
        }
        
        // Use provided command buffer or create new one
        let cmdBuffer = commandBuffer ?? commandQueue.makeCommandBuffer()
        guard let cmdBuffer = cmdBuffer,
              let encoder = cmdBuffer.makeComputeCommandEncoder() else {
            throw Error.encodingFailed
        }
        
        encoder.label = "Semantic Key Composite"
        encoder.setComputePipelineState(pipelineState)
        
        // maskComposite expects: video, text (we use background), mask, output
        // We swap the meaning: foreground is "text", background is "video" base
        // So mask=1 shows foreground (person), mask=0 shows background
        encoder.setTexture(background, index: 0)   // Base layer (new background)
        encoder.setTexture(foreground, index: 1)   // Foreground (person)
        encoder.setTexture(mask, index: 2)         // Segmentation mask
        encoder.setTexture(output, index: 3)       // Output
        encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
        
        // Dispatch
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (foreground.width + 15) / 16,
            height: (foreground.height + 15) / 16,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        // Only commit if we created the buffer
        if commandBuffer == nil {
            cmdBuffer.commit()
            await cmdBuffer.completed()
        }
        
        return output
    }
}

// MARK: - Uniforms

/// Uniforms for semantic keying (matches DepthCompositeUniforms in Metal)
private struct SemanticKeyUniforms {
    var depthThreshold: Float
    var edgeSoftness: Float
    var textDepth: Float
    var mode: UInt32
    var padding: SIMD3<Float> = .zero
}

// MARK: - Quality Extension

extension SemanticKeyPass.Config {
    /// Configuration optimized for realtime preview
    public static let realtime = SemanticKeyPass.Config(
        edgeFeather: 0.03,
        spillSuppression: false,
        quality: .fast
    )
    
    /// Configuration optimized for broadcast quality
    public static let cinema = SemanticKeyPass.Config(
        edgeFeather: 0.02,
        spillSuppression: true,
        quality: .accurate
    )
    
    /// Maximum quality for offline rendering
    public static let lab = SemanticKeyPass.Config(
        edgeFeather: 0.015,
        spillSuppression: true,
        quality: .accurate
    )
}
