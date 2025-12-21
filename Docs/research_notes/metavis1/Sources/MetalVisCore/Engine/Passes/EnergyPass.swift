import Metal
import simd

public class EnergyPass: RenderPass {
    public var label: String = "Energy Field"
    public var inputs: [String] = [] 
    public var outputs: [String] = ["energy_buffer"]
    
    private var pipelineState: MTLComputePipelineState?
    
    // Parameters
    public var intensity: Float = 1.0
    public var speed: Float = 0.5
    public var scale: Float = 1.0
    public var color: SIMD3<Float> = SIMD3(0.8, 0.2, 0.05)
    
    public init(device: MTLDevice) {
        // No-op
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        guard let outputTexture = outputTextures[outputs[0]] else {
            return
        }
        
        if pipelineState == nil {
            try buildPipeline(device: context.device)
        }
        
        guard let pipeline = pipelineState,
              let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = label
        encoder.setComputePipelineState(pipeline)
        
        encoder.setTexture(outputTexture, index: 0)
        
        var timeVal = Float(context.time) * speed
        var intensityVal = intensity
        var scaleVal = scale
        var colorVal = color
        
        encoder.setBytes(&timeVal, length: MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&intensityVal, length: MemoryLayout<Float>.size, index: 1)
        encoder.setBytes(&scaleVal, length: MemoryLayout<Float>.size, index: 2)
        encoder.setBytes(&colorVal, length: MemoryLayout<SIMD3<Float>>.size, index: 3)
        
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(outputTexture.width, outputTexture.height, 1)
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    private func buildPipeline(device: MTLDevice) throws {
        let library = ShaderLibrary(device: device)
        
        if (try? library.makeFunction(name: "fx_energy_field")) == nil {
             try? library.loadSource(resource: "Energy")
        }
        
        let function = try library.makeFunction(name: "fx_energy_field")
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
