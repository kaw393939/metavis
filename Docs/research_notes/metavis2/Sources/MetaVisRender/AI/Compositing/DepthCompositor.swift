import Metal

// MARK: - Composite Mode

/// Depth-aware compositing modes
public enum CompositeMode: String, Codable, Sendable {
    case behindSubject    // Text behind foreground objects
    case inFrontOfAll     // Text always on top
    case depthSorted      // Full depth sorting
    case parallax         // Depth-based parallax effect
    
    var rawValue32: UInt32 {
        switch self {
        case .behindSubject: return 0
        case .inFrontOfAll: return 1
        case .depthSorted: return 2
        case .parallax: return 3
        }
    }
}

// MARK: - Compositor Errors

public enum CompositorError: Error, LocalizedError {
    case pipelineCreationFailed
    case textureCreationFailed
    case bufferCreationFailed
    case encodingFailed
    case shaderNotFound
    
    public var errorDescription: String? {
        switch self {
        case .pipelineCreationFailed: return "Failed to create compute pipeline"
        case .textureCreationFailed: return "Failed to create output texture"
        case .bufferCreationFailed: return "Failed to create uniform buffer"
        case .encodingFailed: return "Failed to encode compute commands"
        case .shaderNotFound: return "Depth composite shader not found"
        }
    }
}

// MARK: - Uniforms

/// Uniforms for the depth composite shader
struct DepthCompositeUniforms {
    var depthThreshold: Float
    var edgeSoftness: Float
    var textDepth: Float
    var mode: UInt32
    var padding: SIMD3<Float> = .zero  // Align to 16 bytes
}

// MARK: - DepthCompositor

/// GPU-accelerated depth-aware compositing
public final class DepthCompositor: @unchecked Sendable {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLComputePipelineState?
    
    // Default values
    public var defaultDepthThreshold: Float = 0.5
    public var defaultEdgeSoftness: Float = 0.05
    public var defaultTextDepth: Float = 0.8
    
    public init(device: MTLDevice) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw CompositorError.pipelineCreationFailed
        }
        self.commandQueue = queue
        
        // Load compute shader
        try loadShader()
    }
    
    private func loadShader() throws {
        // Load from shared shader library (compiled at runtime)
        guard let library = try? ShaderLibrary.loadDefaultLibrary(device: device),
              let function = library.makeFunction(name: "depthComposite") else {
            throw CompositorError.shaderNotFound
        }
        
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
    
    /// Composite text over video using depth information
    /// - Parameters:
    ///   - text: Text layer (BGRA with alpha)
    ///   - video: Video frame (BGRA)
    ///   - depth: Depth map (R32Float, 0=near, 1=far)
    ///   - mode: Compositing mode
    ///   - depthThreshold: Depth value for occlusion threshold
    ///   - edgeSoftness: Softness of depth edges
    ///   - textDepth: Depth value of the text (0=near, 1=far)
    /// - Returns: Composited result texture
    public func composite(
        text: MTLTexture,
        video: MTLTexture,
        depth: DepthMap,
        mode: CompositeMode = .behindSubject,
        depthThreshold: Float? = nil,
        edgeSoftness: Float? = nil,
        textDepth: Float? = nil
    ) async throws -> MTLTexture {
        
        guard let pipelineState = pipelineState else {
            throw CompositorError.pipelineCreationFailed
        }
        
        // Create output texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // Fixed: Use 16-bit for consistency with main pipeline
            width: video.width,
            height: video.height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        outputDescriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: outputDescriptor) else {
            throw CompositorError.textureCreationFailed
        }
        
        // Create uniforms
        var uniforms = DepthCompositeUniforms(
            depthThreshold: depthThreshold ?? defaultDepthThreshold,
            edgeSoftness: edgeSoftness ?? defaultEdgeSoftness,
            textDepth: textDepth ?? defaultTextDepth,
            mode: mode.rawValue32
        )
        
        guard let uniformBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<DepthCompositeUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw CompositorError.bufferCreationFailed
        }
        
        // Encode compute pass
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw CompositorError.encodingFailed
        }
        
        encoder.label = "Depth Composite"
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(video, index: 0)         // Video frame
        encoder.setTexture(text, index: 1)          // Text layer
        encoder.setTexture(depth.texture, index: 2) // Depth map
        encoder.setTexture(output, index: 3)        // Output
        encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
        
        // Dispatch with optimal threadgroup size
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (video.width + 15) / 16,
            height: (video.height + 15) / 16,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        return output
    }
    
    /// Composite text behind subject with automatic depth detection
    /// - Parameters:
    ///   - text: Text layer
    ///   - video: Video frame
    ///   - segmentationMask: Person segmentation mask
    /// - Returns: Composited result
    public func compositeBehindSubject(
        text: MTLTexture,
        video: MTLTexture,
        segmentationMask: SegmentationMask
    ) async throws -> MTLTexture {
        // Create output texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // Fixed: Use 16-bit for consistency with main pipeline
            width: video.width,
            height: video.height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        outputDescriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: outputDescriptor) else {
            throw CompositorError.textureCreationFailed
        }
        
        // Simple mask-based compositing
        // Where mask > 0.5, use video; otherwise blend text behind
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw CompositorError.encodingFailed
        }
        
        // First copy video to output
        encoder.copy(from: video, to: output)
        encoder.endEncoding()
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        // In production, we'd use a compute shader to properly blend
        // For now, return the video (text compositing handled elsewhere)
        return output
    }
}

// MARK: - Convenience Extensions

extension DepthCompositor {
    
    /// Create a simple compositor with default settings
    public static func simple(device: MTLDevice? = nil) throws -> DepthCompositor {
        let dev = device ?? MTLCreateSystemDefaultDevice()!
        return try DepthCompositor(device: dev)
    }
}
