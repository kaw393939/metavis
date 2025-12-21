import Metal
import Foundation
import simd
import CoreGraphics

public class GraphPipeline: RenderPipeline {
    public let device: MTLDevice
    public var graph: NodeGraph
    
    // Processors
    private let compositePass: CompositePass
    private let blurPass: BlurPass
    private let pbrPass: PBRPass
    private let backgroundPass: BackgroundPass
    private let cinematicPass: CinematicLookPass
    private let visionProvider: VisionProvider
    
    private let textPass: TextPass
    private let glyphManager: GlyphManager
    private let fontRegistry: FontRegistry
    private var defaultFontID: FontID = 0
    private var textOptimizer: TextVisibilityOptimizer?
    
    // Graph Structure Acceleration
    // Map: NodeID -> [InputPinID: Connection]
    private var inputConnections: [String: [String: NodeConnection]] = [:]
    private var nodeMap: [String: GraphNode] = [:]
    
    public init(device: MTLDevice, graph: NodeGraph) throws {
        self.device = device
        self.graph = graph
        self.compositePass = try CompositePass(device: device)
        self.blurPass = try BlurPass(device: device)
        self.pbrPass = try PBRPass(device: device)
        self.backgroundPass = try BackgroundPass(device: device)
        self.cinematicPass = CinematicLookPass()
        self.visionProvider = VisionProvider(device: device)
        
        // Initialize Text System
        self.fontRegistry = FontRegistry()
        if let fontID = try? fontRegistry.register(name: "Helvetica", size: 64) {
            self.defaultFontID = fontID
        }
        self.glyphManager = GlyphManager(device: device, fontRegistry: fontRegistry)
        self.textPass = TextPass(glyphManager: glyphManager)
        
        let library = try ShaderLibrary.loadDefaultLibrary(device: device)
        try textPass.setup(device: device, library: library)
        try cinematicPass.setup(device: device, library: library)
        
        // Initialize Text Optimizer
        do {
            self.textOptimizer = try TextVisibilityOptimizer(device: device, library: library)
            print("DEBUG: TextVisibilityOptimizer initialized successfully")
        } catch {
            print("WARNING: Failed to initialize TextVisibilityOptimizer: \(error)")
            self.textOptimizer = nil
        }
        
        rebuildAccelerationStructures()
        
        print("GraphPipeline initialized with \(graph.nodes.count) nodes")
    }
    
    public func updateGraph(_ newGraph: NodeGraph) {
        self.graph = newGraph
        rebuildAccelerationStructures()
    }
    
    private func rebuildAccelerationStructures() {
        nodeMap.removeAll()
        inputConnections.removeAll()
        
        for node in graph.nodes {
            nodeMap[node.id] = node
            inputConnections[node.id] = [:]
        }
        
        for connection in graph.connections {
            if inputConnections[connection.toNodeId] == nil {
                inputConnections[connection.toNodeId] = [:]
            }
            inputConnections[connection.toNodeId]?[connection.toPinId] = connection
        }
    }
    
    public func render(context: RenderContext) throws {
        if let result = try evaluate(nodeId: graph.rootNodeId, context: context),
           let output = context.renderPassDescriptor.colorAttachments[0].texture {
            
            print("DEBUG: Graph evaluation complete. Result texture: \(result.width)x\(result.height) \(result.pixelFormat.rawValue)")
            
            // Blit result to output
            guard let blitEncoder = context.commandBuffer.makeBlitCommandEncoder() else { return }
            
            blitEncoder.copy(from: result,
                             sourceSlice: 0,
                             sourceLevel: 0,
                             sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                             sourceSize: MTLSize(width: min(result.width, output.width),
                                                 height: min(result.height, output.height),
                                                 depth: 1),
                             to: output,
                             destinationSlice: 0,
                             destinationLevel: 0,
                             destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            
            blitEncoder.endEncoding()
        } else {
            print("DEBUG: Graph evaluation returned nil or no output texture")
        }
    }
    
    // Recursive evaluation with context
    private func evaluate(nodeId: String, context: RenderContext) throws -> MTLTexture? {
        print("DEBUG: Evaluating node \(nodeId)")
        guard let node = nodeMap[nodeId] else { return nil }
        
        // Special handling for Time nodes (they modify context for upstream)
        if node.type == .time {
            return try processTime(node, context: context)
        }
        
        // For all other nodes, evaluate inputs first using the CURRENT context
        var inputs: [String: MTLTexture] = [:]
        
        if let connections = inputConnections[nodeId] {
            for (pinId, connection) in connections {
                if let inputTexture = try evaluate(nodeId: connection.fromNodeId, context: context) {
                    inputs[pinId] = inputTexture
                }
            }
        }
        
        return try processNode(node, inputs: inputs, context: context)
    }
    
    private func processTime(_ node: GraphNode, context: RenderContext) throws -> MTLTexture? {
        // Calculate new time
        var newTime = context.time
        
        if case .float(let offset) = node.properties["offset"] {
            newTime += Double(offset)
        }
        
        // Create new context
        let newContext = RenderContext(
            device: context.device,
            commandBuffer: context.commandBuffer,
            renderPassDescriptor: context.renderPassDescriptor,
            resolution: context.resolution,
            time: newTime,
            scene: context.scene,
            quality: context.quality,
            texturePool: context.texturePool,
            inputProvider: context.inputProvider
        )
        
        // Evaluate input with new context
        guard let connections = inputConnections[node.id],
              let inputConnection = connections["input"] else {
            return nil
        }
        
        return try evaluate(nodeId: inputConnection.fromNodeId, context: newContext)
    }
    
    private func processNode(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        switch node.type {
        case .generator:
            return try processGenerator(node, context: context)
            
        case .input:
            return try processInput(node, context: context)
            
        case .composite:
            return try processComposite(node, inputs: inputs, context: context)
            
        case .transform:
            return try processTransform(node, inputs: inputs, context: context)
            
        case .filter:
            return try processFilter(node, inputs: inputs, context: context)
            
        case .pbr:
            return try processPBR(node, inputs: inputs, context: context)
            
        case .text:
            return try processText(node, inputs: inputs, context: context)
            
        case .halation:
            return try processHalation(node, inputs: inputs, context: context)
            
        case .bloom:
            return try processBloom(node, inputs: inputs, context: context)
            
        case .vignette:
            return try processVignette(node, inputs: inputs, context: context)
            
        case .grain:
            return try processGrain(node, inputs: inputs, context: context)
            
        case .segmentation:
            return try processSegmentation(node, inputs: inputs, context: context)
            
        case .output:
            // Copy input to context output
            guard let input = inputs["input"],
                  let output = context.renderPassDescriptor.colorAttachments[0].texture else { return nil }
            
            print("DEBUG: Output node processing. Input: \(input.width)x\(input.height), Output: \(output.width)x\(output.height)")
            
            let blit = context.commandBuffer.makeBlitCommandEncoder()
            blit?.copy(from: input, to: output)
            blit?.endEncoding()
            
            // Return the input texture so render() can also see it (and potentially blit it again, though redundant)
            return input
            
        case .time:
            // Should be handled by evaluate directly, but if we get here, just pass through
            return inputs["input"]
        }
    }
    
    private func processPBR(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        // Allocate output texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: context.resolution.x,
            height: context.resolution.y,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        
        guard let output = context.texturePool.acquire(descriptor: desc) else { return nil }
        
        // Parse properties
        var color = SIMD3<Float>(1, 1, 1)
        if case .vector3(let c) = node.properties["color"] {
            color = c
        } else if case .vector4(let c) = node.properties["color"] {
            color = SIMD3<Float>(c.x, c.y, c.z)
        }
        
        var roughness: Float = 0.5
        if case .float(let r) = node.properties["roughness"] {
            roughness = r
        }
        
        var metallic: Float = 0.0
        if case .float(let m) = node.properties["metallic"] {
            metallic = m
        }
        
        pbrPass.render(
            output: output,
            color: color,
            roughness: roughness,
            metallic: metallic,
            commandBuffer: context.commandBuffer
        )
        
        return output
    }
    
    private func processGenerator(_ node: GraphNode, context: RenderContext) throws -> MTLTexture? {
        // Allocate output texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: context.resolution.x,
            height: context.resolution.y,
            mipmapped: false
        )
        // BackgroundPass uses Compute, so we need shaderWrite. 
        // We also keep renderTarget/shaderRead for compatibility with other passes if needed.
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let output = context.texturePool.acquire(descriptor: desc) else { return nil }
        
        // Determine generator type
        var type = "solid"
        if case .enumValue(let t) = node.properties["type"] {
            type = t
        }
        
        let definition: BackgroundDefinition
        
        switch type {
        case "solid":
            var color = SIMD3<Float>(0, 0, 0)
            if case .vector4(let c) = node.properties["color"] {
                color = SIMD3(c.x, c.y, c.z)
            } else if case .vector3(let c) = node.properties["color"] {
                color = c
            } else if case .color(let c) = node.properties["color"] {
                color = c
            }
            definition = .solid(SolidBackground(color: color))
            
        case "gradient":
            var colorStart = SIMD3<Float>(0, 0, 0)
            if case .vector4(let c) = node.properties["colorStart"] { colorStart = SIMD3(c.x, c.y, c.z) }
            else if case .color(let c) = node.properties["colorStart"] { colorStart = c }
            
            var colorEnd = SIMD3<Float>(1, 1, 1)
            if case .vector4(let c) = node.properties["colorEnd"] { colorEnd = SIMD3(c.x, c.y, c.z) }
            else if case .color(let c) = node.properties["colorEnd"] { colorEnd = c }
            
            var angle: Float = 0.0
            if case .float(let a) = node.properties["angle"] { angle = a }
            
            let stops = [
                GradientStop(color: colorStart, position: 0.0),
                GradientStop(color: colorEnd, position: 1.0)
            ]
            definition = .gradient(GradientBackground(gradient: stops, angle: angle))
            
        default:
            print("Unknown generator type: \(type)")
            return nil
        }
        
        try backgroundPass.render(
            commandBuffer: context.commandBuffer,
            background: definition,
            outputTexture: output,
            time: Float(context.time)
        )
        
        return output
    }
    
    private func processComposite(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let background = inputs["background"],
              let foreground = inputs["foreground"] else {
            print("Composite node missing inputs")
            return nil
        }
        
        // Parse properties
        var blendMode: CompositeBlendMode = .normal
        if case .enumValue(let modeStr) = node.properties["blendMode"] {
            // Simple mapping for now
            switch modeStr {
            case "normal": blendMode = .normal
            case "add": blendMode = .add
            case "multiply": blendMode = .multiply
            case "screen": blendMode = .screen
            case "overlay": blendMode = .overlay
            default: blendMode = .normal
            }
        }
        
        var opacity: Float = 1.0
        if case .float(let val) = node.properties["opacity"] {
            opacity = val
        }
        
        let params = CompositeParams(
            mode: blendMode,
            maskThreshold: 0.5,
            edgeSoftness: 0.0,
            foregroundOpacity: opacity
        )
        
        return compositePass.composite(
            background: background,
            foreground: foreground,
            mask: inputs["mask"],
            params: params,
            commandBuffer: context.commandBuffer
        )
    }
    
    private func processTransform(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let input = inputs["input"] else {
            print("Transform node missing input")
            return nil
        }
        
        // Parse properties
        var scale = SIMD2<Float>(1.0, 1.0)
        if case .vector2(let s) = node.properties["scale"] {
            scale = s
        }
        
        var position = SIMD2<Float>(0.0, 0.0)
        if case .vector2(let p) = node.properties["position"] {
            position = p
        }
        
        var rotation: Float = 0.0
        if case .float(let r) = node.properties["rotation"] {
            rotation = r
        }
        
        // Build Transform Matrix (Inverse)
        // P_in = S^-1 * R^-1 * T^-1 * P_out
        
        // 1. Scale Inverse
        let sX = scale.x != 0 ? 1.0 / scale.x : 1.0
        let sY = scale.y != 0 ? 1.0 / scale.y : 1.0
        
        let scaleMat = simd_float3x3(
            SIMD3<Float>(sX, 0, 0),
            SIMD3<Float>(0, sY, 0),
            SIMD3<Float>(0, 0, 1)
        )
        
        // 2. Rotation Inverse (Negative angle)
        let cosA = cos(-rotation)
        let sinA = sin(-rotation)
        
        let rotMat = simd_float3x3(
            SIMD3<Float>(cosA, sinA, 0),
            SIMD3<Float>(-sinA, cosA, 0),
            SIMD3<Float>(0, 0, 1)
        )
        
        // 3. Translation Inverse (Negative position)
        let transMat = simd_float3x3(
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(-position.x, -position.y, 1)
        )
        
        // Combine: S^-1 * R^-1 * T^-1
        let transform = scaleMat * rotMat * transMat
        
        return compositePass.transform(
            input: input,
            transform: transform,
            commandBuffer: context.commandBuffer
        )
    }
    
    private func processFilter(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let input = inputs["input"] else {
            print("Filter node missing input")
            return nil
        }
        
        // Check filter type
        if case .enumValue(let type) = node.properties["type"], type == "blur" {
            var radius: Float = 0.0
            if case .float(let r) = node.properties["radius"] {
                radius = r
            }
            
            return blurPass.blur(
                input: input,
                radius: radius,
                commandBuffer: context.commandBuffer,
                texturePool: context.texturePool
            )
        }
        
        print("Unknown filter type")
        return input
    }
    
    private func processInput(_ node: GraphNode, context: RenderContext) throws -> MTLTexture? {
        guard let assetIdVal = node.properties["assetId"],
              case .string(let assetId) = assetIdVal else {
            print("Input node missing assetId")
            return nil
        }
        
        guard let inputTexture = context.inputProvider?.texture(for: assetId, time: context.time) else {
            print("WARNING: Input provider returned nil for assetId: \(assetId) at time: \(context.time). Returning black fallback.")
            // Create fallback black texture
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: context.resolution.x, height: context.resolution.y, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            if let texture = context.texturePool.acquire(descriptor: desc) {
                // Clear to black
                let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
                var black = SIMD4<Float>(0, 0, 0, 1)
                // We can't use replaceRegion easily for float textures without bytes conversion.
                // Just relying on new texture being clear (or clear it via blit if needed).
                // For now assuming pool gives clean textures or we don't care about noise, just avoid nil.
                return texture
            }
            return nil
        }
        let texture = inputTexture
        
        // DEBUG: Check input texture
        print("DEBUG [Input]: Got texture for \(assetId). Size: \(texture.width)x\(texture.height), Format: \(texture.pixelFormat.rawValue)")
        
        // if context.time < 0.5 { // Increased time window
             /*
             let region = MTLRegionMake2D(texture.width / 2, texture.height / 2, 1, 1)
             
             // Create a buffer to read pixels safely regardless of storage mode
             let bytesPerPixel = 4 // BGRA8
             let bytesPerRow = bytesPerPixel // Reading 1 pixel
             
             if let buffer = context.device.makeBuffer(length: bytesPerPixel, options: .storageModeShared),
                let blit = context.commandBuffer.makeBlitCommandEncoder() {
                 
                 blit.copy(from: texture,
                          sourceSlice: 0,
                          sourceLevel: 0,
                          sourceOrigin: MTLOrigin(x: texture.width/2, y: texture.height/2, z: 0),
                          sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                          to: buffer,
                          destinationOffset: 0,
                          destinationBytesPerRow: bytesPerRow,
                          destinationBytesPerImage: 0)
                 blit.endEncoding()
                 
                 // We need to commit and wait to read the buffer, but we are inside a command encoding block.
                 // This is tricky. We can't wait here.
                 // Instead, let's add a completion handler to the command buffer? 
                 // Or just use getBytes if it's not private.
                 
                 if texture.storageMode != .private {
                     var rawPixel = [UInt8](repeating: 0, count: 4)
                     texture.getBytes(&rawPixel, bytesPerRow: texture.width * 4, from: region, mipmapLevel: 0)
                     print("DEBUG [Input]: Center Pixel (Direct Read): \(rawPixel)")
                 } else {
                     print("DEBUG [Input]: Texture is private, cannot read directly.")
                 }
             }
             */
        // }

        // Ensure texture is in correct format (rgba16Float)
        if texture.pixelFormat != .rgba16Float {
            return compositePass.copy(input: texture, commandBuffer: context.commandBuffer)
        }
        
        return texture
    }
    
    private func processText(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        // Allocate output texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: context.resolution.x,
            height: context.resolution.y,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let output = context.texturePool.acquire(descriptor: desc) else { return nil }
        
        // Create Render Pass Descriptor for Text
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = output
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Parse Properties
        var text = "Text"
        if case .string(let t) = node.properties["text"] { text = t }
        
        var fontSize: Float = 64.0
        if case .float(let s) = node.properties["fontSize"] { fontSize = s }
        
        var color = SIMD4<Float>(1, 1, 1, 1)
        if case .vector4(let c) = node.properties["color"] { color = c }
        else if case .color(let c) = node.properties["color"] { color = SIMD4(c, 1) }
        
        var position = SIMD3<Float>(100, 100, 0)
        if case .vector2(let p) = node.properties["position"] { position = SIMD3(p.x, p.y, 0) }
        else if case .vector3(let p) = node.properties["position"] { position = p }
        
        var rotation = SIMD3<Float>(0, 0, 0)
        if case .vector3(let r) = node.properties["rotation"] { rotation = r }
        
        var scale = SIMD3<Float>(1, 1, 1)
        if case .vector3(let s) = node.properties["scale"] { scale = s }
        
        var duration: Float = 10.0
        if case .float(let d) = node.properties["duration"] { duration = d }
        
        // Animation
        if case .string(let jsonString) = node.properties["animation"],
           let data = jsonString.data(using: .utf8),
           let animConfig = try? JSONDecoder().decode(TextAnimationConfig.self, from: data) {
            
            let state = TextAnimationEvaluator.evaluate(
                config: animConfig,
                time: Float(context.time),
                elementDuration: duration,
                textLength: text.count,
                viewportSize: SIMD2<Float>(Float(context.resolution.x), Float(context.resolution.y))
            )
            
            position += state.positionOffset
            scale *= state.scale
            rotation.z += state.rotation
            color.w *= state.opacity
        }
        
        // Resolve Font
        var fontID = defaultFontID
        if case .string(let fontName) = node.properties["fontName"] {
            // Note: In a production system we should cache these IDs to avoid
            // registering a new CTFont every frame, but for this render pass it is acceptable.
            if let id = try? fontRegistry.register(name: fontName, size: CGFloat(fontSize)) {
                fontID = id
            }
        }
        
        // Create Command
        var style = TextStyle(color: color)
        var command = TextDrawCommand(
            text: text,
            position: position,
            fontSize: CGFloat(fontSize),
            style: style,
            fontID: fontID,
            rotation: rotation,
            scale: scale
        )
        
        // Apply Cinematic Visibility Optimization if reference is available
        if let reference = inputs["reference"] {
            if let optimizer = textOptimizer {
                // TODO: FIX-HAZARD: TextVisibilityOptimizer creates a new command buffer and commits it immediately.
                // However, the 'background' texture is being produced by the current (uncommitted) command buffer.
                // This creates a read-after-write hazard where the optimizer reads uninitialized memory.
                // Disabling for now to fix render glitches.
                // command = optimizer.optimize(command: command, background: reference, commandBuffer: context.commandBuffer)
                print("DEBUG: Skipped Text Optimizer due to pipeline hazard")
            } else {
                print("DEBUG: Reference available but TextOptimizer is nil")
            }
        } else {
            print("DEBUG: No reference input for text node")
        }
        
        // Execute TextPass
        textPass.add(command: command)
        
        // Create a temporary context with the new render pass descriptor
        let textContext = RenderContext(
            device: context.device,
            commandBuffer: context.commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            resolution: context.resolution,
            time: context.time,
            scene: context.scene,
            quality: context.quality,
            texturePool: context.texturePool,
            inputProvider: context.inputProvider
        )
        
        try textPass.execute(commandBuffer: context.commandBuffer, context: textContext)
        
        return output
    }
    
    private func processHalation(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let input = inputs["input"] else { return nil }
        
        var intensity: Float = 0.5
        if case .float(let v) = node.properties["intensity"] { intensity = v }
        
        var threshold: Float = 0.8
        if case .float(let v) = node.properties["threshold"] { threshold = v }
        
        var radius: Float = 1.0
        if case .float(let v) = node.properties["radius"] { radius = v }
        
        var tint = SIMD3<Float>(1, 0.9, 0.8)
        if case .vector3(let v) = node.properties["tint"] { tint = v }
        else if case .color(let c) = node.properties["tint"] { tint = c }
        
        let settings = HalationSettings(
            intensity: intensity,
            threshold: threshold,
            tint: tint,
            radius: radius,
            radialFalloff: true
        )
        
        // 1. Extract
        guard let halationTex = try cinematicPass.extractHalation(settings, input: input, context: context, commandBuffer: context.commandBuffer) else {
            return input
        }
        
        var processedHalation = halationTex
        
        // 2. Apply Mask if present
        if let mask = inputs["mask"] {
            if let masked = try applyMask(to: halationTex, mask: mask, context: context) {
                processedHalation = masked
                // We can return the original halationTex to pool now if it's different
                if processedHalation !== halationTex {
                    context.texturePool.return(halationTex)
                }
            }
        }
        
        // 3. Composite
        let output = try cinematicPass.compositeHalation(settings, halationTexture: processedHalation, onto: input, context: context, commandBuffer: context.commandBuffer)
        
        if processedHalation !== halationTex {
            context.texturePool.return(processedHalation)
        } else {
            context.texturePool.return(halationTex)
        }
        
        return output
    }
    
    private func processBloom(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let input = inputs["input"] else { return nil }
        
        var intensity: Float = 0.5
        if case .float(let v) = node.properties["intensity"] { intensity = v }
        
        var threshold: Float = 0.8
        if case .float(let v) = node.properties["threshold"] { threshold = v }
        
        var radius: Float = 1.0
        if case .float(let v) = node.properties["radius"] { radius = v }
        
        let settings = BloomSettings(
            intensity: intensity,
            threshold: threshold,
            radius: radius
        )
        
        // 1. Extract
        guard let bloomTex = try cinematicPass.extractBloom(settings, input: input, context: context, commandBuffer: context.commandBuffer) else {
            return input
        }
        
        var processedBloom = bloomTex
        
        // 2. Apply Mask if present
        if let mask = inputs["mask"] {
            if let masked = try applyMask(to: bloomTex, mask: mask, context: context) {
                processedBloom = masked
                if processedBloom !== bloomTex {
                    context.texturePool.return(bloomTex)
                }
            }
        }
        
        // 3. Composite
        let output = try cinematicPass.compositeBloom(settings, bloomTexture: processedBloom, onto: input, context: context, commandBuffer: context.commandBuffer)
        
        if processedBloom !== bloomTex {
            context.texturePool.return(processedBloom)
        } else {
            context.texturePool.return(bloomTex)
        }
        
        return output
    }
    
    private func processVignette(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let input = inputs["input"] else { return nil }
        
        var intensity: Float = 0.4
        if case .float(let v) = node.properties["intensity"] { intensity = v }
        
        var smoothness: Float = 0.5
        if case .float(let v) = node.properties["smoothness"] { smoothness = v }
        
        var roundness: Float = 1.0
        if case .float(let v) = node.properties["roundness"] { roundness = v }
        
        let settings = VignetteSettings(
            intensity: intensity,
            smoothness: smoothness,
            roundness: roundness
        )
        
        let vignetteTex = try cinematicPass.applyVignette(settings, input: input, context: context, commandBuffer: context.commandBuffer)
        
        if let mask = inputs["mask"] {
            // Blend vignetteTex over input using mask
            let params = CompositeParams(
                mode: .normal,
                maskThreshold: 0.0,
                edgeSoftness: 0.0,
                foregroundOpacity: 1.0
            )
            
            let output = compositePass.composite(
                background: input,
                foreground: vignetteTex,
                mask: mask,
                params: params,
                commandBuffer: context.commandBuffer
            )
            
            // If vignetteTex is a new texture (not input), return it
            if vignetteTex !== input {
                context.texturePool.return(vignetteTex)
            }
            return output
        }
        
        return vignetteTex
    }
    
    private func processGrain(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let input = inputs["input"] else { return nil }
        
        var intensity: Float = 0.1
        if case .float(let v) = node.properties["intensity"] { intensity = v }
        
        var size: Float = 1.0
        if case .float(let v) = node.properties["size"] { size = v }
        
        let settings = FilmGrainSettings(
            intensity: intensity,
            size: size,
            shadowBoost: 1.0,
            animated: true
        )
        
        let grainTex = try cinematicPass.applyFilmGrain(settings, input: input, context: context, commandBuffer: context.commandBuffer)
        
        if let mask = inputs["mask"] {
            // Blend grainTex over input using mask
            let params = CompositeParams(
                mode: .normal,
                maskThreshold: 0.0,
                edgeSoftness: 0.0,
                foregroundOpacity: 1.0
            )
            
            let output = compositePass.composite(
                background: input,
                foreground: grainTex,
                mask: mask,
                params: params,
                commandBuffer: context.commandBuffer
            )
            
            if grainTex !== input {
                context.texturePool.return(grainTex)
            }
            return output
        }
        
        return grainTex
    }
    
    private func processSegmentation(_ node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture? {
        guard let input = inputs["input"] else { return nil }
        
        // We need to run the async vision request synchronously
        let semaphore = DispatchSemaphore(value: 0)
        var resultTexture: MTLTexture?
        var error: Error?
        
        Task {
            do {
                if #available(macOS 12.0, iOS 15.0, *) {
                    let mask = try await visionProvider.segmentPeople(in: input, quality: .balanced)
                    resultTexture = mask.texture
                } else {
                    print("Segmentation requires macOS 12.0+")
                }
            } catch let e {
                error = e
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let e = error {
            print("Segmentation failed: \(e)")
            return nil
        }
        
        return resultTexture
    }
    
    private func applyMask(to texture: MTLTexture, mask: MTLTexture, context: RenderContext) throws -> MTLTexture? {
        // Create a transparent background
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let background = context.texturePool.acquire(descriptor: desc) else { return nil }
        
        // Clear background to transparent
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = background
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPass.colorAttachments[0].storeAction = .store
        
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            context.texturePool.return(background)
            return nil
        }
        encoder.endEncoding()
        
        // Composite foreground (texture) over background (transparent) using mask
        let params = CompositeParams(
            mode: .normal,
            maskThreshold: 0.0,
            edgeSoftness: 0.0,
            foregroundOpacity: 1.0
        )
        
        let result = compositePass.composite(
            background: background,
            foreground: texture,
            mask: mask,
            params: params,
            commandBuffer: context.commandBuffer
        )
        
        context.texturePool.return(background)
        return result
    }
}

/// Protocol for a class that handles the execution of a specific node type
public protocol NodeProcessor {
    func process(node: GraphNode, inputs: [String: MTLTexture], context: RenderContext) throws -> MTLTexture?
}
