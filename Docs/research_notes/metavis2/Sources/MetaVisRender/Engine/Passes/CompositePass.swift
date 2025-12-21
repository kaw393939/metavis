import Metal
import simd

// MARK: - CompositeBlendMode

/// Blend modes for video compositing.
public enum CompositeBlendMode: UInt32, Sendable {
    /// Standard alpha blending (foreground over background).
    case normal = 0
    
    /// Graphics appear behind subject using mask.
    case behindMask = 1
    
    /// Multiply blend (darkens).
    case multiply = 2
    
    /// Screen blend (lightens).
    case screen = 3
    
    /// Overlay blend (combines multiply and screen).
    case overlay = 4
    
    /// Darken blend (keeps darker pixels).
    case darken = 5
    
    /// Lighten blend (keeps lighter pixels).
    case lighten = 6
    
    /// Color Burn blend (darkens base to reflect blend).
    case colorBurn = 7
    
    /// Color Dodge blend (brightens base to reflect blend).
    case colorDodge = 8
    
    /// Soft Light blend (darkens or lightens depending on blend).
    case softLight = 9
    
    /// Hard Light blend (multiplies or screens depending on blend).
    case hardLight = 10
    
    /// Difference blend (subtracts darker from lighter).
    case difference = 11
    
    /// Exclusion blend (lower contrast difference).
    case exclusion = 12
    
    /// Hue blend (preserves luma and sat of base, uses hue of blend).
    case hue = 13
    
    /// Saturation blend (preserves luma and hue of base, uses sat of blend).
    case saturation = 14
    
    /// Color blend (preserves luma of base, uses hue and sat of blend).
    case color = 15
    
    /// Luminosity blend (preserves hue and sat of base, uses luma of blend).
    case luminosity = 16
    
    /// Add blend (linear dodge).
    case add = 17
}

extension CompositeBlendMode {
    public init(_ mode: BlendMode) {
        switch mode {
        case .normal: self = .normal
        case .add: self = .add
        case .multiply: self = .multiply
        case .screen: self = .screen
        case .overlay: self = .overlay
        case .darken: self = .darken
        case .lighten: self = .lighten
        case .colorBurn: self = .colorBurn
        case .colorDodge: self = .colorDodge
        case .softLight: self = .softLight
        case .hardLight: self = .hardLight
        case .difference: self = .difference
        case .exclusion: self = .exclusion
        case .hue: self = .hue
        case .saturation: self = .saturation
        case .color: self = .color
        case .luminosity: self = .luminosity
        }
    }
}

// MARK: - CompositeParams

/// Parameters for composite pass execution.
public struct CompositeParams: Sendable {
    /// Blend mode for compositing.
    public let mode: CompositeBlendMode
    
    /// Threshold for mask-based compositing (0.0-1.0).
    public let maskThreshold: Float
    
    /// Edge softness for smooth mask transitions (0.0-0.5).
    public let edgeSoftness: Float
    
    /// Opacity of the foreground layer (0.0-1.0).
    public let foregroundOpacity: Float
    
    /// Opacity of the background layer (0.0-1.0).
    public let backgroundOpacity: Float
    
    public init(
        mode: CompositeBlendMode = .normal,
        maskThreshold: Float = 0.5,
        edgeSoftness: Float = 0.05,
        foregroundOpacity: Float = 1.0,
        backgroundOpacity: Float = 1.0
    ) {
        self.mode = mode
        self.maskThreshold = maskThreshold
        self.edgeSoftness = edgeSoftness
        self.foregroundOpacity = foregroundOpacity
        self.backgroundOpacity = backgroundOpacity
    }
    
    /// Default parameters for standard compositing.
    public static let standard = CompositeParams()
    
    /// Parameters for behind-subject compositing.
    public static let behindSubject = CompositeParams(
        mode: .behindMask,
        maskThreshold: 0.5,
        edgeSoftness: 0.05
    )
}

// MARK: - Shader Uniforms (Must match Composite.metal)

struct CompositeUniforms {
    var blendMode: UInt32
    var maskThreshold: Float
    var edgeSoftness: Float
    var foregroundOpacity: Float
    var backgroundOpacity: Float
    var padding: SIMD3<Float>
}

// MARK: - CompositePassError

/// Errors that can occur during composite pass execution.
public enum CompositePassError: Error, Sendable {
    case shaderNotFound(String)
    case pipelineCreationFailed(Error)
    case commandEncodingFailed
    case textureCreationFailed
}

extension CompositePassError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .shaderNotFound(let name):
            return "Composite shader not found: \(name)"
        case .pipelineCreationFailed(let error):
            return "Failed to create compute pipeline: \(error.localizedDescription)"
        case .commandEncodingFailed:
            return "Failed to encode composite commands"
        case .textureCreationFailed:
            return "Failed to create output texture"
        }
    }
}

// MARK: - CompositePass

/// Metal compute pass for compositing video and graphics.
///
/// `CompositePass` performs GPU-accelerated compositing:
/// - Standard alpha blending (foreground over background)
/// - Mask-based blending (graphics behind subject)
/// - Photoshop-style blend modes (multiply, screen, overlay)
///
/// ## Example Usage
/// ```swift
/// let pass = try CompositePass(device: device)
///
/// let result = pass.composite(
///     background: videoTexture,
///     foreground: graphicsTexture,
///     mask: personMask,
///     blendMode: .behindMask,
///     commandBuffer: commandBuffer
/// )
/// ```
public final class CompositePass: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Metal device.
    public let device: MTLDevice
    
    /// Compute pipeline for masked compositing.
    private let compositePipeline: MTLComputePipelineState
    
    /// Compute pipeline for simple (no mask) compositing.
    private let simpleCompositePipeline: MTLComputePipelineState
    
    /// Compute pipeline for frame copy.
    private let copyPipeline: MTLComputePipelineState
    
    /// Compute pipeline for resize.
    private let resizePipeline: MTLComputePipelineState
    
    /// Compute pipeline for transform.
    private let transformPipeline: MTLComputePipelineState
    
    /// Sampler state for texture sampling.
    private let samplerState: MTLSamplerState
    
    /// Thread group size for compute dispatch.
    private let threadGroupSize: MTLSize
    
    // MARK: - Initialization
    
    /// Creates a composite pass.
    ///
    /// - Parameter device: Metal device.
    /// - Throws: `CompositePassError` if shaders cannot be loaded.
    public init(device: MTLDevice) throws {
        self.device = device
        
        // Load shader library
        let library: MTLLibrary
        do {
            library = try ShaderLibrary.loadDefaultLibrary(device: device)
        } catch {
            throw CompositePassError.shaderNotFound("default library: \(error)")
        }
        
        // Create compute pipelines
        compositePipeline = try Self.createPipeline(
            device: device,
            library: library,
            functionName: "composite"
        )
        
        simpleCompositePipeline = try Self.createPipeline(
            device: device,
            library: library,
            functionName: "compositeSimple"
        )
        
        copyPipeline = try Self.createPipeline(
            device: device,
            library: library,
            functionName: "copyFrame"
        )
        
        resizePipeline = try Self.createPipeline(
            device: device,
            library: library,
            functionName: "resizeTexture"
        )
        
        transformPipeline = try Self.createPipeline(
            device: device,
            library: library,
            functionName: "transform"
        )
        
        // Create sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .notMipmapped
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw CompositePassError.pipelineCreationFailed(
                NSError(domain: "CompositePass", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create sampler"])
            )
        }
        self.samplerState = sampler
        
        // Optimal thread group size for Apple GPUs
        self.threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    }
    
    // MARK: - Public Methods
    
    /// Composites foreground over background with optional mask.
    ///
    /// - Parameters:
    ///   - background: Background texture (video frame).
    ///   - foreground: Foreground texture (rendered graphics).
    ///   - mask: Optional mask texture for behind-subject compositing.
    ///   - blendMode: Blend mode to use.
    ///   - commandBuffer: Metal command buffer.
    /// - Returns: The composited texture.
    public func composite(
        background: MTLTexture,
        foreground: MTLTexture,
        mask: MTLTexture?,
        blendMode: CompositeBlendMode,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture {
        let params = CompositeParams(mode: blendMode)
        return composite(
            background: background,
            foreground: foreground,
            mask: mask,
            params: params,
            commandBuffer: commandBuffer
        )
    }
    
    /// Composites with full parameter control.
    ///
    /// - Parameters:
    ///   - background: Background texture (video frame).
    ///   - foreground: Foreground texture (rendered graphics).
    ///   - mask: Optional mask texture for behind-subject compositing.
    ///   - params: Composite parameters.
    ///   - commandBuffer: Metal command buffer.
    /// - Returns: The composited texture.
    public func composite(
        background: MTLTexture,
        foreground: MTLTexture,
        mask: MTLTexture?,
        params: CompositeParams,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture {
        // Create output texture matching background size
        let outputTexture = createOutputTexture(
            width: background.width,
            height: background.height
        )
        
        // Create uniforms
        var uniforms = CompositeUniforms(
            blendMode: params.mode.rawValue,
            maskThreshold: params.maskThreshold,
            edgeSoftness: params.edgeSoftness,
            foregroundOpacity: params.foregroundOpacity,
            backgroundOpacity: params.backgroundOpacity,
            padding: SIMD3<Float>(0, 0, 0)
        )
        
        // Encode compute command
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return background
        }
        
        encoder.label = "Composite Pass"
        
        if let mask = mask, params.mode == .behindMask {
            // Use masked composite
            encoder.setComputePipelineState(compositePipeline)
            encoder.setTexture(background, index: 0)
            encoder.setTexture(foreground, index: 1)
            encoder.setTexture(mask, index: 2)
            encoder.setTexture(outputTexture, index: 3)
        } else {
            // Use simple composite
            encoder.setComputePipelineState(simpleCompositePipeline)
            encoder.setTexture(background, index: 0)
            encoder.setTexture(foreground, index: 1)
            encoder.setTexture(outputTexture, index: 2)
        }
        
        encoder.setBytes(&uniforms, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        
        // Dispatch threads
        let threadGroups = MTLSize(
            width: (outputTexture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (outputTexture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        return outputTexture
    }
    
    /// Copies a texture (for frames without graphics).
    ///
    /// - Parameters:
    ///   - input: Source texture.
    ///   - commandBuffer: Metal command buffer.
    /// - Returns: Copy of the input texture.
    public func copy(
        input: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture {
        let output = createOutputTexture(width: input.width, height: input.height)
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        encoder.label = "Copy Frame"
        encoder.setComputePipelineState(copyPipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        let threadGroups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        return output
    }
    
    /// Resizes a texture using bilinear filtering.
    ///
    /// - Parameters:
    ///   - input: Source texture.
    ///   - width: Target width.
    ///   - height: Target height.
    ///   - commandBuffer: Metal command buffer.
    /// - Returns: Resized texture.
    public func resize(
        input: MTLTexture,
        width: Int,
        height: Int,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture {
        let output = createOutputTexture(width: width, height: height)
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        encoder.label = "Resize Texture"
        encoder.setComputePipelineState(resizePipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setSamplerState(samplerState, index: 0)
        
        let threadGroups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        return output
    }
    
    /// Applies a 2D transform to a texture.
    ///
    /// - Parameters:
    ///   - input: Source texture.
    ///   - transform: 3x3 transform matrix (inverse).
    ///   - commandBuffer: Metal command buffer.
    /// - Returns: Transformed texture.
    public func transform(
        input: MTLTexture,
        transform: simd_float3x3,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture {
        let output = createOutputTexture(width: input.width, height: input.height)
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return input
        }
        
        encoder.label = "Transform Texture"
        encoder.setComputePipelineState(transformPipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        
        var matrix = transform
        encoder.setBytes(&matrix, length: MemoryLayout<simd_float3x3>.stride, index: 0)
        encoder.setSamplerState(samplerState, index: 0)
        
        let threadGroups = MTLSize(
            width: (output.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (output.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        return output
    }
    
    // MARK: - Private Methods
    
    private static func createPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        functionName: String
    ) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: functionName) else {
            throw CompositePassError.shaderNotFound(functionName)
        }
        
        do {
            return try device.makeComputePipelineState(function: function)
        } catch {
            throw CompositePassError.pipelineCreationFailed(error)
        }
    }
    
    private func createOutputTexture(width: Int, height: Int) -> MTLTexture {
        let descriptor = outputTextureDescriptor(width: width, height: height)
        return device.makeTexture(descriptor: descriptor)!
    }
    
    internal static func outputTextureDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return descriptor
    }

    internal func outputTextureDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
        return Self.outputTextureDescriptor(width: width, height: height)
    }
}

// MARK: - RenderPass Conformance

extension CompositePass: RenderPass {
    public var label: String { "Composite Pass" }
    
    public func setup(device: MTLDevice, library: MTLLibrary) throws {
        // Already set up in init
    }
    
    public func resize(resolution: SIMD2<Int>) {
        // No internal buffers to resize
    }
    
    public func execute(commandBuffer: MTLCommandBuffer, context: RenderContext) throws {
        // This pass is typically used directly via the composite() method
        // rather than through the standard RenderPass pipeline
    }
}
