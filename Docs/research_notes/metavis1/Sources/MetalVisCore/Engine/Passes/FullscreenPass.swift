import Metal
import simd

/// A generic Render Pass that draws a full-screen quad using a specific fragment shader.
/// Used for Tone Mapping, Compositing, Lens FX, etc.
public class FullscreenPass: RenderPass {
    
    public var label: String
    public var inputs: [String]
    public var outputs: [String]
    
    private let fragmentShaderName: String
    private var pipelineState: MTLRenderPipelineState?
    private let quad: QuadMesh
    
    // Optional: Closure to set custom uniforms
    public var updateUniforms: ((MTLRenderCommandEncoder, RenderContext) -> Void)?
    
    public init(device: MTLDevice,
                label: String,
                fragmentShader: String,
                inputs: [String],
                outputs: [String]) {
        self.label = label
        self.fragmentShaderName = fragmentShader
        self.inputs = inputs
        self.outputs = outputs
        self.quad = QuadMesh(device: device)
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        // 1. Create Pipeline State (Lazy Loading)
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let outputTexture = outputTextures[outputs.first ?? ""] else {
            return
        }
        
        // 2. Create Render Pass Descriptor
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = outputTexture
        
        // For alpha blending shaders, we need to load the existing content
        if fragmentShaderName == "fragment_over" {
            descriptor.colorAttachments[0].loadAction = .load // Preserve background for blending
        } else {
            descriptor.colorAttachments[0].loadAction = .dontCare // We overwrite everything
        }
        descriptor.colorAttachments[0].storeAction = .store
        
        // 3. Encode
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        encoder.label = label
        encoder.setRenderPipelineState(pipeline)
        
        // Bind Inputs
        for (index, name) in inputs.enumerated() {
            if let texture = inputTextures[name] {
                encoder.setFragmentTexture(texture, index: index)
            }
        }
        
        // Bind Uniforms
        updateUniforms?(encoder, context)
        
        // Draw
        // Use explicit triangle (3 vertices) for full screen coverage
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "vertex_fullscreen_triangle")) == nil {
             try? library.loadSource(resource: "StandardMesh")
        }
        
        // Try to find the fragment shader. If not found, try loading likely candidates.
        if (try? library.makeFunction(name: fragmentShaderName)) == nil {
             try? library.loadSource(resource: "MetaVisFXShaders")
             try? library.loadSource(resource: "PostProcessing")
             try? library.loadSource(resource: "Blending")
        }
        
        let vertexFn = try library.makeFunction(name: "vertex_fullscreen_triangle")
        let fragmentFn = try library.makeFunction(name: fragmentShaderName)
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float // Standard HDR format
        
        // Configure alpha blending for "over" composite shaders
        if fragmentShaderName == "fragment_over" {
            // Pre-multiplied alpha over blending:
            // C_out = C_src + C_dst * (1 - α_src)
            // α_out = α_src + α_dst * (1 - α_src)
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
