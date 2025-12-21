import Metal
import Foundation

// MARK: - SelectiveEffectPass

/// Applies effects selectively to foreground or background using segmentation mask
/// Supports: blur, desaturation, glow, and custom effects
public actor SelectiveEffectPass {
    
    // MARK: - Effect Types
    
    /// Types of selective effects
    public enum EffectType: String, Codable, CaseIterable, Sendable {
        case backgroundBlur = "background_blur"
        case backgroundDesaturate = "background_desaturate"
        case foregroundGlow = "foreground_glow"
    }
    
    /// Target region for effect application
    public enum TargetRegion: String, Codable, Sendable {
        case foreground  // Person/subject
        case background  // Everything else
    }
    
    /// A selective effect with parameters
    public struct Effect: Codable, Sendable {
        public let type: EffectType
        public let parameters: [String: Float]
        
        public init(type: EffectType, parameters: [String: Float] = [:]) {
            self.type = type
            self.parameters = parameters
        }
        
        /// Default blur radius
        public var blurRadius: Float {
            parameters["radius"] ?? 20.0
        }
        
        /// Default desaturation amount (0-1)
        public var desaturateAmount: Float {
            parameters["amount"] ?? 0.5
        }
        
        /// Default glow intensity
        public var glowIntensity: Float {
            parameters["intensity"] ?? 0.3
        }
    }
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        public let quality: VisionProvider.SegmentationQuality
        public let blurPasses: Int  // Number of blur passes for quality
        
        public static let `default` = Config(
            quality: .balanced,
            blurPasses: 2
        )
        
        public init(
            quality: VisionProvider.SegmentationQuality = .balanced,
            blurPasses: Int = 2
        ) {
            self.quality = quality
            self.blurPasses = blurPasses
        }
    }
    
    // MARK: - Errors
    
    public enum Error: Swift.Error, LocalizedError {
        case pipelineCreationFailed
        case textureCreationFailed
        case encodingFailed
        case segmentationFailed(underlying: Swift.Error)
        case unsupportedEffect(EffectType)
        
        public var errorDescription: String? {
            switch self {
            case .pipelineCreationFailed:
                return "Failed to create compute pipeline"
            case .textureCreationFailed:
                return "Failed to create texture"
            case .encodingFailed:
                return "Failed to encode compute commands"
            case .segmentationFailed(let error):
                return "Segmentation failed: \(error.localizedDescription)"
            case .unsupportedEffect(let type):
                return "Unsupported effect type: \(type.rawValue)"
            }
        }
    }
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let visionProvider: VisionProvider
    
    // Pipeline states
    private var blurHPipeline: MTLComputePipelineState?
    private var blurVPipeline: MTLComputePipelineState?
    private var mixPipeline: MTLComputePipelineState?
    
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
        
        // Load blur pipelines
        if let blurH = library.makeFunction(name: "fx_blur_h") {
            self.blurHPipeline = try device.makeComputePipelineState(function: blurH)
        }
        
        if let blurV = library.makeFunction(name: "fx_blur_v") {
            self.blurVPipeline = try device.makeComputePipelineState(function: blurV)
        }
        
        // Load mask mix pipeline (we use maskComposite for mixing)
        if let mix = library.makeFunction(name: "maskComposite") {
            self.mixPipeline = try device.makeComputePipelineState(function: mix)
        }
    }
    

    
    // MARK: - Public API
    
    /// Apply a single effect to video
    public func execute(
        video: MTLTexture,
        effect: Effect,
        target: TargetRegion,
        config: Config = .default
    ) async throws -> MTLTexture {
        
        // Get segmentation mask
        let mask: SegmentationMask
        do {
            mask = try await visionProvider.segmentPeople(in: video, quality: config.quality)
        } catch {
            throw Error.segmentationFailed(underlying: error)
        }
        
        // Apply effect based on type
        let effectTexture: MTLTexture
        switch effect.type {
        case .backgroundBlur:
            effectTexture = try await applyBlur(
                to: video,
                radius: effect.blurRadius,
                passes: config.blurPasses
            )
            
        case .backgroundDesaturate:
            effectTexture = try await applyDesaturation(
                to: video,
                amount: effect.desaturateAmount
            )
            
        case .foregroundGlow:
            effectTexture = try await applyGlow(
                to: video,
                intensity: effect.glowIntensity,
                mask: mask.texture
            )
        }
        
        // Mix original with effect using mask
        let effectMask = target == .background
            ? try await invertMask(mask.texture)
            : mask.texture
        
        return try await mixWithMask(
            original: video,
            effected: effectTexture,
            mask: effectMask
        )
    }
    
    /// Apply multiple effects in sequence
    public func execute(
        video: MTLTexture,
        effects: [Effect],
        config: Config = .default
    ) async throws -> MTLTexture {
        guard !effects.isEmpty else { return video }
        
        var result = video
        for effect in effects {
            // Determine target from effect type
            let target: TargetRegion = effect.type == .foregroundGlow ? .foreground : .background
            result = try await execute(
                video: result,
                effect: effect,
                target: target,
                config: config
            )
        }
        
        return result
    }
    
    // MARK: - Effect Implementations
    
    private func applyBlur(
        to texture: MTLTexture,
        radius: Float,
        passes: Int
    ) async throws -> MTLTexture {
        
        guard let blurH = blurHPipeline, let blurV = blurVPipeline else {
            throw Error.pipelineCreationFailed
        }
        
        // Create intermediate textures
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        
        guard let temp1 = device.makeTexture(descriptor: descriptor),
              let temp2 = device.makeTexture(descriptor: descriptor) else {
            throw Error.textureCreationFailed
        }
        
        // Create quality settings buffer
        let qualitySettings = MVQualitySettings(mode: .realtime)
        guard let qualityBuffer = device.makeBuffer(
            bytes: [qualitySettings],
            length: MemoryLayout<MVQualitySettings>.stride,
            options: .storageModeShared
        ) else {
            throw Error.encodingFailed
        }
        
        // Create radius buffer
        var radiusValue = radius
        guard let radiusBuffer = device.makeBuffer(
            bytes: &radiusValue,
            length: MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw Error.encodingFailed
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw Error.encodingFailed
        }
        
        var source = texture
        var dest1 = temp1
        var dest2 = temp2
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (texture.width + 15) / 16,
            height: (texture.height + 15) / 16,
            depth: 1
        )
        
        for _ in 0..<passes {
            // Horizontal blur
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.label = "Blur Horizontal"
                encoder.setComputePipelineState(blurH)
                encoder.setTexture(source, index: 0)
                encoder.setTexture(dest1, index: 1)
                encoder.setBuffer(radiusBuffer, offset: 0, index: 0)
                encoder.setBuffer(qualityBuffer, offset: 0, index: 1)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
                encoder.endEncoding()
            }
            
            // Vertical blur
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.label = "Blur Vertical"
                encoder.setComputePipelineState(blurV)
                encoder.setTexture(dest1, index: 0)
                encoder.setTexture(dest2, index: 1)
                encoder.setBuffer(radiusBuffer, offset: 0, index: 0)
                encoder.setBuffer(qualityBuffer, offset: 0, index: 1)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
                encoder.endEncoding()
            }
            
            // Swap for next pass
            source = dest2
            swap(&dest1, &dest2)
        }
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        return source
    }
    
    private func applyDesaturation(
        to texture: MTLTexture,
        amount: Float
    ) async throws -> MTLTexture {
        // For desaturation, we'll use a simple compute shader
        // For now, return a copy (full implementation would use a desaturate kernel)
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: descriptor) else {
            throw Error.textureCreationFailed
        }
        
        // Copy texture (placeholder for actual desaturation)
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw Error.encodingFailed
        }
        
        blitEncoder.copy(from: texture, to: output)
        blitEncoder.endEncoding()
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        // TODO: Implement actual desaturation using a compute shader
        // For now, return the copy
        return output
    }
    
    private func applyGlow(
        to texture: MTLTexture,
        intensity: Float,
        mask: MTLTexture
    ) async throws -> MTLTexture {
        // Apply bloom/glow to foreground
        // First blur the masked area, then add back
        
        let blurred = try await applyBlur(to: texture, radius: 15.0 * intensity, passes: 2)
        
        // For glow, we'd additively blend the blurred version
        // For now, return the blurred texture (full impl would blend)
        return blurred
    }
    
    private func invertMask(_ mask: MTLTexture) async throws -> MTLTexture {
        // Create inverted mask (1 - mask)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mask.pixelFormat,
            width: mask.width,
            height: mask.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: descriptor) else {
            throw Error.textureCreationFailed
        }
        
        // Read mask data, invert, write back
        let bytesPerRow = mask.width * (mask.pixelFormat == .r8Unorm ? 1 : 4)
        var pixels = [UInt8](repeating: 0, count: mask.width * mask.height)
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: mask.width, height: mask.height, depth: 1)
        )
        
        mask.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Invert
        for i in 0..<pixels.count {
            pixels[i] = 255 - pixels[i]
        }
        
        output.replace(region: region, mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
        
        return output
    }
    
    private func mixWithMask(
        original: MTLTexture,
        effected: MTLTexture,
        mask: MTLTexture
    ) async throws -> MTLTexture {
        
        guard let pipeline = mixPipeline else {
            throw Error.pipelineCreationFailed
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: original.pixelFormat,
            width: original.width,
            height: original.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        
        guard let output = device.makeTexture(descriptor: descriptor) else {
            throw Error.textureCreationFailed
        }
        
        var uniforms = MixUniforms(
            depthThreshold: 0.5,
            edgeSoftness: 0.02,
            textDepth: 0.0,
            mode: 0
        )
        
        guard let uniformBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<MixUniforms>.stride,
            options: .storageModeShared
        ) else {
            throw Error.encodingFailed
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw Error.encodingFailed
        }
        
        encoder.label = "Mix with Mask"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(original, index: 0)   // Base
        encoder.setTexture(effected, index: 1)   // Effect
        encoder.setTexture(mask, index: 2)       // Mask
        encoder.setTexture(output, index: 3)     // Output
        encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (original.width + 15) / 16,
            height: (original.height + 15) / 16,
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

private struct MixUniforms {
    var depthThreshold: Float
    var edgeSoftness: Float
    var textDepth: Float
    var mode: UInt32
    var padding: SIMD3<Float> = .zero
}

// MARK: - Quality Presets

extension SelectiveEffectPass.Config {
    /// Realtime preview (3 blur passes)
    public static let realtime = SelectiveEffectPass.Config(quality: .fast, blurPasses: 1)
    
    /// Broadcast quality (7 blur passes)
    public static let cinema = SelectiveEffectPass.Config(quality: .accurate, blurPasses: 3)
    
    /// Maximum quality (11 blur passes)
    public static let lab = SelectiveEffectPass.Config(quality: .accurate, blurPasses: 5)
}
