import Foundation
import AVFoundation
import CoreMedia
import Metal

// MARK: - CompositingPipelineError

/// Errors that can occur during video compositing.
public enum CompositingPipelineError: Error, Sendable {
    case noSourceVideo
    case renderFailed(String)
    case exportFailed(Error)
    case cancelled
    case invalidConfiguration(String)
    case segmentationFailed(Error)
    case textureConversionFailed
}

extension CompositingPipelineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noSourceVideo:
            return "No source video specified in manifest"
        case .renderFailed(let reason):
            return "Render failed: \(reason)"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        case .cancelled:
            return "Compositing was cancelled"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .segmentationFailed(let error):
            return "Person segmentation failed: \(error.localizedDescription)"
        case .textureConversionFailed:
            return "Failed to convert frame to texture"
        }
    }
}

// MARK: - CompositingProgress

/// Progress information during compositing.
public struct CompositingProgress: Sendable {
    /// Current frame being processed.
    public let currentFrame: Int
    
    /// Total frames to process.
    public let totalFrames: Int
    
    /// Current stage of processing.
    public let stage: Stage
    
    /// Progress as a percentage (0-100).
    public var percentage: Double {
        guard totalFrames > 0 else { return 0 }
        return (Double(currentFrame) / Double(totalFrames)) * 100.0
    }
    
    public enum Stage: String, Sendable {
        case decoding = "Decoding"
        case rendering = "Rendering"
        case segmenting = "Segmenting"
        case compositing = "Compositing"
        case encoding = "Encoding"
        case complete = "Complete"
    }
}

// MARK: - CompositingResult

/// Result of a compositing operation.
public struct CompositingResult: Sendable {
    /// Output file URL.
    public let outputURL: URL
    
    /// Total frames processed.
    public let framesProcessed: Int
    
    /// Total time taken.
    public let duration: TimeInterval
    
    /// Frames per second achieved.
    public var fps: Double {
        guard duration > 0 else { return 0 }
        return Double(framesProcessed) / duration
    }
}

// MARK: - VideoCompositingPipeline

/// Actor that orchestrates video compositing with graphics overlay.
///
/// `VideoCompositingPipeline` combines source video with rendered graphics:
/// - Decodes source video frames
/// - Optionally segments people for "behind subject" effects
/// - Renders graphics layers
/// - Composites video and graphics
/// - Exports the final result
///
/// ## Example Usage
/// ```swift
/// let pipeline = try await VideoCompositingPipeline(
///     manifest: manifest,
///     device: device
/// )
/// 
/// let result = try await pipeline.render(to: outputURL) { progress in
///     print("Progress: \(progress.percentage)%")
/// }
/// ```
public actor VideoCompositingPipeline {
    
    // MARK: - Properties
    
    /// The render manifest.
    public let manifest: RenderManifest
    
    /// Metal device.
    public let device: MTLDevice
    
    // MARK: - Private Properties
    
    private let decoder: VideoDecoder
    private let framePool: FrameBufferPool
    private let compositePass: CompositePass
    private let idtPass: InputDeviceTransformPass
    private var visionProvider: VisionProvider?
    private let commandQueue: MTLCommandQueue
    
    private var isCancelled: Bool = false
    
    // Cached decoder properties (loaded during init)
    private let videoResolution: SIMD2<Int>
    private let videoFrameRate: Double
    private let videoDuration: CMTime
    
    // Use compositing mode from manifest
    private var useBehindSubject: Bool {
        manifest.compositing?.mode == "behindSubject"
    }
    
    // MARK: - Initialization
    
    /// Creates a video compositing pipeline.
    ///
    /// - Parameters:
    ///   - manifest: The render manifest with source video.
    ///   - device: Metal device.
    /// - Throws: `CompositingPipelineError` if initialization fails.
    public init(
        manifest: RenderManifest,
        device: MTLDevice
    ) async throws {
        guard let source = manifest.source else {
            throw CompositingPipelineError.noSourceVideo
        }
        
        self.manifest = manifest
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw CompositingPipelineError.renderFailed("Failed to create command queue")
        }
        self.commandQueue = queue
        
        // Create video decoder with path from SourceDefinition
        let sourceURL = URL(fileURLWithPath: source.path)
        self.decoder = try await VideoDecoder(
            url: sourceURL,
            device: device,
            config: .export
        )
        
        // Cache decoder properties from within actor context
        self.videoResolution = await decoder.resolution
        self.videoFrameRate = await decoder.frameRate
        self.videoDuration = await decoder.duration
        
        // Create frame buffer pool
        self.framePool = FrameBufferPool(
            width: videoResolution.x,
            height: videoResolution.y,
            maxBuffers: 6
        )
        
        // Create composite pass
        self.compositePass = try CompositePass(device: device)
        
        // Create IDT pass
        do {
            self.idtPass = try InputDeviceTransformPass(device: device)
        } catch {
            throw CompositingPipelineError.renderFailed("Failed to create IDT pass: \(error.localizedDescription)")
        }
        
        // Create vision provider if needed for person masking
        if manifest.compositing?.mode == "behindSubject" {
            self.visionProvider = VisionProvider(device: device)
        }
    }
    
    
    // MARK: - Public Methods
    
    /// Renders the composited video.
    ///
    /// - Parameters:
    ///   - outputURL: URL to write the composited video.
    ///   - progressHandler: Called with progress updates.
    /// - Returns: The result of the compositing operation.
    /// - Throws: `CompositingPipelineError` if rendering fails.
    public func render(
        to outputURL: URL,
        progressHandler: (@Sendable (CompositingProgress) -> Void)? = nil
    ) async throws -> CompositingResult {
        let startTime = Date()
        
        // Calculate total frames
        let totalFrames = Int(videoDuration.seconds * videoFrameRate)
        var processedFrames = 0
        
        // Create output textures
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: videoResolution.x,
            height: videoResolution.y,
            mipmapped: false
        )
        outputDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        outputDescriptor.storageMode = .private
        
        guard let graphicsTexture = device.makeTexture(descriptor: outputDescriptor),
              let compositeTexture = device.makeTexture(descriptor: outputDescriptor) else {
            throw CompositingPipelineError.renderFailed("Failed to create output textures")
        }
        
        // Create staging texture for CPU access
        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: videoResolution.x,
            height: videoResolution.y,
            mipmapped: false
        )
        stagingDescriptor.usage = [.shaderRead, .shaderWrite]
        stagingDescriptor.storageMode = .shared
        
        guard let stagingTexture = device.makeTexture(descriptor: stagingDescriptor) else {
            throw CompositingPipelineError.renderFailed("Failed to create staging texture")
        }
        
        // Create video exporter
        let exporter = try VideoExporter(
            outputURL: outputURL,
            width: videoResolution.x,
            height: videoResolution.y,
            frameRate: Int(videoFrameRate)
        )
        
        // Apply trim range if specified
        if let source = manifest.source,
           let trim = source.trim {
            let startTimeVal = CMTime(seconds: trim.inPoint, preferredTimescale: 600)
            try await decoder.seek(to: startTimeVal)
        }
        
        let trimEndTime: CMTime
        if let trim = manifest.source?.trim {
            trimEndTime = CMTime(seconds: trim.outPoint, preferredTimescale: 600)
        } else {
            trimEndTime = videoDuration
        }
        
        // Process frames
        while !isCancelled {
            guard let frame = try await decoder.nextFrame() else {
                break
            }
            
            // Check trim range
            if frame.presentationTime >= trimEndTime {
                break
            }
            
            // Report progress - decoding
            progressHandler?(CompositingProgress(
                currentFrame: processedFrames,
                totalFrames: totalFrames,
                stage: .decoding
            ))
            
            // Convert frame to texture
            guard let rawTexture = decoder.texture(from: frame) else {
                throw CompositingPipelineError.textureConversionFailed
            }
            
            // Apply IDT if needed
            let videoTexture: MTLTexture
            if let colorSpaceName = manifest.source?.colorSpace,
               let commandBuffer = commandQueue.makeCommandBuffer() {
                let sourceSpace = RenderColorSpace.from(identifier: colorSpaceName)
                videoTexture = try idtPass.convert(
                    texture: rawTexture,
                    from: sourceSpace,
                    commandBuffer: commandBuffer
                )
                commandBuffer.commit()
                await commandBuffer.completed()
            } else {
                videoTexture = rawTexture
            }
            
            // Render graphics for this frame
            progressHandler?(CompositingProgress(
                currentFrame: processedFrames,
                totalFrames: totalFrames,
                stage: .rendering
            ))
            
            // Clear graphics texture (prepare for rendering)
            try await clearTexture(graphicsTexture)
            
            // Composite video and graphics
            progressHandler?(CompositingProgress(
                currentFrame: processedFrames,
                totalFrames: totalFrames,
                stage: .compositing
            ))
            
            try await compositeFrame(
                video: videoTexture,
                graphics: graphicsTexture,
                output: compositeTexture
            )
            
            // Copy to staging and export
            progressHandler?(CompositingProgress(
                currentFrame: processedFrames,
                totalFrames: totalFrames,
                stage: .encoding
            ))
            
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                throw CompositingPipelineError.renderFailed("Failed to create blit encoder")
            }
            
            blitEncoder.copy(from: compositeTexture, to: stagingTexture)
            blitEncoder.endEncoding()
            commandBuffer.commit()
            await commandBuffer.completed()
            
            // Export frame (VideoExporter uses frame number internally, not CMTime)
            try await exporter.append(texture: stagingTexture)
            
            processedFrames += 1
            
            // Release buffer back to pool
            await framePool.release(frame.pixelBuffer)
        }
        
        if isCancelled {
            throw CompositingPipelineError.cancelled
        }
        
        // Finalize export
        progressHandler?(CompositingProgress(
            currentFrame: totalFrames,
            totalFrames: totalFrames,
            stage: .complete
        ))
        
        try await exporter.finish()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        return CompositingResult(
            outputURL: outputURL,
            framesProcessed: processedFrames,
            duration: elapsedTime
        )
    }
    
    /// Cancels the current render operation.
    public func cancel() {
        isCancelled = true
    }
    
    /// Resets the pipeline for a new render.
    public func reset() async throws {
        isCancelled = false
        try await decoder.reset()
    }
    
    // MARK: - Private Methods
    
    private func clearTexture(_ texture: MTLTexture) async throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw CompositingPipelineError.renderFailed("Failed to create command buffer")
        }
        
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw CompositingPipelineError.renderFailed("Failed to create render encoder")
        }
        
        encoder.endEncoding()
        commandBuffer.commit()
        await commandBuffer.completed()
    }
    
    private func compositeFrame(
        video: MTLTexture,
        graphics: MTLTexture,
        output: MTLTexture
    ) async throws {
        // Get person mask if needed
        var maskTexture: MTLTexture? = nil
        
        if useBehindSubject, let provider = visionProvider {
            do {
                let mask = try await provider.segmentPeople(in: video, quality: .balanced)
                maskTexture = mask.texture
            } catch {
                // Log but continue without mask
                print("Warning: Person segmentation failed, continuing without mask: \(error)")
            }
        }
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw CompositingPipelineError.renderFailed("Failed to create command buffer")
        }
        
        // Determine blend mode and create params
        let blendMode: CompositeBlendMode = useBehindSubject && maskTexture != nil ? .behindMask : .normal
        let params = CompositeParams(
            mode: blendMode,
            maskThreshold: manifest.compositing?.depthThreshold ?? 0.5,
            edgeSoftness: manifest.compositing?.edgeSoftness ?? 0.05
        )
        
        // Run composite pass - returns the result texture
        let resultTexture = compositePass.composite(
            background: video,
            foreground: graphics,
            mask: maskTexture,
            params: params,
            commandBuffer: commandBuffer
        )
        
        // Copy result to output
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw CompositingPipelineError.renderFailed("Failed to create blit encoder")
        }
        
        blitEncoder.copy(from: resultTexture, to: output)
        blitEncoder.endEncoding()
        
        commandBuffer.commit()
        await commandBuffer.completed()
    }
}

// MARK: - Preview Support

extension VideoCompositingPipeline {
    /// Renders a single preview frame at the specified time.
    ///
    /// - Parameters:
    ///   - time: Time in the video to preview.
    ///   - outputTexture: Texture to render the preview into.
    /// - Throws: `CompositingPipelineError` if rendering fails.
    public func previewFrame(at time: CMTime, into outputTexture: MTLTexture) async throws {
        // Seek to time
        try await decoder.seek(to: time)
        
        guard let frame = try await decoder.nextFrame() else {
            throw CompositingPipelineError.renderFailed("No frame at time \(time.seconds)")
        }
        
        guard let videoTexture = decoder.texture(from: frame) else {
            throw CompositingPipelineError.textureConversionFailed
        }
        
        // Create temporary graphics texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: outputTexture.width,
            height: outputTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        
        guard let graphicsTexture = device.makeTexture(descriptor: descriptor) else {
            throw CompositingPipelineError.renderFailed("Failed to create graphics texture")
        }
        
        // Clear graphics texture
        try await clearTexture(graphicsTexture)
        
        // Composite
        try await compositeFrame(
            video: videoTexture,
            graphics: graphicsTexture,
            output: outputTexture
        )
    }
    
    /// Gets video metadata.
    public var metadata: (resolution: SIMD2<Int>, frameRate: Double, duration: CMTime) {
        (videoResolution, videoFrameRate, videoDuration)
    }
}

// MARK: - MTLCommandBuffer Extension

private extension MTLCommandBuffer {
    /// Async wait for completion
    func completed() async {
        await withCheckedContinuation { continuation in
            addCompletedHandler { _ in
                continuation.resume()
            }
        }
    }
}
