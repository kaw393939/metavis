import Metal
import Foundation

// MARK: - OcclusionPass

/// Renders elements (text, graphics) behind a segmented subject
/// Creates proper depth ordering: background → element → person
public actor OcclusionPass {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        public let edgeBlend: Float   // Edge blending amount (0.0-1.0)
        public let quality: VisionProvider.SegmentationQuality
        
        public static let `default` = Config(
            edgeBlend: 0.01,
            quality: .balanced
        )
        
        public init(
            edgeBlend: Float = 0.01,
            quality: VisionProvider.SegmentationQuality = .balanced
        ) {
            self.edgeBlend = edgeBlend
            self.quality = quality
        }
    }
    
    // MARK: - Errors
    
    public enum Error: Swift.Error, LocalizedError {
        case pipelineCreationFailed
        case textureCreationFailed
        case encodingFailed
        case segmentationFailed(underlying: Swift.Error)
        case invalidLayerCount
        
        public var errorDescription: String? {
            switch self {
            case .pipelineCreationFailed:
                return "Failed to create compute pipeline for occlusion"
            case .textureCreationFailed:
                return "Failed to create output texture"
            case .encodingFailed:
                return "Failed to encode compute commands"
            case .segmentationFailed(let error):
                return "Person segmentation failed: \(error.localizedDescription)"
            case .invalidLayerCount:
                return "Invalid number of layers for occlusion"
            }
        }
    }
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let visionProvider: VisionProvider
    private var compositePipeline: MTLComputePipelineState?
    private var alphaBlendPipeline: MTLComputePipelineState?
    
    // MARK: - Initialization
    
    public init(device: MTLDevice, visionProvider: VisionProvider? = nil) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw Error.pipelineCreationFailed
        }
        self.commandQueue = queue
        self.visionProvider = visionProvider ?? VisionProvider(device: device)
        
        // Load pipelines
        let library: MTLLibrary
        if let bundleLib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            library = bundleLib
        } else if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            throw Error.pipelineCreationFailed
        }
        
        // Load mask composite pipeline
        if let maskFunc = library.makeFunction(name: "maskComposite") {
            self.compositePipeline = try device.makeComputePipelineState(function: maskFunc)
        }
        
        // Load alpha blend pipeline
        if let alphaFunc = library.makeFunction(name: "alphaBlend") {
            self.alphaBlendPipeline = try device.makeComputePipelineState(function: alphaFunc)
        }
        
        guard self.compositePipeline != nil else {
            throw Error.pipelineCreationFailed
        }
    }
    

    
    // MARK: - Public API
    
    /// Render an element behind the subject in a video frame
    /// - Parameters:
    ///   - video: Source video frame containing the person
    ///   - element: Element to render behind person (text, graphics)
    ///   - config: Occlusion configuration
    /// - Returns: Composited result with element behind person
    public func execute(
        video: MTLTexture,
        element: MTLTexture,
        config: Config = .default
    ) async throws -> MTLTexture {
        
        // 1. Get person segmentation mask
        let mask: SegmentationMask
        do {
            mask = try await visionProvider.segmentPeople(in: video, quality: config.quality)
        } catch {
            throw Error.segmentationFailed(underlying: error)
        }
        
        // 2. Composite layers in order:
        //    - Base: Video with person removed (background only)
        //    - Middle: Element (text/graphics)  
        //    - Top: Person (extracted from video)
        
        // For efficiency, we use a single pass that:
        // - Where mask < threshold: show element over video background
        // - Where mask > threshold: show video (person)
        
        let output = try await compositeWithOcclusion(
            video: video,
            element: element,
            mask: mask.texture,
            config: config
        )
        
        return output
    }
    
    /// Render multiple elements behind the subject
    /// - Parameters:
    ///   - video: Source video frame
    ///   - elements: Elements to render, in back-to-front order
    ///   - config: Occlusion configuration
    /// - Returns: Composited result
    public func execute(
        video: MTLTexture,
        elements: [MTLTexture],
        config: Config = .default
    ) async throws -> MTLTexture {
        guard !elements.isEmpty else {
            throw Error.invalidLayerCount
        }
        
        // Get segmentation mask once
        let mask: SegmentationMask
        do {
            mask = try await visionProvider.segmentPeople(in: video, quality: config.quality)
        } catch {
            throw Error.segmentationFailed(underlying: error)
        }
        
        // Composite all elements together first
        var combinedElements = elements[0]
        for i in 1..<elements.count {
            combinedElements = try await alphaBlend(
                background: combinedElements,
                foreground: elements[i]
            )
        }
        
        // Then composite combined elements behind person
        return try await compositeWithOcclusion(
            video: video,
            element: combinedElements,
            mask: mask.texture,
            config: config
        )
    }
    
    // MARK: - Private Methods
    
    private func compositeWithOcclusion(
        video: MTLTexture,
        element: MTLTexture,
        mask: MTLTexture,
        config: Config
    ) async throws -> MTLTexture {
        
        guard let pipeline = compositePipeline else {
            throw Error.pipelineCreationFailed
        }
        
        // Create output texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: video.pixelFormat,
            width: video.width,
            height: video.height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        outputDescriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: outputDescriptor) else {
            throw Error.textureCreationFailed
        }
        
        // Uniforms for mask composite
        var uniforms = OcclusionUniforms(
            depthThreshold: 0.5,
            edgeSoftness: config.edgeBlend,
            textDepth: 0.0,
            mode: 0  // behindSubject mode
        )
        
        guard let uniformBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<OcclusionUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw Error.encodingFailed
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.encodingFailed
        }
        
        encoder.label = "Occlusion Composite"
        encoder.setComputePipelineState(pipeline)
        
        // For occlusion: element is "background" where mask=0, video shows where mask=1
        // So we pass element as texture[0] (base) and video as texture[1] (foreground)
        encoder.setTexture(element, index: 0)  // Base (shows through where mask is 0)
        encoder.setTexture(video, index: 1)    // Foreground (shows where mask is 1)
        encoder.setTexture(mask, index: 2)     // Segmentation mask
        encoder.setTexture(output, index: 3)   // Output
        encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
        
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
    
    private func alphaBlend(
        background: MTLTexture,
        foreground: MTLTexture
    ) async throws -> MTLTexture {
        
        guard let pipeline = alphaBlendPipeline else {
            // Fall back to just returning foreground
            return foreground
        }
        
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: background.pixelFormat,
            width: background.width,
            height: background.height,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        outputDescriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: outputDescriptor) else {
            throw Error.textureCreationFailed
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.encodingFailed
        }
        
        encoder.label = "Alpha Blend Layers"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(background, index: 0)
        encoder.setTexture(foreground, index: 1)
        encoder.setTexture(output, index: 2)
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (background.width + 15) / 16,
            height: (background.height + 15) / 16,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        return output
    }
}

// MARK: - Uniforms

/// Uniforms for occlusion composite (matches DepthCompositeUniforms)
private struct OcclusionUniforms {
    var depthThreshold: Float
    var edgeSoftness: Float
    var textDepth: Float
    var mode: UInt32
    var padding: SIMD3<Float> = .zero
}

// MARK: - Quality Presets

extension OcclusionPass.Config {
    /// Realtime preview quality
    public static let realtime = OcclusionPass.Config(
        edgeBlend: 0.02,
        quality: .fast
    )
    
    /// Broadcast quality
    public static let cinema = OcclusionPass.Config(
        edgeBlend: 0.01,
        quality: .accurate
    )
}
