import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Hummingbird
import ImageIO
import Logging
@preconcurrency import Metal
import MetalVisCore
import Shared
import UniformTypeIdentifiers

/// Job queue manager for rendering tasks
public actor JobQueue {
    private var jobs: [String: RenderJob] = [:]
    private var activeJobId: String?
    private let logger: Logger
    // private let coordinator: RenderCoordinator // Disabled legacy coordinator
    private let metalRenderer: MetalRenderer
    private let graphRenderer: GraphRenderer
    private var textRenderer: SDFTextRenderer?

    public init() async throws {
        var logger = Logger(label: "com.metalvis.queue")
        logger.logLevel = .info
        self.logger = logger
        logger.info("Initializing RenderCoordinator... (DISABLED)")
        // coordinator = try RenderCoordinator()
        logger.info("Initializing MetalRenderer...")
        metalRenderer = try MetalRenderer()
        logger.info("Initializing GraphRenderer...")
        graphRenderer = try GraphRenderer(device: metalRenderer.device)

        // Try to initialize text renderer in background
        Task {
            logger.info("Starting background SDFTextRenderer initialization...")
            do {
                let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
                if let atlas = try? SDFFontAtlas(font: font, size: CGSize(width: 512, height: 512), device: metalRenderer.device) {
                    let renderer = try SDFTextRenderer(fontAtlas: atlas, device: metalRenderer.device)
                    self.setTextRenderer(renderer)
                    logger.info("SDF Text renderer initialized successfully in background")
                }
            } catch {
                logger.warning("SDF Text renderer initialization failed", metadata: ["error": "\(error)"])
            }
        }
    }

    private func setTextRenderer(_ renderer: SDFTextRenderer) {
        textRenderer = renderer
    }

    public func submitJob(_ request: VisualizationRequest) -> RenderJob {
        let totalFrames = Int(request.outputConfig.duration * Double(request.outputConfig.frameRate))
        let job = RenderJob(
            request: request,
            totalFrames: totalFrames,
            estimatedDuration: request.outputConfig.duration
        )

        jobs[job.id] = job
        logger.info("Job submitted", metadata: ["jobId": "\(job.id)"])

        // Start processing if no active job
        if activeJobId == nil {
            Task {
                await processNextJob()
            }
        }

        return job
    }

    public func submitAnimatedJob(_ config: MetalVisCore.AnimationConfig) -> RenderJob {
        // Calculate total duration from narration
        let analyzer = NarrationAnalyzer()
        let totalDuration = analyzer.estimateTotalDuration(config.narration)
        let fps = 30 // Default to 30fps for animations
        let totalFrames = Int(totalDuration * Double(fps))

        // Encode config to Data
        let configData = try! JSONEncoder().encode(config)

        let job = RenderJob(
            animationConfigData: configData,
            totalFrames: totalFrames,
            estimatedDuration: totalDuration
        )

        jobs[job.id] = job
        logger.info("Animated job submitted", metadata: [
            "jobId": "\(job.id)",
            "duration": "\(totalDuration)s",
            "frames": "\(totalFrames)"
        ])

        // Start processing if no active job
        if activeJobId == nil {
            Task {
                await processNextJob()
            }
        }

        return job
    }

    public func submitImageAnimationJob(_ request: ImageAnimationRequest) -> RenderJob {
        let fps = request.output.fps
        let totalFrames = Int(request.animation.duration * Double(fps))

        // Encode request to Data
        let requestData = try! JSONEncoder().encode(request)

        let job = RenderJob(
            imageAnimationData: requestData,
            totalFrames: totalFrames,
            estimatedDuration: request.animation.duration
        )

        jobs[job.id] = job
        logger.info("Image animation job submitted", metadata: [
            "jobId": "\(job.id)",
            "image": "\(request.imagePath)",
            "duration": "\(request.animation.duration)s",
            "frames": "\(totalFrames)"
        ])

        // Start processing if no active job
        if activeJobId == nil {
            Task {
                await processNextJob()
            }
        }

        return job
    }

    public func submitCompositionJob(_ composition: Composition) -> RenderJob {
        let fps = 30
        let totalFrames = Int(composition.duration * Double(fps))

        let compositionData = try! JSONEncoder().encode(composition)

        let job = RenderJob(
            compositionData: compositionData,
            totalFrames: totalFrames,
            estimatedDuration: composition.duration
        )

        jobs[job.id] = job
        logger.info("Composition job submitted", metadata: [
            "jobId": "\(job.id)",
            "title": "\(composition.title)",
            "duration": "\(composition.duration)s"
        ])

        if activeJobId == nil {
            Task {
                await processNextJob()
            }
        }

        return job
    }

    public func getJob(id: String) -> RenderJob? {
        return jobs[id]
    }

    public func updateJob(id: String, status: JobStatus, progress: Double, currentFrame: Int, error: String? = nil, outputPath: String? = nil) {
        guard var job = jobs[id] else { return }

        job.status = status
        job.progress = progress
        job.currentFrame = currentFrame
        job.updatedAt = Date()

        if let error = error {
            job.error = error
        }

        if let outputPath = outputPath {
            job.outputPath = outputPath
            job.completedAt = Date()
        }

        jobs[id] = job

        logger.info("Job updated", metadata: [
            "jobId": "\(id)",
            "status": "\(status.rawValue)",
            "progress": "\(progress)"
        ])
    }

    private func processNextJob() async {
        // Find next queued job
        guard let nextJob = jobs.values.first(where: { $0.status == .queued }) else {
            activeJobId = nil
            return
        }

        activeJobId = nextJob.id
        updateJob(id: nextJob.id, status: .rendering, progress: 0.0, currentFrame: 0)

        // Create output path
        let outputDir = "/Users/kwilliams/Desktop/metalvis/output"
        let outputPath = "\(outputDir)/\(nextJob.id).mp4"

        do {
            if nextJob.isImageAnimation {
                // Render image animation job
                try await renderImageAnimationJob(nextJob, outputPath: outputPath)
            } else if nextJob.isComposition {
                // Render Composition job
                try await renderCompositionJob(nextJob, outputPath: outputPath)
            } else if nextJob.isAnimated {
                // Render animated job (handles its own completion)
                try await renderAnimatedJob(nextJob, outputPath: outputPath)
            } else if nextJob.request != nil {
                // Render static job using coordinator
                /*
                try await coordinator.render(
                    request: request,
                    outputPath: outputPath
                ) { [weak self] progress, currentFrame in
                    guard let self = self else { return }
                    await self.updateJobProgress(id: nextJob.id, progress: progress, currentFrame: currentFrame)
                }
                */
                logger.warning("Legacy static render job skipped (RenderCoordinator disabled)")

                // Mark static job as completed
                await completeJob(id: nextJob.id, outputPath: outputPath)
            }

        } catch {
            logger.error("Rendering failed", metadata: [
                "jobId": "\(nextJob.id)",
                "error": "\(error)"
            ])
            await failJob(id: nextJob.id, error: error.localizedDescription)
        }
    }

    private func renderCompositionJob(_ job: RenderJob, outputPath: String) async throws {
        guard let compositionData = job.compositionData else {
            throw NSError(domain: "JobQueue", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing composition data"])
        }

        let composition = try JSONDecoder().decode(Composition.self, from: compositionData)
        _ = composition // Silence unused variable warning


        /*
        try await coordinator.renderComposition(
            composition: composition,
            outputPath: outputPath
        ) { [weak self] progress, currentFrame in
            guard let self = self else { return }
            await self.updateJobProgress(id: job.id, progress: progress, currentFrame: currentFrame)
        }
        */
        logger.warning("Composition render job skipped (RenderCoordinator disabled)")

        await completeJob(id: job.id, outputPath: outputPath)
    }

    private func renderAnimatedJob(_ job: RenderJob, outputPath: String) async throws {
        guard let configData = job.animationConfigData else {
            throw NSError(domain: "JobQueue", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing animation config"])
        }

        // Decode config
        let config = try JSONDecoder().decode(MetalVisCore.AnimationConfig.self, from: configData)

        // Extract node positions (convert to 2D for rendering)
        let nodePositions: [String: SIMD3<Float>] = config.graph.nodes.reduce(into: [:]) { result, node in
            if let pos = node.position, pos.count >= 3 {
                result[node.id] = SIMD3<Float>(pos[0], pos[1], pos[2])
            }
        }

        // Build timeline
        let builder = TimelineBuilder()
        let timeline = try builder.buildTimeline(from: config, nodePositions: nodePositions)

        logger.info("Built animation timeline", metadata: [
            "duration": "\(timeline.duration)s",
            "frames": "\(timeline.frameCount)",
            "markers": "\(timeline.markers.count)"
        ])

        // Create frames directory
        let framesDir = outputPath.replacingOccurrences(of: ".mp4", with: "_frames")
        try FileManager.default.createDirectory(atPath: framesDir, withIntermediateDirectories: true)

        // Resolution (1920x1080 for now)
        let width = 1920
        let height = 1080

        // Render frame-by-frame
        for frameIndex in 0 ..< timeline.frameCount {
            let time = Double(frameIndex) / Double(timeline.fps)
            let state = timeline.evaluate(at: time)

            // Convert TimelineState to drawable nodes/edges/labels
            let (nodes, edges, labels) = try await convertStateToDrawables(
                config: config,
                state: state,
                nodePositions: nodePositions,
                width: width,
                height: height
            )

            // Render frame with Metal
            let texture = try metalRenderer.renderGraphFrame(
                width: width,
                height: height,
                nodes: nodes,
                edges: edges,
                labels: labels,
                graphRenderer: graphRenderer,
                textRenderer: textRenderer
            )

            // Convert to sRGB for export
            let srgbTexture = try metalRenderer.convertToSRGB(texture)

            // Export to PNG
            let framePath = "\(framesDir)/frame_\(String(format: "%04d", frameIndex)).png"
            try await exportTextureToPNG(texture: srgbTexture, path: framePath)

            let progress = Double(frameIndex + 1) / Double(timeline.frameCount)
            await updateJobProgress(id: job.id, progress: progress, currentFrame: frameIndex + 1)
        }

        logger.info("Animation frames rendered", metadata: [
            "jobId": "\(job.id)",
            "frames": "\(timeline.frameCount)",
            "framesDir": "\(framesDir)"
        ])

        // Encode frames to MP4 with FFmpeg
        let videoPath = outputPath
        try await encodeFramesToVideo(framesDir: framesDir, outputPath: videoPath, frameRate: timeline.fps)

        logger.info("Video encoded successfully", metadata: [
            "jobId": "\(job.id)",
            "outputPath": "\(videoPath)"
        ])

        // Mark job as completed
        await completeJob(id: job.id, outputPath: videoPath)
    }

    private func renderImageAnimationJob(_ job: RenderJob, outputPath: String) async throws {
        guard let requestData = job.imageAnimationData else {
            throw NSError(domain: "JobQueue", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing image animation request"])
        }

        // Decode request
        let request = try JSONDecoder().decode(ImageAnimationRequest.self, from: requestData)

        logger.info("Starting image animation render", metadata: [
            "jobId": "\(job.id)",
            "image": "\(request.imagePath)",
            "duration": "\(request.animation.duration)s",
            "output": "\(request.output.width)x\(request.output.height) @ \(request.output.fps)fps"
        ])

        // Create command queue for renderer
        guard let commandQueue = metalRenderer.device.makeCommandQueue() else {
            throw NSError(domain: "JobQueue", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create command queue"])
        }

        // Create image loader
        let imageLoader = ImageLoader(device: metalRenderer.device, commandQueue: commandQueue)

        // Load source image
        let sourceTexture = try imageLoader.loadTexture(from: request.imagePath)

        // Create renderer
        let renderer = ImageAnimationRenderer(
            device: metalRenderer.device,
            commandQueue: commandQueue
        )

        // Generate keyframes
        let keyframes = try renderer.publicGenerateKeyframes(from: request.animation)

        // Create video encoder
        let encoder = VideoEncoder()

        // Create frame stream
        let (stream, continuation) = AsyncStream.makeStream(of: MTLTexture.self)

        // Render frames in background
        Task {
            do {
                let fps = request.output.fps
                let duration = request.animation.duration
                let totalFrames = Int(duration * Double(fps))

                for frameIndex in 0 ..< totalFrames {
                    let time = Double(frameIndex) / Double(fps)
                    let frame = try await renderer.publicRenderFrame(
                        source: sourceTexture,
                        keyframes: keyframes,
                        time: time,
                        easing: request.animation.easing,
                        outputSize: (request.output.width, request.output.height),
                        quality: request.quality
                    )
                    
                    // Convert to sRGB for encoding
                    let srgbFrame = try metalRenderer.convertToSRGB(frame)
                    
                    continuation.yield(srgbFrame)

                    let progress = Double(frameIndex + 1) / Double(totalFrames)
                    await self.updateJobProgress(id: job.id, progress: progress, currentFrame: frameIndex + 1)
                }

                continuation.finish()
            } catch {
                logger.error("Frame rendering error", metadata: [
                    "error": "\(error)",
                    "jobId": "\(job.id)"
                ])
                await self.failJob(id: job.id, error: "\(error)")
                continuation.finish()
            }
        }

        // Encode frames to video
        nonisolated(unsafe) let streamToEncode = stream
        try await encoder.encode(
            frames: streamToEncode,
            outputURL: URL(fileURLWithPath: outputPath),
            width: request.output.width,
            height: request.output.height,
            frameRate: request.output.fps,
            codec: request.output.codec ?? "h264",
            quality: "high"
        )

        logger.info("Image animation complete", metadata: [
            "jobId": "\(job.id)",
            "frames": "\(job.totalFrames)",
            "outputPath": "\(outputPath)"
        ])

        // Mark job as completed
        await completeJob(id: job.id, outputPath: outputPath)
    }

    private func updateJobProgress(id: String, progress: Double, currentFrame: Int) async {
        updateJob(id: id, status: .rendering, progress: progress, currentFrame: currentFrame)
    }

    public func completeJob(id: String, outputPath: String) async {
        guard let job = jobs[id] else { return }
        updateJob(
            id: id,
            status: .completed,
            progress: 1.0,
            currentFrame: job.totalFrames,
            outputPath: outputPath
        )
        activeJobId = nil

        // Process next job
        await processNextJob()
    }

    public func failJob(id: String, error: String) async {
        updateJob(id: id, status: .failed, progress: 0.0, currentFrame: 0, error: error)
        activeJobId = nil

        // Process next job
        await processNextJob()
    }

    // MARK: - Helper Methods

    /// Convert timeline state to drawable nodes and edges for Metal rendering
    private func convertStateToDrawables(
        config: MetalVisCore.AnimationConfig,
        state: TimelineState,
        nodePositions: [String: SIMD3<Float>],
        width: Int,
        height: Int
    ) async throws -> (nodes: [NodeDrawable], edges: [EdgeDrawable], labels: [SDFTextRenderer.LabelRequest]) {
        var nodes: [NodeDrawable] = []
        var edges: [EdgeDrawable] = []
        var labels: [SDFTextRenderer.LabelRequest] = []

        // Convert nodes
        for node in config.graph.nodes {
            guard let pos3D = nodePositions[node.id] else { continue }

            // Apply camera transformation (view + projection matrices)
            let aspectRatio = Float(width) / Float(height)
            let viewMatrix = state.camera.viewMatrix()
            let projectionMatrix = state.camera.projectionMatrix(aspectRatio: aspectRatio)
            let mvpMatrix = projectionMatrix * viewMatrix

            // Transform 3D world position to clip space
            let worldPos = SIMD4<Float>(pos3D.x, pos3D.y, pos3D.z, 1.0)
            let clipPos = mvpMatrix * worldPos

            // Skip nodes behind camera (negative Z in clip space)
            guard clipPos.w > 0, clipPos.z >= 0 else { continue }

            // Perspective divide to get normalized device coordinates [-1, 1]
            let ndc = SIMD2<Float>(clipPos.x / clipPos.w, clipPos.y / clipPos.w)

            // Convert NDC to screen coordinates [0, width/height]
            let screenPos = SIMD2<Float>(
                (ndc.x + 1.0) * 0.5 * Float(width),
                (1.0 - ndc.y) * 0.5 * Float(height) // Flip Y for screen space
            )

            // Get animation state
            let nodeState = state.graph.nodeState(node.id)

            // Base color from style or default
            let baseColor: SIMD4<Float>
            if let styleColor = config.style?.nodeColor, styleColor.count >= 4 {
                baseColor = SIMD4<Float>(styleColor[0], styleColor[1], styleColor[2], styleColor[3])
            } else {
                baseColor = SIMD4<Float>(0.3, 0.6, 0.9, 1.0) // Default blue
            }

            // Apply animation state
            var color = baseColor
            if let stateColor = nodeState.color {
                color = SIMD4<Float>(stateColor.x, stateColor.y, stateColor.z, baseColor.w)
            }
            color.w *= nodeState.opacity // Apply opacity

            // Add highlight glow
            if nodeState.highlightIntensity > 0 {
                let highlightColor: SIMD4<Float>
                if let hColor = config.style?.highlightColor, hColor.count >= 4 {
                    highlightColor = SIMD4<Float>(hColor[0], hColor[1], hColor[2], hColor[3])
                } else {
                    highlightColor = SIMD4<Float>(1.0, 0.8, 0.2, 1.0) // Gold
                }
                let intensity = nodeState.highlightIntensity
                color = color * (1.0 - intensity) + highlightColor * intensity
            }

            nodes.append(NodeDrawable(
                id: node.id,
                position: screenPos,
                size: 30.0 * nodeState.scale, // Base size 30px
                color: color
            ))

            // Generate text label if node is visible
            if nodeState.opacity > 0.1, !node.label.isEmpty {
                // Position label below the node
                let labelPos = CGPoint(
                    x: CGFloat(screenPos.x),
                    y: CGFloat(screenPos.y + 40.0 * nodeState.scale) // Below node
                )

                // Egyptian-themed styling
                let textColor = SIMD4<Float>(0.95, 0.85, 0.6, nodeState.opacity) // Warm golden text
                // Note: Background color is not supported in SDFTextRenderer yet, using outline instead
                let outlineColor = SIMD4<Float>(0.08, 0.06, 0.05, 0.85 * nodeState.opacity) // Dark brown outline

                labels.append(SDFTextRenderer.LabelRequest(
                    text: node.label,
                    position: labelPos,
                    color: textColor,
                    fontSize: 14.0,
                    alignment: .center,
                    outlineColor: outlineColor,
                    outlineWidth: 2.0
                ))
            }
        }

        // Convert edges
        for edge in config.graph.edges {
            guard let sourcePos = nodePositions[edge.source],
                  let targetPos = nodePositions[edge.target] else { continue }

            // Project to screen space
            let sourceScreen = SIMD2<Float>(
                sourcePos.x * 100.0 + Float(width) / 2.0,
                sourcePos.y * 100.0 + Float(height) / 2.0
            )
            let targetScreen = SIMD2<Float>(
                targetPos.x * 100.0 + Float(width) / 2.0,
                targetPos.y * 100.0 + Float(height) / 2.0
            )

            // Get animation state
            let edgeState = state.graph.edgeState(edge.id)

            // Base color
            let baseColor: SIMD4<Float>
            if let styleColor = config.style?.edgeColor, styleColor.count >= 4 {
                baseColor = SIMD4<Float>(styleColor[0], styleColor[1], styleColor[2], styleColor[3])
            } else {
                baseColor = SIMD4<Float>(0.5, 0.5, 0.5, 0.6) // Gray
            }

            var color = baseColor
            color.w *= edgeState.opacity

            // Apply highlight
            if edgeState.highlightIntensity > 0 {
                let highlightColor: SIMD4<Float>
                if let hColor = config.style?.highlightColor, hColor.count >= 4 {
                    highlightColor = SIMD4<Float>(hColor[0], hColor[1], hColor[2], hColor[3])
                } else {
                    highlightColor = SIMD4<Float>(1.0, 0.8, 0.2, 1.0)
                }
                let intensity = edgeState.highlightIntensity
                color = color * (1.0 - intensity) + highlightColor * intensity
            }

            edges.append(EdgeDrawable(
                source: sourceScreen,
                target: targetScreen,
                thickness: 2.0 * edgeState.thickness,
                color: color
            ))
        }

        return (nodes, edges, labels)
    }

    /// Export Metal texture to PNG file
    private func exportTextureToPNG(texture: MTLTexture, path: String) async throws {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bufferSize = bytesPerRow * height

        var pixelData = [UInt8](repeating: 0, count: bufferSize)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&pixelData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        // Create CGImage from pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let dataProvider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: dataProvider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            throw NSError(domain: "JobQueue", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }

        // Write to PNG file
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "JobQueue", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "JobQueue", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG file"])
        }
    }

    /// Encode PNG frame sequence to MP4 video using AVFoundation (native macOS/M3 optimized)
    private func encodeFramesToVideo(framesDir: String, outputPath: String, frameRate: Int) async throws {
        logger.info("Starting AVFoundation encoding", metadata: [
            "framesDir": "\(framesDir)",
            "outputPath": "\(outputPath)",
            "frameRate": "\(frameRate)"
        ])

        // Run encoding in detached task to avoid blocking actor
        try await Task.detached {
            let outputURL = URL(fileURLWithPath: outputPath)

            // Remove existing file if present
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch CocoaError.fileNoSuchFile {
                // Expected case - file doesn't exist
            } catch {
                // Log but continue - might be permission issue
                print("Warning: Failed to remove existing output: \(error)")
            }

            // Create asset writer
            guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
                throw NSError(domain: "JobQueue", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create AVAssetWriter"
                ])
            }

            // Configure video settings for H.264 with Apple Silicon optimization
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000, // 6 Mbps
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: frameRate
                ]
            ]

            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = false

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: 1920,
                    kCVPixelBufferHeightKey as String: 1080
                ]
            )

            writer.add(writerInput)

            guard writer.startWriting() else {
                throw NSError(domain: "JobQueue", code: 6, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")"
                ])
            }

            writer.startSession(atSourceTime: .zero)

            // Get frame files
            let frameFiles = try FileManager.default.contentsOfDirectory(atPath: framesDir)
                .filter { $0.hasPrefix("frame_") && $0.hasSuffix(".png") }
                .sorted()

            // Encode frames
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            var frameIndex = 0

            for frameFile in frameFiles {
                let framePath = "\(framesDir)/\(frameFile)"
                let frameURL = URL(fileURLWithPath: framePath)

                // Wait for input to be ready
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                // Load PNG as CGImage using ImageIO
                guard let imageSource = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
                else {
                    continue
                }

                // Create pixel buffer from CGImage
                var pixelBuffer: CVPixelBuffer?
                let status = CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    cgImage.width,
                    cgImage.height,
                    kCVPixelFormatType_32ARGB,
                    nil,
                    &pixelBuffer
                )

                guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                    continue
                }

                CVPixelBufferLockBaseAddress(buffer, [])
                let pixelData = CVPixelBufferGetBaseAddress(buffer)
                let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

                guard let context = CGContext(
                    data: pixelData,
                    width: cgImage.width,
                    height: cgImage.height,
                    bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: rgbColorSpace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                ) else {
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    continue
                }

                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                CVPixelBufferUnlockBaseAddress(buffer, [])

                // Append pixel buffer
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                adaptor.append(buffer, withPresentationTime: presentationTime)

                frameIndex += 1
            }

            // Finish writing
            writerInput.markAsFinished()
            await writer.finishWriting()

            if writer.status == .failed {
                throw NSError(domain: "JobQueue", code: 7, userInfo: [
                    NSLocalizedDescriptionKey: "Video encoding failed: \(writer.error?.localizedDescription ?? "unknown")"
                ])
            }
        }.value

        logger.info("AVFoundation encoding completed", metadata: [
            "outputPath": "\(outputPath)",
            "frameRate": "\(frameRate)"
        ])

        // Clean up PNG frames after successful encoding
        logger.info("Cleaning up frame files", metadata: ["framesDir": "\(framesDir)"])
        do {
            try FileManager.default.removeItem(atPath: framesDir)
            logger.info("Frame files deleted", metadata: ["framesDir": "\(framesDir)"])
        } catch {
            logger.warning("Failed to delete frame files", metadata: [
                "framesDir": "\(framesDir)",
                "error": "\(error.localizedDescription)"
            ])
            // Don't throw - video was successful, cleanup is just a nice-to-have
        }
    }
}
