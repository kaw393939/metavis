// TransitionRenderer.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// GPU-accelerated transition rendering

import Foundation
import Metal
import simd

// MARK: - TransitionRendererError

/// Errors that can occur during transition rendering.
public enum TransitionRendererError: Error, Sendable {
    case deviceNotFound
    case libraryNotFound
    case pipelineCreationFailed(String)
    case textureCreationFailed
    case encodingFailed
    case invalidTextures
}

extension TransitionRendererError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Metal device not found"
        case .libraryNotFound:
            return "Metal shader library not found"
        case .pipelineCreationFailed(let kernel):
            return "Failed to create pipeline for kernel: \(kernel)"
        case .textureCreationFailed:
            return "Failed to create output texture"
        case .encodingFailed:
            return "Failed to encode render commands"
        case .invalidTextures:
            return "Invalid input textures"
        }
    }
}

// MARK: - TransitionUniforms

/// Uniforms for transition shaders (must match Transition.metal)
struct TransitionUniforms {
    var progress: Float      // 0.0 to 1.0
    var softness: Float      // Edge softness
    var holdRatio: Float     // Dip hold ratio
    var direction: Int32     // Direction enum
    var feather: Float       // Iris feather
    
    init(progress: Float, parameters: TransitionParameters) {
        self.progress = progress
        self.softness = parameters.softness
        self.holdRatio = parameters.holdRatio
        self.direction = Int32(parameters.direction?.rawValue ?? 0)
        self.feather = parameters.feather
    }
}

// MARK: - TransitionRenderer

/// GPU-accelerated transition renderer.
///
/// Applies transition effects between two video frames using Metal compute shaders.
///
/// ## Example
/// ```swift
/// let renderer = try TransitionRenderer(device: mtlDevice)
/// 
/// // Render a crossfade at 50% progress
/// let result = try renderer.render(
///     from: fromTexture,
///     to: toTexture,
///     type: .crossfade,
///     progress: 0.5
/// )
/// ```
public final class TransitionRenderer: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Metal device
    public let device: MTLDevice
    
    /// Command queue for GPU operations
    private let commandQueue: MTLCommandQueue
    
    /// Metal shader library
    private let library: MTLLibrary
    
    /// Cached compute pipelines for each transition type
    private var pipelines: [VideoTransitionType: MTLComputePipelineState] = [:]
    
    /// Thread group size for compute shaders
    private let threadGroupSize: MTLSize
    
    /// Reusable output texture (resized as needed)
    private var outputTexture: MTLTexture?
    private var outputTextureSize: SIMD2<Int> = .zero
    
    // MARK: - Initialization
    
    /// Creates a new transition renderer.
    public init(device: MTLDevice) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw TransitionRendererError.deviceNotFound
        }
        self.commandQueue = queue
        
        // Load shader library - try multiple approaches
        // 1. Try pre-compiled metallib
        if let libraryURL = Bundle.module.url(forResource: "default", withExtension: "metallib"),
           let lib = try? device.makeLibrary(URL: libraryURL) {
            self.library = lib
        } else if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            self.library = lib
        } else if let lib = device.makeDefaultLibrary() {
            self.library = lib
        } else {
            // 2. Fallback to runtime compilation from source
            if let shaderURL = Bundle.module.url(forResource: "Transition", withExtension: "metal", subdirectory: "Shaders"),
               let source = try? String(contentsOf: shaderURL, encoding: .utf8) {
                do {
                    self.library = try device.makeLibrary(source: source, options: nil)
                } catch {
                    throw TransitionRendererError.libraryNotFound
                }
            } else {
                throw TransitionRendererError.libraryNotFound
            }
        }
        
        // Calculate optimal thread group size
        let maxThreads = device.maxThreadsPerThreadgroup
        let width = min(16, maxThreads.width)
        let height = min(16, maxThreads.height)
        self.threadGroupSize = MTLSize(width: width, height: height, depth: 1)
        
        // Pre-create common pipelines
        try createPipeline(for: .crossfade)
        try createPipeline(for: .dipToBlack)
        try createPipeline(for: .wipeLeft)
    }
    
    // MARK: - Pipeline Management
    
    /// Creates or retrieves the compute pipeline for a transition type.
    private func pipeline(for type: VideoTransitionType) throws -> MTLComputePipelineState {
        if let existing = pipelines[type] {
            return existing
        }
        return try createPipeline(for: type)
    }
    
    @discardableResult
    private func createPipeline(for type: VideoTransitionType) throws -> MTLComputePipelineState {
        let kernelName = type.kernelName
        
        guard !kernelName.isEmpty else {
            // Cut transition doesn't need a pipeline
            throw TransitionRendererError.pipelineCreationFailed("cut has no kernel")
        }
        
        guard let function = library.makeFunction(name: kernelName) else {
            throw TransitionRendererError.pipelineCreationFailed(kernelName)
        }
        
        do {
            let pipeline = try device.makeComputePipelineState(function: function)
            pipelines[type] = pipeline
            return pipeline
        } catch {
            throw TransitionRendererError.pipelineCreationFailed(kernelName)
        }
    }
    
    // MARK: - Rendering
    
    /// Renders a transition between two frames.
    ///
    /// - Parameters:
    ///   - from: Outgoing frame texture
    ///   - to: Incoming frame texture
    ///   - type: Transition type
    ///   - progress: Transition progress (0.0 = from, 1.0 = to)
    ///   - parameters: Additional transition parameters
    /// - Returns: Rendered output texture
    public func render(
        from fromTexture: MTLTexture,
        to toTexture: MTLTexture,
        type: VideoTransitionType,
        progress: Float,
        parameters: TransitionParameters = TransitionParameters()
    ) async throws -> MTLTexture {
        // Handle cut transition (no blending needed)
        if type == .cut {
            return progress < 0.5 ? fromTexture : toTexture
        }
        
        // Validate textures
        guard fromTexture.width > 0 && fromTexture.height > 0,
              toTexture.width > 0 && toTexture.height > 0 else {
            throw TransitionRendererError.invalidTextures
        }
        
        // Use the larger of the two dimensions for output
        let width = max(fromTexture.width, toTexture.width)
        let height = max(fromTexture.height, toTexture.height)
        
        // Get or create output texture
        let output = try ensureOutputTexture(width: width, height: height)
        
        // Get pipeline
        let pipeline = try self.pipeline(for: type)
        
        // Create uniforms
        var uniforms = TransitionUniforms(progress: progress, parameters: parameters)
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw TransitionRendererError.encodingFailed
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(fromTexture, index: 0)
        encoder.setTexture(toTexture, index: 1)
        encoder.setTexture(output, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<TransitionUniforms>.stride, index: 0)
        
        // Calculate thread groups
        let threadGroups = MTLSize(
            width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        return output
    }
    
    /// Renders a transition from a TransitionContext.
    public func render(
        context: TransitionContext,
        fromTexture: MTLTexture,
        toTexture: MTLTexture
    ) async throws -> MTLTexture {
        return try await render(
            from: fromTexture,
            to: toTexture,
            type: context.type,
            progress: Float(context.progress),
            parameters: context.parameters
        )
    }
    
    /// Renders a transition asynchronously.
    public func renderAsync(
        from fromTexture: MTLTexture,
        to toTexture: MTLTexture,
        type: VideoTransitionType,
        progress: Float,
        parameters: TransitionParameters = TransitionParameters(),
        completion: @escaping (Result<MTLTexture, Error>) -> Void
    ) {
        // Handle cut transition
        if type == .cut {
            completion(.success(progress < 0.5 ? fromTexture : toTexture))
            return
        }
        
        do {
            let width = max(fromTexture.width, toTexture.width)
            let height = max(fromTexture.height, toTexture.height)
            let output = try ensureOutputTexture(width: width, height: height)
            let pipeline = try self.pipeline(for: type)
            
            var uniforms = TransitionUniforms(progress: progress, parameters: parameters)
            
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                completion(.failure(TransitionRendererError.encodingFailed))
                return
            }
            
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(fromTexture, index: 0)
            encoder.setTexture(toTexture, index: 1)
            encoder.setTexture(output, index: 2)
            encoder.setBytes(&uniforms, length: MemoryLayout<TransitionUniforms>.stride, index: 0)
            
            let threadGroups = MTLSize(
                width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                depth: 1
            )
            
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
            
            commandBuffer.addCompletedHandler { _ in
                completion(.success(output))
            }
            
            commandBuffer.commit()
            
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Texture Management
    
    /// Ensures an output texture of the required size exists.
    private func ensureOutputTexture(width: Int, height: Int) throws -> MTLTexture {
        // DON'T reuse textures for export - each frame needs its own copy
        // to prevent race conditions with async processing and output writing
        
        // Create new texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared  // Must be shared for CPU readback by VideoExporter
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TransitionRendererError.textureCreationFailed
        }
        
        return texture
    }
    
    /// Creates a new texture for output (doesn't reuse).
    public func createOutputTexture(width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared  // Readable by CPU
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TransitionRendererError.textureCreationFailed
        }
        
        return texture
    }
    
    // MARK: - Utilities
    
    /// Pre-warms all transition pipelines.
    public func preloadAllPipelines() throws {
        for type in VideoTransitionType.allCases {
            if type != .cut {
                try createPipeline(for: type)
            }
        }
    }
    
    /// Returns which transition types are currently loaded.
    public var loadedVideoTransitionTypes: [VideoTransitionType] {
        Array(pipelines.keys)
    }
}

// MARK: - Convenience Extensions

extension TransitionRenderer {
    /// Renders a crossfade transition.
    public func crossfade(
        from: MTLTexture,
        to: MTLTexture,
        progress: Float
    ) async throws -> MTLTexture {
        try await render(from: from, to: to, type: .crossfade, progress: progress)
    }
    
    /// Renders a dip to black transition.
    public func dipToBlack(
        from: MTLTexture,
        to: MTLTexture,
        progress: Float,
        holdRatio: Float = 0.2
    ) async throws -> MTLTexture {
        try await render(
            from: from,
            to: to,
            type: .dipToBlack,
            progress: progress,
            parameters: TransitionParameters(holdRatio: holdRatio)
        )
    }
    
    /// Renders a wipe transition.
    public func wipe(
        from: MTLTexture,
        to: MTLTexture,
        direction: TransitionDirection,
        progress: Float,
        softness: Float = 0.02
    ) async throws -> MTLTexture {
        let type: VideoTransitionType = {
            switch direction {
            case .left: return .wipeLeft
            case .right: return .wipeRight
            case .up: return .wipeUp
            case .down: return .wipeDown
            }
        }()
        
        return try await render(
            from: from,
            to: to,
            type: type,
            progress: progress,
            parameters: TransitionParameters(softness: softness, direction: direction)
        )
    }
}
