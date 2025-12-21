import Metal
import simd

/// Applies chromatic aberration (spectral separation) effect
/// Simulates lens dispersion causing RGB channels to shift radially
public class ChromaticAberrationPass: RenderPass {
    public var label: String = "Chromatic Aberration"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["display_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    private let camera: PhysicalCamera?
    
    /// Intensity of the chromatic aberration effect (0.0 - 1.0)
    /// Higher values create more visible color fringing
    public var intensity: Float = 0.5
    
    public init(device: MTLDevice, camera: PhysicalCamera? = nil) {
        self.camera = camera
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let inputTexture = inputTextures[inputs[0]],
              let outputTexture = outputTextures[outputs[0]] else {
            return
        }
        
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        var intensityValue = intensity
        if let cam = camera {
            intensityValue = cam.chromaticAberration
        }
        
        encoder.setBytes(&intensityValue, length: MemoryLayout<Float>.stride, index: 0)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        // Load shader source if not already loaded
        if (try? library.makeFunction(name: "fx_spectral_ca")) == nil {
            try? library.loadSource(resource: "MetaVisFXShaders")
        }
        
        // Use Spectral CA (Cubic falloff) for physically accurate lens simulation
        let function = try library.makeFunction(name: "fx_spectral_ca")
        
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
