import Metal
import CoreGraphics

public class StandardPipeline: RenderPipeline {
    public let textPass: TextPass
    public let glyphManager: GlyphManager
    public let fontRegistry: FontRegistry
    
    // Background rendering
    public let backgroundPass: BackgroundPass
    
    // AI Vision Components
    public private(set) var depthEstimator: (any DepthEstimator)?
    public private(set) var visionProvider: VisionProvider?
    public private(set) var depthCompositor: DepthCompositor?
    public private(set) var textLayoutPlanner: TextLayoutPlanner?
    
    /// Whether AI features are enabled
    public var aiEnabled: Bool = false
    
    public init(device: MTLDevice) throws {
        self.fontRegistry = FontRegistry()
        // Register default font
        // Note: In a real app, we'd handle font loading more gracefully
        _ = try? fontRegistry.register(name: "Helvetica", size: 64)
        
        self.glyphManager = GlyphManager(device: device, fontRegistry: fontRegistry)
        self.textPass = TextPass(glyphManager: glyphManager)
        
        let library = try ShaderLibrary.loadDefaultLibrary(device: device)
        try textPass.setup(device: device, library: library)
        
        // Initialize background pass (loads its own shader library separately)
        self.backgroundPass = try BackgroundPass(device: device)
        
        // Initialize AI components
        do {
            self.depthEstimator = try MLDepthEstimator(device: device)
            self.visionProvider = VisionProvider(device: device)
            self.depthCompositor = try DepthCompositor(device: device)
            self.textLayoutPlanner = TextLayoutPlanner()
            self.aiEnabled = true
        } catch {
            print("StandardPipeline: AI components not available: \(error)")
            self.aiEnabled = false
        }
    }
    
    /// Enable AI features with custom components
    public func enableAI(
        depthEstimator: (any DepthEstimator)? = nil,
        visionProvider: VisionProvider? = nil,
        depthCompositor: DepthCompositor? = nil,
        textLayoutPlanner: TextLayoutPlanner? = nil
    ) {
        if let de = depthEstimator { self.depthEstimator = de }
        if let vp = visionProvider { self.visionProvider = vp }
        if let dc = depthCompositor { self.depthCompositor = dc }
        if let tlp = textLayoutPlanner { self.textLayoutPlanner = tlp }
        self.aiEnabled = true
    }
    
    public func render(context: RenderContext) throws {
        print("StandardPipeline: render called at time \(context.time)")
        let time = Float(context.time)
        let viewportSize = SIMD2<Float>(Float(context.resolution.x), Float(context.resolution.y))
        
        // 1. Render procedural background if specified
        if let procBackground = context.scene.proceduralBackground,
           let outputTexture = context.renderPassDescriptor.colorAttachments[0].texture {
            try backgroundPass.render(
                commandBuffer: context.commandBuffer,
                background: procBackground,
                outputTexture: outputTexture,
                time: time
            )
        }
        
        // 2. Render text elements from the scene
        if context.scene.textElements.isEmpty {
             print("StandardPipeline: No text elements in scene!")
        }
        for (index, element) in context.scene.textElements.enumerated() {
            // Check timing - skip if element isn't active yet or has expired
            if time < element.startTime {
                continue
            }
            if element.duration > 0 && time > element.startTime + element.duration {
                continue
            }
            print("StandardPipeline: Rendering element \(index) at time \(time) (Start: \(element.startTime), Dur: \(element.duration))")
            
            // Calculate local time (time since element started)
            let localTime = time - element.startTime
            
            // Evaluate animation if present
            var animatedPosition = element.position
            var animatedOpacity: Float = 1.0
            var animatedScale: Float = 1.0
            var visibleText = element.content
            
            if let animConfig = element.animation {
                let animState = TextAnimationEvaluator.evaluate(
                    config: animConfig,
                    time: localTime,
                    elementDuration: element.duration,
                    textLength: element.content.count,
                    viewportSize: viewportSize
                )
                
                // Apply animation state
                // Convert pixel offset to match position mode
                var positionOffset = animState.positionOffset
                if element.positionMode == .normalized {
                    // Convert pixel offset to normalized (0-1) space
                    positionOffset.x /= viewportSize.x
                    positionOffset.y /= viewportSize.y
                }
                animatedPosition = element.position + positionOffset
                animatedOpacity = animState.opacity
                animatedScale = animState.scale
                
                // Handle typewriter effect
                if animState.visibleCharacters < element.content.count {
                    let endIndex = element.content.index(
                        element.content.startIndex,
                        offsetBy: min(animState.visibleCharacters, element.content.count)
                    )
                    visibleText = String(element.content[..<endIndex])
                }
                
                // Skip if fully transparent
                if animatedOpacity <= 0.001 {
                    continue
                }
            }
            
            // Build style with animated opacity
            var animatedColor = element.color
            animatedColor.w *= animatedOpacity
            
            let style = TextStyle(
                color: animatedColor,
                outlineColor: element.outlineColor,
                outlineWidth: element.outlineWidth,
                shadowColor: element.shadowColor,
                shadowOffset: element.shadowOffset,
                shadowBlur: element.shadowBlur
            )
            
            // Apply scale to font size
            let animatedFontSize = element.fontSize * animatedScale
            
            textPass.add(command: TextDrawCommand(
                text: visibleText,
                position: animatedPosition,
                fontSize: CGFloat(animatedFontSize),
                style: style,
                fontID: 1, // Assuming default font
                anchor: element.anchor,
                alignment: element.alignment,
                positionMode: element.positionMode,
                rotation: element.rotation ?? .zero,
                scale: element.scale ?? .one
            ))
        }
        
        try textPass.execute(commandBuffer: context.commandBuffer, context: context)
    }
    
    // MARK: - AI-Enhanced Rendering
    
    /// Render with AI-powered depth compositing
    /// - Parameters:
    ///   - context: Render context
    ///   - videoTexture: Optional video frame to composite behind
    ///   - compositingConfig: Compositing configuration
    /// - Returns: The rendered/composited texture (if videoTexture provided)
    public func renderWithDepthCompositing(
        context: RenderContext,
        videoTexture: MTLTexture? = nil,
        compositingConfig: CompositingDefinition? = nil
    ) async throws -> MTLTexture? {
        
        guard aiEnabled, let videoTexture = videoTexture else {
            // Fallback to standard rendering
            try render(context: context)
            return nil
        }
        
        let config = compositingConfig ?? CompositingDefinition()
        
        // 1. Run AI analysis in parallel
        async let depthTask: DepthMap? = {
            if config.enableDepthEstimation, let estimator = self.depthEstimator {
                return try? await estimator.estimateDepth(from: videoTexture)
            }
            return nil
        }()
        
        async let saliencyTask: SaliencyMap? = {
            if config.enableSmartPlacement, let provider = self.visionProvider {
                return try? await provider.detectSaliency(in: videoTexture)
            }
            return nil
        }()
        
        async let segmentationTask: SegmentationMask? = {
            if let provider = self.visionProvider {
                if #available(macOS 12.0, iOS 15.0, *) {
                    return try? await provider.segmentPeople(in: videoTexture)
                }
            }
            return nil
        }()
        
        let (depthMap, saliency, segmentation) = await (depthTask, saliencyTask, segmentationTask)
        
        // 2. Smart text placement (if enabled)
        if config.enableSmartPlacement, let planner = textLayoutPlanner {
            let frameSize = CGSize(width: videoTexture.width, height: videoTexture.height)
            
            for element in context.scene.textElements where element.autoPlace {
                let placement = try await planner.findOptimalPlacement(
                    for: element.content,
                    saliency: saliency,
                    segmentation: segmentation,
                    frameSize: frameSize
                )
                
                // Apply placement to text commands
                // (This would modify the render context or text pass)
                print("Optimal placement for '\(element.content)': \(placement.bounds)")
            }
        }
        
        // 3. Set depth texture for occlusion
        if let depth = depthMap {
            textPass.depthTexture = depth.texture
        }
        
        // 4. Render text layer
        try render(context: context)
        
        // 5. Depth-aware compositing
        if let compositor = depthCompositor,
           let depth = depthMap,
           let textTexture = context.renderPassDescriptor.colorAttachments[0].texture {
            
            let result = try await compositor.composite(
                text: textTexture,
                video: videoTexture,
                depth: depth,
                mode: config.compositeMode,
                depthThreshold: config.depthThreshold,
                edgeSoftness: config.edgeSoftness
            )
            
            return result
        }
        
        return nil
    }
}
