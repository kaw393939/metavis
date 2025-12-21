// TimelineExporter.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// Exports a timeline to video with transitions

import Foundation
import Metal
import AVFoundation
import CoreMedia

// MARK: - TimelineExporterError

/// Errors that can occur during timeline export.
public enum TimelineExporterError: Error, Sendable {
    case noVideoTracks
    case exportFailed(Error?)
    case cancelled
    case deviceNotFound
    case encodingFailed
    case sourceDecodeFailed(String)
}

extension TimelineExporterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noVideoTracks:
            return "Timeline has no video tracks"
        case .exportFailed(let error):
            return "Export failed: \(error?.localizedDescription ?? "Unknown error")"
        case .cancelled:
            return "Export was cancelled"
        case .deviceNotFound:
            return "Metal device not found"
        case .encodingFailed:
            return "Video encoding failed"
        case .sourceDecodeFailed(let source):
            return "Failed to decode source: \(source)"
        }
    }
}

// MARK: - ExportProgress

/// Progress information for export operations.
public struct ExportProgress: Sendable {
    /// Current frame being processed
    public let currentFrame: Int
    
    /// Total frames to process
    public let totalFrames: Int
    
    /// Progress as 0-1
    public var progress: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(currentFrame) / Double(totalFrames)
    }
    
    /// Progress as percentage
    public var percentage: Int {
        Int(progress * 100)
    }
    
    /// Estimated time remaining (seconds)
    public var estimatedTimeRemaining: Double?
    
    public init(
        currentFrame: Int,
        totalFrames: Int,
        estimatedTimeRemaining: Double? = nil
    ) {
        self.currentFrame = currentFrame
        self.totalFrames = totalFrames
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}

// MARK: - TimelineExporter

/// Exports a timeline to a video file.
///
/// Handles multi-clip sequencing, transitions, and source switching.
///
/// ## Example
/// ```swift
/// let exporter = try TimelineExporter(
///     timeline: timeline,
///     device: mtlDevice,
///     outputURL: outputURL
/// )
///
/// // Export with progress callback
/// try await exporter.export { progress in
///     print("Progress: \(progress.percentage)%")
/// }
/// ```
public actor TimelineExporter {
    
    // MARK: - Properties
    
    /// The timeline to export
    public let timeline: TimelineModel
    
    /// Metal device
    public let device: MTLDevice
    
    /// Output file URL
    public let outputURL: URL
    
    /// Command queue for GPU operations
    private let commandQueue: MTLCommandQueue
    
    /// Timeline resolver
    private let resolver: VideoTimelineResolver
    
    /// Multi-source decoder
    private let decoder: MultiSourceDecoder
    
    /// Transition renderer
    private let transitionRenderer: TransitionRenderer
    
    /// Video exporter
    private var exporter: VideoExporter?
    
    /// Cinematic look pass (optional, for face enhancement and effects)
    private var cinematicLookPass: CinematicLookPass?
    
    /// Vision provider for AI features
    private let visionProvider: VisionProvider
    
    /// Texture pool for efficient memory management
    private let texturePool: TexturePool
    
    /// Graph pipeline for node-based rendering
    private let graphPipeline: GraphPipeline?
    
    /// Whether export is cancelled
    private var isCancelled: Bool = false
    
    /// Export start time (for ETA calculation)
    private var exportStartTime: Date?
    
    // MARK: - Initialization
    
    /// Creates a timeline exporter.
    public init(
        timeline: TimelineModel,
        device: MTLDevice,
        outputURL: URL
    ) throws {
        self.timeline = timeline
        self.device = device
        self.outputURL = outputURL
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw TimelineExporterError.deviceNotFound
        }
        self.commandQueue = commandQueue
        
        self.resolver = VideoTimelineResolver(timeline: timeline)
        self.decoder = MultiSourceDecoder(device: device, timeline: timeline)
        self.transitionRenderer = try TransitionRenderer(device: device)
        self.visionProvider = VisionProvider(device: device)
        self.texturePool = TexturePool(device: device)
        
        // Initialize GraphPipeline
        // Convert TimelineModel to NodeGraph
        let graph = TimelineToGraphConverter.convert(timeline)
        do {
            self.graphPipeline = try GraphPipeline(device: device, graph: graph)
            print("TimelineExporter: Initialized GraphPipeline with \(graph.nodes.count) nodes")
        } catch {
            print("Error initializing GraphPipeline: \(error)")
            self.graphPipeline = nil
            throw error
        }
        
        self.cinematicLookPass = nil
    }
    
    // MARK: - Export
    
    /// Exports the timeline to video.
    ///
    /// - Parameter progressHandler: Called periodically with progress updates
    public func export(
        progressHandler: ((ExportProgress) -> Void)? = nil
    ) async throws {
        // Allow timelines with virtual content (procedural/graphics) but no video tracks
        guard !timeline.videoTracks.isEmpty || timeline.hasVirtualContent else {
            throw TimelineExporterError.noVideoTracks
        }
        
        isCancelled = false
        exportStartTime = Date()
        
        // Create exporter with HEVC config
        // Use 8-bit with dithering until 10-bit encoding issue is resolved
        let exporter = try VideoExporter(
            outputURL: outputURL,
            width: timeline.resolution.x,
            height: timeline.resolution.y,
            frameRate: Int(timeline.fps),
            config: VideoExportConfig(
                codec: .hevc,
                quality: 0.95,
                colorDepth: .bit10,  // TESTING: P010-corrected 10-bit path
                bandingMitigation: .none  // No dither needed with true 10-bit
            )
        )
        self.exporter = exporter
        
        let totalFrames = timeline.frameCount
        let trackID = timeline.primaryVideoTrack?.id
        
        // Process each frame
        for frame in 0..<totalFrames {
            guard !isCancelled else {
                throw TimelineExporterError.cancelled
            }
            
            let time = Double(frame) / timeline.fps
            
            // Render frame based on content type
            var texture: MTLTexture
            
            if timeline.videoTracks.isEmpty {
                // Virtual content only (procedural/graphics)
                texture = try await renderVirtualFrame(at: time, frame: frame)
            } else {
                // Video-based content
                guard let resolved = await resolver.resolvedFrame(frame, on: trackID) else {
                    // No content at this frame - render black
                    try await appendBlackFrame(to: exporter)
                    continue
                }
                
                if resolved.inTransition {
                    // Render transition
                    texture = try await renderTransition(resolved)
                } else {
                    // Render single clip
                    texture = try await renderClip(resolved)
                }
            }
            
            // Apply cinematic look pass (face enhancement, etc.)
            if cinematicLookPass != nil {
                texture = try await applyCinematicLook(to: texture, at: Float(time), frame: frame)
            }
            
            // Append to export
            try await exporter.append(texture: texture)
            
            // Report progress
            if let handler = progressHandler {
                let eta = calculateETA(currentFrame: frame, totalFrames: totalFrames)
                let progress = ExportProgress(
                    currentFrame: frame,
                    totalFrames: totalFrames,
                    estimatedTimeRemaining: eta
                )
                handler(progress)
            }
        }
        
        // Finish export
        try await exporter.finish()
    }
    
    /// Cancels the export.
    public func cancel() {
        isCancelled = true
    }
    
    /// Render single frame for testing (bypasses video export).
    /// Used for synthetic debugging to isolate render pipeline from video encoding.
    public func renderSingleFrameForTest(at time: Double) async throws -> MTLTexture {
        let frame = Int(time * timeline.fps)
        return try await renderVirtualFrame(at: time, frame: frame)
    }
    
    // MARK: - Frame Rendering
    
    /// Renders a single clip frame.
    private func renderClip(_ resolved: ResolvedFrame) async throws -> MTLTexture {
        guard let texture = try await decoder.texture(
            source: resolved.primarySource,
            at: resolved.primarySourceTime
        ) else {
            throw TimelineExporterError.sourceDecodeFailed(resolved.primarySource)
        }
        
        return texture
    }
    
    /// Renders a transition frame.
    private func renderTransition(_ resolved: ResolvedFrame) async throws -> MTLTexture {
        // Decode both frames
        guard let fromTexture = try await decoder.texture(
            source: resolved.primarySource,
            at: resolved.primarySourceTime
        ) else {
            throw TimelineExporterError.sourceDecodeFailed(resolved.primarySource)
        }
        
        guard let secondarySource = resolved.secondarySource,
              let secondaryTime = resolved.secondarySourceTime,
              let toTexture = try await decoder.texture(source: secondarySource, at: secondaryTime) else {
            // Fall back to primary if secondary not available
            return fromTexture
        }
        
        // Render transition
        let type = resolved.transitionType ?? .crossfade
        let progress = Float(resolved.transitionProgress ?? 0.5)
        let parameters = resolved.transitionParameters ?? TransitionParameters()
        
        return try await transitionRenderer.render(
            from: fromTexture,
            to: toTexture,
            type: type,
            progress: progress,
            parameters: parameters
        )
    }
    
    /// Renders a virtual frame (procedural background + graphics).
    private func renderVirtualFrame(at time: Double, frame: Int) async throws -> MTLTexture {
        guard let pipeline = graphPipeline else {
            return try await createBlackTexture()
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw TimelineExporterError.encodingFailed
        }
        
        // Create output texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: timeline.resolution.x,
            height: timeline.resolution.y,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            throw TimelineExporterError.encodingFailed
        }
        
        // Build scene from timeline
        let scene = Scene()
        if let proceduralBg = timeline.scene?.proceduralBackground {
            scene.proceduralBackground = proceduralBg
        }
        
        // Add text elements from graphics tracks
        for track in timeline.graphicsTracks {
            for element in track.elements {
                if case .text(let textElement) = element {
                    scene.textElements.append(textElement)
                }
            }
        }
        
        // Set camera from timeline
        if let camera = timeline.camera {
            scene.setCamera(camera)
        }
        
        // Update scene for current time
        scene.update(time: time)
        
        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // Convert QualityMode to MVQualityMode
        let mvQuality: MVQualityMode
        switch timeline.quality {
        case .preview, .draft:
            mvQuality = .realtime
        case .standard:
            mvQuality = .cinema
        case .cinema:
            mvQuality = .lab
        }
        
        // Create render context
        let context = RenderContext(
            device: device,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            resolution: SIMD2<Int>(timeline.resolution.x, timeline.resolution.y),
            time: time,
            scene: scene,
            quality: MVQualitySettings(mode: mvQuality),
            texturePool: texturePool
        )
        
        // Render using GraphPipeline
        try pipeline.render(context: context)
        
        // Commit and wait for completion asynchronously
        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            commandBuffer.commit()
        }
        
        return outputTexture
    }
    
    /// Creates a black texture.
    private func createBlackTexture() async throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: timeline.resolution.x,
            height: timeline.resolution.y,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TimelineExporterError.encodingFailed
        }
        
        return texture
    }
    
    /// Appends a black frame.
    private func appendBlackFrame(to exporter: VideoExporter) async throws {
        // Create black texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,  // 16-bit float for HDR precision
            width: timeline.resolution.x,
            height: timeline.resolution.y,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        
        guard let blackTexture = device.makeTexture(descriptor: descriptor) else {
            throw TimelineExporterError.encodingFailed
        }
        
        // Fill with black (already zero-initialized)
        try await exporter.append(texture: blackTexture)
    }
    
    
    /// Applies cinematic look processing (face enhancement, color grading, etc.)
    private func applyCinematicLook(to inputTexture: MTLTexture, at time: Float, frame: Int) async throws -> MTLTexture {
        guard let lookPass = cinematicLookPass,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return inputTexture
        }
        
        // Create output texture that we control
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: inputTexture.pixelFormat,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            print("[TimelineExporter] Frame \(frame): Failed to create output texture")
            return inputTexture
        }
        
        // Create a minimal render pass descriptor for context
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // Create render context
        let resolution = SIMD2<Int>(inputTexture.width, inputTexture.height)
        let context = RenderContext(
            device: device,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            resolution: resolution,
            time: Double(time),
            scene: Scene(),
            quality: MVQualitySettings(mode: .realtime),
            texturePool: texturePool
        )
        
        // Set input AND output textures on the pass
        lookPass.inputTexture = inputTexture
        lookPass.outputTexture = outputTexture
        
        do {
            try lookPass.execute(commandBuffer: commandBuffer, context: context)
            if frame == 0 || frame == 30 || frame == 60 {
                print("[TimelineExporter] Frame \(frame): CinematicLookPass executed")
            }
        } catch {
            print("[TimelineExporter] Frame \(frame): CinematicLookPass failed: \(error)")
            return inputTexture
        }
        
        commandBuffer.commit()
        await commandBuffer.waitUntilCompleted()
        
        // Return the output texture we created
        return outputTexture
    }
    // MARK: - Utilities
    
    /// Calculates estimated time remaining.
    private func calculateETA(currentFrame: Int, totalFrames: Int) -> Double? {
        guard let startTime = exportStartTime, currentFrame > 0 else {
            return nil
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let framesPerSecond = Double(currentFrame) / elapsed
        let remainingFrames = totalFrames - currentFrame
        
        return Double(remainingFrames) / framesPerSecond
    }
}

// MARK: - Convenience Factory

extension TimelineExporter {
    /// Creates an exporter with the default Metal device.
    public static func create(
        timeline: TimelineModel,
        outputURL: URL
    ) throws -> TimelineExporter {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TimelineExporterError.deviceNotFound
        }
        
        return try TimelineExporter(
            timeline: timeline,
            device: device,
            outputURL: outputURL
        )
    }
}

// MARK: - Simple Export Function

/// Exports a timeline to video (convenience function).
public func exportTimeline(
    _ timeline: TimelineModel,
    to outputURL: URL,
    device: MTLDevice? = nil,
    progressHandler: ((ExportProgress) -> Void)? = nil
) async throws {
    let mtlDevice = device ?? MTLCreateSystemDefaultDevice()
    guard let mtlDevice else {
        throw TimelineExporterError.deviceNotFound
    }
    
    let exporter = try TimelineExporter(
        timeline: timeline,
        device: mtlDevice,
        outputURL: outputURL
    )
    
    try await exporter.export(progressHandler: progressHandler)
}

// MARK: - PDF Support

extension TimelineExporter {
    /// Registers PDF page sources from the timeline.
    ///
    /// Call this after initialization to set up PDF sources defined in the manifest.
    /// PDF sources use the format: `pdf://path/to/file.pdf#page=N`
    public func registerPDFSources(pageRenderer: PageRenderer) async throws {
        // PDF sources are handled by the MultiSourceDecoder internally
        // This method is a no-op placeholder for API compatibility
        // The actual PDF rendering happens in the decoder when frames are requested
    }
}
