import Metal
import simd

public class BackgroundPass: RenderPass {
    public var label: String = "Background"
    public var inputs: [String] = []
    public var outputs: [String] = ["main_buffer"]
    
    private var gradientPipeline: MTLRenderPipelineState?
    private var starfieldPipeline: MTLRenderPipelineState?
    private let quad: QuadMesh
    
    public var colorTop: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    public var colorBottom: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    
    public init(device: MTLDevice) {
        self.quad = QuadMesh(device: device)
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        if gradientPipeline == nil {
            try buildPipelines(device: context.device)
        }
        
        // Determine which pipeline to use
        let bgType = context.scene.background?.type ?? "GRADIENT"
        let pipeline = (bgType == "STARFIELD") ? starfieldPipeline : gradientPipeline
        
        guard let activePipeline = pipeline,
              let outputTexture = outputTextures[outputs[0]] else {
            return
        }
        
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = outputTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        encoder.label = label
        
        // Fix 2: Reset Viewport
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(outputTexture.width),
            height: Double(outputTexture.height),
            znear: 0,
            zfar: 1
        ))
        
        encoder.setRenderPipelineState(activePipeline)
        
        struct BackgroundUniforms {
            var colorTop: SIMD4<Float>
            var colorBottom: SIMD4<Float>
            var starDensity: Float
            var padding: SIMD3<Float>
        }
        
        // Resolve Colors
        var top = colorTop
        var bottom = colorBottom
        var density: Float = 0.0
        
        if let bg = context.scene.background {
            // Handle single color (SOLID)
            if let c = bg.color {
                let color = hexToSIMD3(c)
                top = color
                bottom = color
            }
            
            // Override with gradients if present
            if let t = bg.colorTop { top = hexToSIMD3(t) }
            if let b = bg.colorBottom { bottom = hexToSIMD3(b) }
            if let d = bg.starDensity { density = Float(d) }
        }
        
        var uniforms = BackgroundUniforms(
            colorTop: SIMD4<Float>(top, 1.0),
            colorBottom: SIMD4<Float>(bottom, 1.0),
            starDensity: density,
            padding: .zero
        )
        
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
        
        // Use explicit triangle (3 vertices) for full screen coverage
        // Use vertex_background_quad which expects 6 vertices (2 triangles)
        // The shader 'vertex_background_quad' uses vertexID to index into a 6-element array.
        // If we only draw 3, we only get half the screen.
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }
    
    private func buildPipelines(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        // Ensure shaders are loaded
        if (try? library.makeFunction(name: "vertex_fullscreen_triangle")) == nil {
             try? library.loadSource(resource: "StandardMesh")
        }
        
        // Ensure Background shaders are loaded
        if (try? library.makeFunction(name: "fragment_background_starfield")) == nil {
             try? library.loadSource(resource: "Background")
        }
        
        let vertexFn = try library.makeFunction(name: "vertex_fullscreen_triangle")
        
        // Gradient Pipeline
        let gradientFn = try library.makeFunction(name: "fragment_background_gradient")
        let gradDesc = MTLRenderPipelineDescriptor()
        gradDesc.label = "Background Gradient"
        gradDesc.vertexFunction = vertexFn
        gradDesc.fragmentFunction = gradientFn
        gradDesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.gradientPipeline = try device.makeRenderPipelineState(descriptor: gradDesc)
        
        // Starfield Pipeline
        // Check if starfield shader exists (it might not if we haven't recompiled/reloaded)
        // But we just edited the file.
        if let starFn = try? library.makeFunction(name: "fragment_background_starfield") {
            let starDesc = MTLRenderPipelineDescriptor()
            starDesc.label = "Background Starfield"
            starDesc.vertexFunction = vertexFn
            starDesc.fragmentFunction = starFn
            starDesc.colorAttachments[0].pixelFormat = .rgba16Float
            self.starfieldPipeline = try device.makeRenderPipelineState(descriptor: starDesc)
        }
    }
    
    private func hexToSIMD3(_ hex: String) -> SIMD3<Float> {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if (cString.hasPrefix("#")) { cString.remove(at: cString.startIndex) }
        if ((cString.count) != 6) { return SIMD3<Float>(0,0,0) }
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        return SIMD3<Float>(
            Float((rgbValue & 0xFF0000) >> 16) / 255.0,
            Float((rgbValue & 0x00FF00) >> 8) / 255.0,
            Float(rgbValue & 0x0000FF) / 255.0
        )
    }
}
